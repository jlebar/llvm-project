; RUN: not llc < %s -mtriple=nvptx -mcpu=sm_20 2>&1 | FileCheck %s

; Check that we get a clear error message on fsin without fast-math enabled,
; rather than a cannot-select crash.

declare float @llvm.sin.f32(float)

; CHECK: error:
; CHECK-SAME: in function test_fsin_safe
; CHECK-SAME: 'fsin' requires the afn fast-math flag
define float @test_fsin_safe(float %a) #0 {
  %r = tail call float @llvm.sin.f32(float %a)
  ret float %r
}

attributes #0 = { "unsafe-fp-math" = "false" }

; CHECK: error:
; CHECK-SAME: in function test_fsin_f64
; CHECK-SAME: 'fsin' is not supported for f64
define double @test_fsin_f64(double %a) {
  %r = tail call afn double @llvm.sin.f64(double %a)
  ret double %r
}
