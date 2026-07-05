; REQUIRES: asserts
; RUN: llc -mtriple=amdgcn-amd-amdhsa -O3 -verify-machineinstrs \
; RUN:   -debug-only=amdgpu-rewrite-agpr-copy-mfma -filetype=null %s 2>&1 \
; RUN:   | FileCheck %s

; Reduced from a bf16 attention kernel (issue #204224). One of the spill
; slots considered by the AGPR copy MFMA rewrite pass has a discontiguous
; live interval, with a
; large gap where the slot's value is dead in memory. The register replacing
; the slot has to stay live across the gap, so checking interference against
; only the slot interval's covered segments used to pick a register that is
; busy inside the gap, and LiveRegMatrix::assign failed with an "Overlapping
; insert" assertion. Check that this compiles and that unspilling still
; happens for the slots where it is sound.

; CHECK: Reassigning SS#

target triple = "amdgcn-amd-amdhsa"

define amdgpu_kernel void @unspill_discontiguous_slot_interval(<16 x float> %i241, <16 x float> %i242, <16 x float> %i243, <16 x float> %i244, <16 x float> %i245, i1 %i255, <4 x i32> %i73, <4 x i32> %i74, float %i377, i1 %i630, <4 x bfloat> %i478, ptr addrspace(3) %arg, <8 x bfloat> %i263) #0 {
bb:
  %i16 = tail call i32 @llvm.amdgcn.mbcnt.hi(i32 0, i32 0)
  %i60 = or i32 %i16, 64
  %i61 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i60, i32 0, i32 0)
  %i62 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i60, i32 1, i32 0)
  %i63 = or i32 %i16, 128
  %i64 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i63, i32 0, i32 0)
  %i65 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i63, i32 1, i32 0)
  %i68 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i16, i32 32, i32 0)
  %i69 = or i32 %i16, 256
  %i70 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i69, i32 0, i32 0)
  %i71 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i16, i32 1, i32 0)
  %i17 = zext i32 %i16 to i64
  %i51 = shl i64 %i17, 1
  %i56 = trunc i64 %i51 to i32
  %i76 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i56, i32 0, i32 0)
  %i66 = or i32 %i16, 1
  %i77 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i66, i32 0, i32 0)
  %i79 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i16, i32 0, i32 0)
  %i80 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 %i56, i32 1, i32 0)
  %i35 = load i32, ptr null, align 4
  %i36 = zext i32 %i35 to i64
  %i39 = sub i64 0, %i36
  %i90 = trunc i64 %i39 to i32
  %i93 = tail call i32 @llvm.umin.i32(i32 1, i32 %i90)
  %i109 = and i64 %i17, 1
  %.tr2330.i = trunc i64 %i109 to i32
  %.neg12572.i = mul i32 %.tr2330.i, -4
  br label %bb140

bb140:                                            ; preds = %bb140, %bb
  %i179 = tail call { float, float, i64, i64, float } asm sideeffect "\0A                                    v_mov_b32 $4, 0xc61c4000\0A                                    v_cmp_lt_i32_e64 $2, $6, $5\0A                                    v_cmp_lt_i32_e64 $3, $9, $8\0A                                    v_cndmask_b32_e64 $0, $4, $7, $2\0A                                    v_cndmask_b32_e64 $1, $4, $10, $3\0A                                    ", "=v,=v,=&s,=&s,=&v,v,n,v,v,n,v,~{vcc}"(i32 0, i32 0, float 0.000000e+00, i32 %.tr2330.i, i32 0, float 0.000000e+00)
  %i191 = tail call { i32, i32 } @llvm.amdgcn.permlane32.swap(i32 0, i32 0, i1 false, i1 false)
  %i247 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> zeroinitializer, i32 0, i32 0, i32 0)
  %i248 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> splat (float 1.000000e+00), i32 0, i32 0, i32 0)
  %i249 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> splat (float +qnan), i32 0, i32 0, i32 0)
  %i250 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i241, i32 0, i32 0, i32 0)
  %i251 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i242, i32 0, i32 0, i32 0)
  %i252 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i243, i32 0, i32 0, i32 0)
  %i253 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i244, i32 0, i32 0, i32 0)
  %i254 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i245, i32 0, i32 0, i32 0)
  br i1 %i255, label %._crit_edge.i.loopexit, label %bb140

