// RUN: %clang_cc1 -triple amdgcn-amd-amdhsa -fcuda-is-device -std=c++17 \
// RUN:   -emit-llvm -o - -x hip %s | FileCheck -check-prefixes=COMMON,DEV %s

// RUN: %clang_cc1 -triple x86_64-gnu-linux -std=c++17 \
// RUN:   -emit-llvm -o - -x hip %s | FileCheck -check-prefixes=COMMON,HOST %s

#include "Inputs/cuda.h"

__managed__ int x;

// A<&x>::p (defined at the end of this file) must not be emitted with a
// constant initializer referencing the managed variable.
// HOST-DAG: @_ZN1AIXadL_Z1xEEE1pE = weak_odr global ptr null

// The address of a managed variable is not a constant, but it is still
// allowed as a non-type template argument (it participates in mangling
// only). Uses of the template parameter must load the managed variable's
// runtime address.
// COMMON-LABEL: define {{.*}}@_Z3getIXadL_Z1xEEEPiv()
// DEV:  %ld.managed = load ptr addrspace(1), ptr addrspace(1) @x, align 4
// DEV:  %[[AC:.*]] = addrspacecast ptr addrspace(1) %ld.managed to ptr
// DEV:  ret ptr %[[AC]]
// HOST:  %ld.managed = load ptr, ptr @x, align 4
// HOST:  ret ptr %ld.managed
template <int *P> __device__ __host__ int *get() { return P; }
__device__ __host__ int *addr_of_managed() { return get<&x>(); }

// A local aggregate initialized from such a template parameter must not
// become a memcpy from a constant global referencing the managed variable
// either: the initializer is not a constant initializer (evaluating it
// re-checks the managed variable), so it is emitted as stores of the
// loaded runtime address.
// COMMON-LABEL: define {{.*}}@_Z10local_aggrIXadL_Z1xEEEvv()
// COMMON-NOT: memcpy
// DEV:  %ld.managed = load ptr addrspace(1), ptr addrspace(1) @x, align 4
// HOST:  %ld.managed = load ptr, ptr @x, align 4
// COMMON:  ret void
template <int *P> __device__ __host__ void local_aggr() {
  struct S {
    int *a, *b, *c, *d;
  } s = {P, P, P, P};
}
__device__ __host__ void call_local_aggr() { local_aggr<&x>(); }

// A global whose initializer is such a template parameter must be
// dynamically initialized: the APValue cached in the template argument
// bypasses Sema's constant initializer check, and used to be emitted as a
// constant initializer referencing the managed variable, which crashed
// CGNVCUDARuntime::finalizeModule.
// HOST-LABEL: define internal void @__cxx_global_var_init()
// HOST:  %ld.managed = load ptr, ptr @x, align 4
// HOST:  store ptr %ld.managed, ptr @_ZN1AIXadL_Z1xEEE1pE, align 8
template <int *P> struct A { static int *p; };
template <int *P> int *A<P>::p = P;
template int *A<&x>::p;
