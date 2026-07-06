// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn -target-cpu gfx1030 -verify %s -fcuda-is-device
// RUN: %clang_cc1 -fsyntax-only -triple x86_64 -aux-triple amdgcn -aux-target-cpu gfx1030 -verify=host %s

// The DPP builtins take their data argument in any arithmetic type, but only
// 32- and 64-bit intrinsics lower (sub-32-bit types are widened to 32 bits by
// CodeGen). In the host pass of a HIP compile the sizes come from the host
// ABI -- where long double is 128 bits -- so the size diagnostic must be
// deferred and dropped for device-only functions. Target-independent checks
// (like update_dpp's argument-type match) still fire in the host pass.

#define __global__ __attribute__((global))

__global__ void test_wide(long *out, int x) {
  out[0] = (long)__builtin_amdgcn_mov_dpp((__int128)x, 0x101, 0xf, 0xf, 0); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was '__int128')}}
  out[1] = (long)__builtin_amdgcn_mov_dpp8((unsigned __int128)x, 1); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was 'unsigned __int128')}}
  out[2] = (long)__builtin_amdgcn_update_dpp((__int128)0, (__int128)x, 0x101, 0xf, 0xf, 0); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was '__int128')}}
  out[3] = (long)__builtin_amdgcn_update_dpp(0, (__int128)x, 0x101, 0xf, 0xf, 0); // expected-error {{2nd argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was '__int128')}} host-error {{arguments are of different types ('int' vs '__int128')}}
  out[4] = (long)__builtin_amdgcn_mov_dpp((_BitInt(128))x, 0x101, 0xf, 0xf, 0); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was '_BitInt(128)')}}
  // CodeGen emits a 48-bit intrinsic for _BitInt(48) rather than widening it
  // to 64 bits, and that does not lower either.
  out[5] = (long)__builtin_amdgcn_mov_dpp((_BitInt(48))x, 0x101, 0xf, 0xf, 0); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was '_BitInt(48)')}}
}

__global__ void test_supported(long *out, int x) {
  out[0] = (long)__builtin_amdgcn_mov_dpp((bool)x, 0x101, 0xf, 0xf, 0);
  out[1] = (long)__builtin_amdgcn_mov_dpp((char)x, 0x101, 0xf, 0xf, 0);
  out[2] = (long)__builtin_amdgcn_mov_dpp((short)x, 0x101, 0xf, 0xf, 0);
  out[3] = (long)__builtin_amdgcn_mov_dpp(x, 0x101, 0xf, 0xf, 0);
  out[4] = (long)__builtin_amdgcn_mov_dpp((long)x, 0x101, 0xf, 0xf, 0);
  out[5] = (long)__builtin_amdgcn_mov_dpp((_BitInt(24))x, 0x101, 0xf, 0xf, 0);
  out[6] = (long)__builtin_amdgcn_mov_dpp((_BitInt(64))x, 0x101, 0xf, 0xf, 0);
  out[7] = (long)__builtin_amdgcn_mov_dpp((_Float16)x, 0x101, 0xf, 0xf, 0);
  out[8] = (long)__builtin_amdgcn_mov_dpp((float)x, 0x101, 0xf, 0xf, 0);
  out[9] = (long)__builtin_amdgcn_mov_dpp((double)x, 0x101, 0xf, 0xf, 0);
  // 64 bits on the device even though the host pass sees a 128-bit type.
  out[10] = (long)__builtin_amdgcn_mov_dpp((long double)x, 0x101, 0xf, 0xf, 0);
  out[11] = (long)__builtin_amdgcn_update_dpp(0.0, (double)x, 0x101, 0xf, 0xf, 0);
  out[12] = (long)__builtin_amdgcn_mov_dpp8((long)x, 1);
}

template <typename T> __global__ void ktempl(long *out, T x) {
  out[0] = (long)__builtin_amdgcn_update_dpp((T)0, x, 0x101, 0xf, 0xf, 0); // expected-error {{1st argument must be a scalar 64 bit or smaller integer or 64 bit or smaller floating-point type (was 'unsigned __int128')}}
}

template __global__ void ktempl<unsigned __int128>(long *, unsigned __int128); // expected-note {{in instantiation of function template specialization 'ktempl<unsigned __int128>' requested here}}