._crit_edge.i.loopexit:                           ; preds = %bb140
  %.not.i = icmp eq i64 %i36, 0
  br i1 %.not.i, label %bb720, label %bb259

bb259:                                            ; preds = %._crit_edge.i.loopexit
  %i59 = tail call <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.not7772.not.i = icmp ugt i32 1, %i35
  br i1 %.not7772.not.i, label %bb313, label %bb319

bb313:                                            ; preds = %bb259
  br label %bb319

bb319:                                            ; preds = %bb313, %bb259
  %i32020 = phi <16 x float> [ zeroinitializer, %bb313 ], [ splat (float 1.000000e+00), %bb259 ]
  %i365 = extractelement <16 x float> %i32020, i64 0
  %i3661 = tail call float @llvm.amdgcn.exp2.f32(float %i365)
  %i372 = tail call float @llvm.amdgcn.exp2.f32(float 0.000000e+00)
  %i378 = tail call float @llvm.amdgcn.exp2.f32(float %i377)
  %i375 = tail call float @llvm.amdgcn.exp2.f32(float +qnan)
  %i430 = fadd float %i372, 1.000000e+00
  %i431 = fadd float %i375, %i430
  %i432 = fadd float %i378, %i431
  %i436 = fadd float 1.000000e+00, %i432
  %i437 = fadd float 1.000000e+00, %i436
  %i399 = tail call float @llvm.amdgcn.exp2.f32(float 1.000000e+00)
  %i439 = fadd float %i399, %i437
  %i442 = fadd float %i372, %i439
  %i444 = bitcast float %i442 to i32
  %i445 = tail call { i32, i32 } @llvm.amdgcn.permlane32.swap(i32 0, i32 %i444, i1 false, i1 false)
  %i192 = extractvalue { i32, i32 } %i191, 0
  %i194 = insertelement <2 x i32> zeroinitializer, i32 %i192, i64 0
  %i193 = extractvalue { i32, i32 } %i191, 1
  %i195 = insertelement <2 x i32> %i194, i32 %i193, i64 1
  %i196 = bitcast <2 x i32> %i195 to <2 x float>
  %i197 = extractelement <2 x float> %i196, i64 %i109
  %i456 = fadd float %i197, %i442
  %i489 = fmul <16 x float> %i247, zeroinitializer
  %i490 = fmul <16 x float> %i248, zeroinitializer
  %i491 = fmul <16 x float> %i249, zeroinitializer
  %i492 = fmul <16 x float> %i250, zeroinitializer
  %i493 = fmul <16 x float> %i251, zeroinitializer
  %i494 = fmul <16 x float> %i252, zeroinitializer
  %i496 = fmul <16 x float> %i254, zeroinitializer
  %i499 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i489, i32 0, i32 0, i32 0)
  %i500 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i490, i32 0, i32 0, i32 0)
  %i501 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i491, i32 0, i32 0, i32 0)
  %i502 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i492, i32 0, i32 0, i32 0)
  %i503 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i493, i32 0, i32 0, i32 0)
  %i504 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i494, i32 0, i32 0, i32 0)
  %i505 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> zeroinitializer, i32 0, i32 0, i32 0)
  %i506 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i496, i32 0, i32 0, i32 0)
  %i508 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i499, i32 0, i32 0, i32 0)
  %i509 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i500, i32 0, i32 0, i32 0)
  %i510 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i501, i32 0, i32 0, i32 0)
  %i511 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i502, i32 0, i32 0, i32 0)
  %i512 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i503, i32 0, i32 0, i32 0)
  %i513 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i504, i32 0, i32 0, i32 0)
  %i514 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i505, i32 0, i32 0, i32 0)
  %i515 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i506, i32 0, i32 0, i32 0)
  %i518 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i508, i32 0, i32 0, i32 0)
  %i519 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i509, i32 0, i32 0, i32 0)
  %i520 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i510, i32 0, i32 0, i32 0)
  %i521 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i511, i32 0, i32 0, i32 0)
  %i522 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i512, i32 0, i32 0, i32 0)
  %i524 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i514, i32 0, i32 0, i32 0)
  %i525 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i515, i32 0, i32 0, i32 0)
  %i516 = fptrunc <16 x float> %i241 to <16 x bfloat>
  %i526 = shufflevector <16 x bfloat> %i516, <16 x bfloat> zeroinitializer, <8 x i32> <i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  %i527 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i518, i32 0, i32 0, i32 0)
  %i528 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i519, i32 0, i32 0, i32 0)
  %i529 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i520, i32 0, i32 0, i32 0)
  %i530 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i521, i32 0, i32 0, i32 0)
  %i531 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i522, i32 0, i32 0, i32 0)
  %i532 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i526, <16 x float> %i513, i32 0, i32 0, i32 0)
  %i533 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> <bfloat 0.000000e+00, bfloat 0.000000e+00, bfloat 0.000000e+00, bfloat 0.000000e+00, bfloat +qnan, bfloat +qnan, bfloat +qnan, bfloat +qnan>, <8 x bfloat> splat (bfloat +qnan), <16 x float> %i524, i32 0, i32 0, i32 0)
  %i534 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> splat (bfloat 1.000000e+00), <16 x float> %i525, i32 0, i32 0, i32 0)
  %i556 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 43008), align 16
  %i560 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 45056), align 16
  %i564 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 47104), align 16
  %i570 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 49152), align 16
  %i572 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 51200), align 16
  %i578 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 53248), align 16
  %i580 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 55296), align 16
  %i586 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 57344), align 16
  %i589 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 61440), align 16
  %i591 = load <8 x bfloat>, ptr addrspace(3) null, align 16
  %i548 = load <8 x bfloat>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 38912), align 16
  %i269 = bitcast <4 x i32> %i61 to <8 x bfloat>
  %i542 = load <8 x bfloat>, ptr addrspace(3) %arg, align 16
  %i266 = bitcast <4 x i32> %i59 to <8 x bfloat>
  %i595 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i263, <16 x float> zeroinitializer, i32 0, i32 0, i32 0)
  %i597 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i542, <8 x bfloat> %i266, <16 x float> %i595, i32 0, i32 0, i32 0)
  %i599 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i548, <8 x bfloat> %i269, <16 x float> %i597, i32 0, i32 0, i32 0)
  %i272 = bitcast <4 x i32> %i62 to <8 x bfloat>
  %i601 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i272, <16 x float> %i599, i32 0, i32 0, i32 0)
  %i275 = bitcast <4 x i32> %i64 to <8 x bfloat>
  %i278 = bitcast <4 x i32> %i65 to <8 x bfloat>
  %i603 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i556, <8 x bfloat> %i275, <16 x float> %i601, i32 0, i32 0, i32 0)
  %i605 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i278, <16 x float> %i603, i32 0, i32 0, i32 0)
  %i604 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> zeroinitializer, i32 0, i32 0, i32 0)
  %i606 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i560, <8 x bfloat> splat (bfloat +qnan), <16 x float> %i604, i32 0, i32 0, i32 0)
  %i607 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i564, <8 x bfloat> zeroinitializer, <16 x float> %i605, i32 0, i32 0, i32 0)
  %i284 = bitcast <4 x i32> %i68 to <8 x bfloat>
  %i608 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i284, <16 x float> %i606, i32 0, i32 0, i32 0)
  %i287 = bitcast <4 x i32> %i70 to <8 x bfloat>
  %i610 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i287, <16 x float> %i608, i32 0, i32 0, i32 0)
  %i611 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i572, <8 x bfloat> zeroinitializer, <16 x float> %i607, i32 0, i32 0, i32 0)
  %i290 = bitcast <4 x i32> %i71 to <8 x bfloat>
  %i612 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i570, <8 x bfloat> %i290, <16 x float> %i610, i32 0, i32 0, i32 0)
  %i293 = bitcast <4 x i32> %i73 to <8 x bfloat>
  %i614 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i293, <16 x float> %i612, i32 0, i32 0, i32 0)
  %i615 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i580, <8 x bfloat> zeroinitializer, <16 x float> %i611, i32 0, i32 0, i32 0)
  %i296 = bitcast <4 x i32> %i74 to <8 x bfloat>
  %i616 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i578, <8 x bfloat> %i296, <16 x float> %i614, i32 0, i32 0, i32 0)
  %i618 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i616, i32 0, i32 0, i32 0)
  %i620 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i586, <8 x bfloat> zeroinitializer, <16 x float> %i618, i32 0, i32 0, i32 0)
  %i622 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i620, i32 0, i32 0, i32 0)
  %i623 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i591, <8 x bfloat> zeroinitializer, <16 x float> %i615, i32 0, i32 0, i32 0)
  %i624 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> %i589, <8 x bfloat> zeroinitializer, <16 x float> %i622, i32 0, i32 0, i32 0)
  %i625 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i623, i32 0, i32 0, i32 0)
  %.not9369.not.i = icmp ugt i32 1, %i93
  %i629 = icmp ult i32 0, %i90
  %i63038 = and i1 %.not9369.not.i, %i629
  br i1 %i63038, label %bb631, label %bb646

