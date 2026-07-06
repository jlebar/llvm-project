// RUN: %clang_cc1 -x cuda -triple nvptx64-nvidia-cuda -fcuda-is-device \
// RUN:     -fgpu-rdc -emit-llvm %s -o - | FileCheck %s

#include "Inputs/cuda.h"

// S is not trivially copyable, so a __device__ function must receive it as a
// pointer to the caller-constructed temporary, not byval. A byval argument is
// an extra bitwise copy made at the call boundary; the copy constructor would
// never have run on the parameter object the callee sees, and check() below
// would return false.
struct S {
  S *self;
  __device__ S() : self(this) {}
  __device__ S(const S &) : self(this) {}
};

// CHECK: define{{.*}} i1 @_Z5check1S(ptr noundef align 8 dead_on_return %s)
__device__ bool check(S s) { return s.self == &s; }

// Kernel arguments are still passed byval: CUDA defines __global__ function
// arguments as bitwise copies delivered through the kernel parameter buffer.
// CHECK: define{{.*}} ptx_kernel void @_Z6kernel1SPb(ptr noundef byval(%struct.S) align 8 %s, ptr noundef %out)
__global__ void kernel(S s, bool *out) {
  // CHECK: call{{.*}} i1 @_Z5check1S(ptr noundef align 8 dead_on_return %agg.tmp)
  *out = check(s);
}

// A declaration of an extern kernel referenced for a device-side launch also
// carries the ptx_kernel calling convention.
__global__ void extk(int);
__device__ void launcher() { extk<<<1, 1>>>(42); }
// CHECK: declare ptx_kernel void @_Z4extki(i32 noundef)
