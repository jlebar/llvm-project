; RUN: not llc -mtriple=amdgcn -mcpu=tahiti -filetype=null %s 2>&1 | FileCheck %s
; RUN: not llc -mtriple=amdgcn -mcpu=gfx942 -filetype=null %s 2>&1 | FileCheck %s
; RUN: not llc -mtriple=amdgcn -mcpu=gfx1100 -filetype=null %s 2>&1 | FileCheck %s

; There is no f64 fpow expansion or libcall. Check that this reports a
; missing libcall instead of failing to select.

; CHECK: error: no libcall available for fpow
define double @v_pow_f64(double %x, double %y) {
  %pow = call double @llvm.pow.f64(double %x, double %y)
  ret double %pow
}

; CHECK: error: no libcall available for fpow
define double @v_pow_f64_fast(double %x, double %y) {
  %pow = call fast double @llvm.pow.f64(double %x, double %y)
  ret double %pow
}

; CHECK: error: no libcall available for fpow
; CHECK: error: no libcall available for fpow
define <2 x double> @v_pow_v2f64(<2 x double> %x, <2 x double> %y) {
  %pow = call <2 x double> @llvm.pow.v2f64(<2 x double> %x, <2 x double> %y)
  ret <2 x double> %pow
}
