; RUN: llc < %s -mtriple=nvptx64 -mcpu=sm_20 | FileCheck %s
; RUN: %if ptxas %{ llc < %s -mtriple=nvptx64 -mcpu=sm_20 | %ptxas-verify %}

; CHECK: shift_parts_left_128
define void @shift_parts_left_128(ptr %val, ptr %amtptr) {
; CHECK: shl.b64
; CHECK: sub.s32
; CHECK: shr.u64
; CHECK: or.b64
; CHECK: add.s32
; CHECK: shl.b64
; CHECK: setp.gt.s32
; CHECK: selp.b64
; CHECK: shl.b64
  %amt = load i128, ptr %amtptr
  %a = load i128, ptr %val
  %val0 = shl i128 %a, %amt
  store i128 %val0, ptr %val
  ret void
}

; CHECK: shift_parts_right_128
define void @shift_parts_right_128(ptr %val, ptr %amtptr) {
; CHECK: shr.u64
; CHECK: sub.s32
; CHECK: shl.b64
; CHECK: or.b64
; CHECK: add.s32
; CHECK: shr.s64
; CHECK: setp.gt.s32
; CHECK: selp.b64
; CHECK: shr.s64
  %amt = load i128, ptr %amtptr
  %a = load i128, ptr %val
  %val0 = ashr i128 %a, %amt
  store i128 %val0, ptr %val
  ret void
}

; The i128 shift-parts lowering computes one limb as a plain shift of one
; source limb by the full (up to 127) shift amount, relying on the PTX shift
; instructions clamping oversized amounts. That limb must not be emitted as a
; generic ISD node: generic shifts are poison for amounts >= 64, which lets
; DAG combines rewrite them with modulo-64 semantics. The xor fold
; (xor (shl 1, x), -1) -> (rotl ~1, x) used to do exactly that here, turning
; the low limb of ~(1 << amt) into a modulo-64 rotate: for amt = 77 it
; produced 0xffffffffffffdfff instead of all ones.

define void @not_shl_one_i128(ptr %out, i32 %amt) {
; CHECK-LABEL: not_shl_one_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<5>;
; CHECK-NEXT:    .reg .b64 %rd<9>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [not_shl_one_i128_param_0];
; CHECK-NEXT:    ld.param.b32 %r1, [not_shl_one_i128_param_1];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    mov.b64 %rd2, 1;
; CHECK-NEXT:    shr.u64 %rd3, %rd2, %r3;
; CHECK-NEXT:    add.s32 %r4, %r2, -64;
; CHECK-NEXT:    shl.b64 %rd4, %rd2, %r4;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd5, %rd4, %rd3, %p1;
; CHECK-NEXT:    shl.b64 %rd6, %rd2, %r2;
; CHECK-NEXT:    not.b64 %rd7, %rd5;
; CHECK-NEXT:    not.b64 %rd8, %rd6;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd8, %rd7};
; CHECK-NEXT:    ret;
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = shl i128 1, %a
  %n = xor i128 %s, -1
  store i128 %n, ptr %out
  ret void
}

define void @shl_i128(ptr %out, i128 %v, i32 %amt) {
; CHECK-LABEL: shl_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<5>;
; CHECK-NEXT:    .reg .b64 %rd<10>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [shl_i128_param_0];
; CHECK-NEXT:    ld.param.b32 %r1, [shl_i128_param_2];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    ld.param.v2.b64 {%rd2, %rd3}, [shl_i128_param_1];
; CHECK-NEXT:    shl.b64 %rd4, %rd3, %r2;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    shr.u64 %rd5, %rd2, %r3;
; CHECK-NEXT:    or.b64 %rd6, %rd4, %rd5;
; CHECK-NEXT:    add.s32 %r4, %r2, -64;
; CHECK-NEXT:    shl.b64 %rd7, %rd2, %r4;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd8, %rd7, %rd6, %p1;
; CHECK-NEXT:    shl.b64 %rd9, %rd2, %r2;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd9, %rd8};
; CHECK-NEXT:    ret;
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = shl i128 %v, %a
  store i128 %s, ptr %out
  ret void
}

define void @lshr_i128(ptr %out, i128 %v, i32 %amt) {
; CHECK-LABEL: lshr_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<5>;
; CHECK-NEXT:    .reg .b64 %rd<10>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [lshr_i128_param_0];
; CHECK-NEXT:    ld.param.b32 %r1, [lshr_i128_param_2];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    ld.param.v2.b64 {%rd2, %rd3}, [lshr_i128_param_1];
; CHECK-NEXT:    shr.u64 %rd4, %rd2, %r2;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    shl.b64 %rd5, %rd3, %r3;
; CHECK-NEXT:    or.b64 %rd6, %rd4, %rd5;
; CHECK-NEXT:    add.s32 %r4, %r2, -64;
; CHECK-NEXT:    shr.u64 %rd7, %rd3, %r4;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd8, %rd7, %rd6, %p1;
; CHECK-NEXT:    shr.u64 %rd9, %rd3, %r2;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd8, %rd9};
; CHECK-NEXT:    ret;
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = lshr i128 %v, %a
  store i128 %s, ptr %out
  ret void
}

