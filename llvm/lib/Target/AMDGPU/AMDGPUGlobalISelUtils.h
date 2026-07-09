//===- AMDGPUGlobalISelUtils -------------------------------------*- C++ -*-==//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_AMDGPU_AMDGPUGLOBALISELUTILS_H
#define LLVM_LIB_TARGET_AMDGPU_AMDGPUGLOBALISELUTILS_H

#include "llvm/ADT/DenseSet.h"
#include "llvm/CodeGen/Register.h"
#include <utility>

namespace llvm {

class MachineRegisterInfo;
class GCNSubtarget;
class GISelValueTracking;
class LLT;
class MachineFunction;
class MachineIRBuilder;
class RegisterBankInfo;

namespace AMDGPU {

/// Returns base register and constant offset.
std::pair<Register, unsigned>
getBaseWithConstantOffset(MachineRegisterInfo &MRI, Register Reg,
                          GISelValueTracking *ValueTracking = nullptr,
                          bool CheckNUW = false);

// Currently finds S32/S64 lane masks that can be declared as divergent by
// uniformity analysis (all are phis at the moment).
// These are defined as i32/i64 in some IR intrinsics (not as i1).
// Tablegen forces(via telling that lane mask IR intrinsics are uniform) most of
// S32/S64 lane masks to be uniform, as this results in them ending up with sgpr
// reg class after instruction-select, don't search for all of them.
class IntrinsicLaneMaskAnalyzer {
  SmallDenseSet<Register, 8> S32S64LaneMask;
  MachineRegisterInfo &MRI;

public:
  IntrinsicLaneMaskAnalyzer(MachineFunction &MF);
  bool isS32S64LaneMask(Register Reg) const;

private:
  void initLaneMaskIntrinsics(MachineFunction &MF);
};

/// Whether \p Reg is defined by a COPY with an implicit use of exec, the
/// pattern DivergenceLowering uses to mark a temporal-divergence value: one
/// computed uniformly inside a cycle but read on a divergent path out of it.
/// Such a value is divergent at the point of use even though uniformity
/// analysis reports its def as uniform, and it lives in a vgpr.
bool isTemporalDivergenceCopy(Register Reg, const MachineRegisterInfo &MRI);

void buildReadAnyLane(MachineIRBuilder &B, Register SgprDst, Register VgprSrc,
                      const RegisterBankInfo &RBI);
void buildReadFirstLane(MachineIRBuilder &B, Register SgprDst, Register VgprSrc,
                        const RegisterBankInfo &RBI);
}
}

#endif
