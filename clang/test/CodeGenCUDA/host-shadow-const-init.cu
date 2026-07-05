// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++17 -emit-llvm \
// RUN:   -o - %s | FileCheck %s --implicit-check-not=device_fn \
// RUN:   --implicit-check-not=Holder --implicit-check-not=_ZTV
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -std=c++17 -emit-llvm \
// RUN:   -o - -x hip %s | FileCheck %s --implicit-check-not=device_fn \
// RUN:   --implicit-check-not=Holder --implicit-check-not=_ZTV

#include "Inputs/cuda.h"

// In host compilation, shadows of const-qualified device-side variables with
// constant initializers carry the real initializer. The value is immutable,
// so host and device are guaranteed to agree on it, and host code reads the
// shadow directly (e.g. when copying a whole aggregate); the constant
// evaluator already folds member reads to the initializer value, so an undef
// shadow would make direct loads disagree with folded ones.

struct S {
  int a;
  float b;
};

// CHECK-DAG: @_ZL12const_struct = internal constant %struct.S { i32 1, float 2.000000e+00 }
const __constant__ S const_struct = {1, 2.0f};

// CHECK-DAG: @_ZL11const_array = internal constant [4 x i32] [i32 2, i32 3, i32 5, i32 7]
__constant__ const int const_array[4] = {2, 3, 5, 7};

// CHECK-DAG: @_ZL16const_device_var = internal constant i32 3
const __device__ int const_device_var = 3;

// CHECK-DAG: @_ZL13constexpr_var = internal constant i32 4
constexpr __device__ int constexpr_var = 4;

// Non-const variables can diverge from their initial value (__device__
// variables are mutable by device code, __constant__ ones writable from the
// host via the runtime), so their shadows stay undef.

// CHECK-DAG: @nonconst_constant = internal global %struct.S undef
__constant__ S nonconst_constant = {3, 4.0f};

// CHECK-DAG: @nonconst_device = internal global %struct.S undef
__device__ S nonconst_device = {5, 6.0f};

// Mutable members make a const object writable by device code.
struct M {
  int a;
  mutable int b;
};

// CHECK-DAG: @_ZL11mutable_var = internal global %struct.M undef
const __constant__ M mutable_var = {1, 2};

// An initializer referencing another global keeps the undef shadow: the
// symbol may not exist on the host side (e.g. a device function). Such an
// initializer must not be emitted in host compilation at all — no
// declaration of device_fn, and no host copy of Holder::device_fn_2, whose
// in-class definition would otherwise get deferred-emitted as host code
// (hence the --implicit-check-not patterns above).
__device__ int device_fn();

// CHECK-DAG: @_ZL8const_fp = internal constant ptr undef
__device__ int (*const const_fp)() = device_fn;

struct Holder {
  static __device__ int device_fn_2() { return 2; }
};

// CHECK-DAG: @_ZL9const_fp2 = internal constant ptr undef
__device__ int (*const const_fp2)() = Holder::device_fn_2;

// A polymorphic object's vtable pointer is a reference to the vtable
// global, but it is not part of the evaluated constant value, so it needs
// the type-based check: emitting the initializer would point the shadow at
// the *host* vtable (dragging in host RTTI and virtual functions) while the
// device object holds the device vtable. Keep the shadow undef; the
// --implicit-check-not=_ZTV above verifies no vtable is emitted.
struct Poly {
  constexpr Poly() {}
  __device__ virtual int f() const;
  int x = 1;
};

// CHECK-DAG: @_ZL8poly_var = internal constant %struct.Poly undef
const __constant__ Poly poly_var{};

// The vtable pointer may sit in a subobject rather than the variable's own
// type.
struct HasPolyMember {
  Poly p;
  int y;
};

// CHECK-DAG: @_ZL10member_var = internal constant %struct.HasPolyMember undef
const __device__ HasPolyMember member_var{Poly(), 2};

// Internal-linkage variables are emitted only if used; reference them all
// from host code.
void use(const void *);
void refs() {
  use(&const_struct);
  use(&const_array);
  use(&const_device_var);
  use(&constexpr_var);
  use(&mutable_var);
  use(&const_fp);
  use(&const_fp2);
  use(&poly_var);
  use(&member_var);
}

// Host code copying the whole aggregate reads the shadow, which now holds
// the same value the constant evaluator folds member accesses to.
// CHECK-LABEL: define {{.*}}_Z9ret_wholev
// CHECK: call void @llvm.memcpy{{.*}}(ptr {{.*}}, ptr {{.*}}@_ZL12const_struct, i64 8,
S ret_whole() { return const_struct; }

// CHECK-LABEL: define {{.*}}_Z10ret_memberv
// CHECK: ret i32 1
int ret_member() { return const_struct.a; }
