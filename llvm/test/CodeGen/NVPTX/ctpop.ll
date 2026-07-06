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

; (ctpop x) ugt 0 -> x != 0 used to build a setcc mixing the i64 operand with
; an i32 zero and hit "SETCC operands must have the same type" (UB with
; assertions off). The compare-with-zero only appears post-legalization, once
; the prmt has been constant-folded.
define i1 @setcc_narrow_ctpop(i16 %x) {
; CHECK-LABEL: setcc_narrow_ctpop(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<2>;
; CHECK-NEXT:    .reg .b64 %rd<2>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b16 %rd1, [setcc_narrow_ctpop_param_0];
; CHECK-NEXT:    setp.ne.b64 %p1, %rd1, 0;
; CHECK-NEXT:    selp.b32 %r1, -1, 0, %p1;
; CHECK-NEXT:    st.param.b32 [func_retval0], %r1;
; CHECK-NEXT:    ret;
  %p = call i32 @llvm.nvvm.prmt(i32 0, i32 0, i32 0)
  %pz = zext i32 %p to i64
  %c = call i16 @llvm.ctpop.i16(i16 %x)
  %cz = zext i16 %c to i64
  %cmp = icmp ult i64 %pz, %cz
  ret i1 %cmp
}

declare i32 @llvm.nvvm.prmt(i32, i32, i32)
