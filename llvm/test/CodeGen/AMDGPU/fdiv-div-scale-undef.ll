; RUN: llc -mtriple=amdgcn -mcpu=gfx90a -verify-machineinstrs < %s | FileCheck %s

; The fdiv expansion creates DIV_SCALE nodes whose src0 is the same value as
; src1 or src2, and v_div_scale requires the same of its register operands.
; Post-legalization simplification can turn the operands into undef, and each
; undef use is materialized as a separate register, so a DIV_SCALE with undef
; src0 must fold away instead of reaching instruction selection.

; CHECK-LABEL: {{^}}fdiv_undef_elt:
; CHECK-NOT: v_div_scale
define amdgpu_kernel void @fdiv_undef_elt(<2 x float> %x, i1 %cond) {
entry:
  %shuf = shufflevector <2 x float> %x, <2 x float> zeroinitializer, <8 x i32> <i32 0, i32 1, i32 poison, i32 poison, i32 poison, i32 poison, i32 poison, i32 poison>
  %vec = shufflevector <8 x float> <float 0.0, float 1.0, float 1.0, float 1.0, float 1.0, float 1.0, float 1.0, float 1.0>, <8 x float> %shuf, <8 x i32> <i32 0, i32 1, i32 2, i32 3, i32 8, i32 9, i32 poison, i32 poison>
  %div = fdiv <8 x float> %vec, %vec
  br i1 %cond, label %truncstore, label %convert

truncstore:
  %elt0 = extractelement <8 x float> %div, i64 0
  %half0 = fptrunc float %elt0 to half
  store half %half0, ptr addrspace(1) null, align 2
  ret void

convert:
  %elt1 = extractelement <8 x float> %div, i64 0
  %int1 = fptoui float %elt1 to i32
  %fp1 = uitofp i32 %int1 to double
  %add = fadd double 0.0, %fp1
  store double %add, ptr addrspace(1) null, align 8
  ret void
}