define void @ashr_i128(ptr %out, i128 %v, i32 %amt) {
; CHECK-LABEL: ashr_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<5>;
; CHECK-NEXT:    .reg .b64 %rd<10>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [ashr_i128_param_0];
; CHECK-NEXT:    ld.param.b32 %r1, [ashr_i128_param_2];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    ld.param.v2.b64 {%rd2, %rd3}, [ashr_i128_param_1];
; CHECK-NEXT:    shr.u64 %rd4, %rd2, %r2;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    shl.b64 %rd5, %rd3, %r3;
; CHECK-NEXT:    or.b64 %rd6, %rd4, %rd5;
; CHECK-NEXT:    add.s32 %r4, %r2, -64;
; CHECK-NEXT:    shr.s64 %rd7, %rd3, %r4;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd8, %rd7, %rd6, %p1;
; CHECK-NEXT:    shr.s64 %rd9, %rd3, %r2;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd8, %rd9};
; CHECK-NEXT:    ret;
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = ashr i128 %v, %a
  store i128 %s, ptr %out
  ret void
}

; The clamp nodes are opaque to generic combines, so the lowering folds the
; trivial limbs itself: the high limb of a zero-extended source must fold to
; 0, and of a sign-extended source to the (all-sign-bits) high word.
define void @lshr_zext_i128(ptr %out, i64 %v, i32 %amt) {
; CHECK-LABEL: lshr_zext_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<3>;
; CHECK-NEXT:    .reg .b64 %rd<5>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [lshr_zext_i128_param_0];
; CHECK-NEXT:    ld.param.b64 %rd2, [lshr_zext_i128_param_1];
; CHECK-NEXT:    ld.param.b32 %r1, [lshr_zext_i128_param_2];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    shr.u64 %rd3, %rd2, %r2;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd4, 0, %rd3, %p1;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd4, 0};
; CHECK-NEXT:    ret;
  %z = zext i64 %v to i128
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = lshr i128 %z, %a
  store i128 %s, ptr %out
  ret void
}

define void @ashr_sext_i128(ptr %out, i64 %v, i32 %amt) {
; CHECK-LABEL: ashr_sext_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<4>;
; CHECK-NEXT:    .reg .b64 %rd<8>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [ashr_sext_i128_param_0];
; CHECK-NEXT:    ld.param.b64 %rd2, [ashr_sext_i128_param_1];
; CHECK-NEXT:    shr.s64 %rd3, %rd2, 63;
; CHECK-NEXT:    ld.param.b32 %r1, [ashr_sext_i128_param_2];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    shr.u64 %rd4, %rd2, %r2;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    shl.b64 %rd5, %rd3, %r3;
; CHECK-NEXT:    or.b64 %rd6, %rd4, %rd5;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd7, %rd3, %rd6, %p1;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd7, %rd3};
; CHECK-NEXT:    ret;
  %z = sext i64 %v to i128
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = ashr i128 %z, %a
  store i128 %s, ptr %out
  ret void
}

; Mirror shape for the right-shift lowering's high limb (latent: no generic
; fold rewrites it today, but the limb has the same reliance on clamping).
define void @not_lshr_signbit_i128(ptr %out, i32 %amt) {
; CHECK-LABEL: not_lshr_signbit_i128(
; CHECK:       {
; CHECK-NEXT:    .reg .pred %p<2>;
; CHECK-NEXT:    .reg .b32 %r<5>;
; CHECK-NEXT:    .reg .b64 %rd<9>;
; CHECK-EMPTY:
; CHECK-NEXT:  // %bb.0:
; CHECK-NEXT:    ld.param.b64 %rd1, [not_lshr_signbit_i128_param_0];
; CHECK-NEXT:    ld.param.b32 %r1, [not_lshr_signbit_i128_param_1];
; CHECK-NEXT:    and.b32 %r2, %r1, 127;
; CHECK-NEXT:    sub.s32 %r3, 64, %r2;
; CHECK-NEXT:    mov.b64 %rd2, -9223372036854775808;
; CHECK-NEXT:    shl.b64 %rd3, %rd2, %r3;
; CHECK-NEXT:    add.s32 %r4, %r2, -64;
; CHECK-NEXT:    shr.u64 %rd4, %rd2, %r4;
; CHECK-NEXT:    setp.gt.s32 %p1, %r2, 63;
; CHECK-NEXT:    selp.b64 %rd5, %rd4, %rd3, %p1;
; CHECK-NEXT:    shr.u64 %rd6, %rd2, %r2;
; CHECK-NEXT:    not.b64 %rd7, %rd5;
; CHECK-NEXT:    not.b64 %rd8, %rd6;
; CHECK-NEXT:    st.v2.b64 [%rd1], {%rd7, %rd8};
; CHECK-NEXT:    ret;
  %m = and i32 %amt, 127
  %a = zext i32 %m to i128
  %s = lshr i128 -170141183460469231731687303715884105728, %a
  %n = xor i128 %s, -1
  store i128 %n, ptr %out
  ret void
}
