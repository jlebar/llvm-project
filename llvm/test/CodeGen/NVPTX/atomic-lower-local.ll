; RUN: opt < %s -S -nvptx-atomic-lower | FileCheck %s

; This test ensures that there is a legal way for ptx to lower atomics
; on local memory. Here, we demonstrate this by lowering them to simple
; load and stores.

target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"
target triple = "nvptx64-unknown-unknown"

define double @kernel(ptr addrspace(5) %ptr, double %val) {
  %res = atomicrmw fadd ptr addrspace(5) %ptr, double %val monotonic, align 8
  ret double %res
; CHECK:   %1 = load double, ptr addrspace(5) %ptr, align 8
; CHECK-NEXT:   %new = fadd double %1, %val
; CHECK-NEXT:   store double %new, ptr addrspace(5) %ptr, align 8
; CHECK-NEXT:   ret double %1
}

define i32 @cmpxchg_local(ptr addrspace(5) %ptr, i32 %cmp, i32 %new) {
  %pair = cmpxchg ptr addrspace(5) %ptr, i32 %cmp, i32 %new acquire acquire
  %res = extractvalue { i32, i1 } %pair, 0
  ret i32 %res
; CHECK-LABEL: @cmpxchg_local
; CHECK:   %1 = load i32, ptr addrspace(5) %ptr, align 4
; CHECK-NEXT:   %2 = icmp eq i32 %1, %cmp
; CHECK-NEXT:   %3 = select i1 %2, i32 %new, i32 %1
; CHECK-NEXT:   store i32 %3, ptr addrspace(5) %ptr, align 4
; CHECK-NEXT:   %4 = insertvalue { i32, i1 } poison, i32 %1, 0
; CHECK-NEXT:   %5 = insertvalue { i32, i1 } %4, i1 %2, 1
; CHECK-NEXT:   %res = extractvalue { i32, i1 } %5, 0
; CHECK-NEXT:   ret i32 %res
}

define i1 @cmpxchg_local_weak_volatile(ptr addrspace(5) %ptr, i64 %cmp, i64 %new) {
  %pair = cmpxchg weak volatile ptr addrspace(5) %ptr, i64 %cmp, i64 %new seq_cst monotonic
  %ok = extractvalue { i64, i1 } %pair, 1
  ret i1 %ok
; CHECK-LABEL: @cmpxchg_local_weak_volatile
; CHECK:   %1 = load i64, ptr addrspace(5) %ptr, align 8
; CHECK-NEXT:   %2 = icmp eq i64 %1, %cmp
; CHECK-NEXT:   %3 = select i1 %2, i64 %new, i64 %1
; CHECK-NEXT:   store i64 %3, ptr addrspace(5) %ptr, align 8
; CHECK:   %ok = extractvalue { i64, i1 } %5, 1
; CHECK-NEXT:   ret i1 %ok
}
