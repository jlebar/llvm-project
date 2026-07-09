//===-- NVPTXAtomicLower.cpp - Lower atomics of local memory ----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
//  Lower atomics of local memory to simple load/stores
//
//===----------------------------------------------------------------------===//

#include "NVPTXAtomicLower.h"
#include "NVPTX.h"
#include "llvm/CodeGen/StackProtector.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Transforms/Utils/LowerAtomic.h"

#include "MCTargetDesc/NVPTXBaseInfo.h"
using namespace llvm;

namespace {
// Hoisting the alloca instructions in the non-entry blocks to the entry
// block.
class NVPTXAtomicLower : public FunctionPass {
public:
  static char ID; // Pass ID
  NVPTXAtomicLower() : FunctionPass(ID) {}

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.setPreservesCFG();
  }

  StringRef getPassName() const override {
    return "NVPTX lower atomics of local memory";
  }

  bool runOnFunction(Function &F) override;
};
} // namespace

bool NVPTXAtomicLower::runOnFunction(Function &F) {
  bool Changed = false;
  for (Instruction &I : make_early_inc_range(instructions(F))) {
    if (auto *RMWI = dyn_cast<AtomicRMWInst>(&I)) {
      if (RMWI->getPointerAddressSpace() == ADDRESS_SPACE_LOCAL)
        Changed |= lowerAtomicRMWInst(RMWI);
    } else if (auto *CXI = dyn_cast<AtomicCmpXchgInst>(&I)) {
      if (CXI->getPointerAddressSpace() == ADDRESS_SPACE_LOCAL)
        Changed |= lowerAtomicCmpXchgInst(CXI);
    }
  }
  return Changed;
}

char NVPTXAtomicLower::ID = 0;

INITIALIZE_PASS(NVPTXAtomicLower, "nvptx-atomic-lower",
                "Lower atomics of local memory to simple load/stores", false,
                false)

FunctionPass *llvm::createNVPTXAtomicLowerPass() {
  return new NVPTXAtomicLower();
}
