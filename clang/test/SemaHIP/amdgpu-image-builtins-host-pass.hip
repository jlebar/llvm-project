// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -triple amdgcn-amd-amdhsa -target-cpu gfx1100 -fcuda-is-device -aux-triple x86_64-unknown-linux-gnu -verify=expected,device %s
// RUN: %clang_cc1 -fsyntax-only -triple x86_64-unknown-linux-gnu -aux-triple amdgcn-amd-amdhsa -verify=expected,host %s

// During the host pass AMDGPU builtins are aux-target builtins: their IDs are
// remapped by getAuxBuiltinID() and the caller's feature map describes the
// host, so feature availability cannot be checked. It used to be checked
// anyway, against the required features of whatever host builtin shared the
// remapped ID, rejecting valid device code with diagnostics like "'f' needs
// target feature avx512vl". Feature checking is the device pass's job;
// feature-independent argument checking still runs in both passes.

#define __device__ __attribute__((device))

typedef float float4 __attribute__((ext_vector_type(4)));
typedef int int4 __attribute__((ext_vector_type(4)));

// gfx1100 has image-insts; valid in the device pass and must not be rejected
// in the host pass.
__device__ float4 valid_load(__amdgpu_texture_t tex, int i) {
  return __builtin_amdgcn_image_load_1d_v4f32_i32(15, i, tex, 0, 0);
}

__device__ void valid_store(__amdgpu_texture_t tex, float4 texel, int i) {
  __builtin_amdgcn_image_store_1d_v4f32_i32(texel, 15, i, tex, 0, 0);
}

// gfx1100 lacks extended-image-insts; only the device pass can tell.
__device__ float4 missing_feature(__amdgpu_texture_t tex, float f, int4 offsets) {
  return __builtin_amdgcn_image_sample_lz_1d_v4f32_f32(15, f, tex, offsets, 0, 101, 121); // device-error{{'missing_feature' needs target feature extended-image-insts}}
}

__device__ float4 bad_dmask(__amdgpu_texture_t tex, int i) {
  return __builtin_amdgcn_image_load_1d_v4f32_i32(i, i, tex, 0, 0); // expected-error{{argument to '__builtin_amdgcn_image_load_1d_v4f32_i32' must be a constant integer}}
}
