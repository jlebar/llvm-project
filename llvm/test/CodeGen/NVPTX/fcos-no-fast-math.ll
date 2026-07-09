; RUN: not llc < %s -mtriple=nvptx -mcpu=sm_20 2>&1 | FileCheck %s

; Check that we get a clear error message on fcos without fast-math enabled,
; rather than a cannot-select crash.

declare float @llvm.cos.f32(float)

; CHECK: error:
; CHECK-SAME: in function test_fcos_safe
; CHECK-SAME: 'fcos' requires the afn fast-math flag
define float @test_fcos_safe(float %a) #0 {
  %r = tail call float @llvm.cos.f32(float %a)
  ret float %r
}

attributes #0 = { "unsafe-fp-math" = "false" }

; CHECK: error:
; CHECK-SAME: in function test_fcos_f64
; CHECK-SAME: 'fcos' is not supported for f64
define double @test_fcos_f64(double %a) {
  %r = tail call afn double @llvm.cos.f64(double %a)
  ret double %r
}
