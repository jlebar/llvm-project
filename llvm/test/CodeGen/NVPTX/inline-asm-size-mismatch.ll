; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_70 2>&1 | FileCheck %s

; An inline-asm operand wider than its constraint's register does not fit;
; only the low bits would reach the asm. Reject it instead of silently
; truncating (scalars, i128) or asserting (integer vectors).

; CHECK: error: could not allocate output register for constraint 'r'
define i64 @scalar_r(i64 %x) {
  %r = call i64 asm "mov.b32 $0, $1;", "=r,r"(i64 %x)
  ret i64 %r
}

; CHECK: error: could not allocate output register for constraint 'l'
define i128 @scalar_l(i128 %x) {
  %r = call i128 asm "mov.b64 $0, $1;", "=l,l"(i128 %x)
  ret i128 %r
}

; CHECK: error: could not allocate output register for constraint 'l'
define <4 x i32> @vector_l(<4 x i32> %x) {
  %r = call <4 x i32> asm "mov.b64 $0, $1;", "=l,l"(<4 x i32> %x)
  ret <4 x i32> %r
}

; "q" is a .b128 register with no extending moves: a narrower operand cannot
; be placed in it either.
; CHECK: error: could not allocate output register for constraint 'q'
define i64 @narrow_q(i64 %x) {
  %r = call i64 asm "mov.b128 $0, $1;", "=q,q"(i64 %x)
  ret i64 %r
}

; CHECK: error: could not allocate input reg for constraint 'f'
define void @input_f(double %x) {
  call void asm sideeffect "mov.b32 _, $0;", "f"(double %x)
  ret void
}
