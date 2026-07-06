// REQUIRES: amdgpu-registered-target
// RUN: %clang_cc1 -fsyntax-only -std=c++17 -triple amdgcn -target-cpu gfx942 -verify=expected,dev %s -fcuda-is-device
// RUN: %clang_cc1 -fsyntax-only -std=c++17 -triple x86_64 -aux-triple amdgcn -verify %s

#define __device__ __attribute__((device))

typedef float float4 __attribute__((ext_vector_type(4)));
typedef int int4 __attribute__((ext_vector_type(4)));

// Builtin calls outside of any function (global variable initializers,
// default arguments) used to crash Sema, which assumed an enclosing
// FunctionDecl when computing the caller's target feature map.

__device__ unsigned gvar = __builtin_amdgcn_workgroup_size_x(); // expected-error {{dynamic initialization is not supported for __device__, __constant__, __shared__, and __managed__ variables}}

__device__ int defarg(int w = __builtin_amdgcn_workgroup_size_x()) { return w; }

constexpr unsigned cvar = __builtin_amdgcn_workgroup_size_x(); // expected-error {{constexpr variable 'cvar' must be initialized by a constant expression}}

#ifdef __HIP_DEVICE_COMPILE__
// With no enclosing function, feature checking falls back to the target
// feature map; gfx942 lacks extended-image-insts.
__device__ __amdgpu_texture_t tex;
__device__ float4 img = __builtin_amdgcn_image_sample_lz_1d_v4f32_f32(105, 1.0f, tex, int4{0, 0, 0, 0}, 0, 101, 121); // dev-error {{'__builtin_amdgcn_image_sample_lz_1d_v4f32_f32' needs target feature extended-image-insts}} \
                                                                                                                         dev-error {{dynamic initialization is not supported for __device__, __constant__, __shared__, and __managed__ variables}}
#endif
