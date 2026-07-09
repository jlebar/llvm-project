; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_75 -mattr=+ptx70 2>&1 | FileCheck %s --check-prefix=NOAFN
; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_70 -mattr=+ptx70 2>&1 | FileCheck %s --check-prefix=SM70

; tanh.approx.f32 is the only implementation of ftanh: without the afn flag
; (or on targets older than sm_75) we should get a clear error message rather
; than a cannot-select crash.

declare float @llvm.tanh.f32(float)

; NOAFN: error:
; NOAFN-SAME: in function test_ftanh_safe
; NOAFN-SAME: 'ftanh' requires the afn fast-math flag
define float @test_ftanh_safe(float %a) {
  %r = tail call float @llvm.tanh.f32(float %a)
  ret float %r
}

; SM70: error: {{.*}}in function test_ftanh_afn_sm70
; SM70-SAME: 'ftanh' requires sm_75 or later and PTX ISA 7.0 or later
define float @test_ftanh_afn_sm70(float %a) {
  %r = tail call afn float @llvm.tanh.f32(float %a)
  ret float %r
}