bb631:                                            ; preds = %bb319
  %i634 = extractelement <16 x float> %i624, i64 0
  %i636 = tail call { float, float, i64, i64, float } asm sideeffect "\0A                                    v_mov_b32 $4, 0xc61c4000\0A                                    v_cmp_lt_i32_e64 $2, $6, $5\0A                                    v_cmp_lt_i32_e64 $3, $9, $8\0A                                    v_cndmask_b32_e64 $0, $4, $7, $2\0A                                    v_cndmask_b32_e64 $1, $4, $10, $3\0A                                    ", "=v,=v,=&s,=&s,=&v,v,n,v,v,n,v,~{vcc}"(i32 %.neg12572.i, i32 0, float 1.000000e+00, i32 1, i32 0, float %i634)
  br label %bb646

bb646:                                            ; preds = %bb631, %bb319
  br i1 %i630, label %bb648, label %bb653

bb648:                                            ; preds = %bb646
  %i650 = extractelement <16 x float> %i625, i64 0
  %i652 = tail call { float, float, i64, i64, float } asm sideeffect "\0A                                    v_mov_b32 $4, 0xc61c4000\0A                                    v_cmp_lt_i32_e64 $2, $6, $5\0A                                    v_cmp_lt_i32_e64 $3, $9, $8\0A                                    v_cndmask_b32_e64 $0, $4, $7, $2\0A                                    v_cndmask_b32_e64 $1, $4, $10, $3\0A                                    ", "=v,=v,=&s,=&s,=&v,v,n,v,v,n,v,~{vcc}"(i32 0, i32 0, float 0.000000e+00, i32 0, i32 0, float %i650)
  br label %bb653

