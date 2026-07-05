; RUN: llc -mtriple=amdgcn-amd-amdhsa -mcpu=gfx908 -verify-machineinstrs < %s | FileCheck %s

; The scheduler reorders the COPY of $agpr0 into the accumulator with
; the other subregister defs of the accumulator when it reschedules the
; copy next to the inline asm def. This used to leave the read-undef
; flags on the wrong defs, failing -verify-machineinstrs with "No live
; segment at use" and hitting "Must have following segment" in
; LiveIntervals::handleMoveDown on the next scheduling round (issues
; #129028 and #130884).

; CHECK-LABEL: {{^}}sched_subreg_def_reorder:
; CHECK: v_mfma_f32_16x16x1{{.*}}f32
; CHECK: s_endpgm
define amdgpu_kernel void @sched_subreg_def_reorder(float %v0, float %v1) #0 {
  %agpr0 = call float asm sideeffect "; def $0", "=${a0}"()
  %agpr.vec = insertelement <16 x float> zeroinitializer, float %agpr0, i32 0
  %vgpr.vec = call <16 x float> asm sideeffect "; def $0, use $1", "=v,v"(<16 x float> %agpr.vec)
  %mfma0 = call <16 x float> @llvm.amdgcn.mfma.f32.16x16x1f32(float %v0, float %v1, <16 x float> %vgpr.vec, i32 0, i32 0, i32 0)
  %insert = insertelement <16 x float> %mfma0, float %agpr0, i32 8
  %mfma1 = call <16 x float> @llvm.amdgcn.mfma.f32.16x16x1f32(float %v0, float %v1, <16 x float> %insert, i32 0, i32 0, i32 0)
  %mfma1.3 = extractelement <16 x float> %mfma1, i32 3
  call void asm sideeffect "; use $0", "{a1}"(float %mfma1.3)
  ret void
}

declare <16 x float> @llvm.amdgcn.mfma.f32.16x16x1f32(float, float, <16 x float>, i32 immarg, i32 immarg, i32 immarg)

attributes #0 = { "amdgpu-waves-per-eu"="10,10" }
