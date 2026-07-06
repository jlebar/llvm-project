// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -triple spirv64-amd-amdhsa -fcuda-is-device -verify %s

// On arch-generic AMDGCN SPIR-V the concrete subtarget is only known when the
// module is finalized, and clang skips AMDGPU builtin Sema checks entirely
// (CheckTargetBuiltinFunctionCall returns early for spirv64-amd-amdhsa). The
// dpp_ctrl check therefore must not fire here: encodings valid only pre-GFX10
// or only on GFX10+ -- and even reserved values -- are accepted and left to
// the finalizing compile to diagnose. (Values reserved on every subtarget,
// like 0x110 below, could in principle be diagnosed even for generic SPIR-V,
// but that would take a change to the dispatch, not to this check.)
// expected-no-diagnostics

#define __global__ __attribute__((global))

__global__ void test(int *p) {
  if (__builtin_amdgcn_is_invocable(__builtin_amdgcn_update_dpp)) {
    p[0] = __builtin_amdgcn_update_dpp(p[0], p[1], 0x130, 0xf, 0xf, 1); // wave_shl:1, pre-GFX10 only
    p[1] = __builtin_amdgcn_update_dpp(p[0], p[1], 0x142, 0xf, 0xf, 1); // row_bcast:15, pre-GFX10 only
    p[2] = __builtin_amdgcn_update_dpp(p[0], p[1], 0x150, 0xf, 0xf, 1); // row_share:0, GFX90A/GFX10+ only
    p[3] = __builtin_amdgcn_update_dpp(p[0], p[1], 0x110, 0xf, 0xf, 1); // reserved on every subtarget
  }
  if (__builtin_amdgcn_is_invocable(__builtin_amdgcn_mov_dpp)) {
    p[4] = __builtin_amdgcn_mov_dpp(p[4], 0x143, 0xf, 0xf, 0); // row_bcast:31, pre-GFX10 only
    p[5] = __builtin_amdgcn_mov_dpp(p[5], 0x160, 0xf, 0xf, 0); // row_xmask:0, GFX10+ only
  }
}
