; RUN: llc < %s -mtriple=nvptx64 -mcpu=sm_20 -verify-machineinstrs | FileCheck %s
; RUN: %if ptxas %{ llc < %s -mtriple=nvptx64 -mcpu=sm_20 -verify-machineinstrs | %ptxas-verify %}

target datalayout = "e-p:32:32:32-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"

define i32 @myctpop(i32 %a) {
; CHECK: popc.b32
  %val = tail call i32 @llvm.ctpop.i32(i32 %a)
  ret i32 %val
}

define i16 @myctpop16(i16 %a) {
; CHECK: popc.b32
  %val = tail call i16 @llvm.ctpop.i16(i16 %a)
  ret i16 %val
}

define i64 @myctpop64(i64 %a) {
; CHECK: popc.b64
  %val = tail call i64 @llvm.ctpop.i64(i64 %a)
  ret i64 %val
}

declare i16 @llvm.ctpop.i16(i16)
declare i32 @llvm.ctpop.i32(i32)
declare i64 @llvm.ctpop.i64(i64)

; The prmt intrinsic constant-folds only after legalization (it's lowered to a
; target node), so the setcc re-enters DAGCombine post-legalization and
; simplifySetCCWithCTPOP sees the lowered i64 ctpop.  When the lowering
; produced a generic CTPOP with i32 result but i64 operand, that combine built
; a setcc mixing the i64 operand with an i32 constant and asserted.
define i1 @ctpop_setcc_late(i16 %a) {
; CHECK-LABEL: ctpop_setcc_late(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<3>;
; CHECK-NEXT:    .reg .b64 %rd<2>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b16 %rd1, [ctpop_setcc_late_param_0];
; CHECK-NEXT:    popc.b64 %r1, %rd1;
; CHECK-NEXT:    setp.ne.b32 %p1, %r1, 0;
; CHECK-NEXT:    selp.b32 %r2, -1, 0, %p1;
; CHECK-NEXT:    st.param.b32 [func_retval0], %r2;
; CHECK-NEXT:    ret;
  %p = tail call i32 @llvm.nvvm.prmt(i32 0, i32 0, i32 0)
  %pz = zext i32 %p to i64
  %ct = tail call i16 @llvm.ctpop.i16(i16 %a)
  %cz = zext i16 %ct to i64
  %cmp = icmp ult i64 %pz, %cz
  ret i1 %cmp
}

declare i32 @llvm.nvvm.prmt(i32, i32, i32)
