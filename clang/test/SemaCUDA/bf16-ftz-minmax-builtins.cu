// RUN: %clang_cc1 -triple nvptx64-nvidia-cuda -target-cpu sm_80 \
// RUN:   -target-feature +ptx70 -fcuda-is-device -fsyntax-only \
// RUN:   -fno-spell-checking -verify %s

// PTX has no ftz variant of min/max on bf16, so there are no such builtins.
// They used to exist and crashed the backend with "Cannot select".

#include "Inputs/cuda.h"

typedef __bf16 bf16x2 __attribute__((ext_vector_type(2)));

__device__ void test(__bf16 s, bf16x2 v) {
  __nvvm_fmin_ftz_bf16(s, s);        // expected-error {{use of undeclared identifier '__nvvm_fmin_ftz_bf16'}}
  __nvvm_fmin_ftz_nan_bf16(s, s);    // expected-error {{use of undeclared identifier '__nvvm_fmin_ftz_nan_bf16'}}
  __nvvm_fmin_ftz_bf16x2(v, v);      // expected-error {{use of undeclared identifier '__nvvm_fmin_ftz_bf16x2'}}
  __nvvm_fmin_ftz_nan_bf16x2(v, v);  // expected-error {{use of undeclared identifier '__nvvm_fmin_ftz_nan_bf16x2'}}
  __nvvm_fmax_ftz_bf16(s, s);        // expected-error {{use of undeclared identifier '__nvvm_fmax_ftz_bf16'}}
  __nvvm_fmax_ftz_nan_bf16(s, s);    // expected-error {{use of undeclared identifier '__nvvm_fmax_ftz_nan_bf16'}}
  __nvvm_fmax_ftz_bf16x2(v, v);      // expected-error {{use of undeclared identifier '__nvvm_fmax_ftz_bf16x2'}}
  __nvvm_fmax_ftz_nan_bf16x2(v, v);  // expected-error {{use of undeclared identifier '__nvvm_fmax_ftz_nan_bf16x2'}}
}
