//===- ExecutionEngineTest.cpp - Unit tests for ExecutionEngine -----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/STLExtras.h"
#include "llvm/ExecutionEngine/Interpreter.h"
#include "llvm/ExecutionEngine/RTDyldMemoryManager.h"
#include "llvm/ExecutionEngine/GenericValue.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/NoFolder.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/DynamicLibrary.h"
#include "llvm/Support/ManagedStatic.h"
#include "gtest/gtest.h"

using namespace llvm;

namespace {

class ExecutionEngineTest : public testing::Test {
private:
  llvm_shutdown_obj Y; // Call llvm_shutdown() on exit.

protected:
  ExecutionEngineTest() {
    auto Owner = std::make_unique<Module>("<main>", Context);
    M = Owner.get();
    Engine.reset(EngineBuilder(std::move(Owner)).setErrorStr(&Error).create());
  }

  void SetUp() override {
    ASSERT_TRUE(Engine.get() != nullptr) << "EngineBuilder returned error: '"
      << Error << "'";
  }

  GlobalVariable *NewExtGlobal(Type *T, const Twine &Name) {
    return new GlobalVariable(*M, T, false,  // Not constant.
                              GlobalValue::ExternalLinkage, nullptr, Name);
  }

  std::string Error;
  LLVMContext Context;
  Module *M;  // Owned by ExecutionEngine.
  std::unique_ptr<ExecutionEngine> Engine;
};

TEST_F(ExecutionEngineTest, ForwardGlobalMapping) {
  GlobalVariable *G1 = NewExtGlobal(Type::getInt32Ty(Context), "Global1");
  int32_t Mem1 = 3;
  Engine->addGlobalMapping(G1, &Mem1);
  EXPECT_EQ(&Mem1, Engine->getPointerToGlobalIfAvailable(G1));
  EXPECT_EQ(&Mem1, Engine->getPointerToGlobalIfAvailable("Global1"));
  int32_t Mem2 = 4;
  Engine->updateGlobalMapping(G1, &Mem2);
  EXPECT_EQ(&Mem2, Engine->getPointerToGlobalIfAvailable(G1));
  Engine->updateGlobalMapping(G1, nullptr);
  EXPECT_EQ(nullptr, Engine->getPointerToGlobalIfAvailable(G1));
  Engine->updateGlobalMapping(G1, &Mem2);
  EXPECT_EQ(&Mem2, Engine->getPointerToGlobalIfAvailable(G1));

  GlobalVariable *G2 = NewExtGlobal(Type::getInt32Ty(Context), "Global1");
  EXPECT_EQ(nullptr, Engine->getPointerToGlobalIfAvailable(G2))
    << "The NULL return shouldn't depend on having called"
    << " updateGlobalMapping(..., NULL)";
  // Check that update...() can be called before add...().
  Engine->updateGlobalMapping(G2, &Mem1);
  EXPECT_EQ(&Mem1, Engine->getPointerToGlobalIfAvailable(G2));
  EXPECT_EQ(&Mem2, Engine->getPointerToGlobalIfAvailable(G1))
    << "A second mapping shouldn't affect the first.";
}

TEST_F(ExecutionEngineTest, ReverseGlobalMapping) {
  GlobalVariable *G1 = NewExtGlobal(Type::getInt32Ty(Context), "Global1");

  int32_t Mem1 = 3;
  Engine->addGlobalMapping(G1, &Mem1);
  EXPECT_EQ(G1, Engine->getGlobalValueAtAddress(&Mem1));
  int32_t Mem2 = 4;
  Engine->updateGlobalMapping(G1, &Mem2);
  EXPECT_EQ(nullptr, Engine->getGlobalValueAtAddress(&Mem1));
  EXPECT_EQ(G1, Engine->getGlobalValueAtAddress(&Mem2));

  GlobalVariable *G2 = NewExtGlobal(Type::getInt32Ty(Context), "Global2");
  Engine->updateGlobalMapping(G2, &Mem1);
  EXPECT_EQ(G2, Engine->getGlobalValueAtAddress(&Mem1));
  EXPECT_EQ(G1, Engine->getGlobalValueAtAddress(&Mem2));
  Engine->updateGlobalMapping(G1, nullptr);
  EXPECT_EQ(G2, Engine->getGlobalValueAtAddress(&Mem1))
    << "Removing one mapping doesn't affect a different one.";
  EXPECT_EQ(nullptr, Engine->getGlobalValueAtAddress(&Mem2));
  Engine->updateGlobalMapping(G2, &Mem2);
  EXPECT_EQ(nullptr, Engine->getGlobalValueAtAddress(&Mem1));
  EXPECT_EQ(G2, Engine->getGlobalValueAtAddress(&Mem2))
    << "Once a mapping is removed, we can point another GV at the"
    << " now-free address.";
}

TEST_F(ExecutionEngineTest, ClearModuleMappings) {
  GlobalVariable *G1 = NewExtGlobal(Type::getInt32Ty(Context), "Global1");

  int32_t Mem1 = 3;
  Engine->addGlobalMapping(G1, &Mem1);
  EXPECT_EQ(G1, Engine->getGlobalValueAtAddress(&Mem1));

  Engine->clearGlobalMappingsFromModule(M);

  EXPECT_EQ(nullptr, Engine->getGlobalValueAtAddress(&Mem1));

  GlobalVariable *G2 = NewExtGlobal(Type::getInt32Ty(Context), "Global2");
  // After clearing the module mappings, we can assign a new GV to the
  // same address.
  Engine->addGlobalMapping(G2, &Mem1);
  EXPECT_EQ(G2, Engine->getGlobalValueAtAddress(&Mem1));
}

TEST_F(ExecutionEngineTest, DestructionRemovesGlobalMapping) {
  GlobalVariable *G1 = NewExtGlobal(Type::getInt32Ty(Context), "Global1");
  int32_t Mem1 = 3;
  Engine->addGlobalMapping(G1, &Mem1);
  // Make sure the reverse mapping is enabled.
  EXPECT_EQ(G1, Engine->getGlobalValueAtAddress(&Mem1));
  // When the GV goes away, the ExecutionEngine should remove any
  // mappings that refer to it.
  G1->eraseFromParent();
  EXPECT_EQ(nullptr, Engine->getGlobalValueAtAddress(&Mem1));
}

TEST_F(ExecutionEngineTest, LookupWithMangledAndDemangledSymbol) {
  int x;
  int _x;
  llvm::sys::DynamicLibrary::AddSymbol("x", &x);
  llvm::sys::DynamicLibrary::AddSymbol("_x", &_x);

  // RTDyldMemoryManager::getSymbolAddressInProcess expects a mangled symbol,
  // but DynamicLibrary is a wrapper for dlsym, which expects the unmangled C
  // symbol name. This test verifies that getSymbolAddressInProcess strips the
  // leading '_' on Darwin, but not on other platforms.
#ifdef __APPLE__
  EXPECT_EQ(reinterpret_cast<uint64_t>(&x),
            RTDyldMemoryManager::getSymbolAddressInProcess("_x"));
#else
  EXPECT_EQ(reinterpret_cast<uint64_t>(&_x),
            RTDyldMemoryManager::getSymbolAddressInProcess("_x"));
#endif
}

TEST(ExecutionEngineInterpreterTest, PoisonDivisorTrapsUB) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  FunctionType *FTy = FunctionType::get(Type::getInt64Ty(Context), false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *PoisonDivisor = PoisonValue::get(Type::getInt64Ty(Context));
  Value *Numerator = ConstantInt::get(Type::getInt64Ty(Context), 1);
  Value *Rem = Builder.CreateSRem(Numerator, PoisonDivisor);
  Builder.CreateRet(Rem);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  (void)EE->runFunction(F, {});
  EXPECT_TRUE(EE->hasTrappedUB());
}

TEST(ExecutionEngineInterpreterTest, ExactUDivRemainderIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt8Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *Numerator = ConstantInt::get(Ty, 1);
  Value *Divisor = ConstantInt::get(Ty, 2);
  Value *Div = Builder.CreateUDiv(Numerator, Divisor, "", /*IsExact=*/true);
  Builder.CreateRet(Div);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, ExactSDivPoisonNumeratorIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt64Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *Numerator = PoisonValue::get(Ty);
  Value *Divisor = ConstantInt::get(Ty, 2);
  auto *Div = cast<BinaryOperator>(Builder.CreateSDiv(Numerator, Divisor));
  Div->setIsExact(true);
  Builder.CreateRet(Div);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

static GenericValue runIntrinsicNoArgFunction(Intrinsic::ID ID,
                                              unsigned BitWidth,
                                              bool PoisonOnZero) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getIntNTy(Context, BitWidth);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *Zero = ConstantInt::get(Ty, 0);
  Value *Flag = ConstantInt::get(Type::getInt1Ty(Context), PoisonOnZero);
  Function *Intr = Intrinsic::getOrInsertDeclaration(
      M.get(), ID, Ty, {Ty, Type::getInt1Ty(Context)});
  Value *Res = Builder.CreateCall(Intr, {Zero, Flag});
  Builder.CreateRet(Res);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  EXPECT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  return EE->runFunction(F, {});
}

TEST(ExecutionEngineInterpreterTest, CttzPoisonOnZeroFlagIsPoison) {
  GenericValue RetGV =
      runIntrinsicNoArgFunction(Intrinsic::cttz, 8, /*PoisonOnZero=*/true);
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, CtlzPoisonOnZeroFlagIsPoison) {
  GenericValue RetGV =
      runIntrinsicNoArgFunction(Intrinsic::ctlz, 8, /*PoisonOnZero=*/true);
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, CtlzCttzZeroNoPoisonFlag) {
  GenericValue Ctlz =
      runIntrinsicNoArgFunction(Intrinsic::ctlz, 8, /*PoisonOnZero=*/false);
  EXPECT_EQ(Ctlz.State, GenericValue::ValueState::Concrete);
  EXPECT_EQ(Ctlz.IntVal, APInt(8, 8));

  GenericValue Cttz =
      runIntrinsicNoArgFunction(Intrinsic::cttz, 8, /*PoisonOnZero=*/false);
  EXPECT_EQ(Cttz.State, GenericValue::ValueState::Concrete);
  EXPECT_EQ(Cttz.IntVal, APInt(8, 8));
}

TEST(ExecutionEngineInterpreterTest, ExactLShrNonZeroRemainderIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt8Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *LHS = ConstantInt::get(Ty, 1);
  Value *RHS = ConstantInt::get(Ty, 1);
  auto *Shift = cast<BinaryOperator>(Builder.CreateLShr(LHS, RHS));
  Shift->setIsExact(true);
  Builder.CreateRet(Shift);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, SelectPoisonCondIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt64Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *Cond = PoisonValue::get(Type::getInt1Ty(Context));
  Value *Zero = ConstantInt::get(Ty, 0);
  Value *Sel = Builder.CreateSelect(Cond, Zero, Zero);
  Builder.CreateRet(Sel);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, ShiftPoisonAmountIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt1Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *ValueToShift = ConstantInt::get(Ty, 1);
  Value *ShiftAmount = PoisonValue::get(Ty);
  Value *Shift = Builder.CreateShl(ValueToShift, ShiftAmount);
  Builder.CreateRet(Shift);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, ShiftOutOfRangeIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt8Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *ValueToShift = ConstantInt::get(Ty, 1);
  Value *ShiftAmount = ConstantInt::get(Ty, 8);
  Value *Shift = Builder.CreateShl(ValueToShift, ShiftAmount);
  Builder.CreateRet(Shift);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, DisjointOrOverlapIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt8Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *LHS = ConstantInt::get(Ty, 3);
  Value *RHS = ConstantInt::get(Ty, 1);
  auto *Or = cast<BinaryOperator>(Builder.CreateOr(LHS, RHS));
  cast<PossiblyDisjointInst>(Or)->setIsDisjoint(true);
  Builder.CreateRet(Or);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

TEST(ExecutionEngineInterpreterTest, DisjointOrPoisonOperandIsPoison) {
  LLVMContext Context;
  auto M = std::make_unique<Module>("<main>", Context);
  IRBuilder<NoFolder> Builder(Context);

  Type *Ty = Type::getInt8Ty(Context);
  FunctionType *FTy = FunctionType::get(Ty, false);
  Function *F =
      Function::Create(FTy, GlobalValue::ExternalLinkage, "f", M.get());
  BasicBlock *BB = BasicBlock::Create(Context, "entry", F);
  Builder.SetInsertPoint(BB);

  Value *LHS = PoisonValue::get(Ty);
  Value *RHS = ConstantInt::get(Ty, 1);
  auto *Or = cast<BinaryOperator>(Builder.CreateOr(LHS, RHS));
  cast<PossiblyDisjointInst>(Or)->setIsDisjoint(true);
  Builder.CreateRet(Or);

  std::string Error;
  EngineBuilder EB(std::move(M));
  EB.setErrorStr(&Error);
  EB.setEngineKind(EngineKind::Interpreter);
  EB.setModelPoisonAndUB(true);
  std::unique_ptr<ExecutionEngine> EE(EB.create());
  ASSERT_TRUE(EE != nullptr) << "EngineBuilder returned error: '" << Error
                             << "'";

  EE->resetTrappedUB();
  GenericValue RetGV = EE->runFunction(F, {});
  EXPECT_FALSE(EE->hasTrappedUB());
  EXPECT_EQ(RetGV.State, GenericValue::ValueState::Poison);
}

}
