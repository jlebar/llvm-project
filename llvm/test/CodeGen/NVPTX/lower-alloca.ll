; RUN: opt < %s -S -nvptx-lower-alloca -infer-address-spaces | FileCheck %s
; RUN: opt < %s -S -nvptx-lower-alloca | FileCheck %s --check-prefix LOWERALLOCAONLY
; RUN: llc < %s -mtriple=nvptx64 -mcpu=sm_35 | FileCheck %s --check-prefix PTX
; RUN: %if ptxas %{ llc < %s -mtriple=nvptx64 -mcpu=sm_35 | %ptxas-verify %}

target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"
target triple = "nvptx64-unknown-unknown"

define ptx_kernel void @kernel() {
; LABEL: @lower_alloca
; PTX-LABEL: .visible .entry kernel(
  %A = alloca i32
; CHECK: addrspacecast ptr %A to ptr addrspace(5)
; CHECK: store i32 0, ptr addrspace(5) {{%.+}}
; LOWERALLOCAONLY: [[V1:%.*]] = addrspacecast ptr %A to ptr addrspace(5)
; LOWERALLOCAONLY: [[V2:%.*]] = addrspacecast ptr addrspace(5) [[V1]] to ptr
; LOWERALLOCAONLY: store i32 0, ptr [[V2]], align 4
; PTX: st.local.b32 [{{%rd[0-9]+}}], 0
  store i32 0, ptr %A
  call void @callee(ptr %A)
  ret void
}

define void @alloca_in_explicit_local_as() {
; LABEL: @lower_alloca_addrspace5
; PTX-LABEL: .visible .func alloca_in_explicit_local_as(
  %A = alloca i32, addrspace(5)
; The alloca is rewritten to the generic address space; its local-typed value
; is recovered with an addrspacecast, so the local-typed accesses get a local
; address (%SPL-based), not the depot's generic address (%SP-based).
; CHECK: %A = alloca i32
; CHECK: store i32 0, ptr addrspace(5) {{%.+}}
; PTX: add.u64 %[[ALLOCA_ADDR:rd[0-9]+]], %SPL, 0
; PTX: st.local.b32 [%[[ALLOCA_ADDR]]], 0
; LOWERALLOCAONLY: %A = alloca i32
; LOWERALLOCAONLY: [[V1:%.*]] = addrspacecast ptr %A to ptr addrspace(5)
; LOWERALLOCAONLY: store i32 0, ptr addrspace(5) [[V1]], align 4
  store i32 0, ptr addrspace(5) %A
  call void @callee(ptr addrspace(5) %A)
  ret void
}

define void @lifetime_in_explicit_local_as() {
; PTX-LABEL: .visible .func lifetime_in_explicit_local_as(
; Lifetime intrinsics only accept an alloca; they must follow it to the
; rewritten generic alloca rather than the addrspacecast.
; LOWERALLOCAONLY: %A = alloca i32
; LOWERALLOCAONLY: [[CAST:%.*]] = addrspacecast ptr %A to ptr addrspace(5)
; LOWERALLOCAONLY: call void @llvm.lifetime.start.p0(ptr %A)
; LOWERALLOCAONLY: store i32 0, ptr addrspace(5) [[CAST]]
; LOWERALLOCAONLY: call void @llvm.lifetime.end.p0(ptr %A)
  %A = alloca i32, addrspace(5)
  call void @llvm.lifetime.start.p5(i64 4, ptr addrspace(5) %A)
  store i32 0, ptr addrspace(5) %A
  call void @callee(ptr addrspace(5) %A)
  call void @llvm.lifetime.end.p5(i64 4, ptr addrspace(5) %A)
  ret void
}

declare void @llvm.lifetime.start.p5(i64, ptr addrspace(5))
declare void @llvm.lifetime.end.p5(i64, ptr addrspace(5))
declare void @callee(ptr)
declare void @callee_addrspace5(ptr addrspace(5))

!nvvm.annotations = !{!1}
!1 = !{ptr @alloca_in_explicit_local_as, !"alloca_in_explicit_local_as", i32 1}
