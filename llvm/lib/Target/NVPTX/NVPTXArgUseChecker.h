//===-- NVPTXArgUseChecker.h - Classify uses of a pointer argument --------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// ArgUseChecker walks all uses of a pointer argument and reports whether the
// pointed-to memory is only ever read and the pointer never escapes. When
// visitArgPtr returns with neither isAborted() (a write through a derived
// pointer) nor isEscaped() (the pointer handed to a call, stored, converted
// to an integer, ...) set, every load from the argument observes the bytes
// the caller passed in. NVPTXLowerArgs uses this to decide whether a byval
// argument can be accessed directly in param space instead of via a local
// copy; NVPTXMarkKernelPtrsGlobal uses it to decide whether pointers loaded
// from a kernel byval argument are still the launch-provided (global) ones.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_NVPTX_NVPTXARGUSECHECKER_H
#define LLVM_LIB_TARGET_NVPTX_NVPTXARGUSECHECKER_H

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Analysis/PtrUseVisitor.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/NVPTXAddrSpace.h"

namespace llvm {
namespace NVPTX {

struct ArgUseChecker : PtrUseVisitor<ArgUseChecker> {
  using Base = PtrUseVisitor<ArgUseChecker>;

  // Set of phi/select instructions using the Arg
  SmallPtrSet<Instruction *, 4> Conditionals;

  ArgUseChecker(const DataLayout &DL) : PtrUseVisitor(DL) {}

  PtrInfo visitArgPtr(Argument &A) {
    assert(A.getType()->isPointerTy());
    IntegerType *IntIdxTy = cast<IntegerType>(DL.getIndexType(A.getType()));
    IsOffsetKnown = false;
    Offset = APInt(IntIdxTy->getBitWidth(), 0);
    PI.reset();

    DEBUG_WITH_TYPE("nvptx-arg-use-checker",
                    dbgs() << "Checking Argument " << A << "\n");
    // Enqueue the uses of this pointer.
    enqueueUsers(A);

    // Visit all the uses off the worklist until it is empty.
    // Note that unlike PtrUseVisitor we intentionally do not track offsets.
    // We're only interested in how we use the pointer.
    while (!(Worklist.empty() || PI.isAborted())) {
      UseToVisit ToVisit = Worklist.pop_back_val();
      U = ToVisit.UseAndIsOffsetKnown.getPointer();
      Instruction *I = cast<Instruction>(U->getUser());
      DEBUG_WITH_TYPE("nvptx-arg-use-checker",
                      dbgs() << "Processing " << *I << "\n");
      Base::visit(I);
    }
    if (PI.isEscaped())
      DEBUG_WITH_TYPE("nvptx-arg-use-checker",
                      dbgs() << "Argument pointer escaped: "
                             << *PI.getEscapingInst() << "\n");
    else if (PI.isAborted())
      DEBUG_WITH_TYPE("nvptx-arg-use-checker",
                      dbgs() << "Pointer use needs a copy: "
                             << *PI.getAbortingInst() << "\n");
    DEBUG_WITH_TYPE("nvptx-arg-use-checker", dbgs() << "Traversed "
                                                    << Conditionals.size()
                                                    << " conditionals\n");
    return PI;
  }

  void visitStoreInst(StoreInst &SI) {
    // Storing the pointer escapes it.
    if (U->get() == SI.getValueOperand())
      return PI.setEscapedAndAborted(&SI);

    PI.setAborted(&SI);
  }

  void visitAddrSpaceCastInst(AddrSpaceCastInst &ASC) {
    // ASC to param space are no-ops and do not need a copy
    if (ASC.getDestAddressSpace() != NVPTXAS::ADDRESS_SPACE_ENTRY_PARAM)
      return PI.setEscapedAndAborted(&ASC);
    Base::visitAddrSpaceCastInst(ASC);
  }

  void visitPHINodeOrSelectInst(Instruction &I) {
    assert(isa<PHINode>(I) || isa<SelectInst>(I));
    enqueueUsers(I);
    Conditionals.insert(&I);
  }
  // PHI and select just pass through the pointers.
  void visitPHINode(PHINode &PN) { visitPHINodeOrSelectInst(PN); }
  void visitSelectInst(SelectInst &SI) { visitPHINodeOrSelectInst(SI); }

  // memcpy/memmove are OK when the pointer is source. We can convert them to
  // AS-specific memcpy.
  void visitMemTransferInst(MemTransferInst &II) {
    if (*U == II.getRawDest())
      PI.setAborted(&II);
  }

  // Atomics write memory through their pointer operand. InstVisitor's default
  // for them is the no-op visitInstruction, which would report the pointed-to
  // memory as never written. Any other use passes the pointer's own value into
  // the instruction (e.g. xchg'ing it into unrelated memory), escaping it.
  void visitAtomicInst(Instruction &I, unsigned PtrOpIdx) {
    if (U->getOperandNo() != PtrOpIdx)
      return PI.setEscapedAndAborted(&I);
    PI.setAborted(&I);
  }
  void visitAtomicRMWInst(AtomicRMWInst &I) {
    visitAtomicInst(I, AtomicRMWInst::getPointerOperandIndex());
  }
  void visitAtomicCmpXchgInst(AtomicCmpXchgInst &I) {
    visitAtomicInst(I, AtomicCmpXchgInst::getPointerOperandIndex());
  }

  void visitMemSetInst(MemSetInst &II) { PI.setAborted(&II); }
}; // struct ArgUseChecker

} // namespace NVPTX
} // namespace llvm

#endif // LLVM_LIB_TARGET_NVPTX_NVPTXARGUSECHECKER_H
