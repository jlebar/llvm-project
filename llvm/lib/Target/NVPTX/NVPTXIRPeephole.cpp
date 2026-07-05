//===------ NVPTXIRPeephole.cpp - NVPTX IR Peephole --------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements IR-level peephole optimizations. These transformations
// run late in the NVPTX IR pass pipeline just before the instruction selection.
//
// Currently, it implements the following transformation(s):
// 1. FMA folding (float/double types):
//    Transforms FMUL+FADD/FSUB sequences into FMA intrinsics when the
//    'contract' fast-math flag is present. Supported patterns:
//    - fadd(fmul(a, b), c) => fma(a, b, c)
//    - fadd(c, fmul(a, b)) => fma(a, b, c)
//    - fadd(fmul(a, b), fmul(c, d)) => fma(a, b, fmul(c, d))
//    - fsub(fmul(a, b), c) => fma(a, b, fneg(c))
//    - fsub(a, fmul(b, c)) => fma(fneg(b), c, a)
//    - fsub(fmul(a, b), fmul(c, d)) => fma(a, b, fneg(fmul(c, d)))
// 2. Scalarization of v2f32/v2i32 PHIs:
//    Splits 2 x 32-bit vector PHIs into scalar PHIs when the vector is only
//    ever taken apart into scalars. On targets where these types are legal
//    (sm_100+), a vector PHI otherwise occupies a packed 64-bit register,
//    and every round trip through it costs a pair of packing and unpacking
//    movs. On other targets the type legalizer scalarizes these PHIs anyway,
//    so running this unconditionally does not change the generated code.
//
//===----------------------------------------------------------------------===//

#include "NVPTXUtilities.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/ValueHandle.h"
#include "llvm/Transforms/Utils/Local.h"

#define DEBUG_TYPE "nvptx-ir-peephole"

using namespace llvm;

static bool tryFoldBinaryFMul(BinaryOperator *BI) {
  Value *Op0 = BI->getOperand(0);
  Value *Op1 = BI->getOperand(1);

  auto *FMul0 = dyn_cast<BinaryOperator>(Op0);
  auto *FMul1 = dyn_cast<BinaryOperator>(Op1);

  BinaryOperator *FMul = nullptr;
  Value *OtherOperand = nullptr;
  bool IsFirstOperand = false;

  // Either Op0 or Op1 should be a valid FMul
  if (FMul0 && FMul0->getOpcode() == Instruction::FMul && FMul0->hasOneUse() &&
      FMul0->hasAllowContract()) {
    FMul = FMul0;
    OtherOperand = Op1;
    IsFirstOperand = true;
  } else if (FMul1 && FMul1->getOpcode() == Instruction::FMul &&
             FMul1->hasOneUse() && FMul1->hasAllowContract()) {
    FMul = FMul1;
    OtherOperand = Op0;
    IsFirstOperand = false;
  } else {
    return false;
  }

  bool IsFSub = BI->getOpcode() == Instruction::FSub;
  LLVM_DEBUG({
    const char *OpName = IsFSub ? "FSub" : "FAdd";
    dbgs() << "Found " << OpName << " with FMul (single use) as "
           << (IsFirstOperand ? "first" : "second") << " operand: " << *BI
           << "\n";
  });

  Value *MulOp0 = FMul->getOperand(0);
  Value *MulOp1 = FMul->getOperand(1);
  IRBuilder<> Builder(BI);
  Value *FMA = nullptr;

  if (!IsFSub) {
    // fadd(fmul(a, b), c) => fma(a, b, c)
    // fadd(c, fmul(a, b)) => fma(a, b, c)
    FMA = Builder.CreateIntrinsic(Intrinsic::fma, {BI->getType()},
                                  {MulOp0, MulOp1, OtherOperand});
  } else {
    if (IsFirstOperand) {
      // fsub(fmul(a, b), c) => fma(a, b, fneg(c))
      Value *NegOtherOp =
          Builder.CreateFNegFMF(OtherOperand, BI->getFastMathFlags());
      FMA = Builder.CreateIntrinsic(Intrinsic::fma, {BI->getType()},
                                    {MulOp0, MulOp1, NegOtherOp});
    } else {
      // fsub(a, fmul(b, c)) => fma(fneg(b), c, a)
      Value *NegMulOp0 =
          Builder.CreateFNegFMF(MulOp0, FMul->getFastMathFlags());
      FMA = Builder.CreateIntrinsic(Intrinsic::fma, {BI->getType()},
                                    {NegMulOp0, MulOp1, OtherOperand});
    }
  }

  // Combine fast-math flags from the original instructions
  auto *FMAInst = cast<Instruction>(FMA);
  FastMathFlags BinaryFMF = BI->getFastMathFlags();
  FastMathFlags FMulFMF = FMul->getFastMathFlags();
  FastMathFlags NewFMF = FastMathFlags::intersectRewrite(BinaryFMF, FMulFMF) |
                         FastMathFlags::unionValue(BinaryFMF, FMulFMF);
  FMAInst->setFastMathFlags(NewFMF);

  LLVM_DEBUG({
    const char *OpName = IsFSub ? "FSub" : "FAdd";
    dbgs() << "Replacing " << OpName << " with FMA: " << *FMA << "\n";
  });
  BI->replaceAllUsesWith(FMA);
  BI->eraseFromParent();
  FMul->eraseFromParent();
  return true;
}

