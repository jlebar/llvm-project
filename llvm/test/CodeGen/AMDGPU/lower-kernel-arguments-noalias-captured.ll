; RUN: opt -mtriple=amdgcn-amd-amdhsa -S -passes=amdgpu-lower-kernel-arguments %s | FileCheck %s

; A call may access memory reached through a noalias kernel argument if a
; copy of the pointer was captured before the call (here: stored to an LDS
; variable the callee can read). Such an access goes through a pointer based
; on the argument, which noalias permits, so addAliasScopeMetadata must not
; give the call the argument's scope in !noalias. Doing so let ScopedNoAliasAA
; report the call as NoModRef for accesses through the argument, and e.g.
; AMDGPUAnnotateUniformValues then marked a load after the call as
; amdgpu.noclobber, turning it into an SMEM load that does not observe the
; callee's VMEM store through the captured pointer.

@cap = addrspace(3) global ptr addrspace(1) poison

declare void @readwrite_no_ptr_args() #0
declare void @readwrite_with_ptr_arg(ptr addrspace(1)) #0
declare void @argmemonly_rw_with_ptr_arg(ptr addrspace(1)) #1

; The callee has no pointer arguments but can reach *%p via @cap, so the
; call must not carry %p's scope.
; CHECK-LABEL: define amdgpu_kernel void @captured_before_call_no_ptr_args(
; CHECK: call void @readwrite_no_ptr_args(){{$}}
; CHECK: load i32, ptr addrspace(1) %p.load, align 4, !alias.scope !{{[0-9]+$}}
define amdgpu_kernel void @captured_before_call_no_ptr_args(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  store ptr addrspace(1) %p, ptr addrspace(3) @cap
  call void @readwrite_no_ptr_args()
  %v = load i32, ptr addrspace(1) %p
  store i32 %v, ptr addrspace(1) %out
  ret void
}

; Same with a pointer argument that does not derive from %p: the callee is
; not argmem-only, so it can still reach *%p through the capture.
; CHECK-LABEL: define amdgpu_kernel void @captured_before_call_with_ptr_arg(
; CHECK: call void @readwrite_with_ptr_arg(ptr addrspace(1) %out.load){{$}}
; CHECK: load i32, ptr addrspace(1) %p.load, align 4, !alias.scope !{{[0-9]+$}}
define amdgpu_kernel void @captured_before_call_with_ptr_arg(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  store ptr addrspace(1) %p, ptr addrspace(3) @cap
  call void @readwrite_with_ptr_arg(ptr addrspace(1) %out)
  %v = load i32, ptr addrspace(1) %p
  store i32 %v, ptr addrspace(1) %out
  ret void
}

; A capture after the call is not observable by the callee — the call keeps
; %p's scope.
; CHECK-LABEL: define amdgpu_kernel void @captured_after_call_no_ptr_args(
; CHECK: call void @readwrite_no_ptr_args(), !noalias !{{[0-9]+$}}
define amdgpu_kernel void @captured_after_call_no_ptr_args(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  %v = load i32, ptr addrspace(1) %p
  call void @readwrite_no_ptr_args()
  store ptr addrspace(1) %p, ptr addrspace(3) @cap
  store i32 %v, ptr addrspace(1) %out
  ret void
}

; An argmem-only callee can only access memory through its own pointer
; arguments, so the capture does not matter and the scope is kept.
; CHECK-LABEL: define amdgpu_kernel void @captured_before_argmemonly_call(
; CHECK: call void @argmemonly_rw_with_ptr_arg(ptr addrspace(1) %out.load), !noalias !{{[0-9]+$}}
define amdgpu_kernel void @captured_before_argmemonly_call(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  store ptr addrspace(1) %p, ptr addrspace(3) @cap
  call void @argmemonly_rw_with_ptr_arg(ptr addrspace(1) %out)
  %v = load i32, ptr addrspace(1) %p
  store i32 %v, ptr addrspace(1) %out
  ret void
}

; A call that is not argmem-only may access memory other than its pointer
; arguments' pointees, so it must not get !alias.scope claiming its accesses
; stay within %p's scope. It keeps !noalias for %q's scope, which it cannot
; reach (%q is never captured).
; CHECK-LABEL: define amdgpu_kernel void @no_alias_scope_on_nonargmem_call(
; CHECK: call void @readwrite_with_ptr_arg(ptr addrspace(1) %p.load), !noalias !{{[0-9]+$}}
define amdgpu_kernel void @no_alias_scope_on_nonargmem_call(ptr addrspace(1) noalias %p, ptr addrspace(1) noalias %q, ptr addrspace(1) %out) #2 {
  call void @readwrite_with_ptr_arg(ptr addrspace(1) %p)
  %w = load i32, ptr addrspace(1) %q
  store i32 %w, ptr addrspace(1) %out
  ret void
}

; A call that can only access inaccessible memory cannot alias any IR-visible
; location; it gets no metadata (and no capture analysis).
declare void @inaccessible_only() #3

; CHECK-LABEL: define amdgpu_kernel void @inaccessiblemem_call(
; CHECK: call void @inaccessible_only(){{$}}
define amdgpu_kernel void @inaccessiblemem_call(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  call void @inaccessible_only()
  %v = load i32, ptr addrspace(1) %p
  store i32 %v, ptr addrspace(1) %out
  ret void
}

; When the underlying-object walk is truncated (12 GEPs > MaxLookupSearchDepth)
; the object is unknown and may well be %p itself — the store must get no
; metadata at all. It used to get !noalias with %p's scope, i.e. a store
; through %p was declared not to alias %p.
; CHECK-LABEL: define amdgpu_kernel void @unknown_object_deep_gep(
; CHECK: store i32 42, ptr addrspace(1) %gback, align 4{{$}}
; CHECK: load i32, ptr addrspace(1) %p.load, align 4, !alias.scope !{{[0-9]+$}}
define amdgpu_kernel void @unknown_object_deep_gep(ptr addrspace(1) noalias %p, ptr addrspace(1) %out) #2 {
  %g1 = getelementptr i8, ptr addrspace(1) %p, i64 1
  %g2 = getelementptr i8, ptr addrspace(1) %g1, i64 1
  %g3 = getelementptr i8, ptr addrspace(1) %g2, i64 1
  %g4 = getelementptr i8, ptr addrspace(1) %g3, i64 1
  %g5 = getelementptr i8, ptr addrspace(1) %g4, i64 1
  %g6 = getelementptr i8, ptr addrspace(1) %g5, i64 1
  %g7 = getelementptr i8, ptr addrspace(1) %g6, i64 1
  %g8 = getelementptr i8, ptr addrspace(1) %g7, i64 1
  %g9 = getelementptr i8, ptr addrspace(1) %g8, i64 1
  %g10 = getelementptr i8, ptr addrspace(1) %g9, i64 1
  %g11 = getelementptr i8, ptr addrspace(1) %g10, i64 1
  %gback = getelementptr i8, ptr addrspace(1) %g11, i64 -11
  store i32 42, ptr addrspace(1) %gback
  %v = load i32, ptr addrspace(1) %p
  store i32 %v, ptr addrspace(1) %out
  ret void
}

attributes #0 = { nounwind memory(readwrite) }
attributes #1 = { nounwind memory(argmem: readwrite) }
attributes #2 = { nounwind }
attributes #3 = { nounwind memory(inaccessiblemem: readwrite) }
