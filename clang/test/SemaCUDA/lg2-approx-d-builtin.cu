// RUN: %clang_cc1 -triple nvptx64-nvidia-cuda -fcuda-is-device -fsyntax-only \
// RUN:   -fno-spell-checking -verify %s

// PTX has no double-precision variant of lg2.approx, so there is no such
// builtin. It used to exist and compiled to an invalid lg2.approx.f64
// instruction.

#include "Inputs/cuda.h"

__device__ double test(double x) {
  return __nvvm_lg2_approx_d(x); // expected-error {{use of undeclared identifier '__nvvm_lg2_approx_d'}}
}