bb653:                                            ; preds = %bb648, %bb646
  %i674 = fmul <16 x float> %i527, zeroinitializer
  %i675 = fmul <16 x float> %i528, zeroinitializer
  %i676 = fmul <16 x float> %i529, zeroinitializer
  %i677 = fmul <16 x float> %i530, zeroinitializer
  %i678 = fmul <16 x float> %i531, zeroinitializer
  %i679 = fmul <16 x float> %i532, zeroinitializer
  %i680 = fmul <16 x float> %i533, zeroinitializer
  %i681 = fmul <16 x float> %i534, zeroinitializer
  %i684 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i674, i32 0, i32 0, i32 0)
  %i686 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i676, i32 0, i32 0, i32 0)
  %i689 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i679, i32 0, i32 0, i32 0)
  %i690 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i680, i32 0, i32 0, i32 0)
  %i691 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i681, i32 0, i32 0, i32 0)
  %i693 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i684, i32 0, i32 0, i32 0)
  %i707 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i678, i32 0, i32 0, i32 0)
  %i713 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i675, i32 0, i32 0, i32 0)
  %i715 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i677, i32 0, i32 0, i32 0)
  br label %nn_attention_gpu_amd_structur6A6A6A6A6A6A_384cc4c79495a048.exit

bb720:                                            ; preds = %._crit_edge.i.loopexit
  %i725 = bitcast <4 x i32> %i77 to <8 x bfloat>
  %i72239 = bitcast <4 x i32> %i76 to <8 x bfloat>
  %i723 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i72239, <16 x float> zeroinitializer, i32 0, i32 0, i32 0)
  %i726 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i725, <16 x float> %i723, i32 0, i32 0, i32 0)
  %i731 = bitcast <4 x i32> %i80 to <8 x bfloat>
  %i728 = bitcast <4 x i32> %i79 to <8 x bfloat>
  %i729 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i728, <16 x float> %i726, i32 0, i32 0, i32 0)
  %i732 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> %i731, <16 x float> %i729, i32 0, i32 0, i32 0)
  %i750 = extractelement <16 x float> %i732, i64 0
  %i752 = tail call { float, float, i64, i64, float } asm sideeffect "\0A                                    v_mov_b32 $4, 0xc61c4000\0A                                    v_cmp_lt_i32_e64 $2, $6, $5\0A                                    v_cmp_lt_i32_e64 $3, $9, $8\0A                                    v_cndmask_b32_e64 $0, $4, $7, $2\0A                                    v_cndmask_b32_e64 $1, $4, $10, $3\0A                                    ", "=v,=v,=&s,=&s,=&v,v,n,v,v,n,v,~{vcc}"(i32 %.neg12572.i, i32 0, float 0.000000e+00, i32 0, i32 0, float %i750)
  %i763 = fmul <16 x float> %i250, zeroinitializer
  %i773 = tail call <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat> zeroinitializer, <8 x bfloat> zeroinitializer, <16 x float> %i763, i32 0, i32 0, i32 0)
  br label %nn_attention_gpu_amd_structur6A6A6A6A6A6A_384cc4c79495a048.exit

