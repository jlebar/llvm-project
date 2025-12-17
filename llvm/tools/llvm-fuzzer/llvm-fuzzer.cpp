//===- llvm-fuzzer.cpp - Differential fuzzer for LLVM opts (InstCombine) -===//
//
// Builds random single-basic-block functions with i32 binary operations,
// returns a struct of sampled values, runs InstCombine, and compares
// interpreter outputs before and after the pass. On a mismatch the IR is
// printed.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/GenericValue.h"
#include "llvm/ExecutionEngine/Interpreter.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/NoFolder.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/Transforms/InstCombine/InstCombine.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/Local.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <deque>
#include <memory>
#include <random>
#include <string>
#include <utility>
#include <vector>

#undef DEBUG_TYPE
#define DEBUG_TYPE "fuzzer"

using namespace llvm;

// Provided by libfuzzer
extern "C" size_t LLVMFuzzerMutate(uint8_t *Data, size_t Size, size_t MaxSize);

namespace {

template <typename T, typename... Ts>
auto chooseValueImpl(size_t Index, T &&First, Ts &&...Rest) {
  if (Index == 0)
    return std::forward<T>(First);
  if constexpr (sizeof...(Rest) > 0)
    return chooseValueImpl(Index - 1, std::forward<Ts>(Rest)...);
  else
    llvm_unreachable("No values to choose from");
}

template <typename... Ts>
auto chooseValue(std::minstd_rand &Gen, Ts &&...Values) {
  return chooseValueImpl(Gen() % sizeof...(Values),
                         std::forward<Ts>(Values)...);
}

template <typename Func, typename... Funcs>
auto chooseFnImpl(size_t Index, Func &&First, Funcs &&...Rest) {
  if (Index == 0)
    return std::forward<Func>(First)();
  if constexpr (sizeof...(Rest) > 0)
    return chooseFnImpl(Index - 1, std::forward<Funcs>(Rest)...);
  else
    llvm_unreachable("No functions to choose from");
}

// Calls one of the given functions based on a random choice, and returns the
// result.  The functions must take no arguments and return a value of the same
// type.
template <typename... Functions>
auto chooseFn(std::minstd_rand &Gen, Functions &&...Fns) {
  return chooseFnImpl(Gen() % sizeof...(Fns), std::forward<Functions>(Fns)...);
}

template <typename VectorT>
auto chooseElem(std::minstd_rand &Gen, VectorT &&Vec) {
  assert(!Vec.empty());
  return Vec[Gen() % Vec.size()];
}

Type *chooseIntegerType(std::minstd_rand &Gen, LLVMContext &Ctx) {
  return chooseFn(
      Gen, [&] { return Type::getInt1Ty(Ctx); },
      [&] { return Type::getInt8Ty(Ctx); },
      [&] { return Type::getInt16Ty(Ctx); },
      [&] { return Type::getInt32Ty(Ctx); },
      [&] { return Type::getInt64Ty(Ctx); },
      // Include i33 so we exercise non-power-of-two bitwidths.
      [&] { return Type::getIntNTy(Ctx, 33); });
}

Type *chooseFpTy(std::minstd_rand &Gen, LLVMContext &Ctx) {
  return chooseFn(
      Gen, [&] { return Type::getFloatTy(Ctx); },
      [&] { return Type::getDoubleTy(Ctx); });
}

Value *canonicalizeFP(IRBuilder<NoFolder> &B, Value *V) {
  if (!V->getType()->isFloatingPointTy())
    return V;
  if (auto *Call = dyn_cast<CallInst>(V)) {
    if (Call->getIntrinsicID() == Intrinsic::canonicalize)
      return V;
  }
  return B.CreateUnaryIntrinsic(Intrinsic::canonicalize, V);
}

void canonicalizeFPToInt(Module &M) {
  for (Function &F : M) {
    for (BasicBlock &BB : F) {
      for (Instruction &I : BB) {
        auto *BC = dyn_cast<BitCastInst>(&I);
        if (!BC || !BC->getType()->isIntegerTy() ||
            !BC->getOperand(0)->getType()->isFloatingPointTy())
          continue;
        IRBuilder<NoFolder> B(&I);
        BC->setOperand(0, canonicalizeFP(B, BC->getOperand(0)));
      }
    }
  }
}

void canonicalizeCopysignSign(Module &M) {
  for (Function &F : M) {
    for (BasicBlock &BB : F) {
      for (Instruction &I : BB) {
        auto *Call = dyn_cast<CallInst>(&I);
        if (!Call)
          continue;
        if (Call->getIntrinsicID() != Intrinsic::copysign)
          continue;
        Value *Sign = Call->getArgOperand(1);
        if (!Sign->getType()->isFloatingPointTy())
          continue;
        IRBuilder<NoFolder> B(&I);
        Call->setArgOperand(1, canonicalizeFP(B, Sign));
      }
    }
  }
}

std::string argGlobalName(unsigned Index) {
  return "arg" + std::to_string(Index);
}

std::unique_ptr<Module> createSkeletonModule(LLVMContext &Ctx) {
  auto M = std::make_unique<Module>("llvm-fuzzer", Ctx);
  M->setTargetTriple(Triple(sys::getDefaultTargetTriple()));

  // Arguments to the function.
  SmallVector<Type *, 8> ArgTys;
  for (unsigned I = 0; I < 2; ++I)
    ArgTys.push_back(Type::getInt32Ty(Ctx));
  for (unsigned I = 0; I < 2; ++I)
    ArgTys.push_back(Type::getInt64Ty(Ctx));
  for (unsigned I = 0; I < 2; ++I)
    ArgTys.push_back(Type::getFloatTy(Ctx));
  for (unsigned I = 0; I < 2; ++I)
    ArgTys.push_back(Type::getDoubleTy(Ctx));

  // Parameters to the function.  We store these as global variables so they're
  // serialized in the bitcode.
  for (unsigned I = 0; I < ArgTys.size(); ++I) {
    Type *Ty = ArgTys[I];
    new GlobalVariable(*M, Ty, /*isConstant=*/true,
                       GlobalValue::InternalLinkage, Constant::getNullValue(Ty),
                       argGlobalName(I));
  }

  Type *RetTy = Type::getInt64Ty(Ctx);
  FunctionType *FnTy = FunctionType::get(RetTy, ArgTys, /*isVarArg=*/false);
  Function *F = Function::Create(FnTy, Function::ExternalLinkage, "f", *M);
  BasicBlock *Entry = BasicBlock::Create(Ctx, "entry", F);
  IRBuilder<NoFolder> B(Entry);
  B.CreateRet(Constant::getNullValue(RetTy));
  return M;
}

// Parses bitcode from the given buffer.  If the buffer is empty, we return a
// skeleton module that has a single function "f" that returns 0.
std::unique_ptr<Module> parseBitcode(const uint8_t *Data, size_t Size,
                                     LLVMContext &Ctx) {
  if (Size == 0)
    return createSkeletonModule(Ctx);
  StringRef Buffer(reinterpret_cast<const char *>(Data), Size);
  MemoryBufferRef MemBuf(Buffer, "llvm-fuzzer-bitcode");
  Expected<std::unique_ptr<Module>> MOrErr = parseBitcodeFile(MemBuf, Ctx);
  if (!MOrErr) {
    std::string Msg = toString(MOrErr.takeError());
    LLVM_DEBUG(dbgs() << "Failed to parse bitcode: " << Msg << "\n");
    return createSkeletonModule(Ctx);
  }
  return std::move(*MOrErr);
}

struct ExecutionResult {
  std::vector<APInt> Returns;
  std::vector<GenericValue::ValueState> States;
  std::string Error;
  bool HitUB = false;
};

void applyInstCombine(Module &M) {
  PassBuilder PB;
  LoopAnalysisManager LAM;
  FunctionAnalysisManager FAM;
  CGSCCAnalysisManager CGAM;
  ModuleAnalysisManager MAM;

  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  FunctionPassManager FPM;
  FPM.addPass(InstCombinePass());

  ModulePassManager MPM;
  MPM.addPass(createModuleToFunctionPassAdaptor(std::move(FPM)));
  MPM.run(M, MAM);
}

bool containsFreeze(const Module &M) {
  for (const Function &F : M) {
    for (const BasicBlock &BB : F) {
      for (const Instruction &I : BB) {
        if (isa<FreezeInst>(&I))
          return true;
      }
    }
  }
  return false;
}

// Choose a constant, using the old value as a hint to the fuzzer, if the old
// value is available and is itself a constant.
Constant *chooseConstant(std::minstd_rand &Gen, Type *Ty,
                         Value *OldValue = nullptr, bool AllowPoison = true) {
  // 1/64 chance of choosing poison
  // 63/64 chance of choosing a constant
  // (These proportions were chosen arbitrarily.)
  //
  // Note we can't choose undef, for basically the same reason we can't fuzz
  // programs which contain freeze.  Consider the following program:
  //   x = undef;
  //   y = and x, 1;
  //   z = or y, 1;
  //
  // In this case, z must equal 1.  Essentially, using x inside `and x, 1`
  // freezes it (and also sets all but the lowest bit to 0).  Running this in
  // the interpreter would require the interpreter to implement symbolic
  // execution, which is not practical for fuzzing.
  //
  // Thankfully if we don't introduce undef as a constant, it's unlikely
  // (impossible?) that we'll get undef as an intermediate result.
  if (AllowPoison && Gen() % 64 == 0)
    return PoisonValue::get(Ty);

  if (auto *ITy = dyn_cast<IntegerType>(Ty)) {
    unsigned NBits = ITy->getBitWidth();
    if (NBits == 1) {
      return ConstantInt::get(Ty, chooseValue(Gen, false, true));
    }

    assert(NBits <= 64);
    unsigned NBytes = (NBits + 7) / 8;

    uint64_t NewConstant = chooseFn(
        Gen,
        [&]() -> uint64_t { // Value in [0,64]
          // You'd think the fuzzer would do this itself because we're using
          // LLVMFuzzerMutate, but based on coverage data, it doesn't seem to.
          return Gen() % 65;
        },
        [&] { // e.g. 000111
          uint64_t Mask = NBits < 64 ? (1ULL << NBits) - 1 : -1ULL;
          unsigned Shift = Gen() % NBits;
          if (Shift < NBits)
            return Mask >> Shift;
          return 0ULL;
        },
        [&] { // e.g. 00011000
          uint64_t Mask = NBits < 64 ? (1ULL << NBits) - 1 : -1ULL;
          unsigned ShiftDown = Gen() % NBits;
          unsigned ShiftUp = Gen() % NBits;
          if (ShiftDown < NBits)
            Mask >>= ShiftDown;
          else
            Mask = 0ULL;
          if (ShiftUp < NBits)
            Mask <<= ShiftUp;
          else
            Mask = 0ULL;
          Mask &= (NBits < 64 ? (1ULL << NBits) - 1 : -1ULL);
          return Mask;
        },
        [&] { // arbitrary value
          uint64_t OldConstant = [&] {
            if (auto *C = dyn_cast_or_null<ConstantInt>(OldValue))
              return htonll(C->getValue().getZExtValue());
            return 0ULL;
          }();
          unsigned NewSize = LLVMFuzzerMutate(
              reinterpret_cast<uint8_t *>(&OldConstant), NBytes, NBytes);

          uint64_t Mask = NewSize < 64 ? (1ULL << NewSize) - 1 : -1ULL;
          return ntohll(OldConstant) & Mask;
        });
    return ConstantInt::get(ITy, APInt(NBits, NewConstant));
  }

  if (Ty->isFloatingPointTy()) {
    auto &Sem = Ty->getFltSemantics();
    APFloat OldConstant = [&] {
      if (OldValue) {
        if (auto *C = dyn_cast<ConstantFP>(OldValue))
          return C->getValue();
      }
      return APFloat(Sem);
    }();
    APFloat NewConstant = chooseFn(
        Gen, [&] { return APFloat::getInf(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getNaN(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getZero(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getOne(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getInf(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getLargest(Sem, /*Negative=*/Gen() % 2); },
        [&] { return APFloat::getSmallest(Sem, /*Negative=*/Gen() % 2); },
        [&] {
          return APFloat::getSmallestNormalized(Sem, /*Negative=*/Gen() % 2);
        },
        [&] {
          uint64_t Bits = htonll(OldConstant.bitcastToAPInt().getZExtValue());
          size_t NewSize = LLVMFuzzerMutate(reinterpret_cast<uint8_t *>(&Bits),
                                            sizeof(Bits), sizeof(Bits));
          if (NewSize < sizeof(Bits))
            Bits &= (1ULL << NewSize * 8) - 1;
          if (APFloat::getSizeInBits(Sem) < sizeof(Bits) * 8)
            Bits &= (1ULL << APFloat::getSizeInBits(Sem)) - 1;
          Bits = ntohll(Bits);

          // XXX: Confirm this actually bitcasts `Bits` into an APFloat?
          return APFloat(Sem, Bits);
        });

    if (NewConstant.isNaN())
      NewConstant = NewConstant.makeQuiet();
    return ConstantFP::get(Ty, NewConstant);
  }

  return Constant::getNullValue(Ty);
}

// OldValue is optional.  If it's a constant value, we ask the fuzzer to mutate
// the constant value, instead of choosing a new one arbitrarily.
Value *chooseOper(std::minstd_rand &Gen, Instruction *Instr, Type *Ty,
                  Value *OldValue = nullptr) {
  Function &F = *Instr->getParent()->getParent();
  BasicBlock &BB = *Instr->getParent();
  SmallVector<Value *, 32> Candidates;
  // A null value means "choose a random constant".
  Candidates.push_back(nullptr);
  for (Argument &Arg : F.args()) {
    Value *V = &Arg;
    if (V->getType() == Ty)
      Candidates.push_back(V);
  }

  for (auto It = BB.begin(); It != Instr->getIterator(); ++It) {
    if (It->getType() == Ty)
      Candidates.push_back(&*It);
  }
  Value *NewOper = chooseElem(Gen, Candidates);
  if (NewOper) {
    return NewOper;
  }

  return chooseConstant(Gen, Ty, OldValue);
}

// Change an operand of an instruction.
void mutateModifyOperand(Function &F, std::minstd_rand &Gen) {
  BasicBlock &BB = F.getEntryBlock();
  Instruction *Instr = &*std::next(BB.begin(), Gen() % BB.size());
  if (Instr->getNumOperands() == 0)
    return;

  unsigned OperIdx = Gen() % Instr->getNumOperands();
  // Don't change the last operand (the callee) of a call instruction.  Also,
  // ensure immargs of call instructions are constants.
  if (auto *CB = dyn_cast<CallBase>(Instr)) {
    if (OperIdx == CB->arg_size())
      return;
    if (CB->paramHasAttr(OperIdx, Attribute::ImmArg)) {
      Value *OldVal = Instr->getOperand(OperIdx);
      Instr->setOperand(OperIdx, chooseConstant(Gen, OldVal->getType(), OldVal,
                                                /*allowPoison=*/false));
      RecursivelyDeleteTriviallyDeadInstructions(OldVal);
      return;
    }
  }

  Value *OldOper = Instr->getOperand(OperIdx);
  LLVM_DEBUG(dbgs() << "Mutating operand " << OperIdx << " of " << *Instr
                    << "\n";);
  Instr->setOperand(OperIdx,
                    chooseOper(Gen, Instr, OldOper->getType(), OldOper));
  RecursivelyDeleteTriviallyDeadInstructions(OldOper);
}

Value *mutateAddIntInstr(std::minstd_rand &Gen, Instruction *TargetInstr,
                         Type *Ty) {
  assert(Ty->isIntegerTy());

  LLVMContext &Ctx = TargetInstr->getContext();
  IRBuilder<NoFolder> B(TargetInstr);
  return chooseFn(
      Gen,
      [&] { // integer binary op
        auto Opc =
            chooseValue(Gen, Instruction::Add, Instruction::Sub,
                        Instruction::Mul, Instruction::UDiv, Instruction::SDiv,
                        Instruction::URem, Instruction::SRem, Instruction::Shl,
                        Instruction::LShr, Instruction::AShr, Instruction::And,
                        Instruction::Or, Instruction::Xor);
        return B.CreateBinOp(Opc, chooseOper(Gen, TargetInstr, Ty),
                             chooseOper(Gen, TargetInstr, Ty));
      },
      [&]() -> Value * { // integer intrinsic
        Value *Oper = chooseOper(Gen, TargetInstr, Ty);
        return chooseFn(
            Gen,
            [&]() -> Value * { // unary intrinsic
              auto IID =
                  chooseValue(Gen, Intrinsic::ctpop, Intrinsic::bitreverse);
              return B.CreateUnaryIntrinsic(IID, Oper);
            },
            [&]() -> Value * { // bswap
              if (Ty->getIntegerBitWidth() % 16 != 0)
                return nullptr;
              return B.CreateUnaryIntrinsic(Intrinsic::bswap, Oper);
            },
            [&]() -> Value * {
              ConstantInt *MinIsPoison = ConstantInt::get(
                  Type::getInt1Ty(Ctx), chooseValue(Gen, 0, 1));
              return B.CreateIntrinsic(Intrinsic::abs, {Ty},
                                       {Oper, MinIsPoison});
            },
            [&]() { // binary intrinsic
              auto ID = chooseValue(
                  Gen, Intrinsic::sadd_sat, Intrinsic::uadd_sat,
                  Intrinsic::ssub_sat, Intrinsic::usub_sat, Intrinsic::smin,
                  Intrinsic::smax, Intrinsic::umin, Intrinsic::umax);
              return B.CreateBinaryIntrinsic(ID, Oper,
                                             chooseOper(Gen, TargetInstr, Ty));
            },
            [&]() { // ctlz / cttz
              auto IID = chooseValue(Gen, Intrinsic::ctlz, Intrinsic::cttz);
              // ZeroIsPoison must be a constant.
              ConstantInt *ZeroIsPoison = ConstantInt::get(
                  Type::getInt1Ty(Ctx), chooseValue(Gen, 0, 1));
              return B.CreateBinaryIntrinsic(IID, Oper, ZeroIsPoison);
            },
            [&]() -> Value * { // fshl / fshr
              auto ID = chooseValue(Gen, Intrinsic::fshl, Intrinsic::fshr);
              Value *X = Oper;
              Value *Y = chooseOper(Gen, TargetInstr, Ty);
              Value *Z = chooseOper(Gen, TargetInstr, Ty);
              return B.CreateIntrinsic(ID, {Ty}, {X, Y, Z});
            },
            // XXX These cause problems in the interpreter; it tries to
            // constant-fold it but can't because it returns a tuple type.  For
            // now, just skip them.
            /*[&]() -> Value * { // foo_with_overflow
              auto ID = chooseValue(
                  Gen, Intrinsic::sadd_with_overflow,
                  Intrinsic::uadd_with_overflow, Intrinsic::ssub_with_overflow,
                  Intrinsic::usub_with_overflow, Intrinsic::smul_with_overflow,
                  Intrinsic::umul_with_overflow);
              Value *LHS = Oper;
              Value *RHS = chooseOper(Gen, OldInstr, OperTy);
              Value *Call = B.CreateBinaryIntrinsic(ID, LHS, RHS);
              Value *Res1 = B.CreateExtractValue(Call, 0);
              Value *Res2 = B.CreateZExt(B.CreateExtractValue(Call, 1), OperTy);
              return chooseValue(Gen, Res1, Res2);
            },*/
            [&]() -> Value * { // sext / zext / trunc
              Type *SrcTy = chooseIntegerType(Gen, Ctx);
              if (SrcTy != Ty) {
                return chooseFn(
                    Gen,
                    [&] {
                      return B.CreateSExtOrTrunc(
                          chooseOper(Gen, TargetInstr, SrcTy), Ty);
                    },
                    [&] {
                      return B.CreateZExtOrTrunc(
                          chooseOper(Gen, TargetInstr, SrcTy), Ty);
                    });
              }
              return nullptr;
            },
            [&]() -> Value * { // icmp
              if (Ty != Type::getInt1Ty(Ctx))
                return nullptr;

              using Pred = CmpInst::Predicate;
              auto NumPredicates =
                  Pred::LAST_ICMP_PREDICATE - Pred::FIRST_ICMP_PREDICATE + 1;
              Pred P = static_cast<Pred>(Pred::FIRST_ICMP_PREDICATE +
                                         Gen() % NumPredicates);
              Type *Ty = chooseIntegerType(Gen, Ctx);
              return B.CreateICmp(P, chooseOper(Gen, TargetInstr, Ty),
                                  chooseOper(Gen, TargetInstr, Ty));
            },
            // fcmp is an "integer instruction", because it returns i1.
            [&]() -> Value * { // fcmp
              if (Ty != Type::getInt1Ty(Ctx))
                return nullptr;

              using Pred = CmpInst::Predicate;
              auto NumPredicates =
                  Pred::LAST_FCMP_PREDICATE - Pred::FIRST_FCMP_PREDICATE + 1;
              Pred P = static_cast<Pred>(Pred::FIRST_FCMP_PREDICATE +
                                         Gen() % NumPredicates);
              Type *Ty = chooseFpTy(Gen, Ctx);
              return B.CreateFCmp(P, chooseOper(Gen, TargetInstr, Ty),
                                  chooseOper(Gen, TargetInstr, Ty));
            },
            [&]() -> Value * { // fptoui / fptosi
              Type *SrcTy;
              if (Ty == Type::getInt32Ty(Ctx))
                SrcTy = Type::getFloatTy(Ctx);
              else if (Ty == Type::getInt64Ty(Ctx))
                SrcTy = Type::getDoubleTy(Ctx);
              else
                return nullptr;
              return chooseFn(
                  Gen,
                  [&] {
                    return B.CreateFPToUI(chooseOper(Gen, TargetInstr, SrcTy),
                                          Ty);
                  },
                  [&] {
                    return B.CreateFPToSI(chooseOper(Gen, TargetInstr, SrcTy),
                                          Ty);
                  });
            },
            [&]() -> Value * { // bitcast float to int
              Type *SrcTy;
              if (Ty == Type::getInt32Ty(Ctx))
                SrcTy = Type::getFloatTy(Ctx);
              else if (Ty == Type::getInt64Ty(Ctx))
                SrcTy = Type::getDoubleTy(Ctx);
              else
                return nullptr;
              return B.CreateBitCast(chooseOper(Gen, TargetInstr, SrcTy), Ty);
            },
            [&] { // select
              return B.CreateSelect(
                  chooseOper(Gen, TargetInstr, Type::getInt1Ty(Ctx)),
                  chooseOper(Gen, TargetInstr, Ty),
                  chooseOper(Gen, TargetInstr, Ty));
            });
      });
}

Value *mutateAddFpInstr(std::minstd_rand &Gen, Instruction *TargetInstr,
                        Type *Ty) {
  assert(Ty->isFloatingPointTy());
  LLVMContext &Ctx = TargetInstr->getContext();
  IRBuilder<NoFolder> B(TargetInstr);
  return chooseFn(
      Gen,
      [&] { // floating point binary op
        auto Opc = chooseValue(Gen, Instruction::FAdd, Instruction::FSub,
                               Instruction::FMul, Instruction::FDiv,
                               Instruction::FRem);
        return B.CreateBinOp(Opc, chooseOper(Gen, TargetInstr, Ty),
                             chooseOper(Gen, TargetInstr, Ty));
      },
      [&]() -> Value * { // fneg
        return B.CreateFNeg(chooseOper(Gen, TargetInstr, Ty));
      },
      [&]() -> Value * { // fabs / round
        auto ID =
            chooseValue(Gen, Intrinsic::fabs, Intrinsic::floor, Intrinsic::ceil,
                        Intrinsic::trunc, Intrinsic::round,
                        Intrinsic::nearbyint, Intrinsic::rint);
        return B.CreateUnaryIntrinsic(ID, chooseOper(Gen, TargetInstr, Ty));
      },
      [&]() -> Value * { // copysign / min / max
        auto ID = chooseValue(Gen, Intrinsic::copysign, Intrinsic::minnum,
                              Intrinsic::maxnum, Intrinsic::minimum,
                              Intrinsic::maximum);
        return B.CreateBinaryIntrinsic(ID, chooseOper(Gen, TargetInstr, Ty),
                                       chooseOper(Gen, TargetInstr, Ty));
      },
      [&]() -> Value * { // fma
        Value *A = chooseOper(Gen, TargetInstr, Ty);
        Value *BVal = chooseOper(Gen, TargetInstr, Ty);
        Value *CVal = chooseOper(Gen, TargetInstr, Ty);
        return B.CreateIntrinsic(Intrinsic::fma, {Ty}, {A, BVal, CVal});
      },
      [&]() -> Value * { // fptrunc / fpext
        Type *SrcTy = chooseFpTy(Gen, Ctx);
        auto SrcSize = SrcTy->getPrimitiveSizeInBits();
        auto TySize = Ty->getPrimitiveSizeInBits();
        if (SrcSize < TySize)
          return B.CreateFPExt(chooseOper(Gen, TargetInstr, SrcTy), Ty);
        if (SrcSize > TySize)
          return B.CreateFPTrunc(chooseOper(Gen, TargetInstr, SrcTy), Ty);
        return nullptr;
      },
      [&]() -> Value * { // uitofp / sitofp
        Type *SrcTy;
        if (Ty == Type::getFloatTy(Ctx))
          SrcTy = Type::getInt32Ty(Ctx);
        else if (Ty == Type::getDoubleTy(Ctx))
          SrcTy = Type::getInt64Ty(Ctx);
        else
          return nullptr;

        return chooseFn(
            Gen,
            [&] {
              return B.CreateUIToFP(chooseOper(Gen, TargetInstr, SrcTy), Ty);
            },
            [&] {
              return B.CreateSIToFP(chooseOper(Gen, TargetInstr, SrcTy), Ty);
            });
      },
            [&]() -> Value * { // bitcast int to float
              Type *SrcTy;
              if (Ty == Type::getFloatTy(Ctx))
                SrcTy = Type::getInt32Ty(Ctx);
              else if (Ty == Type::getDoubleTy(Ctx))
                SrcTy = Type::getInt64Ty(Ctx);
              else
                return nullptr;
              Value *BC =
                  B.CreateBitCast(chooseOper(Gen, TargetInstr, SrcTy), Ty);
              return B.CreateUnaryIntrinsic(Intrinsic::canonicalize, BC);
            },
      [&] { // select
        return B.CreateSelect(
            chooseOper(Gen, TargetInstr, Type::getInt1Ty(Ctx)),
            chooseOper(Gen, TargetInstr, Ty), chooseOper(Gen, TargetInstr, Ty));
      });
}

void mutateAddInstruction(Function &F, std::minstd_rand &Gen) {
  // Choose a random operand of a random instruction.  We'll add a new
  // instruction right before it, feeding it into the operand.
  BasicBlock &BB = F.getEntryBlock();
  Instruction *TargetInstr = &*std::next(BB.begin(), Gen() % BB.size());
  unsigned TargetOperIdx = Gen() % TargetInstr->getNumOperands();
  Value *TargetOper = TargetInstr->getOperand(TargetOperIdx);
  Type *Ty = TargetOper->getType();

  // Don't change immargs of call instructions.
  if (auto *CB = dyn_cast<CallBase>(TargetInstr)) {
    if (TargetOperIdx < CB->arg_size() &&
        CB->paramHasAttr(TargetOperIdx, Attribute::ImmArg))
      return;
  }

  Value *NewInstr = [&]() -> Value * {
    if (Ty->isIntegerTy())
      return mutateAddIntInstr(Gen, TargetInstr, Ty);
    if (Ty->isFloatingPointTy())
      return mutateAddFpInstr(Gen, TargetInstr, Ty);
    return nullptr;
  }();

  if (NewInstr) {
    TargetInstr->setOperand(TargetOperIdx, NewInstr);
    RecursivelyDeleteTriviallyDeadInstructions(TargetOper);
  }
}

// Remove an instruction, replacing it with 0.
void mutateRemoveInstruction(Function &F, std::minstd_rand &Gen) {
  BasicBlock &BB = F.getEntryBlock();
  if (BB.size() <= 1)
    return;
  Instruction *Instr = &*std::next(BB.begin(), Gen() % (BB.size() - 1));
  Instr->replaceAllUsesWith(Constant::getNullValue(Instr->getType()));
  RecursivelyDeleteTriviallyDeadInstructions(Instr);
}

void mutateModifyArgValue(Module &M, Function &F, std::minstd_rand &Gen) {
  if (F.arg_empty())
    return;

  unsigned Index = Gen() % F.arg_size();
  GlobalVariable *G =
      M.getGlobalVariable(argGlobalName(Index), /*AllowInternal=*/true);
  assert(G && "Missing arg global");

  G->setInitializer(
      chooseConstant(Gen, G->getValueType(), G->getInitializer()));
}

// Modify the flags of a random instruction (e.g. add nsw).
void mutateModifyInstructionFlags(Function &F, std::minstd_rand &Gen) {
  BasicBlock &BB = F.getEntryBlock();

  auto HasFlags = [&](Instruction &I) {
    switch (I.getOpcode()) {
    case Instruction::Add:  // nsw nuw
    case Instruction::Sub:  // nsw nuw
    case Instruction::Mul:  // nsw nuw
    case Instruction::Shl:  // nuw nsw
    case Instruction::UDiv: // exact
    case Instruction::SDiv: // exact
    case Instruction::LShr: // exact
    case Instruction::AShr: // exact
    case Instruction::Or:   // disjoint
      return true;
    default:
      return false;
    };
  };

  SmallVector<Instruction *, 32> Candidates;
  for (Instruction &I : BB) {
    if (HasFlags(I))
      Candidates.push_back(&I);
  }
  if (Candidates.empty())
    return;

  Instruction &I = *Candidates[Gen() % Candidates.size()];
  switch (I.getOpcode()) {
  case Instruction::Add:
  case Instruction::Sub:
  case Instruction::Mul:
  case Instruction::Shl: {
    chooseFn(
        Gen, [&] { I.setHasNoUnsignedWrap(!I.hasNoUnsignedWrap()); },
        [&] { I.setHasNoSignedWrap(!I.hasNoSignedWrap()); });
    break;
  }
  case Instruction::UDiv:
  case Instruction::SDiv:
  case Instruction::LShr:
  case Instruction::AShr: {
    I.setIsExact(!I.isExact());
    break;
  }
  case Instruction::Or: {
    auto *OrOp = cast<PossiblyDisjointInst>(&I);
    OrOp->setIsDisjoint(!OrOp->isDisjoint());
    break;
  }
  default:
    llvm_unreachable("Unsupported instruction opcode");
    break;
  }
}

void mutateModifyReturnType(Function &F, std::minstd_rand &Gen) {
  // For simplicity, we don't actualy change the return type of the function.
  // Just choose a new operand and bitcast it to i64, the return type of `f`.
  LLVMContext &Ctx = F.getContext();
  Type *NewTy = chooseElem(
      Gen,
      std::array<Type *, 6>({Type::getInt8Ty(Ctx), Type::getInt16Ty(Ctx),
                             Type::getInt32Ty(Ctx), Type::getInt64Ty(Ctx),
                             Type::getFloatTy(Ctx), Type::getDoubleTy(Ctx)}));
  IRBuilder<NoFolder> B(F.getEntryBlock().getTerminator());
  Value *NewRetVal = chooseOper(Gen, F.getEntryBlock().getTerminator(), NewTy);

  // Can't use CreateZExtOrBitCast to cast from e.g. f32 to i64; have to cast
  // f32 -> i32 first.
  if (NewTy->isFloatingPointTy()) {
    NewRetVal = B.CreateBitCast(
        NewRetVal, Type::getIntNTy(Ctx, NewTy->getPrimitiveSizeInBits()));
  }

  NewRetVal = B.CreateZExtOrBitCast(NewRetVal, F.getReturnType());
  B.CreateRet(NewRetVal);

  Instruction *OldRet = F.getEntryBlock().getTerminator();
  Value* OldRetVal = OldRet->getOperand(0);
  OldRet->eraseFromParent();
  RecursivelyDeleteTriviallyDeadInstructions(OldRetVal);
}

void mutateModule(Module &M, std::minstd_rand &Gen) {
  Function *F = M.getFunction("f");

  // Choose NumMutations distributed as 1 + exp(1/32).
  unsigned NumMutations = 1 + [&] {
    unsigned Choice = Gen();
    if (Choice == 0)
      return 32;
    return __builtin_clz(Choice);
  }();

  for (unsigned I = 0; I < NumMutations; ++I) {
    chooseFn(
        Gen, [&] { mutateAddInstruction(*F, Gen); },
        [&] { mutateRemoveInstruction(*F, Gen); },
        [&] { mutateModifyOperand(*F, Gen); },
        [&] { mutateModifyArgValue(M, *F, Gen); },
        [&] { mutateModifyInstructionFlags(*F, Gen); },
        [&] { mutateModifyReturnType(*F, Gen); });
  }
}

bool buildArgsForCall(Function &Fn, std::vector<GenericValue> &Args,
                      std::vector<APInt> &PrintableArgs, std::string &Error) {
  Args.clear();
  PrintableArgs.clear();
  Module *M = Fn.getParent();
  unsigned Index = 0;
  for (Argument &Arg : Fn.args()) {
    Type *Ty = Arg.getType();
    GlobalVariable *G =
        M->getGlobalVariable(argGlobalName(Index), /*AllowInternal=*/true);
    if (!G || !G->isConstant() || G->getValueType() != Ty ||
        !G->hasInitializer()) {
      Error = "Missing arg global";
      return false;
    }
    GenericValue GV;
    if (auto *Init = dyn_cast<ConstantInt>(G->getInitializer())) {
      GV.IntVal = Init->getValue();
      Args.push_back(GV);
      PrintableArgs.push_back(GV.IntVal);
    } else if (auto *Init = dyn_cast<ConstantFP>(G->getInitializer())) {
      APFloat Val = Init->getValue();
      if (Ty->isFloatTy())
        GV.FloatVal = Val.convertToFloat();
      else if (Ty->isDoubleTy())
        GV.DoubleVal = Val.convertToDouble();
      else {
        Error = "Unsupported floating arg type";
        return false;
      }
      Args.push_back(GV);
      PrintableArgs.push_back(Val.bitcastToAPInt());
    } else {
      Error = "Unsupported arg initializer";
      return false;
    }
    ++Index;
  }
  return true;
}

ExecutionResult runModule(std::unique_ptr<Module> M,
                          ArrayRef<GenericValue> Args) {
  ExecutionResult R;
  Module *RawM = M.get();
  if (verifyModule(*RawM, &errs())) {
    R.Error = "Module failed verification";
    return R;
  }

  std::string ErrorStr;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&ErrorStr);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  if (!EE) {
    R.Error = ErrorStr;
    return R;
  }

  Function *Fn = RawM->getFunction("f");
  if (!Fn || Fn->isDeclaration()) {
    R.Error = "Missing function 'f'";
    return R;
  }

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(Fn, Args);
  if (EE->hasTrappedUB()) {
    R.HitUB = true;
    return R;
  }
  Type *RetTy = Fn->getReturnType();
  assert(RetTy->isIntegerTy() && "Unsupported return type");
  R.Returns.push_back(RetGV.IntVal);
  R.States.push_back(RetGV.State);
  return R;
}

bool compareAndReport(const std::vector<APInt> &Args,
                      const ExecutionResult &Before,
                      const ExecutionResult &After, const Module &Original,
                      const Module &Optimized) {
  if (Before.HitUB)
    return true;
  if (After.HitUB) {
    errs() << "=== MISMATCH (UB after InstCombine) ===\n";
    errs() << "Args: ";
    for (auto Arg : Args) {
      SmallString<32> S;
      Arg.toString(S, 10, /*Signed=*/true);
      errs() << S << " ";
    }
    errs() << "\n";
    errs() << "\nOriginal module\n";
    Original.print(errs(), nullptr);
    errs() << "\nAfter InstCombine\n";
    Optimized.print(errs(), nullptr);
    return false;
  }
  if (!Before.Error.empty() || !After.Error.empty()) {
    errs() << "Failed to execute\n";
    if (!Before.Error.empty())
      errs() << "  Before: " << Before.Error << "\n";
    if (!After.Error.empty())
      errs() << "  After: " << After.Error << "\n";
    errs() << "\nOriginal module\n";
    Original.print(errs(), nullptr);
    errs() << "\nAfter InstCombine\n";
    Optimized.print(errs(), nullptr);
    return false;
  }

  bool Mismatch = false;
  for (unsigned I = 0; I < Before.Returns.size(); ++I) {
    auto BeforeState = Before.States[I];
    auto AfterState = After.States[I];
    if (BeforeState == GenericValue::ValueState::Poison)
      continue;
    if (AfterState != GenericValue::ValueState::Concrete ||
        Before.Returns[I] != After.Returns[I]) {
      Mismatch = true;
      break;
    }
  }
  if (!Mismatch)
    return true;

  errs() << "=== MISMATCH ===\n";
  errs() << "Args: ";
  for (auto Arg : Args) {
    SmallString<32> S;
    Arg.toString(S, 10, /*Signed=*/true);
    errs() << S << " ";
  }

  // XXX: Just return the GenericValue's instead of these parallel vectors?
  // We know the types of the return values so we can read the GenericValues
  // correctly.
  errs() << "\nReturns: ";
  for (auto [I, V] : llvm::enumerate(Before.Returns)) {
    switch (Before.States[I]) {
    case GenericValue::ValueState::Poison:
      errs() << "poison ";
      break;
    case GenericValue::ValueState::Concrete: {
      SmallString<32> S;
      V.toString(S, 10, /*Signed=*/true);
      errs() << S << " ";
    } break;
    }
  }

  errs() << "\nOptimized returns: ";
  for (auto [I, V] : llvm::enumerate(After.Returns)) {
    switch (After.States[I]) {
    case GenericValue::ValueState::Poison:
      errs() << "poison ";
      break;
    case GenericValue::ValueState::Concrete: {
      SmallString<32> S;
      V.toString(S, 10, /*Signed=*/true);
      errs() << S << " ";
    } break;
    }
  }
  errs() << "\n";

  errs() << "\nOriginal module\n";
  Original.print(errs(), nullptr);
  errs() << "\nAfter InstCombine\n";
  Optimized.print(errs(), nullptr);
  return false;
}

} // namespace

extern "C" size_t LLVMFuzzerCustomMutator(uint8_t *Data, size_t Size,
                                          size_t MaxSize, unsigned int Seed) {
  LLVMContext Ctx;
  auto M = parseBitcode(Data, Size, Ctx);
  if (verifyModule(*M, &errs())) {
    LLVM_DEBUG(
        dbgs() << "Failed to verify original module; swapping in skeleton\n");
    M = createSkeletonModule(Ctx);
  }

  std::minstd_rand Gen(Seed);
  LLVM_DEBUG({
    dbgs() << "Before mutation:\n";
    M->print(dbgs(), nullptr);
    dbgs() << "\n";
  });
  mutateModule(*M, Gen);
  LLVM_DEBUG({
    dbgs() << "After mutation:\n";
    M->print(dbgs(), nullptr);
    dbgs() << "\n";
  });

  if (verifyModule(*M, &errs())) {
    errs() << "\nFailed to verify module after mutation\n";
    errs() << "After mutation\n";
    M->print(errs(), nullptr);
    llvm_unreachable("Failed to verify module after mutation");
  }

  SmallVector<char, 0> Out;
  raw_svector_ostream OS(Out);
  WriteBitcodeToFile(*M, OS);

  if (Out.size() > MaxSize)
    return 0;

  std::memcpy(Data, Out.data(), Out.size());
  return Out.size();
}

// Create a new module by merging part of Data2 into Data1.
//
//   1. Call Data1 "Base" and Data2 "Other".
//   2. Pick an arbitrary instruction operand Oper in Base.
//   3. Pick an arbitrary instruction I in Other that has the same type as Oper.
//   4. Replace Oper with I.
//   5. Add all dependencies of I to Base, forming a new module, which we
//      return.
//
// Also cross over the args of the functions.
extern "C" size_t LLVMFuzzerCustomCrossOver(const uint8_t *Data1, size_t Size1,
                                            const uint8_t *Data2, size_t Size2,
                                            uint8_t *Out, size_t MaxOutSize,
                                            unsigned int Seed) {
  assert(Size1 <= MaxOutSize);
  assert(Size2 <= MaxOutSize);

  std::minstd_rand Gen(Seed);
  LLVMContext Ctx;
  auto Base = parseBitcode(Data1, Size1, Ctx);
  auto Other = parseBitcode(Data2, Size2, Ctx);
  LLVM_DEBUG({
    dbgs() << "Crossing over modules:\n";
    dbgs() << "Base:\n";
    Base->print(dbgs(), nullptr);
    dbgs() << "Other:\n";
    Other->print(dbgs(), nullptr);
    dbgs() << "\n";
  });

  Function *BaseF = Base->getFunction("f");
  Function *OtherF = Other->getFunction("f");
  if (!BaseF || BaseF->isDeclaration() || !OtherF || OtherF->isDeclaration())
    return 0;

  DenseMap<
      Type *,
      std::pair<
          std::vector<std::pair<Instruction *, unsigned>> /*Operand in Base*/,
          std::vector<Instruction *> /*Instruction in Other*/>>
      Candidates;

  for (Instruction &I : BaseF->getEntryBlock()) {
    for (unsigned OperIdx = 0; OperIdx < I.getNumOperands(); ++OperIdx) {
      auto *Oper = I.getOperand(OperIdx);

      // Don't cross over the callee argument of call instructions; leave it
      // as-is.  Also, don't cross over immargs of call instructions; leave
      // them as constants.
      if (auto *CB = dyn_cast<CallBase>(&I)) {
        if (OperIdx == CB->arg_size())
          continue;
        if (CB->paramHasAttr(OperIdx, Attribute::ImmArg))
          continue;
      }

      Candidates[Oper->getType()].first.emplace_back(&I, OperIdx);
    }
  }
  for (Instruction &I : OtherF->getEntryBlock()) {
    if (!I.getType()->isVoidTy())
      Candidates[I.getType()].second.push_back(&I);
  }

  // Choose a random type that has at least one candidate operand and
  // instruction.  Then choose a random operand and instruction that have that
  // type.
  SmallVector<Type *, 8> CandidateTypes;
  for (auto [Ty, Candidates] : Candidates) {
    if (!Candidates.first.empty() && !Candidates.second.empty())
      CandidateTypes.push_back(Ty);
  }
  if (CandidateTypes.empty()) {
    errs() << "Crossover failed, no values of matching types found\n";
    return 0;
  }

  Type *TargetTy = chooseElem(Gen, CandidateTypes);
  auto [BaseI, BaseOperIdx] = chooseElem(Gen, Candidates[TargetTy].first);
  auto *OtherI = chooseElem(Gen, Candidates[TargetTy].second);
  LLVM_DEBUG(dbgs() << "Crossover will replace operand " << BaseOperIdx
                    << " of " << *BaseI << " with " << *OtherI << "\n";);

  // Collect all transitive dependencies of `OtherI` and add them to `Merged`
  // right before `BaseI`, in the same order as they appear in `Other`.
  DenseSet<Instruction *> Deps;
  SmallVector<Instruction *, 8> Worklist;
  Worklist.push_back(OtherI);
  while (!Worklist.empty()) {
    Instruction *I = Worklist.pop_back_val();
    Deps.insert(I);
    for (Value *Op : I->operands()) {
      if (auto *OpI = dyn_cast<Instruction>(Op))
        Worklist.push_back(OpI);
    }
  }
  SmallVector<Instruction *, 8> ToAdd;
  for (Instruction &I : OtherF->getEntryBlock()) {
    if (!Deps.count(&I))
      continue;
    ToAdd.push_back(&I);

    // Clear users of I that will not be moved into Base.
    for (auto &Use : I.uses()) {
      if (!Deps.count(dyn_cast<Instruction>(Use.getUser())))
        Use.set(Constant::getNullValue(I.getType()));
    }
  }

  for (Instruction *I : ToAdd) {
    I->removeFromParent();
    I->insertBefore(BaseI->getIterator());

    // If I uses any args from OtherF, change them to point to the
    // corresponding args from BaseF.  Also redirect function calls.
    for (unsigned OpIdx = 0; OpIdx < I->getNumOperands(); ++OpIdx) {
      if (auto *OpArg = dyn_cast<Argument>(I->getOperand(OpIdx))) {
        I->setOperand(OpIdx, BaseF->getArg(OpArg->getArgNo()));
      } else if (auto *OldFn = dyn_cast<Function>(I->getOperand(OpIdx))) {
        assert(OldFn->isIntrinsic());

        // Clone the intrinsic function declaration from Other into Base.
        SmallVector<Type *, 8> ArgTys;
        for (Argument &A : OldFn->args())
          ArgTys.push_back(A.getType());
        auto *NewFn = Intrinsic::getOrInsertDeclaration(
            Base.get(), OldFn->getIntrinsicID(), OldFn->getReturnType(),
            ArgTys);

        I->setOperand(OpIdx, NewFn);
      }
    }
  }
  Value *OldOper = BaseI->getOperand(BaseOperIdx);
  BaseI->setOperand(BaseOperIdx, OtherI);
  RecursivelyDeleteTriviallyDeadInstructions(OldOper);

  for (unsigned ArgIdx = 0; ArgIdx < BaseF->arg_size(); ++ArgIdx) {
    if (Gen() % 2 == 0) {
      auto *BaseG = Base->getGlobalVariable(argGlobalName(ArgIdx),
                                            /*AllowInternal=*/true);
      auto *OtherG = Other->getGlobalVariable(argGlobalName(ArgIdx),
                                              /*AllowInternal=*/true);
      if (!BaseG || !OtherG || !OtherG->hasInitializer())
        continue;
      BaseG->setInitializer(OtherG->getInitializer());
    }
  }

  LLVM_DEBUG({
    dbgs() << "After crossing over:\n";
    Base->print(dbgs(), nullptr);
    dbgs() << "\n";
  });

  if (verifyModule(*Base, &errs())) {
    errs() << "\nFailed to verify merged module\n";
    Base->print(errs(), nullptr);
    llvm_unreachable("Failed to verify merged module");
  }

  SmallVector<char, 0> Buffer;
  raw_svector_ostream OS(Buffer);
  WriteBitcodeToFile(*Base, OS);
  if (Buffer.size() > MaxOutSize)
    return 0;
  std::memcpy(Out, Buffer.data(), Buffer.size());
  return Buffer.size();
}

extern "C" LLVM_ATTRIBUTE_USED int LLVMFuzzerInitialize(int *Argc,
                                                        char ***Argv) {
  static std::unique_ptr<InitLLVM> X;
  SmallVector<const char *, 8> Filtered;
  if (*Argc > 0)
    Filtered.push_back((*Argv)[0]);
  for (int I = 1; I < *Argc; ++I) {
    StringRef Arg((*Argv)[I]);
    if (Arg.starts_with("-debug"))
      Filtered.push_back((*Argv)[I]);
  }
  if (Filtered.size() > 1) {
    cl::ParseCommandLineOptions(
        static_cast<int>(Filtered.size()), Filtered.data(),
        "LLVM differential fuzzer (InstCombine for now)\n");
  }
  return 0;
}

extern "C" LLVM_ATTRIBUTE_USED int LLVMFuzzerTestOneInput(const uint8_t *Data,
                                                          size_t Size) {
  LLVMContext Ctx;
  auto Original = parseBitcode(Data, Size, Ctx);
  canonicalizeFPToInt(*Original);
  canonicalizeCopysignSign(*Original);
  LLVM_DEBUG({
    dbgs() << "Original module\n";
    Original->print(errs(), nullptr);
  });

  std::unique_ptr<Module> Optimized = CloneModule(*Original);
  applyInstCombine(*Optimized);

  // The interpreter can't handle freeze ops when we model poison/UB. In fact
  // I think it's *impossible* to handle freeze in this mode except by doing
  // symbolic execution (i.e. keeping track of "value X must be the sum of Y
  // and Z" and then shoving it all into a SAT solver).
  if (containsFreeze(*Optimized))
    return 0;

  LLVM_DEBUG({
    dbgs() << "After InstCombine\n";
    Optimized->print(dbgs(), nullptr);
  });

  std::unique_ptr<Module> OriginalForPrint = CloneModule(*Original);
  std::unique_ptr<Module> OptimizedForPrint = CloneModule(*Optimized);

  Function *Fn = Original->getFunction("f");
  assert(Fn && !Fn->isDeclaration());

  std::vector<GenericValue> Args;
  std::vector<APInt> PrintableArgs;
  std::string ArgError;
  if (!buildArgsForCall(*Fn, Args, PrintableArgs, ArgError))
    return 0;

  ExecutionResult Before = runModule(std::move(Original), Args);
  ExecutionResult After = runModule(std::move(Optimized), Args);
  if (!compareAndReport(PrintableArgs, Before, After, *OriginalForPrint,
                        *OptimizedForPrint)) {
    abort();
  }

  return 0;
}
