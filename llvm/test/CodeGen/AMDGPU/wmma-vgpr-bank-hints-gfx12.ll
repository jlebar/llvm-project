; RUN: llc -mtriple=amdgcn -mcpu=gfx1200 < %s | FileCheck %s

; A dependent WMMA issues back to back only when its matrix A, B and C
; operands start in three different VGPR banks (bank = starting register
; index % 4); any shared bank costs 2 extra cycles per issue. Each operand is
; a multiple of 4 VGPRs wide, so consecutive allocation puts all three
; operands in the same bank. Check that register allocation hints spread the
; operands over different banks. For SWMMAC the accumulator is the tied vdst
; and src2 is the sparsity index.

define amdgpu_kernel void @wmma_f32_16x16x16_f16_loop(ptr addrspace(1) %out, ptr addrspace(1) %pa, ptr addrspace(1) %pb, i32 %n) {
; CHECK-LABEL: wmma_f32_16x16x16_f16_loop:
; CHECK: v_wmma_f32_16x16x16_f16 v[0:7], v[9:12], v[14:17], v[0:7]
entry:
  %a = load <8 x half>, ptr addrspace(1) %pa
  %b = load <8 x half>, ptr addrspace(1) %pb
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %loop ]
  %c = phi <8 x float> [ zeroinitializer, %entry ], [ %d, %loop ]
  %d = call <8 x float> @llvm.amdgcn.wmma.f32.16x16x16.f16.v8f32.v8f16(<8 x half> %a, <8 x half> %b, <8 x float> %c)
  %i.next = add i32 %i, 1
  %cond = icmp eq i32 %i.next, %n
  br i1 %cond, label %exit, label %loop

exit:
  store <8 x float> %d, ptr addrspace(1) %out
  ret void
}

define amdgpu_kernel void @swmmac_f32_16x16x32_f16_loop(ptr addrspace(1) %out, ptr addrspace(1) %pa, ptr addrspace(1) %pb, i16 %idx, i32 %n) {
; CHECK-LABEL: swmmac_f32_16x16x32_f16_loop:
; CHECK: v_swmmac_f32_16x16x32_f16 v[0:7], v[18:21], v[9:16], v8
entry:
  %a = load <8 x half>, ptr addrspace(1) %pa
  %b = load <16 x half>, ptr addrspace(1) %pb
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %loop ]
  %c = phi <8 x float> [ zeroinitializer, %entry ], [ %d, %loop ]
  %d = call <8 x float> @llvm.amdgcn.swmmac.f32.16x16x32.f16.v8f32.v8f16.v16f16.i16(<8 x half> %a, <16 x half> %b, <8 x float> %c, i16 %idx)
  %i.next = add i32 %i, 1
  %cond = icmp eq i32 %i.next, %n
  br i1 %cond, label %exit, label %loop

exit:
  store <8 x float> %d, ptr addrspace(1) %out
  ret void
}

declare <8 x float> @llvm.amdgcn.wmma.f32.16x16x16.f16.v8f32.v8f16(<8 x half>, <8 x half>, <8 x float>)
declare <8 x float> @llvm.amdgcn.swmmac.f32.16x16x32.f16.v8f32.v8f16.v16f16.i16(<8 x half>, <16 x half>, <8 x float>, i16)