static bool foldFMA(Function &F) {
  bool Changed = false;

  // Iterate and process float/double FAdd/FSub instructions with allow-contract
  for (auto &I : llvm::make_early_inc_range(instructions(F))) {
    if (auto *BI = dyn_cast<BinaryOperator>(&I)) {
      // Only FAdd and FSub are supported.
      if (BI->getOpcode() != Instruction::FAdd &&
          BI->getOpcode() != Instruction::FSub)
        continue;

      // At minimum, the instruction should have allow-contract.
      if (!BI->hasAllowContract())
        continue;

      // Only float and double are supported.
      if (!BI->getType()->isFloatTy() && !BI->getType()->isDoubleTy())
        continue;

      if (tryFoldBinaryFMul(BI))
        Changed = true;
    }
  }
  return Changed;
}

// The number of lanes in the vector PHIs handled by scalarizeVectorPHIs.
static constexpr unsigned NumLanes = 2;

// Give up on insertelement chains longer than this. The cap bounds the cost
// of the chain walks and terminates them on the cyclic chains that
// unreachable code may contain.
static constexpr unsigned MaxChainLength = 32;

static bool isCandidatePHIType(Type *Ty) {
  auto *VecTy = dyn_cast<FixedVectorType>(Ty);
  return VecTy && VecTy->getNumElements() == NumLanes &&
         (VecTy->getElementType()->isFloatTy() ||
          VecTy->getElementType()->isIntegerTy(32));
}

/// Decompose the vector value \p V into per-lane scalars by looking through
/// insertelement chains, and return the base of the chain. Lanes covered by
/// the chain (or by a constant base) are filled in \p Lanes; the rest stay
/// null and must be extracted from the returned base. The visited
/// insertelements are appended to \p Chain. Returns null on failure.
static Value *getLaneValues(Value *V, MutableArrayRef<Value *> Lanes,
                            SmallVectorImpl<Instruction *> &Chain) {
  llvm::fill(Lanes, nullptr);
  while (auto *IE = dyn_cast<InsertElementInst>(V)) {
    auto *Idx = dyn_cast<ConstantInt>(IE->getOperand(2));
    if (!Idx || Idx->uge(NumLanes) || Chain.size() == MaxChainLength)
      return nullptr;
    // A later insert into the same lane shadows earlier ones.
    if (!Lanes[Idx->getZExtValue()])
      Lanes[Idx->getZExtValue()] = IE->getOperand(1);
    Chain.push_back(IE);
    V = IE->getOperand(0);
  }
  if (auto *C = dyn_cast<Constant>(V))
    for (unsigned I = 0; I != NumLanes; ++I)
      if (!Lanes[I] && !(Lanes[I] = C->getAggregateElement(I)))
        return nullptr;
  return V;
}