nn_attention_gpu_amd_structur6A6A6A6A6A6A_384cc4c79495a048.exit: ; preds = %bb720, %bb653
  %.sroa.506.2 = phi <16 x float> [ %i253, %bb720 ], [ %i690, %bb653 ]
  %.sroa.422.2 = phi <16 x float> [ %i241, %bb720 ], [ %i689, %bb653 ]
  %.sroa.338.2 = phi <16 x float> [ %i251, %bb720 ], [ %i707, %bb653 ]
  %.sroa.254.2 = phi <16 x float> [ %i773, %bb720 ], [ %i715, %bb653 ]
  %.sroa.170.2 = phi <16 x float> [ %i249, %bb720 ], [ %i686, %bb653 ]
  %.sroa.86.2 = phi <16 x float> [ %i248, %bb720 ], [ %i713, %bb653 ]
  %.sroa.01465.2 = phi <16 x float> [ %i247, %bb720 ], [ %i693, %bb653 ]
  %.sroa.590.2 = phi <16 x float> [ %i254, %bb720 ], [ %i691, %bb653 ]
  %.2 = phi float [ 0.000000e+00, %bb720 ], [ %i456, %bb653 ]
  %.sroa.6212505.204.vec.insert.i = shufflevector <16 x float> %.sroa.254.2, <16 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  %i820 = fptrunc <4 x float> %.sroa.6212505.204.vec.insert.i to <4 x bfloat>
  %i822 = bitcast <4 x bfloat> %i820 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i822, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.8212511.268.vec.insert.i = shufflevector <16 x float> %.sroa.338.2, <16 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  %i823 = fptrunc <4 x float> %.sroa.8212511.268.vec.insert.i to <4 x bfloat>
  %i82540 = bitcast <4 x bfloat> %i823 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i82540, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.10212517.332.vec.insert.i = shufflevector <16 x float> %.sroa.422.2, <16 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  %i826 = fptrunc <4 x float> %.sroa.10212517.332.vec.insert.i to <4 x bfloat>
  %i828 = bitcast <4 x bfloat> %i826 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i828, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.12212523.396.vec.insert.i = shufflevector <16 x float> %.sroa.506.2, <16 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  %i829 = fptrunc <4 x float> %.sroa.12212523.396.vec.insert.i to <4 x bfloat>
  %i831 = bitcast <4 x bfloat> %i829 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i831, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.14212529.460.vec.insert.i = shufflevector <16 x float> %.sroa.590.2, <16 x float> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  %i832 = fptrunc <4 x float> %.sroa.14212529.460.vec.insert.i to <4 x bfloat>
  %i834 = bitcast <4 x bfloat> %i832 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i834, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.7.28.vec.insert.i = shufflevector <16 x float> %.sroa.01465.2, <16 x float> zeroinitializer, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
  %i835 = fptrunc <4 x float> %.sroa.7.28.vec.insert.i to <4 x bfloat>
  %i837 = bitcast <4 x bfloat> %i835 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i837, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %i806 = tail call float @llvm.amdgcn.rcp.f32(float %.2)
  %i807 = insertelement <16 x float> zeroinitializer, float %i806, i64 0
  %i808 = shufflevector <16 x float> %i807, <16 x float> zeroinitializer, <16 x i32> zeroinitializer
  %i810 = fmul <16 x float> %.sroa.86.2, %i808
  %.sroa.27.92.vec.insert.i = shufflevector <16 x float> %i810, <16 x float> zeroinitializer, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
  %i838 = fptrunc <4 x float> %.sroa.27.92.vec.insert.i to <4 x bfloat>
  %i840 = bitcast <4 x bfloat> %i838 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i840, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  %.sroa.47.156.vec.insert.i = shufflevector <16 x float> %.sroa.170.2, <16 x float> zeroinitializer, <4 x i32> <i32 4, i32 5, i32 6, i32 7>
  %i841 = fptrunc <4 x float> %.sroa.47.156.vec.insert.i to <4 x bfloat>
  %i843 = bitcast <4 x bfloat> %i841 to <2 x i32>
  tail call void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32> %i843, <4 x i32> zeroinitializer, i32 0, i32 0, i32 0)
  ret void
}

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind willreturn memory(none)
declare i32 @llvm.amdgcn.mbcnt.hi(i32, i32) #1

