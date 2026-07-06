// REQUIRES: nvptx-registered-target
// RUN: %clang_cc1 -triple nvptx64-nvidia-cuda -fcuda-is-device -S -o - %s | FileCheck %s

#include "Inputs/cuda.h"

__device__ int arr[4];

// The address of a device global is a link-time constant that PTX can
// reference symbolically, so it satisfies the "i" constraint even though it
// reaches the backend as an addrspacecast to the generic address space.

// CHECK-LABEL: _Z11test_symbolv
__device__ void test_symbol() {
  // CHECK: // TEST arr{{$}}
  asm volatile("// TEST %0" ::"i"(&arr));
}

// CHECK-LABEL: _Z11test_offsetv
__device__ void test_offset() {
  // CHECK: // TEST arr+12{{$}}
  asm volatile("// TEST %0" ::"i"(&arr[3]));
}
