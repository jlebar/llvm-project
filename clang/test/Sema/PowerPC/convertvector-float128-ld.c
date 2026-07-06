// RUN: %clang_cc1 -fsyntax-only -verify -triple powerpc64le-unknown-linux-gnu \
// RUN:   -target-cpu pwr9 -target-feature +float128 %s
// RUN: %clang_cc1 -fsyntax-only -verify -triple powerpc64le-unknown-linux-gnu \
// RUN:   -target-cpu pwr9 -target-feature +float128 -x c++ %s

typedef __float128 v2f128 __attribute__((ext_vector_type(2)));
typedef __ibm128 v2ibm128 __attribute__((ext_vector_type(2)));
typedef long double v2ld __attribute__((ext_vector_type(2)));
typedef double v2d __attribute__((ext_vector_type(2)));

// long double is PPC double-double here; converting to/from __float128 (IEEE
// quad) cannot be lowered, same as for the scalar types.
v2f128 ld_to_f128(v2ld x) {
  return __builtin_convertvector(x, v2f128); // expected-error {{conversion between vector element types 'long double' and '__float128' is not supported}}
}

v2ld f128_to_ld(v2f128 x) {
  return __builtin_convertvector(x, v2ld); // expected-error {{conversion between vector element types '__float128' and 'long double' is not supported}}
}

v2f128 ibm128_to_f128(v2ibm128 x) {
  return __builtin_convertvector(x, v2f128); // expected-error {{conversion between vector element types '__ibm128' and '__float128' is not supported}}
}

v2ibm128 f128_to_ibm128(v2f128 x) {
  return __builtin_convertvector(x, v2ibm128); // expected-error {{conversion between vector element types '__float128' and '__ibm128' is not supported}}
}

// Conversions involving only one 128-bit format are fine.
v2d ld_to_d(v2ld x) {
  return __builtin_convertvector(x, v2d);
}

v2f128 d_to_f128(v2d x) {
  return __builtin_convertvector(x, v2f128);
}

v2ld ibm128_to_ld(v2ibm128 x) {
  return __builtin_convertvector(x, v2ld);
}
