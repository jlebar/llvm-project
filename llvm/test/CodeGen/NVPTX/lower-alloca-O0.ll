; RUN: llc < %s -mtriple=nvptx64 -mcpu=sm_52 -mattr=+ptx73 -O0 | FileCheck %s
; RUN: %if ptxas-isa-7.3 %{ llc < %s -mtriple=nvptx64 -mcpu=sm_52 -mattr=+ptx73 -O0 | %ptxas-verify %}

; Allocas in the local address space must yield local addresses for their
; local-typed accesses even at -O0, where InferAddressSpaces does not run:
; the frame index and the PTX alloca instruction result are generic addresses,
; so the value used by st.local/ld.local has to go through cvta.to.local (or
; be the raw PTX alloca result).

define void @static_local_as(ptr %out) {
; CHECK-LABEL: .visible .func static_local_as(
; CHECK: add.u64 %[[GENERIC:rd[0-9]+]], %SP, 0
; CHECK: cvta.to.local.u64 %[[LOCAL:rd[0-9]+]], %[[GENERIC]]
; CHECK: st.local.b32 [%[[LOCAL]]], 42
; CHECK: ld.local.b32 {{%r[0-9]+}}, [%[[LOCAL]]]
  %A = alloca i32, align 4, addrspace(5)
  store i32 42, ptr addrspace(5) %A
  %v = load volatile i32, ptr addrspace(5) %A
  store i32 %v, ptr %out
  ret void
}

define void @dynamic_local_as(ptr %out, i64 %n) {
; CHECK-LABEL: .visible .func dynamic_local_as(
; CHECK: alloca.u64 %[[PTR:rd[0-9]+]], {{%rd[0-9]+}}, 8
; CHECK-NOT: cvta.local.u64
; CHECK: st.local.b8 [%[[PTR]]], 42
; CHECK: ld.local.b8 {{%rs[0-9]+}}, [%[[PTR]]]
  %A = alloca i8, i64 %n, align 8, addrspace(5)
  store i8 42, ptr addrspace(5) %A
  %v = load volatile i8, ptr addrspace(5) %A
  store i8 %v, ptr %out
  ret void
}
