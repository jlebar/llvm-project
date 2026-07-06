// REQUIRES: amdgpu-registered-target, nvptx-registered-target
// RUN: %clang_cc1 -triple amdgcn-amd-amdhsa -fcuda-is-device -std=c++17 \
// RUN:   -fno-threadsafe-statics -emit-llvm -o - -x hip %s | FileCheck %s
// RUN: %clang_cc1 -triple nvptx64-nvidia-cuda -fcuda-is-device -std=c++17 \
// RUN:   -fno-threadsafe-statics -emit-llvm -o - -x hip %s | FileCheck %s

#define __device__ __attribute__((device))
#define __global__ __attribute__((global))
#define __shared__ __attribute__((shared))

struct SB {
  unsigned size;
  void *data;
};

extern __device__ void use(SB &);
extern __device__ void use_size(unsigned);

// The address of a __shared__ variable is assigned when the kernel launches,
// so it must not appear in the initializer of any global. In particular a
// local aggregate mentioning one must not be promoted to a memcpy from an
// unnamed constant global; it is initialized with ordinary stores, whose
// operands the backend can materialize at runtime.

// CHECK: @_ZZ6kernelE5cache = internal addrspace(3) global [256 x i32]
// CHECK-NOT: addrspacecast (ptr addrspace(3)
// CHECK: @_ZGRZ14kernel_reftempE1r_ = internal {{.*}}global %struct.SB zeroinitializer
// CHECK-NOT: addrspacecast (ptr addrspace(3)

// CHECK-LABEL: define{{.*}} void @kernel()
// CHECK: store i32 16,
// CHECK: store ptr addrspacecast (ptr addrspace(3) @_ZZ6kernelE5cache to ptr),
extern "C" __global__ void kernel() {
  __shared__ unsigned cache[256];
  SB b{16, cache};
  use(b);
}

// A function-local static falls back to a guarded dynamic initialization
// storing the runtime address.

// CHECK-LABEL: define{{.*}} void @kernel_static()
// CHECK: icmp eq i8 %{{.*}}, 0
// CHECK: store i32 16,
// CHECK: store ptr addrspacecast (ptr addrspace(3) @_ZZ13kernel_staticE6scache to ptr),
extern "C" __global__ void kernel_static() {
  __shared__ unsigned scache[256];
  static SB sb{16, scache};
  use(sb);
}

// An aggregate not mentioning a __shared__ variable is still promoted.

// CHECK: call void @llvm.memcpy{{.*}} @__const.control.c
extern "C" __global__ void control() {
  SB c{16, nullptr};
  use(c);
}

// A constexpr local mentioning a __shared__ variable, read from a lambda that
// does not capture it (a non-odr-use), is materialized in a local temporary
// instead of being spilled to a global.

// CHECK: %b.const = alloca %struct.SB
// CHECK: store ptr addrspacecast (ptr addrspace(3) @_ZZ11kernel_nourE6ncache to ptr),
extern "C" __global__ void kernel_nour() {
  __shared__ unsigned ncache[256];
  constexpr SB b{16, (void *)ncache};
  [] { use_size(b.size); }();
}

// A temporary whose initializer list contains a large trivially copyable
// array of pointers into __shared__ memory (the "constinit" promotion in
// aggregate codegen) is also emitted element-wise.

struct W {
  void *p[4];
};
extern __device__ void use_w(W);

// CHECK-LABEL: define{{.*}} void @kernel_arrtemp()
// CHECK: store ptr addrspacecast (ptr addrspace(3) @_ZZ14kernel_arrtempE6tcache to ptr),
extern "C" __global__ void kernel_arrtemp() {
  __shared__ unsigned tcache[256];
  use_w(W{{tcache, tcache + 1, tcache + 2, tcache + 3}});
}

// A lifetime-extended temporary bound to a static reference goes through
// GetAddrOfGlobalTemporary. The temporary's global is emitted without the
// constant (zeroinitializer above), and both it and the reference take
// guarded dynamic initialization.

extern __device__ void use_c(const SB &);

// CHECK-LABEL: define{{.*}} void @kernel_reftemp()
// CHECK: icmp eq i8 %{{.*}}, 0
// CHECK: store i32 16,
// CHECK: store ptr addrspacecast (ptr addrspace(3) @_ZZ14kernel_reftempE6rcache to ptr),
// CHECK: store ptr addrspacecast (ptr addrspace(1) @_ZGRZ14kernel_reftempE1r_ to ptr),
extern "C" __global__ void kernel_reftemp() {
  __shared__ unsigned rcache[256];
  static const SB &r = SB{16, rcache};
  use_c(r);
}
