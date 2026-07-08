//===-- NVPTXLowerAlloca.cpp - Make alloca to use local memory =====--===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Handles the address spaces of alloca instructions:
//
// Allocas in ADDRESS_SPACE_LOCAL are rewritten to allocas in
// ADDRESS_SPACE_GENERIC followed by an addrspacecast back to
// ADDRESS_SPACE_LOCAL, because ISel only produces generic addresses for
// allocas (see lowerLocalAllocaToGeneric). This is required for correctness
// and runs at every optimization level.
//
// With optimizations enabled, generic allocas additionally get a pair of
// casts to expose the local address space to InferAddressSpaces:
//
//   %A = alloca i32
//   store i32 0, i32* %A ; emits st.u32
//
// will be transformed to
//
//   %A = alloca i32
//   %Local = addrspacecast i32* %A to i32 addrspace(5)*
//   %Generic = addrspacecast i32 addrspace(5)* %A to i32*
//   store i32 0, i32 addrspace(5)* %Generic ; emits st.local.u32
//
// And we will rely on NVPTXInferAddressSpaces to combine the last two
// instructions.
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/NVPTXBaseInfo.h"
#include "NVPTX.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Type.h"
#include "llvm/Pass.h"

using namespace llvm;

namespace {
class NVPTXLowerAlloca : public FunctionPass {
  bool runOnFunction(Function &F) override;

  // When false, only rewrite allocas in the local address space to generic
  // ones (a correctness requirement, see lowerLocalAllocaToGeneric) and skip
  // the addrspacecast scaffolding that exists to feed InferAddressSpaces,
  // which does not run without optimizations.
  bool ScaffoldForInferAddressSpaces;

public:
  static char ID; // Pass identification, replacement for typeid
  NVPTXLowerAlloca(bool ScaffoldForInferAddressSpaces = true)
      : FunctionPass(ID),
        ScaffoldForInferAddressSpaces(ScaffoldForInferAddressSpaces) {}
  StringRef getPassName() const override {
    return "convert address space of alloca'ed memory to local";
  }
};
} // namespace

char NVPTXLowerAlloca::ID = 1;

INITIALIZE_PASS(NVPTXLowerAlloca, "nvptx-lower-alloca", "Lower Alloca", false,
                false)

// =============================================================================
// Main function for this pass.
// =============================================================================
// Rewrite an alloca in ADDRESS_SPACE_LOCAL to an alloca in
// ADDRESS_SPACE_GENERIC followed by an addrspacecast back to
// ADDRESS_SPACE_LOCAL. ISel only produces generic addresses for allocas: a
// static alloca becomes an address relative to %SP (the depot's generic
// address), and a dynamic alloca is the result of the PTX alloca instruction
// wrapped in cvta.local. An alloca whose value is typed addrspace(5) would
// feed those generic addresses directly into ld.local/st.local, which would
// access the wrong memory. The addrspacecast (cvta.to.local) recovers the
// local address for the existing users.
static void lowerLocalAllocaToGeneric(AllocaInst *Alloca) {
  auto *NewAlloca = new AllocaInst(
      Alloca->getAllocatedType(), ADDRESS_SPACE_GENERIC, Alloca->getArraySize(),
      Alloca->getAlign(), "", Alloca->getIterator());
  NewAlloca->copyMetadata(*Alloca);
  auto *CastToLocal = new AddrSpaceCastInst(NewAlloca, Alloca->getType(),
                                            Alloca->getName() + ".local",
                                            Alloca->getIterator());
  // Lifetime intrinsics must be applied to the alloca itself, not the cast;
  // move them over to the new alloca before replacing the remaining uses.
  for (Use &U : llvm::make_early_inc_range(Alloca->uses())) {
    auto *II = dyn_cast<IntrinsicInst>(U.getUser());
    if (II && II->isLifetimeStartOrEnd()) {
      IRBuilder<> Builder(II);
      if (II->getIntrinsicID() == Intrinsic::lifetime_start)
        Builder.CreateLifetimeStart(NewAlloca);
      else
        Builder.CreateLifetimeEnd(NewAlloca);
      II->eraseFromParent();
    }
  }
  Alloca->replaceAllUsesWith(CastToLocal);
  NewAlloca->takeName(Alloca);
  Alloca->eraseFromParent();
}

