// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn -target-cpu gfx1201 -verify %s -fcuda-is-device
// RUN: %clang_cc1 -fsyntax-only -triple x86_64 -aux-triple amdgcn -aux-target-cpu gfx1201 -verify=host %s

// In the host pass of a HIP compile the device builtins are checked against
// the host feature map; the dpp_ctrl diagnostics must be deferred so that
// encodings that are valid on the device target are not rejected here.
// host-no-diagnostics

#define __global__ __attribute__((global))

__global__ void test(int *p) {
  p[0] = __builtin_amdgcn_update_dpp(p[0], p[1], 272, 0xf, 0xf, 1); // expected-error {{invalid dpp_ctrl value 272}}
  p[1] = __builtin_amdgcn_mov_dpp(p[1], 0x150, 0xf, 0xf, 0); // row_share:0, valid on gfx12
  p[2] = __builtin_amdgcn_mov_dpp(p[2], 0x142, 0xf, 0xf, 0); // row_bcast:15, expected-error {{dpp_ctrl value 322 is not supported on this target}}
  p[3] = __builtin_amdgcn_mov_dpp(p[3], (__int128)1 << 100, 0xf, 0xf, 0); // expected-error {{invalid dpp_ctrl value 1267650600228229401496703205376}}
}

template <int Ctrl> __global__ void ktempl(int *p) {
  p[0] = __builtin_amdgcn_update_dpp(p[0], p[1], Ctrl, 0xf, 0xf, 1); // expected-error {{invalid dpp_ctrl value 272}}
}

template __global__ void ktempl<272>(int *); // expected-note {{in instantiation of function template specialization 'ktempl<272>' requested here}}
