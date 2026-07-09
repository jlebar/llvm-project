; RUN: opt < %s -passes=loop-vectorize -force-vector-width=4 -force-vector-interleave=1 -S | FileCheck %s
; RUN: opt < %s -passes=loop-vectorize -force-vector-width=4 -force-vector-interleave=1 -prefer-inloop-reductions -S | FileCheck %s --check-prefix=INLOOP
; RUN: opt < %s -passes=loop-vectorize -force-vector-width=4 -force-vector-interleave=1 -force-target-supports-scalable-vectors=true -scalable-vectorization=on -S | FileCheck %s --check-prefix=SCALABLE

; The loop's fcmp+select min/max recurrence passes the chosen operand through
; bit-for-bit (only the compare goes through the FP environment), but
; vector.reduce.fmin/fmax have minnum/maxnum semantics: under a non-IEEE
; denormal mode they must treat a denormal operand as zero under input
; flushing and may flush a denormal result under output flushing (LangRef,
; denormal_fpenv). The loop must still vectorize, but the final reduction has
; to stay in select form.

; CHECK-LABEL: define float @fmin_preservesign(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: vector.body:
; CHECK: fcmp nnan nsz olt <4 x float>
; CHECK-NEXT: select nnan nsz <4 x i1>
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float> [[RDX:%.*]], <4 x float> poison, <4 x i32> <i32 2, i32 3, i32 poison, i32 poison>
; CHECK-NEXT: %rdx.minmax.cmp = fcmp nnan nsz olt <4 x float> [[RDX]], %rdx.shuf
; CHECK-NEXT: %rdx.minmax.select = select nnan nsz <4 x i1> %rdx.minmax.cmp, <4 x float> [[RDX]], <4 x float> %rdx.shuf
; CHECK-NEXT: %rdx.shuf1 = shufflevector <4 x float> %rdx.minmax.select, <4 x float> poison, <4 x i32> <i32 1, i32 poison, i32 poison, i32 poison>
; CHECK-NEXT: %rdx.minmax.cmp2 = fcmp nnan nsz olt <4 x float> %rdx.minmax.select, %rdx.shuf1
; CHECK-NEXT: %rdx.minmax.select3 = select nnan nsz <4 x i1> %rdx.minmax.cmp2, <4 x float> %rdx.minmax.select, <4 x float> %rdx.shuf1
; CHECK-NEXT: {{%.*}} = extractelement <4 x float> %rdx.minmax.select3, i32 0
; CHECK-NOT: @llvm.vector.reduce

; The in-loop form would reduce the raw loaded lanes with vector.reduce.fmin
; every iteration; it must stay out-of-loop.
; INLOOP-LABEL: define float @fmin_preservesign(
; INLOOP-NOT: @llvm.vector.reduce
; INLOOP: vector.body:
; INLOOP-NOT: @llvm.vector.reduce
; INLOOP: middle.block:
; INLOOP-NEXT: %rdx.shuf = shufflevector <4 x float>
; INLOOP-NOT: @llvm.vector.reduce

; There is no select-based reduction expansion for scalable vectors, so a
; scalable VF must not be used (with the forced flags above the loop simply
; stays scalar).
; SCALABLE-LABEL: define float @fmin_preservesign(
; SCALABLE-NOT: <vscale
define float @fmin_preservesign(ptr %p, i64 %n) denormal_fpenv(preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; CHECK-LABEL: define float @fmax_preservesign(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NEXT: %rdx.minmax.cmp = fcmp nnan nsz ogt <4 x float>
; CHECK-NEXT: %rdx.minmax.select = select nnan nsz <4 x i1> %rdx.minmax.cmp
; CHECK-NOT: @llvm.vector.reduce
define float @fmax_preservesign(ptr %p, i64 %n) denormal_fpenv(preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0xFFF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz ogt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; CHECK-LABEL: define float @fmin_positivezero(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
define float @fmin_positivezero(ptr %p, i64 %n) denormal_fpenv(positivezero) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; CHECK-LABEL: define float @fmin_dynamic(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
define float @fmin_dynamic(ptr %p, i64 %n) denormal_fpenv(dynamic) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; Input-only flushing (the attribute is output|input) is enough to block the
; intrinsic: it must treat a denormal operand as zero.
; CHECK-LABEL: define float @fmin_input_flush(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
define float @fmin_input_flush(ptr %p, i64 %n) denormal_fpenv(ieee|preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; Output-only flushing also blocks it: the intrinsic may flush a denormal
; result.
; CHECK-LABEL: define float @fmin_output_flush(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
define float @fmin_output_flush(ptr %p, i64 %n) denormal_fpenv(preservesign|ieee) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; An IEEE mode keeps the intrinsic reduction.
; CHECK-LABEL: define float @fmin_ieee(
; CHECK: middle.block:
; CHECK-NEXT: {{%.*}} = call nnan nsz float @llvm.vector.reduce.fmin.v4f32(

; INLOOP-LABEL: define float @fmin_ieee(
; INLOOP: vector.body:
; INLOOP: {{%.*}} = call nnan nsz float @llvm.vector.reduce.fmin.v4f32(<4 x float> %wide.load)

; SCALABLE-LABEL: define float @fmin_ieee(
; SCALABLE: {{%.*}} = call nnan nsz float @llvm.vector.reduce.fmin.nxv4f32(
define float @fmin_ieee(ptr %p, i64 %n) denormal_fpenv(ieee) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; The mode is keyed on the element type: an f32-only flushing mode blocks the
; f32 reduction but not the f64 one.
; CHECK-LABEL: define float @fmin_f32_flush(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
define float @fmin_f32_flush(ptr %p, i64 %n) denormal_fpenv(ieee, float: preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %cmp = fcmp nnan nsz olt float %x, %m
  %m.next = select nnan nsz i1 %cmp, float %x, float %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

; CHECK-LABEL: define double @fmin_f32_flush_f64(
; CHECK: middle.block:
; CHECK-NEXT: {{%.*}} = call nnan nsz double @llvm.vector.reduce.fmin.v4f64(
define double @fmin_f32_flush_f64(ptr %p, i64 %n) denormal_fpenv(ieee, float: preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi double [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds double, ptr %p, i64 %iv
  %x = load double, ptr %gep, align 8
  %cmp = fcmp nnan nsz olt double %x, %m
  %m.next = select nnan nsz i1 %cmp, double %x, double %m
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret double %m.next
}

; A minnum recurrence with nnan nsz uses the same FMin recurrence kind and
; also reduces via selects under flushing. That is safe in both directions:
; every lane fed to the final reduction already went through a minnum in the
; loop body, so no denormal can reach it under input flushing, and under
; output-only flushing not flushing is always a permitted result.
; CHECK-LABEL: define float @fmin_intrinsic_preservesign(
; CHECK-NOT: @llvm.vector.reduce
; CHECK: vector.body:
; CHECK: {{%.*}} = call nnan nsz <4 x float> @llvm.minnum.v4f32(
; CHECK: middle.block:
; CHECK-NEXT: %rdx.shuf = shufflevector <4 x float>
; CHECK-NOT: @llvm.vector.reduce
; CHECK: scalar.ph:
define float @fmin_intrinsic_preservesign(ptr %p, i64 %n) denormal_fpenv(preservesign) {
entry:
  br label %loop

loop:
  %iv = phi i64 [ 0, %entry ], [ %iv.next, %loop ]
  %m = phi float [ 0x7FF0000000000000, %entry ], [ %m.next, %loop ]
  %gep = getelementptr inbounds float, ptr %p, i64 %iv
  %x = load float, ptr %gep, align 4
  %m.next = call nnan nsz float @llvm.minnum.f32(float %x, float %m)
  %iv.next = add nuw nsw i64 %iv, 1
  %ec = icmp eq i64 %iv.next, %n
  br i1 %ec, label %exit, label %loop

exit:
  ret float %m.next
}

declare float @llvm.minnum.f32(float, float)
