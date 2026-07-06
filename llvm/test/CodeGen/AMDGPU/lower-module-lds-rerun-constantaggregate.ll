; RUN: opt -S -mtriple=amdgcn-amd-amdhsa -passes=amdgpu-lower-module-lds < %s | FileCheck %s
; RUN: opt -S -mtriple=amdgcn-amd-amdhsa -passes=amdgpu-lower-module-lds,amdgpu-lower-module-lds < %s | FileCheck %s

; The only use of the LDS variable is through a constantaggregate anchored in
; an instruction. The pass expands the aggregate into instructions
; (convertUsersOfConstantsToInstructions) and then lowers the variable, so the
; already-lowered early exit must not classify this module as lowered on the
; first run, and both RUN lines must produce identical, lowered output.

@agg.lds = internal addrspace(3) global i32 poison, align 4
@out = addrspace(1) global { ptr addrspace(3) } zeroinitializer

; CHECK-NOT: @agg.lds
; CHECK: @llvm.amdgcn.kernel.k.lds = internal addrspace(3) global %llvm.amdgcn.kernel.k.lds.t poison, align 4, !absolute_symbol !0

; CHECK-LABEL: define amdgpu_kernel void @k(
; CHECK: %1 = insertvalue { ptr addrspace(3) } poison, ptr addrspace(3) @llvm.amdgcn.kernel.k.lds, 0
; CHECK: store { ptr addrspace(3) } %1, ptr addrspace(1) @out, align 4
define amdgpu_kernel void @k() {
  store { ptr addrspace(3) } { ptr addrspace(3) @agg.lds }, ptr addrspace(1) @out
  ret void
}