bool NVPTXLowerAlloca::runOnFunction(Function &F) {
  // Rewriting local-AS allocas is required for correctness, so it is not
  // subject to skipFunction.
  const bool Scaffold = ScaffoldForInferAddressSpaces && !skipFunction(F);

  SmallVector<AllocaInst *, 16> Allocas;
  for (auto &BB : F)
    for (auto &I : BB)
      if (auto *Alloca = dyn_cast<AllocaInst>(&I)) {
        assert((Alloca->getAddressSpace() == ADDRESS_SPACE_GENERIC ||
                Alloca->getAddressSpace() == ADDRESS_SPACE_LOCAL) &&
               "AllocaInst can only be in Generic or Local address space for "
               "NVPTX.");
        if (Scaffold || Alloca->getAddressSpace() == ADDRESS_SPACE_LOCAL)
          Allocas.push_back(Alloca);
      }

  bool Changed = false;
  for (AllocaInst *allocaInst : Allocas) {
    if (allocaInst->getAddressSpace() == ADDRESS_SPACE_LOCAL) {
      lowerLocalAllocaToGeneric(allocaInst);
      Changed = true;
      continue;
    }

    Changed = true;

    // We need to make sure that LLVM has info that alloca needs to go to
    // ADDRESS_SPACE_LOCAL for InferAddressSpace pass.
    //
    // We add addrspacecast to ADDRESS_SPACE_LOCAL and back to
    // ADDRESS_SPACE_GENERIC, so that the alloca's users still use a generic
    // pointer to operate on.
    auto ASCastToLocalAS = new AddrSpaceCastInst(
        allocaInst,
        PointerType::get(allocaInst->getContext(), ADDRESS_SPACE_LOCAL), "");
    ASCastToLocalAS->insertAfter(allocaInst->getIterator());

    auto AllocaInGenericAS = new AddrSpaceCastInst(
        ASCastToLocalAS,
        PointerType::get(allocaInst->getContext(), ADDRESS_SPACE_GENERIC), "");
    AllocaInGenericAS->insertAfter(ASCastToLocalAS->getIterator());

    for (Use &AllocaUse : llvm::make_early_inc_range(allocaInst->uses())) {
      // Check Load, Store, GEP, and BitCast Uses on alloca and make them
      // use the converted generic address, in order to expose non-generic
      // addrspacecast to NVPTXInferAddressSpaces. For other types
      // of instructions this is unnecessary and may introduce redundant
      // address cast.
      auto LI = dyn_cast<LoadInst>(AllocaUse.getUser());
      if (LI && LI->getPointerOperand() == allocaInst && !LI->isVolatile()) {
        LI->setOperand(LI->getPointerOperandIndex(), AllocaInGenericAS);
        continue;
      }
      auto SI = dyn_cast<StoreInst>(AllocaUse.getUser());
      if (SI && SI->getPointerOperand() == allocaInst && !SI->isVolatile()) {
        SI->setOperand(SI->getPointerOperandIndex(), AllocaInGenericAS);
        continue;
      }
      auto GI = dyn_cast<GetElementPtrInst>(AllocaUse.getUser());
      if (GI && GI->getPointerOperand() == allocaInst) {
        GI->setOperand(GI->getPointerOperandIndex(), AllocaInGenericAS);
        continue;
      }
      auto BI = dyn_cast<BitCastInst>(AllocaUse.getUser());
      if (BI && BI->getOperand(0) == allocaInst) {
        BI->setOperand(0, AllocaInGenericAS);
        continue;
      }
    }
  }
  return Changed;
}

FunctionPass *
llvm::createNVPTXLowerAllocaPass(bool ScaffoldForInferAddressSpaces) {
  return new NVPTXLowerAlloca(ScaffoldForInferAddressSpaces);
}
