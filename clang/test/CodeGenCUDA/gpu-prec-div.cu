// RUN: %clang_cc1 -fcuda-is-device -triple nvptx64-nvidia-cuda \
// RUN:   -emit-llvm -o - %s | FileCheck -check-prefix=PREC %s

// RUN: %clang_cc1 -fcuda-is-device -fno-gpu-prec-div -triple nvptx64-nvidia-cuda \
// RUN:   -emit-llvm -o - %s | FileCheck -check-prefix=APPROX %s

#include "Inputs/cuda.h"

// Check that we emit the nvvm-reflect-prec-div module flag NVVMReflect uses
// to answer libdevice's __nvvm_reflect("__CUDA_PREC_DIV"), and that
// -fno-gpu-prec-div sets it to 0.

extern "C" __device__ void foo() {}

// PREC: !{i32 4, !"nvvm-reflect-prec-div", i32 1}
// APPROX: !{i32 4, !"nvvm-reflect-prec-div", i32 0}
