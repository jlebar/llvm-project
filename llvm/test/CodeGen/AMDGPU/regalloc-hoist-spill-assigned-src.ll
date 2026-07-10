; RUN: llc -mcpu=gfx1250 -global-isel -verify-regalloc < %s | FileCheck %s
;
; During the WWM-register regalloc round, spilling a WWM register whose
; value is a block live-in makes hoistSpillInsideBB insert the spill at
; the top of the block, past the basic-block prologue
; (SkipPHIsLabelsAndDebug). The prologue contains live-range split
; copies of other WWM registers, one of which is assigned to the same
; physical register as the register being spilled. Extending the
; spilled register's live range down to the store would overlap that
; copy's def: the store would save the clobbered value, and the
; LiveRegMatrix would no longer match the extended interval, failing
; "Inconsistent LiveInterval" in LiveIntervalUnion::extract when the
; register is later unassigned. The spiller must give up on hoisting
; instead.

; CHECK-LABEL: {{^}}test:
target triple = "amdgcn-amd-amdhsa"

define amdgpu_kernel void @test(ptr addrspace(1) %p2.coerce, i1 %cmp52, <2 x half> %0, ptr addrspace(3) %1, ptr addrspace(3) %2, <2 x half> %3, ptr addrspace(3) %4, ptr addrspace(3) %5, <2 x half> %6, ptr addrspace(3) %7, ptr addrspace(1) %arrayidx63.60, ptr addrspace(1) %arrayidx63.56, ptr addrspace(1) %arrayidx63.55, ptr addrspace(1) %arrayidx63.53, ptr addrspace(1) %arrayidx63.41, ptr addrspace(1) %arrayidx63.40, ptr addrspace(1) %arrayidx63.39, ptr addrspace(1) %arrayidx63.38, ptr addrspace(1) %arrayidx63.37, ptr addrspace(1) %arrayidx63.36, ptr addrspace(1) %arrayidx63.35, ptr addrspace(1) %arrayidx63.34, ptr addrspace(1) %arrayidx63.33, ptr addrspace(1) %arrayidx63.32, ptr addrspace(1) %arrayidx63.31, float %arrayidx63.62.promoted, float %arrayidx63.61.promoted, float %arrayidx63.60.promoted, <2 x half> %broadcast.splat350, <2 x half> %broadcast.splatinsert353, <2 x float> %8, <2 x float> %9, <2 x float> %10, <2 x float> %11, <2 x float> %invariant.op1147, <2 x float> %invariant.op1149, <2 x float> %12, <2 x float> %.reass1148.reass, <2 x float> %broadcast.splat362, <2 x float> %vec.phi544, <2 x float> %vec.phi511, <2 x float> %broadcast.splat414, <2 x float> %factor.op.fmul1164, <2 x half> %broadcast.splat336, ptr addrspace(3) %13, <2 x float> %broadcast.splat36467, <2 x float> %broadcast.splat368, <2 x float> %vec.phi538, <2 x float> %14, <2 x float> %vec.phi548, <2 x float> %invariant.op909, ptr addrspace(1) %arrayidx63.5445) {
entry:
  %15 = load volatile i32, ptr null, align 4
  %16 = cmpxchg ptr addrspace(3) null, i16 0, i16 0 release monotonic, align 16
  br i1 %cmp52, label %if.then53, label %for.body49.preheader

for.body49.preheader:                             ; preds = %entry
  %17 = load <2 x half>, ptr addrspace(3) %2, align 4
  %18 = fpext <2 x half> %17 to <2 x float>
  %19 = load <2 x half>, ptr addrspace(3) null, align 4
  %20 = load <2 x half>, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 48), align 16
  %arrayidx63.38.promoted = load float, ptr addrspace(1) %arrayidx63.38, align 4
  %arrayidx63.37.promoted = load float, ptr addrspace(1) %arrayidx63.37, align 4
  %arrayidx63.36.promoted = load float, ptr addrspace(1) %arrayidx63.36, align 4
  %arrayidx63.35.promoted = load float, ptr addrspace(1) %arrayidx63.35, align 4
  %arrayidx63.34.promoted = load float, ptr addrspace(1) %arrayidx63.34, align 4
  %arrayidx63.33.promoted = load float, ptr addrspace(1) %arrayidx63.53, align 4
  %arrayidx63.32.promoted = load float, ptr addrspace(1) %arrayidx63.33, align 4
  %arrayidx63.31.promoted = load float, ptr addrspace(1) null, align 4
  %arrayidx63.24.promoted = load float, ptr addrspace(1) %arrayidx63.55, align 4
  %arrayidx63.23.promoted = load float, ptr addrspace(1) %arrayidx63.60, align 4
  %arrayidx63.21.promoted = load float, ptr addrspace(1) %arrayidx63.41, align 4
  %arrayidx63.10.promoted = load float, ptr addrspace(1) %arrayidx63.40, align 4
  %arrayidx63.6.promoted = load float, ptr addrspace(1) %p2.coerce, align 4
  %21 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.62.promoted, i64 0
  %22 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.61.promoted, i64 0
  %23 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.60.promoted, i64 0
  %arrayidx63.57.promoted = load float, ptr addrspace(1) %arrayidx63.31, align 4
  %24 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.57.promoted, i64 0
  %25 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.62.promoted, i64 0
  %arrayidx63.39.promoted = load float, ptr addrspace(1) %arrayidx63.39, align 4
  %26 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.39.promoted, i64 0
  %27 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.38.promoted, i64 0
  %28 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.37.promoted, i64 0
  %29 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.36.promoted, i64 0
  %30 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.35.promoted, i64 0
  %31 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.34.promoted, i64 0
  %32 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.33.promoted, i64 0
  %33 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.32.promoted, i64 0
  %34 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.31.promoted, i64 0
  %35 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.24.promoted, i64 0
  %36 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.23.promoted, i64 0
  %arrayidx63.22.promoted = load float, ptr addrspace(1) %p2.coerce, align 4
  %37 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.22.promoted, i64 0
  %38 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.21.promoted, i64 0
  %39 = insertelement <2 x float> splat (float 1.000000e+00), float %arrayidx63.10.promoted, i64 0
  %40 = insertelement <2 x float> zeroinitializer, float %arrayidx63.6.promoted, i64 0
  %arrayidx63.2.promoted = load float, ptr addrspace(1) null, align 4
  %41 = insertelement <2 x float> zeroinitializer, float %arrayidx63.2.promoted, i64 0
  %42 = load half, ptr addrspace(3) getelementptr inbounds nuw (i8, ptr addrspace(3) null, i32 72), align 8
  %broadcast.splatinsert = insertelement <2 x half> zeroinitializer, half %42, i64 0
  %broadcast.splat = shufflevector <2 x half> %broadcast.splatinsert, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %43 = fpext <2 x half> %broadcast.splat to <2 x float>
  %44 = fpext <2 x half> %3 to <2 x float>
  %45 = load half, ptr addrspace(3) %1, align 2
  %broadcast.splatinsert305 = insertelement <2 x half> zeroinitializer, half %45, i64 0
  %broadcast.splat306 = shufflevector <2 x half> %broadcast.splatinsert305, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %46 = fpext <2 x half> %broadcast.splat306 to <2 x float>
  %47 = load half, ptr addrspace(3) %7, align 16
  %broadcast.splatinsert307 = insertelement <2 x half> zeroinitializer, half %47, i64 0
  %broadcast.splat308 = shufflevector <2 x half> %broadcast.splatinsert307, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %48 = fpext <2 x half> %broadcast.splat308 to <2 x float>
  %49 = load half, ptr addrspace(3) %4, align 8
  %broadcast.splatinsert331 = insertelement <2 x half> zeroinitializer, half %49, i64 0
  %broadcast.splat332 = shufflevector <2 x half> %broadcast.splatinsert331, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %50 = fpext <2 x half> %broadcast.splat332 to <2 x float>
  %51 = load half, ptr addrspace(3) %13, align 16
  %broadcast.splatinsert339 = insertelement <2 x half> zeroinitializer, half %51, i64 0
  %broadcast.splat340 = shufflevector <2 x half> %broadcast.splatinsert339, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %52 = fpext <2 x half> %broadcast.splat340 to <2 x float>
  %53 = fpext <2 x half> %6 to <2 x float>
  %broadcast.splat354 = shufflevector <2 x half> %broadcast.splatinsert353, <2 x half> zeroinitializer, <2 x i32> zeroinitializer
  %54 = fpext <2 x half> %broadcast.splat354 to <2 x float>
  %55 = load <2 x half>, ptr addrspace(3) %5, align 4
  %56 = fpext <2 x half> %0 to <2 x float>
  %broadcast.splat372 = shufflevector <2 x float> %8, <2 x float> zeroinitializer, <2 x i32> zeroinitializer
  %invariant.op933 = fmul <2 x float> %broadcast.splat372, %8
  br label %vector.body

