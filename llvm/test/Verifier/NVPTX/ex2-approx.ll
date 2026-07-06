; RUN: not llvm-as %s -o /dev/null 2>&1 | FileCheck %s

; PTX only defines ex2.approx for f32, f16, and f16x2 (plus bf16 and bf16x2
; with ftz). In particular there is no f64 variant.

define double @test_ex2_f64(double %a) {
  ; CHECK: unsupported type for nvvm.ex2.approx
  %r = call double @llvm.nvvm.ex2.approx.f64(double %a)
  ret double %r
}

; The legacy llvm.nvvm.ex2.approx.d spelling is rejected rather than
; auto-upgraded.
define double @test_ex2_d(double %a) {
  ; CHECK: unsupported type for nvvm.ex2.approx
  %r = call double @llvm.nvvm.ex2.approx.d(double %a)
  ret double %r
}

; bf16 requires the ftz variant.
define bfloat @test_ex2_bf16(bfloat %a) {
  ; CHECK: unsupported type for nvvm.ex2.approx
  %r = call bfloat @llvm.nvvm.ex2.approx.bf16(bfloat %a)
  ret bfloat %r
}

; f16 is only available without ftz.
define half @test_ex2_ftz_f16(half %a) {
  ; CHECK: unsupported type for nvvm.ex2.approx
  %r = call half @llvm.nvvm.ex2.approx.ftz.f16(half %a)
  ret half %r
}
