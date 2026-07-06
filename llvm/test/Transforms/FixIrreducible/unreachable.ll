; NOTE: Do not autogenerate
; RUN: opt < %s -fix-irreducible --verify-loop-info -S | FileCheck %s
; RUN: opt < %s -passes='fix-irreducible,verify<loops>' -S | FileCheck %s
; RUN: opt < %s -passes='verify<loops>,fix-irreducible,verify<loops>' -S | FileCheck %s

; CHECK-LABEL: @unreachable(
; CHECK: entry:
; CHECK-NOT: irr.guard:
define void @unreachable(i32 %n, i1 %arg) {
entry:
  br label %loop.body

loop.body:
  br label %inner.block

unreachable.block:
  br label %inner.block

inner.block:
  br i1 %arg, label %loop.exit, label %loop.latch

loop.latch:
  br label %loop.body

loop.exit:
  ret void
}

; CHECK-LABEL: @unreachable_callbr(
; CHECK: entry:
; CHECK-NOT: irr.guard:
define void @unreachable_callbr(i32 %n, i1 %arg) {
entry:
  callbr void asm "", ""() to label %loop.body []

loop.body:
  callbr void asm "", ""() to label %inner.block []

unreachable.block:
  callbr void asm "", ""() to label %inner.block []

inner.block:
  callbr void asm "", "r,!i"(i1 %arg) to label %loop.exit [label %loop.latch]

loop.latch:
  callbr void asm "", ""() to label %loop.body []

loop.exit:
  ret void
}

; Edges from unreachable predecessors must not be redirected through the
; control-flow hub. The hub statically admits control flow from every incoming
; block to every outgoing block, so routing a statically dead edge creates
; reachable paths that did not exist in the original function.

; %b4 is unreachable and branches to both %b2 (an entry of the irreducible
; cycle {%b2, %b6, %b3}) and %b6 (a non-entry block of that cycle). If the
; edge %b4 -> %b6 were routed through the hub, %b6 would become an outgoing
; block of the hub, admitting the path entry -> guards -> %b6 which bypasses
; %b2; %def would no longer dominate %use. Both of %b4's edges must survive
; unchanged.
define i32 @unreachable_pred_dominance(i1 %c1, i1 %c2, i32 %n) {
; CHECK-LABEL: @unreachable_pred_dominance(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[C1_INV:%.*]] = xor i1 [[C1:%.*]], true
; CHECK-NEXT:    br label [[IRR_GUARD:%.*]]
; CHECK:       b2:
; CHECK-NEXT:    [[DEF:%.*]] = add i32 [[N:%.*]], 1
; CHECK-NEXT:    br label [[B6:%.*]]
; CHECK:       b3:
; CHECK-NEXT:    br i1 [[C2:%.*]], label [[B2:%.*]], label [[EXIT:%.*]]
; CHECK:       b4:
; CHECK-NEXT:    br i1 [[C1]], label [[B2]], label [[B6]]
; CHECK:       b6:
; CHECK-NEXT:    [[USE:%.*]] = mul i32 [[DEF]], 3
; CHECK-NEXT:    br label [[IRR_GUARD]]
; CHECK:       exit:
; CHECK-NEXT:    ret i32 [[N]]
; CHECK:       irr.guard:
; CHECK-NEXT:    [[GUARD_B3:%.*]] = phi i1 [ true, [[B6]] ], [ [[C1_INV]], [[ENTRY:%.*]] ]
; CHECK-NEXT:    br i1 [[GUARD_B3]], label [[B3:%.*]], label [[B2]]
;
entry:
  br i1 %c1, label %b2, label %b3

b2:
  %def = add i32 %n, 1
  br label %b6

b3:
  br i1 %c2, label %b2, label %exit

b4:
  br i1 %c1, label %b2, label %b6

b6:
  %use = mul i32 %def, 3
  br label %b3

exit:
  ret i32 %n
}

; %b7 is unreachable and branches to %b2 (an entry of the outermost
; irreducible cycle) and %b13. If the edge %b7 -> %b13 were routed through the
; hub of the outermost cycle, %b13 (a non-entry block of the inner cycles)
; would become reachable from a guard block outside those cycles, and the
; transforms of the inner cycles would fail CycleInfo verification:
; "Non-entry block reachable from outside!".
define void @unreachable_pred_nested_cycles(i1 %c) {
; CHECK-LABEL: @unreachable_pred_nested_cycles(
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[C_INV:%.*]] = xor i1 [[C:%.*]], true
; CHECK-NEXT:    br label [[IRR_GUARD:%.*]]
; CHECK:       b2:
; CHECK-NEXT:    br i1 [[C]], label [[B5:%.*]], label [[IRR_GUARD1:%.*]]
; CHECK:       b3:
; CHECK-NEXT:    br i1 [[C]], label [[IRR_GUARD1]], label [[B6:%.*]]
; CHECK:       b5:
; CHECK-NEXT:    br label [[IRR_GUARD1]]
; CHECK:       b6:
; CHECK-NEXT:    br i1 [[C]], label [[IRR_GUARD]], label [[IRR_GUARD3:%.*]]
; CHECK:       b7:
; CHECK-NEXT:    br i1 [[C]], label [[B2:%.*]], label [[B13:%.*]]
; CHECK:       b8:
; CHECK-NEXT:    br label [[IRR_GUARD3]]
; CHECK:       b11:
; CHECK-NEXT:    br i1 [[C]], label [[B3:%.*]], label [[RET:%.*]]
; CHECK:       b12:
; CHECK-NEXT:    br i1 [[C]], label [[B13]], label [[RET]]
; CHECK:       b13:
; CHECK-NEXT:    br i1 [[C]], label [[B11:%.*]], label [[RET]]
; CHECK:       ret:
; CHECK-NEXT:    ret void
; CHECK:       irr.guard:
; CHECK-NEXT:    [[GUARD_B2:%.*]] = phi i1 [ true, [[B6]] ], [ [[C_INV]], [[ENTRY:%.*]] ]
; CHECK-NEXT:    br i1 [[GUARD_B2]], label [[B2]], label [[IRR_GUARD1]]
; CHECK:       irr.guard1:
; CHECK-NEXT:    [[GUARD_B8:%.*]] = phi i1 [ true, [[B3]] ], [ true, [[B2]] ], [ false, [[IRR_GUARD]] ], [ false, [[B5]] ]
; CHECK-NEXT:    [[GUARD_B12:%.*]] = phi i1 [ false, [[B3]] ], [ false, [[B2]] ], [ true, [[IRR_GUARD]] ], [ [[C]], [[B5]] ]
; CHECK-NEXT:    br i1 [[GUARD_B8]], label [[B8:%.*]], label [[IRR_GUARD2:%.*]]
; CHECK:       irr.guard2:
; CHECK-NEXT:    br label [[IRR_GUARD3]]
; CHECK:       irr.guard3:
; CHECK-NEXT:    [[GUARD_B124:%.*]] = phi i1 [ true, [[B6]] ], [ [[GUARD_B12]], [[IRR_GUARD2]] ], [ true, [[B8]] ]
; CHECK-NEXT:    br i1 [[GUARD_B124]], label [[B12:%.*]], label [[B11]]
;
entry:
  br i1 %c, label %b12, label %b2

b2:
  br i1 %c, label %b5, label %b8

b3:
  br i1 %c, label %b8, label %b6

b5:
  br i1 %c, label %b12, label %b11

b6:
  br i1 %c, label %b2, label %b12

b7:
  br i1 %c, label %b2, label %b13

b8:
  br label %b12

b11:
  br i1 %c, label %b3, label %ret

b12:
  br i1 %c, label %b13, label %ret

b13:
  br i1 %c, label %b11, label %ret

ret:
  ret void
}
