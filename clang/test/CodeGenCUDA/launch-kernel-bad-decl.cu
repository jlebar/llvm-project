// A TU-scope declaration of the kernel launch API whose signature doesn't
// match the real API used to crash device stub emission when it was picked
// up instead of the real declaration. Such declarations must be ignored: the
// stub uses the matching declaration if there is one, and a diagnostic is
// emitted otherwise.

// RUN: %clang_cc1 -fhip-new-launch-api -x hip -emit-llvm -o /dev/null \
// RUN:   -verify=hip %s
// RUN: %clang_cc1 -target-sdk-version=9.2 -emit-llvm -o /dev/null \
// RUN:   -verify=cuda %s
// RUN: %clang_cc1 -DUSE_HEADER -fhip-new-launch-api -x hip -emit-llvm -o - \
// RUN:   -verify=good %s | FileCheck --check-prefix=HIP %s
// RUN: %clang_cc1 -DUSE_HEADER -target-sdk-version=9.2 -emit-llvm -o - \
// RUN:   -verify=good %s | FileCheck --check-prefix=CUDA %s

// good-no-diagnostics

#ifdef USE_HEADER
#include "Inputs/cuda.h"
#else
#define __global__ __attribute__((global))
#endif

void hipLaunchKernel();
void cudaLaunchKernel();
void hipLaunchKernel(int, int, int, int, int, int);
void cudaLaunchKernel(int, int, int, int, int, int);

// Right shape, but the dim3-position record type is incomplete.
struct IncompleteDim;
void hipLaunchKernel(const void *, IncompleteDim, IncompleteDim, void **,
                     unsigned long, void *);
void cudaLaunchKernel(const void *, IncompleteDim, IncompleteDim, void **,
                      unsigned long, void *);

// Right shape, but sharedMem is narrower than size_t.
struct SomeDim { unsigned x, y, z; };
void hipLaunchKernel(const void *, SomeDim, SomeDim, void **, short, void *);
void cudaLaunchKernel(const void *, SomeDim, SomeDim, void **, short, void *);

// HIP-LABEL: define{{.*}}kernel
// HIP: call{{.*}}hipLaunchKernel
// CUDA-LABEL: define{{.*}}kernel
// CUDA: call{{.*}}cudaLaunchKernel
__global__ void kernel() {}
// hip-error@-1 {{Can't find declaration for hipLaunchKernel}}
// cuda-error@-2 {{Can't find declaration for cudaLaunchKernel}}