; Function Attrs: convergent nocallback nofree nounwind willreturn memory(none)
declare { i32, i32 } @llvm.amdgcn.permlane32.swap(i32, i32, i1 immarg, i1 immarg) #2

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(read)
declare <4 x i32> @llvm.amdgcn.raw.buffer.load.v4i32(<4 x i32>, i32, i32, i32 immarg) #3

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(write)
declare void @llvm.amdgcn.raw.buffer.store.v2i32(<2 x i32>, <4 x i32>, i32, i32, i32 immarg) #4

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.umin.i32(i32, i32) #5

; Function Attrs: convergent nocallback nocreateundeforpoison nofree nosync nounwind willreturn memory(none)
declare <16 x float> @llvm.amdgcn.mfma.f32.32x32x16.bf16(<8 x bfloat>, <8 x bfloat>, <16 x float>, i32 immarg, i32 immarg, i32 immarg) #6

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare float @llvm.amdgcn.exp2.f32(float) #5

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare float @llvm.amdgcn.rcp.f32(float) #5

attributes #0 = { "amdgpu-flat-work-group-size"="1,256" "target-cpu"="gfx950" }
attributes #1 = { nocallback nocreateundeforpoison nofree nosync nounwind willreturn memory(none) }
attributes #2 = { convergent nocallback nofree nounwind willreturn memory(none) }
attributes #3 = { nocallback nofree nosync nounwind willreturn memory(read) }
attributes #4 = { nocallback nofree nosync nounwind willreturn memory(write) }
attributes #5 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
attributes #6 = { convergent nocallback nocreateundeforpoison nofree nosync nounwind willreturn memory(none) }