/// Collect the connected component of scalarizable vector PHIs containing
/// \p Root into \p Web. PHIs are connected through PHI users, PHI incoming
/// values, and shared insertelement chains: if a chain feeding one PHI is
/// also used by another PHI, the two must be scalarized together, or the
/// chain stays live as a vector for the unscalarized PHI. Returns false if
/// any PHI in the component has a user or an incoming value we cannot
/// scalarize. Sets \p HasExtractUser if some PHI is used by an
/// extractelement.
static bool collectPHIWeb(PHINode *Root, SmallSetVector<PHINode *, 8> &Web,
                          bool &HasExtractUser) {
  Web.insert(Root);
  HasExtractUser = false;
  // The web set doubles as the worklist: newly discovered PHIs are appended
  // and visited in turn.
  for (unsigned WebIdx = 0; WebIdx != Web.size(); ++WebIdx) {
    PHINode *P = Web[WebIdx];
    for (User *U : P->users()) {
      if (auto *EE = dyn_cast<ExtractElementInst>(U)) {
        auto *Idx = dyn_cast<ConstantInt>(EE->getIndexOperand());
        if (!Idx || Idx->uge(NumLanes))
          return false;
        HasExtractUser = true;
        continue;
      }
      // A PHI user has the same type, so it is itself a candidate.
      if (auto *PU = dyn_cast<PHINode>(U)) {
        Web.insert(PU);
        continue;
      }
      // Storing the value is fine: we rebuild the vector right before the
      // store, and store lowering takes it apart again anyway. (A vector
      // cannot be a store's pointer operand.)
      if (isa<StoreInst>(U))
        continue;
      return false;
    }
    for (unsigned I = 0, E = P->getNumIncomingValues(); I != E; ++I) {
      Value *In = P->getIncomingValue(I);
      if (auto *PI = dyn_cast<PHINode>(In)) {
        Web.insert(PI);
        continue;
      }
      std::array<Value *, NumLanes> Lanes;
      SmallVector<Instruction *, 4> Chain;
      Value *Base = getLaneValues(In, Lanes, Chain);
      if (!Base)
        return false;
      // Lanes not covered by the chain are extracted from the base right
      // before the incoming block's terminator. That fails if the base is
      // the terminator itself (it would not dominate the extracts), or if
      // nothing may be inserted in front of the terminator (catchswitch).
      if (llvm::is_contained(Lanes, nullptr)) {
        Instruction *Term = P->getIncomingBlock(I)->getTerminator();
        if (Base == Term || isa<CatchSwitchInst>(Term))
          return false;
      }
      // PHI users of the chain have the same type, so they are candidates.
      for (Instruction *IE : Chain)
        for (User *U : IE->users())
          if (auto *PU = dyn_cast<PHINode>(U))
            Web.insert(PU);
    }
  }
  return true;
}

/// Rewrite extractelement and store users of \p V (skipping PHIs) with the
/// per-lane scalars in \p Lanes: extracts become the lane value, and stores
/// get the vector rebuilt right in front of them, where the packing is free
/// (store lowering takes vectors apart again anyway).
static void rewriteScalarizedUsers(Value *V, ArrayRef<Value *> Lanes) {
  for (User *U : llvm::make_early_inc_range(V->users())) {
    if (auto *EE = dyn_cast<ExtractElementInst>(U)) {
      if (auto *Idx = dyn_cast<ConstantInt>(EE->getIndexOperand());
          Idx && !Idx->uge(NumLanes)) {
        EE->replaceAllUsesWith(Lanes[Idx->getZExtValue()]);
        EE->eraseFromParent();
      }
      continue;
    }
    if (auto *SI = dyn_cast<StoreInst>(U)) {
      IRBuilder<> Builder(SI);
      Value *NewV = PoisonValue::get(V->getType());
      for (unsigned L = 0; L != NumLanes; ++L)
        NewV = Builder.CreateInsertElement(NewV, Lanes[L], L);
      SI->replaceUsesOfWith(V, NewV);
    }
    // PHI users are handled by the caller; anything else keeps using V.
  }
}