vector.body:                                      ; preds = %vector.body.1, %for.body49.preheader
  %index = phi i32 [ 0, %for.body49.preheader ], [ %index.next.3, %vector.body.1 ]
  %vec.phi427 = phi <2 x float> [ zeroinitializer, %for.body49.preheader ], [ %.reass1156.reass, %vector.body.1 ]
  %vec.phi428 = phi <2 x float> [ %21, %for.body49.preheader ], [ %.reass1150.reass, %vector.body.1 ]
  %vec.phi429 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi4307 = phi <2 x float> [ %22, %for.body49.preheader ], [ %.reass1146.reass, %vector.body.1 ]
  %vec.phi43176 = phi <2 x float> [ zeroinitializer, %for.body49.preheader ], [ %.reass1148.reass, %vector.body.1 ]
  %vec.phi432 = phi <2 x float> [ %23, %for.body49.preheader ], [ splat (float 1.000000e+00), %vector.body.1 ]
  %vec.phi433 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi438 = phi <2 x float> [ %24, %for.body49.preheader ], [ splat (float 1.000000e+00), %vector.body.1 ]
  %vec.phi439 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi44077 = phi <2 x float> [ zeroinitializer, %for.body49.preheader ], [ %invariant.op909, %vector.body.1 ]
  %vec.phi441 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi442 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi443 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi444 = phi <2 x float> [ <float 0.000000e+00, float 1.000000e+00>, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi445 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi446 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi447 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi448 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi449 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi466 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi470 = phi <2 x float> [ %broadcast.splat362, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi471 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi472 = phi <2 x float> [ %25, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi473 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi474 = phi <2 x float> [ %26, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi475 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi476 = phi <2 x float> [ %27, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi477 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi478 = phi <2 x float> [ %28, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi479 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi480 = phi <2 x float> [ %29, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi481 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi482 = phi <2 x float> [ %30, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi483 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi484 = phi <2 x float> [ %31, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi485 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi486 = phi <2 x float> [ %32, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi487 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi488 = phi <2 x float> [ %33, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi489 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi490 = phi <2 x float> [ %34, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi491 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi492 = phi <2 x float> [ splat (float +qnan), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi493 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi494 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi495 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi496 = phi <2 x float> [ %broadcast.splat362, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi497 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi503 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi504 = phi <2 x float> [ %35, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi505 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi506 = phi <2 x float> [ %36, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi507 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi508 = phi <2 x float> [ %37, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi509 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi510 = phi <2 x float> [ %38, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi514 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi515 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi516 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi522 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi523 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi524 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi525 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi530 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi531 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi532 = phi <2 x float> [ %39, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi533 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi534 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi535 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi536 = phi <2 x float> [ zeroinitializer, %for.body49.preheader ], [ %invariant.op933, %vector.body.1 ]
  %vec.phi537 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi539 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi540 = phi <2 x float> [ %40, %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi541 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi542 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi543 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi545 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi546 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi547 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi5489 = phi <2 x float> [ %41, %for.body49.preheader ], [ %.reass910.reass, %vector.body.1 ]
  %vec.phi549 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi550 = phi <2 x float> [ zeroinitializer, %for.body49.preheader ], [ %.reass906.reass, %vector.body.1 ]
  %vec.phi551 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi552 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %vec.phi553 = phi <2 x float> [ splat (float 1.000000e+00), %for.body49.preheader ], [ zeroinitializer, %vector.body.1 ]
  %57 = fpext <2 x half> %0 to <2 x float>
  %58 = fmul <2 x float> %vec.phi5489, %57
  %59 = fmul <2 x float> %vec.phi546, %8
  %60 = fmul <2 x float> %vec.phi547, %invariant.op1147
  %61 = fmul <2 x float> %8, %broadcast.splat36467
  %62 = fmul <2 x float> %vec.phi545, %invariant.op1149
  %broadcast.splat366 = shufflevector <2 x float> %8, <2 x float> zeroinitializer, <2 x i32> <i32 1, i32 1>
  %63 = fmul <2 x float> %vec.phi542, %broadcast.splat366
  %64 = fmul <2 x float> %vec.phi540, %9
  %65 = fmul <2 x float> %vec.phi541, %broadcast.splat368
  %66 = fmul <2 x float> %vec.phi539, %10
  %67 = fmul <2 x float> %vec.phi536, zeroinitializer
  %68 = fmul <2 x float> %vec.phi537, %9
  %69 = fmul <2 x float> %vec.phi534, %vec.phi511
  %70 = fmul <2 x float> %vec.phi535, %broadcast.splat362
  %71 = fmul <2 x float> %vec.phi532, %broadcast.splat414
  %72 = fmul <2 x float> %vec.phi533, %9
  %73 = fpext <2 x half> %55 to <2 x float>
  %broadcast.splat378 = shufflevector <2 x float> %73, <2 x float> zeroinitializer, <2 x i32> <i32 1, i32 1>
  %74 = fmul <2 x float> %vec.phi530, %broadcast.splat378
  %75 = fmul <2 x float> %vec.phi531, %9
  %broadcast.splat384 = shufflevector <2 x float> %10, <2 x float> zeroinitializer, <2 x i32> zeroinitializer
  %76 = fmul <2 x float> %vec.phi524, %broadcast.splat384
  %77 = fmul <2 x float> %vec.phi525, %9
  %78 = fmul <2 x float> %vec.phi522, %9
  %broadcast.splat386 = shufflevector <2 x float> %56, <2 x float> zeroinitializer, <2 x i32> <i32 1, i32 1>
  %79 = fmul <2 x float> %vec.phi523, %broadcast.splat386
  %80 = fpext <2 x half> %19 to <2 x float>
  %broadcast.splat392 = shufflevector <2 x float> %80, <2 x float> zeroinitializer, <2 x i32> zeroinitializer
  %81 = fmul <2 x float> %vec.phi516, %broadcast.splat392
  %broadcast.splat394 = shufflevector <2 x float> %invariant.op1147, <2 x float> zeroinitializer, <2 x i32> <i32 1, i32 1>
  %82 = fmul <2 x float> %vec.phi514, %broadcast.splat394
  %83 = fmul <2 x float> %vec.phi515, %9
  %84 = fmul <2 x float> %vec.phi510, %9
  %85 = fmul <2 x float> %vec.phi508, %9
  %86 = fmul <2 x float> %vec.phi509, %9
  %87 = fmul <2 x float> %vec.phi506, %9
  %88 = fmul <2 x float> %vec.phi507, %9
  %89 = fpext <2 x half> %20 to <2 x float>
  %broadcast.splat404 = shufflevector <2 x float> %89, <2 x float> zeroinitializer, <2 x i32> zeroinitializer
  %90 = fmul <2 x float> %vec.phi504, %broadcast.splat404
  %91 = fmul <2 x float> %vec.phi505, %vec.phi538
  %92 = fmul <2 x float> %vec.phi503, %8
  %93 = fmul <2 x float> %vec.phi496, %11
  %94 = fmul <2 x float> %vec.phi497, %8
  %95 = fmul <2 x float> %vec.phi494, %9
  %96 = fmul <2 x float> %vec.phi495, %8
  %97 = fmul <2 x float> %vec.phi492, %9
  %broadcast.splat416 = shufflevector <2 x float> %8, <2 x float> zeroinitializer, <2 x i32> zeroinitializer
  %98 = fmul <2 x float> %vec.phi493, %broadcast.splat416
  %99 = fmul <2 x float> %vec.phi490, %vec.phi544
  %100 = fmul <2 x float> %vec.phi491, %8
  %101 = fmul <2 x float> %vec.phi488, %9
  %102 = fmul <2 x float> %vec.phi489, %9
  %103 = fmul <2 x float> %vec.phi486, %8
  %104 = fmul <2 x float> %vec.phi487, %9
  %105 = fmul <2 x float> %vec.phi484, %8
  %106 = fmul <2 x float> %vec.phi482, %9
  %107 = fmul <2 x float> %vec.phi483, %9
  %108 = fmul <2 x float> %vec.phi480, %43
  %109 = fmul <2 x float> %vec.phi478, %44
  %110 = fmul <2 x float> %vec.phi476, %8
  %111 = fmul <2 x float> %vec.phi474, %46
  %112 = fmul <2 x float> %vec.phi472, %48
  %113 = fmul <2 x float> %vec.phi448, %50
  %114 = fmul <2 x float> %vec.phi44077, %52
  %115 = fmul <2 x float> %vec.phi438, %53
  %116 = fmul <2 x float> %vec.phi4307, %vec.phi548
  %117 = fmul <2 x float> %vec.phi427, %54
  %118 = icmp eq i32 %index, 0
  br i1 %118, label %for.body49, label %vector.body.1

vector.body.1:                                    ; preds = %vector.body
  %.reass906.reass = fmul <2 x float> %vec.phi550, %14
  %.reass910.reass = fmul <2 x float> %vec.phi548, %broadcast.splat36467
  %119 = fpext <2 x half> %broadcast.splat350 to <2 x float>
  %factor.op.fmul1278 = fmul <2 x float> %119, %broadcast.splat368
  %.reass1146.reass = fmul <2 x float> zeroinitializer, %factor.op.fmul1278
  %factor.op.fmul1280 = fmul <2 x float> %9, %11
  %.reass1150.reass = fmul <2 x float> %vec.phi428, %factor.op.fmul1280
  %.reass1156.reass = fmul <2 x float> %vec.phi427, zeroinitializer
  %index.next.3 = or i32 %index, 1
  br label %vector.body

for.body49:                                       ; preds = %vector.body
  %bin.rdx554 = fmul <2 x float> %vec.phi429, %vec.phi428
  %120 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx554)
  %121 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %117)
  %bin.rdx556 = fmul <2 x float> %vec.phi433, %vec.phi432
  %122 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx556)
  %123 = insertelement <2 x float> zeroinitializer, float %122, i64 0
  %bin.rdx555 = fmul <2 x float> %vec.phi43176, %116
  %124 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx555)
  %bin.rdx560 = fmul <2 x float> %vec.phi441, %114
  %125 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx560)
  %126 = insertelement <2 x float> zeroinitializer, float %125, i64 0
  %bin.rdx559 = fmul <2 x float> %vec.phi439, %115
  %127 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx559)
  %128 = fmul <2 x float> %vec.phi444, %8
  %bin.rdx562 = fmul <2 x float> %vec.phi445, %128
  %129 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx562)
  %130 = insertelement <2 x float> zeroinitializer, float %129, i64 0
  %bin.rdx561 = fmul <2 x float> %vec.phi443, %vec.phi442
  %131 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx561)
  %bin.rdx564 = fmul <2 x float> %vec.phi449, %113
  %132 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx564)
  %133 = insertelement <2 x float> zeroinitializer, float %132, i64 0
  %bin.rdx563 = fmul <2 x float> %vec.phi447, %vec.phi446
  %134 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx563)
  %bin.rdx573 = fmul <2 x float> %8, %vec.phi466
  %135 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx573)
  %bin.rdx576 = fmul <2 x float> %vec.phi473, %112
  %136 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx576)
  %137 = insertelement <2 x float> zeroinitializer, float %136, i64 0
  %bin.rdx575 = fmul <2 x float> %vec.phi471, %vec.phi470
  %138 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx575)
  %bin.rdx578 = fmul <2 x float> %vec.phi477, %110
  %139 = tail call reassoc float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx578)
  %140 = insertelement <2 x float> zeroinitializer, float %139, i64 0
  %bin.rdx577 = fmul <2 x float> %vec.phi475, %111
  %141 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx577)
  %bin.rdx580 = fmul <2 x float> %vec.phi481, %108
  %142 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx580)
  %143 = insertelement <2 x float> zeroinitializer, float %142, i64 0
  %bin.rdx579 = fmul <2 x float> %vec.phi479, %109
  %144 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx579)
  %bin.rdx582 = fmul <2 x float> %vec.phi485, %105
  %bin.rdx581 = fmul <2 x float> %107, %106
  %145 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx581)
  %bin.rdx584 = fmul <2 x float> %102, %101
  %bin.rdx583 = fmul <2 x float> %104, %103
  %146 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx583)
  %bin.rdx585 = fmul <2 x float> %100, %99
  %bin.rdx587 = fmul <2 x float> %96, %95
  %bin.rdx591 = fmul <2 x float> %92, %11
  %147 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx591)
  %bin.rdx594 = fmul <2 x float> %86, %85
  %bin.rdx593 = fmul <2 x float> %88, %87
  %148 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx593)
  %bin.rdx595 = fmul <2 x float> %12, %84
  %149 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx595)
  %bin.rdx598 = fmul <2 x float> %factor.op.fmul1164, %81
  %bin.rdx597 = fmul <2 x float> %83, %82
  %150 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx597)
  %bin.rdx602 = fmul <2 x float> %77, %76
  %bin.rdx601 = fmul <2 x float> %79, %78
  %151 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx601)
  %bin.rdx606 = fmul <2 x float> %72, %71
  %bin.rdx605 = fmul <2 x float> %75, %74
  %152 = tail call float @llvm.vector.reduce.fmul.v2f32(float 1.000000e+00, <2 x float> %bin.rdx605)
  %bin.rdx608 = fmul <2 x float> %68, %67
  %bin.rdx607 = fmul <2 x float> %70, %69
  %153 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx607)
  %bin.rdx609 = fmul <2 x float> %66, zeroinitializer
  %bin.rdx610 = fmul <2 x float> %65, %64
  %154 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx609)
  %155 = insertelement <2 x float> %bin.rdx610, float %154, i64 0
  %bin.rdx611 = fmul <2 x float> %vec.phi543, %63
  %bin.rdx614 = fmul <2 x float> %vec.phi549, %58
  %156 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx614)
  %bin.rdx613 = fmul <2 x float> %60, %59
  %bin.rdx616 = fmul <2 x float> %vec.phi553, %vec.phi552
  %157 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx616)
  %158 = insertelement <2 x float> zeroinitializer, float %157, i64 0
  %bin.rdx615 = fmul <2 x float> %vec.phi551, %vec.phi550
  %159 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx615)
  %160 = insertelement <2 x float> %158, float %159, i64 1
  store <2 x float> %160, ptr addrspace(1) %p2.coerce, align 4
  %161 = insertelement <2 x float> zeroinitializer, float %156, i64 0
  %162 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx613)
  %163 = insertelement <2 x float> %161, float %162, i64 1
  store <2 x float> %163, ptr addrspace(1) null, align 4
  %bin.rdx612 = fmul <2 x float> %62, %61
  %164 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx611)
  %165 = insertelement <2 x float> %bin.rdx612, float %164, i64 0
  %arrayidx63.411 = getelementptr i8, ptr addrspace(1) %p2.coerce, i64 16
  store <2 x float> %165, ptr addrspace(1) %arrayidx63.411, align 4
  %166 = fmul <2 x float> %18, %155
  %arrayidx63.613 = getelementptr i8, ptr addrspace(1) %p2.coerce, i64 24
  store <2 x float> %166, ptr addrspace(1) %arrayidx63.613, align 4
  %167 = insertelement <2 x float> %bin.rdx608, float %153, i64 0
  store <2 x float> %167, ptr addrspace(1) null, align 4
  %168 = insertelement <2 x float> %bin.rdx606, float %152, i64 0
  store <2 x float> %168, ptr addrspace(1) %p2.coerce, align 4
  %169 = insertelement <2 x float> %bin.rdx602, float %151, i64 0
  store <2 x float> %169, ptr addrspace(1) null, align 4
  %170 = insertelement <2 x float> %bin.rdx598, float %150, i64 0
  store <2 x float> %170, ptr addrspace(1) %p2.coerce, align 4
  %171 = insertelement <2 x float> zeroinitializer, float %149, i64 0
  store <2 x float> %171, ptr addrspace(1) null, align 4
  %172 = insertelement <2 x float> %bin.rdx594, float %148, i64 0
  store <2 x float> %172, ptr addrspace(1) %p2.coerce, align 4
  %bin.rdx592 = fmul <2 x float> %91, %90
  %173 = insertelement <2 x float> %bin.rdx592, float %147, i64 0
  store <2 x float> %173, ptr addrspace(1) null, align 4
  %bin.rdx588 = fmul <2 x float> %94, %93
  %174 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx587)
  %175 = insertelement <2 x float> %bin.rdx588, float %174, i64 0
  store <2 x float> %175, ptr addrspace(1) %p2.coerce, align 4
  %bin.rdx586 = fmul <2 x float> %98, %97
  %176 = tail call float @llvm.vector.reduce.fmul.v2f32(float 0.000000e+00, <2 x float> %bin.rdx585)
  %177 = insertelement <2 x float> %bin.rdx586, float %176, i64 0
  store <2 x float> %177, ptr addrspace(1) null, align 4
  %178 = insertelement <2 x float> %bin.rdx584, float %146, i64 0
  store <2 x float> %178, ptr addrspace(1) %p2.coerce, align 4
  %179 = insertelement <2 x float> %bin.rdx582, float %145, i64 1
  store <2 x float> %179, ptr addrspace(1) null, align 4
  %180 = insertelement <2 x float> %143, float %144, i64 1
  store <2 x float> %180, ptr addrspace(1) %p2.coerce, align 4
  %181 = insertelement <2 x float> %140, float %141, i64 1
  store <2 x float> %181, ptr addrspace(1) null, align 4
  %182 = insertelement <2 x float> %137, float %138, i64 1
  store <2 x float> %182, ptr addrspace(1) %p2.coerce, align 4
  %183 = insertelement <2 x float> zeroinitializer, float %135, i64 0
  store <2 x float> %183, ptr addrspace(1) null, align 4
  %arrayidx63.44 = getelementptr i8, ptr addrspace(1) %p2.coerce, i64 176
  store <2 x float> zeroinitializer, ptr addrspace(1) %arrayidx63.44, align 4
  %arrayidx63.46 = getelementptr i8, ptr addrspace(1) %p2.coerce, i64 184
  store <2 x float> zeroinitializer, ptr addrspace(1) %arrayidx63.46, align 4
  %184 = insertelement <2 x float> %133, float %134, i64 1
  store <2 x float> %184, ptr addrspace(1) null, align 4
  %185 = insertelement <2 x float> %130, float %131, i64 1
  store <2 x float> %185, ptr addrspace(1) %arrayidx63.5445, align 4
  %186 = insertelement <2 x float> %126, float %127, i64 1
  store <2 x float> %186, ptr addrspace(1) null, align 4
  %187 = insertelement <2 x float> %123, float %124, i64 1
  store <2 x float> %187, ptr addrspace(1) %arrayidx63.60, align 4
  %188 = insertelement <2 x float> zeroinitializer, float %120, i64 0
  %189 = insertelement <2 x float> %188, float %121, i64 1
  store <2 x float> %189, ptr addrspace(1) null, align 4
  %190 = atomicrmw max ptr addrspace(1) null, i32 0 monotonic, align 4
  ret void

if.then53:                                        ; preds = %entry
  tail call void null(ptr null, i32 0)
  unreachable
}

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare float @llvm.vector.reduce.fmul.v2f32(float, <2 x float>) #0

attributes #0 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
