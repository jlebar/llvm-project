// REQUIRES: amdgpu-registered-target
// REQUIRES: spirv-registered-target
// RUN: %clang_cc1 -fsyntax-only -std=c++17 -triple spirv64-amd-amdhsa -verify %s -fcuda-is-device
// RUN: %clang_cc1 -fsyntax-only -std=c++17 -triple x86_64 -aux-triple spirv64-amd-amdhsa -verify %s

#define __device__ __attribute__((device))

// Builtin calls outside of any function (global variable initializers,
// default arguments) used to crash Sema for AMD SPIR-V, which records the
// enclosing function of every target-specific builtin call in support of
// -Wamdgpu-unguarded-builtin-usage and assumed one always exists.

__device__ unsigned gvar = __builtin_amdgcn_workgroup_size_x(); // expected-error {{dynamic initialization is not supported for __device__, __constant__, __shared__, and __managed__ variables}}

__device__ int defarg(int w = __builtin_amdgcn_workgroup_size_x()) { return w; }

constexpr unsigned cvar = __builtin_amdgcn_workgroup_size_x(); // expected-error {{constexpr variable 'cvar' must be initialized by a constant expression}}
