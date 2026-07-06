// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -triple amdgcn-unknown-unknown -target-cpu gfx908 -verify=pregfx940 -S -o - %s
// RUN: %clang_cc1 -triple amdgcn-unknown-unknown -target-cpu gfx90a -verify=pregfx940 -S -o - %s
// RUN: %clang_cc1 -triple amdgcn-unknown-unknown -target-cpu gfx942 -verify=gfx940plus -S -o - %s
// RUN: %clang_cc1 -triple amdgcn-unknown-unknown -target-cpu gfx950 -verify=gfx940plus,noxf32 -S -o - %s
// RUN: %clang_cc1 -triple amdgcn-unknown-unknown -target-cpu gfx9-4-generic -verify=gfx940plus,noxf32 -S -o - %s

// GFX940 removed the GFX908 MFMA i8/bf16 instructions (replacing them with the
// double-K i8 and bf16_1k variants), and GFX950 dropped the xf32 instructions,
// so each group of builtins must be rejected on the targets that lack the
// instructions rather than crashing the backend.

typedef float  v2f   __attribute__((ext_vector_type(2)));
typedef float  v4f   __attribute__((ext_vector_type(4)));
typedef float  v16f  __attribute__((ext_vector_type(16)));
typedef float  v32f  __attribute__((ext_vector_type(32)));
typedef int    v4i   __attribute__((ext_vector_type(4)));
typedef int    v16i  __attribute__((ext_vector_type(16)));
typedef short  v2s   __attribute__((ext_vector_type(2)));

void test_mfma(global v4i* out4i, global v16i* out16i,
               global v4f* out4f, global v16f* out16f,
               global v32f* out32f, int a, long l, v2s b, v2f f)
{
  *out4i = __builtin_amdgcn_mfma_i32_16x16x16i8(a, a, *out4i, 0, 0, 0);       // gfx940plus-error{{'__builtin_amdgcn_mfma_i32_16x16x16i8' needs target feature mfma-gfx908-insts}}
  *out16i = __builtin_amdgcn_mfma_i32_32x32x8i8(a, a, *out16i, 0, 0, 0);      // gfx940plus-error{{'__builtin_amdgcn_mfma_i32_32x32x8i8' needs target feature mfma-gfx908-insts}}
  *out4f = __builtin_amdgcn_mfma_f32_4x4x2bf16(b, b, *out4f, 0, 0, 0);        // gfx940plus-error{{'__builtin_amdgcn_mfma_f32_4x4x2bf16' needs target feature mfma-gfx908-insts}}
  *out16f = __builtin_amdgcn_mfma_f32_16x16x2bf16(b, b, *out16f, 0, 0, 0);    // gfx940plus-error{{'__builtin_amdgcn_mfma_f32_16x16x2bf16' needs target feature mfma-gfx908-insts}}
  *out4f = __builtin_amdgcn_mfma_f32_16x16x8bf16(b, b, *out4f, 0, 0, 0);      // gfx940plus-error{{'__builtin_amdgcn_mfma_f32_16x16x8bf16' needs target feature mfma-gfx908-insts}}
  *out32f = __builtin_amdgcn_mfma_f32_32x32x2bf16(b, b, *out32f, 0, 0, 0);    // gfx940plus-error{{'__builtin_amdgcn_mfma_f32_32x32x2bf16' needs target feature mfma-gfx908-insts}}
  *out16f = __builtin_amdgcn_mfma_f32_32x32x4bf16(b, b, *out16f, 0, 0, 0);    // gfx940plus-error{{'__builtin_amdgcn_mfma_f32_32x32x4bf16' needs target feature mfma-gfx908-insts}}
  *out4i = __builtin_amdgcn_mfma_i32_16x16x32_i8(l, l, *out4i, 0, 0, 0);      // pregfx940-error{{'__builtin_amdgcn_mfma_i32_16x16x32_i8' needs target feature gfx940-insts}}
  *out16i = __builtin_amdgcn_mfma_i32_32x32x16_i8(l, l, *out16i, 0, 0, 0);    // pregfx940-error{{'__builtin_amdgcn_mfma_i32_32x32x16_i8' needs target feature gfx940-insts}}
  *out4f = __builtin_amdgcn_mfma_f32_16x16x8_xf32(f, f, *out4f, 0, 0, 0);     // pregfx940-error{{'__builtin_amdgcn_mfma_f32_16x16x8_xf32' needs target feature xf32-insts}} noxf32-error{{'__builtin_amdgcn_mfma_f32_16x16x8_xf32' needs target feature xf32-insts}}
  *out16f = __builtin_amdgcn_mfma_f32_32x32x4_xf32(f, f, *out16f, 0, 0, 0);   // pregfx940-error{{'__builtin_amdgcn_mfma_f32_32x32x4_xf32' needs target feature xf32-insts}} noxf32-error{{'__builtin_amdgcn_mfma_f32_32x32x4_xf32' needs target feature xf32-insts}}
}