/// Split 2 x 32-bit vector PHIs into scalar PHIs when the vector is only
/// taken apart into scalars. This matters for kernels that carry MMA
/// accumulators as <2 x float> across loop iterations and pass the elements
/// to inline asm: with v2f32 as a legal type (sm_100+), the PHI occupies a
/// packed 64-bit register, so every iteration unpacks it before the asm
/// (mov.b32x2-from-b64) and repacks the asm results after. ptxas penalizes
/// these extra movs on the accumulator registers heavily. Splitting the PHI
/// keeps the values in 32-bit registers throughout, so the asm operands can
/// stay in place.
static bool scalarizeVectorPHIs(Function &F) {
  // Gather the candidates up front; the rewrite below mutates PHIs. Value
  // handles, because processing one web can erase other candidates (a PHI
  // whose only use is an insertelement chain dies with the chain).
  SmallVector<WeakVH, 16> Candidates;
  for (BasicBlock &BB : F)
    for (PHINode &P : BB.phis())
      if (isCandidatePHIType(P.getType()))
        Candidates.push_back(&P);

  bool Changed = false;
  SmallPtrSet<PHINode *, 16> Visited;
  for (const WeakVH &VH : Candidates) {
    auto *Root = cast_or_null<PHINode>(static_cast<Value *>(VH));
    if (!Root || Visited.count(Root))
      continue;
    SmallSetVector<PHINode *, 8> Web;
    bool HasExtractUser = false;
    // A failed web is not marked visited: web collection is not symmetric
    // (chain edges are only discovered from the PHI they feed), so a member
    // of a failed web may still form a valid web of its own.
    if (!collectPHIWeb(Root, Web, HasExtractUser))
      continue;
    Visited.insert_range(Web);
    // Only scalarize webs where some PHI is taken apart into scalars;
    // otherwise there is no repacking to save.
    if (!HasExtractUser)
      continue;

    LLVM_DEBUG(dbgs() << "Scalarizing web of " << Web.size()
                      << " vector PHI(s) rooted at: " << *Root << "\n");

    auto *VecTy = cast<FixedVectorType>(Root->getType());
    // Create the scalar replacement PHIs.
    DenseMap<PHINode *, std::array<PHINode *, NumLanes>> ScalarPHIs;
    for (PHINode *P : Web) {
      auto &Scalar = ScalarPHIs[P];
      for (unsigned I = 0; I != NumLanes; ++I) {
        Scalar[I] =
            PHINode::Create(VecTy->getElementType(), P->getNumIncomingValues(),
                            P->getName() + "." + Twine(I), P->getIterator());
        Scalar[I]->setDebugLoc(P->getDebugLoc());
      }
    }

    // Wire up the incoming values and remember the resolved insertelement
    // chains. Lanes not covered by a chain or constant are extracted from
    // the base vector at the end of the incoming block, i.e. once outside
    // the loop for a warm-started accumulator.
    // Tracking handles, because a lane value may itself be an extract of a
    // web PHI (or of another chain), which the rewrites below replace and
    // erase before the chain's own users are rewritten.
    MapVector<Instruction *, std::array<WeakTrackingVH, NumLanes>> Chains;
    SmallDenseMap<std::pair<BasicBlock *, Value *>,
                  std::array<Value *, NumLanes>>
        ExtractCache;
    for (PHINode *P : Web) {
      const auto Scalar = ScalarPHIs.lookup(P);
      for (unsigned I = 0, E = P->getNumIncomingValues(); I != E; ++I) {
        Value *In = P->getIncomingValue(I);
        BasicBlock *IncBB = P->getIncomingBlock(I);
        std::array<Value *, NumLanes> Lanes;
        if (auto *PI = dyn_cast<PHINode>(In)) {
          llvm::copy(ScalarPHIs.lookup(PI), Lanes.begin());
        } else {
          SmallVector<Instruction *, 4> Chain;
          Value *Base = getLaneValues(In, Lanes, Chain);
          assert(Base && "checked by collectPHIWeb");
          // The base is never a web PHI: the insertelement using it would
          // have failed the user check in collectPHIWeb.
          assert((!isa<PHINode>(Base) || !Web.contains(cast<PHINode>(Base))) &&
                 "extracting from an erased PHI");
          // Only fully covered chains may have their own users rewritten
          // below: their lane values are chain operands and so dominate any
          // user of the chain; the extracts created here do not.
          if (!Chain.empty() && !llvm::is_contained(Lanes, nullptr))
            llvm::copy(Lanes, Chains[Chain.front()].begin());
          for (unsigned L = 0; L != NumLanes; ++L) {
            if (Lanes[L])
              continue;
            Value *&Extract = ExtractCache[{IncBB, Base}][L];
            if (!Extract) {
              // Like the PHI copy it replaces, the extract executes on every
              // path through the incoming block.
              IRBuilder<> Builder(IncBB->getTerminator());
              Builder.SetCurrentDebugLocation(DebugLoc());
              Extract = Builder.CreateExtractElement(Base, L);
            }
            Lanes[L] = Extract;
          }
        }
        for (unsigned L = 0; L != NumLanes; ++L)
          Scalar[L]->addIncoming(Lanes[L], IncBB);
      }
    }

    for (PHINode *P : Web)
      rewriteScalarizedUsers(P, to_vector_of<Value *>(ScalarPHIs.lookup(P)));
    // Rewriting the chains' own extract and store users lets the chains go
    // dead even when the rebuilt vector is used across basic blocks directly
    // rather than through a PHI.
    for (const auto &[Chain, Lanes] : Chains)
      rewriteScalarizedUsers(Chain, to_vector_of<Value *>(Lanes));

    // The web PHIs now only reference each other; drop the references before
    // erasing them.
    for (PHINode *P : Web)
      P->dropAllReferences();
    for (PHINode *P : Web)
      P->eraseFromParent();

    SmallVector<WeakTrackingVH, 8> MaybeDead(llvm::make_first_range(Chains));
    RecursivelyDeleteTriviallyDeadInstructionsPermissive(MaybeDead);
    Changed = true;
  }
  return Changed;
}

namespace {

struct NVPTXIRPeephole : public FunctionPass {
  static char ID;
  NVPTXIRPeephole() : FunctionPass(ID) {}
  bool runOnFunction(Function &F) override;
};

} // namespace

char NVPTXIRPeephole::ID = 0;
INITIALIZE_PASS(NVPTXIRPeephole, "nvptx-ir-peephole", "NVPTX IR Peephole",
                false, false)

static bool runPeepholes(Function &F) {
  bool Changed = foldFMA(F);
  Changed |= scalarizeVectorPHIs(F);
  return Changed;
}

bool NVPTXIRPeephole::runOnFunction(Function &F) {
  if (skipFunction(F))
    return false;
  return runPeepholes(F);
}

FunctionPass *llvm::createNVPTXIRPeepholePass() {
  return new NVPTXIRPeephole();
}

PreservedAnalyses NVPTXIRPeepholePass::run(Function &F,
                                           FunctionAnalysisManager &) {
  if (!runPeepholes(F))
    return PreservedAnalyses::all();

  PreservedAnalyses PA;
  PA.preserveSet<CFGAnalyses>();
  return PA;
}
