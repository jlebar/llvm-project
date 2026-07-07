; RUN: llc -march=nvptx64 < %s | FileCheck %s

; The legacy nvvm.abs intrinsics are upgraded to llvm.abs with
; is_int_min_poison=false, preserving the defined INT_MIN -> INT_MIN behavior
; of the original neg+icmp+select upgrade. NVPTX expands that to neg+max;
; abs.s32/abs.s64 selection is reserved for is_int_min_poison=true
; (ABS_MIN_POISON).

declare i32 @llvm.nvvm.abs.i(i32)
declare i64 @llvm.nvvm.abs.ll(i64)

define i32 @test_nvvm_abs_i(i32 %x) {
; CHECK-LABEL: test_nvvm_abs_i(
; CHECK: neg.s32
; CHECK: max.s32
; CHECK: ret;
  %r = call i32 @llvm.nvvm.abs.i(i32 %x)
  ret i32 %r
}

define i64 @test_nvvm_abs_ll(i64 %x) {
; CHECK-LABEL: test_nvvm_abs_ll(
; CHECK: neg.s64
; CHECK: max.s64
; CHECK: ret;
  %r = call i64 @llvm.nvvm.abs.ll(i64 %x)
  ret i64 %r
}
