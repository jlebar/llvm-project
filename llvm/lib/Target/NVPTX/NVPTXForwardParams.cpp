//- NVPTXForwardParams.cpp - NVPTX Forward Device Params Removing Local Copy -//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// PTX supports 2 methods of accessing device function parameters:
//
//   - "simple" case: A load that addresses the parameter symbol at a constant
//     offset may read the parameter directly via the ".param" address space.
//     This is not possible if the parameter is stored to or has its address
//     taken. This method is preferable when possible. Ex:
//
//            ld.param.u32    %r1, [foo_param_1];
//            ld.param.u32    %r2, [foo_param_1+4];
//
//   - "move param" case: For more complex cases the address of the param may be
//     placed in a register via a "mov" instruction. This "mov" also implicitly
//     moves the param to the ".local" address space and allows for it to be
//     written to. This essentially defers the responsibilty of the byval copy
//     to the PTX calling convention.
//
//            mov.b64         %rd1, foo_param_0;
//            st.local.u32    [%rd1], 42;
//            add.u64         %rd3, %rd1, %rd2;
//            ld.local.u32    %r2, [%rd3];
//
// In NVPTXLowerArgs and SelectionDAG, we pessimistically assume that all
// parameters will use the "move param" case and the local address space. This
// pass is responsible for switching to the "simple" case when possible, as it
// is more efficient.
//
// We do this by traversing the uses of the param "mov" instructions and
// checking that the parameter is only ever loaded from (possibly through
// address arithmetic and address-space casts). If so, every load that
// addresses the parameter at a constant offset is rewritten into an ld.param.
// Loads whose offset is not a compile-time constant cannot be expressed as
// ld.param for device function parameters and keep using the address produced
// by the "mov"; only for those does the local copy remain.
//
//===----------------------------------------------------------------------===//

#include "NVPTX.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/CodeGen/MachineOperand.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

/// Traverse a use of a MOV_PARAM-derived address. Returns false if the
/// parameter may be stored to or have its address escape, in which case none
/// of its loads may be forwarded to the param space. Loads that address the
/// parameter at a constant offset (\p IsDirectAddr) are collected in
/// \p DirectLoads; they can be rewritten into ld.param. The visited address
/// computation instructions are collected in \p AddrInsts, users before defs.
static bool traverseMoveUse(MachineInstr &U, const MachineRegisterInfo &MRI,
                            bool IsDirectAddr,
                            SmallVectorImpl<MachineInstr *> &AddrInsts,
                            SmallVectorImpl<MachineInstr *> &DirectLoads,
                            SmallPtrSetImpl<const MachineInstr *> &Visited) {
  if (!Visited.insert(&U).second)
    return true;

  switch (U.getOpcode()) {
  case NVPTX::LD_i16:
  case NVPTX::LD_i32:
  case NVPTX::LD_i64:
  case NVPTX::LDV_i16_v2:
  case NVPTX::LDV_i16_v4:
  case NVPTX::LDV_i32_v2:
  case NVPTX::LDV_i32_v4:
  case NVPTX::LDV_i64_v2:
  case NVPTX::LDV_i64_v4: {
    if (IsDirectAddr)
      DirectLoads.push_back(&U);
    return true;
  }
  case NVPTX::ADD32ri:
  case NVPTX::ADD64ri:
  case NVPTX::ADD32rr:
  case NVPTX::ADD64rr:
    // Pointer arithmetic. Loads reached through it still only read the
    // parameter, but cannot be rewritten to ld.param since they don't address
    // the parameter symbol at an immediate offset. (ISel folds constant GEPs
    // into the load's immediate, so the ri forms rarely feed a load's base.)
    IsDirectAddr = false;
    [[fallthrough]];
  case NVPTX::cvta_local:
  case NVPTX::cvta_local_64:
  case NVPTX::cvta_to_local:
  case NVPTX::cvta_to_local_64: {
    for (auto &U2 : MRI.use_instructions(U.operands_begin()->getReg()))
      if (!traverseMoveUse(U2, MRI, IsDirectAddr, AddrInsts, DirectLoads,
                           Visited))
        return false;

    AddrInsts.push_back(&U);
    return true;
  }
  default:
    return false;
  }
}

static bool forwardParamLoads(MachineInstr &Mov,
                              const MachineRegisterInfo &MRI) {
  SmallVector<MachineInstr *, 16> AddrInsts;
  SmallVector<MachineInstr *, 16> DirectLoads;
  SmallPtrSet<const MachineInstr *, 16> Visited;

  for (auto &U : MRI.use_instructions(Mov.operands_begin()->getReg()))
    if (!traverseMoveUse(U, MRI, /*IsDirectAddr=*/true, AddrInsts, DirectLoads,
                         Visited))
      return false;

  const MachineOperand *ParamSymbol = Mov.uses().begin();
  assert(ParamSymbol->isSymbol());

  for (auto *LI : DirectLoads) {
    LI->getOperand(
          NVPTX::getNamedOperandIdx(LI->getOpcode(), NVPTX::OpName::addr))
        .ChangeToES(ParamSymbol->getSymbolName());
    LI->getOperand(
          NVPTX::getNamedOperandIdx(LI->getOpcode(), NVPTX::OpName::addsp))
        .ChangeToImmediate(NVPTX::AddressSpace::DeviceParam);
  }

  // Rewriting the loads removed their uses of the address computation
  // instructions, so some of those may now be dead. AddrInsts is ordered users
  // before defs (with the mov, the ultimate def, appended last), so a single
  // forward sweep erases the transitively dead ones. Instructions still
  // feeding non-forwardable loads are kept.
  AddrInsts.push_back(&Mov);
  bool Removed = false;
  for (MachineInstr *MI : AddrInsts)
    if (MRI.use_empty(MI->operands_begin()->getReg())) {
      MI->eraseFromParent();
      Removed = true;
    }
  return !DirectLoads.empty() || Removed;
}

static bool forwardDeviceParams(MachineFunction &MF) {
  const auto &MRI = MF.getRegInfo();

  // Collect the movs first; forwardParamLoads may erase instructions.
  SmallVector<MachineInstr *, 16> Movs;
  for (auto &MI : *MF.begin())
    if (MI.getOpcode() == NVPTX::MOV32_PARAM ||
        MI.getOpcode() == NVPTX::MOV64_PARAM)
      Movs.push_back(&MI);

  bool Changed = false;
  for (auto *Mov : Movs)
    Changed |= forwardParamLoads(*Mov, MRI);
  return Changed;
}

/// ----------------------------------------------------------------------------
///                       Pass (Manager) Boilerplate
/// ----------------------------------------------------------------------------

namespace {
struct NVPTXForwardParamsPass : public MachineFunctionPass {
  static char ID;
  NVPTXForwardParamsPass() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    MachineFunctionPass::getAnalysisUsage(AU);
  }
};
} // namespace

char NVPTXForwardParamsPass::ID = 0;

INITIALIZE_PASS(NVPTXForwardParamsPass, "nvptx-forward-params",
                "NVPTX Forward Params", false, false)

bool NVPTXForwardParamsPass::runOnMachineFunction(MachineFunction &MF) {
  return forwardDeviceParams(MF);
}

MachineFunctionPass *llvm::createNVPTXForwardParamsPass() {
  return new NVPTXForwardParamsPass();
}
