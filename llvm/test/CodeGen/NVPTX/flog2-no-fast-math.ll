; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_20 2>&1 | FileCheck %s
; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_20 -nvptx-approx-log2f32 2>&1 | FileCheck --check-prefix=FLAG %s

; lg2.approx.f32 is the only implementation of log2: without the afn flag or
; -nvptx-approx-log2f32 we should get a clear error message rather than a "no
; libcall available" crash.

declare float @llvm.log2.f32(float)
declare half @llvm.log2.f16(half)
declare double @llvm.log2.f64(double)

; CHECK: error:
; CHECK-SAME: in function test_flog2_safe
; CHECK-SAME: 'flog2' requires the afn fast-math flag or -nvptx-approx-log2f32
define float @test_flog2_safe(float %a) {
  %r = tail call float @llvm.log2.f32(float %a)
  ret float %r
}

; CHECK: error:
; CHECK-SAME: in function test_flog2_f16_safe
; CHECK-SAME: 'flog2' requires the afn fast-math flag or -nvptx-approx-log2f32
define half @test_flog2_f16_safe(half %a) {
  %r = tail call half @llvm.log2.f16(half %a)
  ret half %r
}

; PTX has no double-precision lg2, so f64 is rejected even with afn or
; -nvptx-approx-log2f32.
; CHECK: error:
; CHECK-SAME: in function test_flog2_f64
; CHECK-SAME: 'flog2' is not supported for f64
; FLAG: error:
; FLAG-SAME: in function test_flog2_f64
; FLAG-SAME: 'flog2' is not supported for f64
define double @test_flog2_f64(double %a) {
  %r = tail call afn double @llvm.log2.f64(double %a)
  ret double %r
}
