// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-- -target-cpu fiji -verify=expected,pregfx10,noxmask %s
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-- -target-cpu gfx90a -verify=expected,gfx90a,noxmask %s
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-- -target-cpu gfx1010 -verify=expected,gfx10 %s
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-- -target-cpu gfx1100 -verify=expected,gfx10 %s
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-- -target-cpu gfx1201 -verify=expected,gfx10 %s

// The check keys off the gfx10-insts feature bit as a proxy for the encoding
// tables, so several GFX10+ generations run to pin that the proxy holds on
// each of them.

void test_reserved_everywhere(global int* out, int a)
{
  *out = __builtin_amdgcn_mov_dpp(a, 0x100, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 256}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x110, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 272}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x120, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 288}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x131, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 305}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x13F, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 319}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x144, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 324}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x14F, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 335}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x170, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 368}}
  *out = __builtin_amdgcn_mov_dpp(a, -1, 0xf, 0xf, false);    // expected-error {{invalid dpp_ctrl value -1}}
  *out = __builtin_amdgcn_update_dpp(a, a, 0x110, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 272}}
  *out = __builtin_amdgcn_update_dpp(a, a, 0x1000, 0xf, 0xf, false); // expected-error {{invalid dpp_ctrl value 4096}}
}

void test_valid_everywhere(global int* out, int a)
{
  *out = __builtin_amdgcn_mov_dpp(a, 0x000, 0xf, 0xf, false); // quad_perm([0,0,0,0])
  *out = __builtin_amdgcn_mov_dpp(a, 0x0E4, 0xf, 0xf, false); // quad_perm identity
  *out = __builtin_amdgcn_mov_dpp(a, 0x0FF, 0xf, 0xf, false); // quad_perm([3,3,3,3])
  *out = __builtin_amdgcn_mov_dpp(a, 0x101, 0xf, 0xf, false); // row_shl:1
  *out = __builtin_amdgcn_mov_dpp(a, 0x11F, 0xf, 0xf, false); // row_shr:15
  *out = __builtin_amdgcn_mov_dpp(a, 0x12F, 0xf, 0xf, false); // row_ror:15
  *out = __builtin_amdgcn_mov_dpp(a, 0x140, 0xf, 0xf, false); // row_mirror
  *out = __builtin_amdgcn_mov_dpp(a, 0x141, 0xf, 0xf, false); // row_half_mirror
  *out = __builtin_amdgcn_update_dpp(a, a, 0x101, 0xf, 0xf, false); // row_shl:1
}

void test_wave_shifts_and_bcast(global int* out, int a)
{
  *out = __builtin_amdgcn_mov_dpp(a, 0x130, 0xf, 0xf, false); // wave_shl:1, gfx10-error {{dpp_ctrl value 304 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x134, 0xf, 0xf, false); // wave_rol:1, gfx10-error {{dpp_ctrl value 308 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x138, 0xf, 0xf, false); // wave_shr:1, gfx10-error {{dpp_ctrl value 312 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x13C, 0xf, 0xf, false); // wave_ror:1, gfx10-error {{dpp_ctrl value 316 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x142, 0xf, 0xf, false); // row_bcast:15, gfx10-error {{dpp_ctrl value 322 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x143, 0xf, 0xf, false); // row_bcast:31, gfx10-error {{dpp_ctrl value 323 is not supported on this target}}
}

void test_row_share_xmask(global int* out, int a)
{
  *out = __builtin_amdgcn_mov_dpp(a, 0x150, 0xf, 0xf, false); // row_newbcast:0/row_share:0, pregfx10-error {{dpp_ctrl value 336 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x15F, 0xf, 0xf, false); // row_newbcast:15/row_share:15, pregfx10-error {{dpp_ctrl value 351 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x160, 0xf, 0xf, false); // row_xmask:0, noxmask-error {{dpp_ctrl value 352 is not supported on this target}}
  *out = __builtin_amdgcn_mov_dpp(a, 0x16F, 0xf, 0xf, false); // row_xmask:15, noxmask-error {{dpp_ctrl value 367 is not supported on this target}}
}
