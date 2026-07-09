; RUN: opt < %s -passes=slsr -S | FileCheck %s --check-prefixes=CHECK,LIMIT
; RUN: opt < %s -passes=slsr -slsr-max-bases-to-check=17 -S | FileCheck %s --check-prefixes=CHECK,NOLIMIT
; RUN: opt < %s -passes=slsr -slsr-max-bases-to-check=0 -S | FileCheck %s --check-prefixes=CHECK,NOLIMIT

target datalayout = "e-i64:64-v16:16-v32:32-n16:32:64"
target triple = "nvptx64-nvidia-cuda"

; %xn's only viable basis is %x0: they index the same underlying pointer, and
; the base delta %d is available as a function argument. The 16 geps in between
; are in the same candidate group (same stride %i, same element size) but have
; unrelated bases, so each one costs a getMinusSCEV call that produces nothing.
; With the default limit of 16 the search gives up before it reaches %x0; with
; a limit of 17 (or no limit) it finds %x0, the 17th candidate checked, and
; rewrites %xn to %x0 + %d.

define void @max_bases_to_check(ptr %p, ptr %q1, ptr %q2, ptr %q3, ptr %q4, ptr %q5, ptr %q6, ptr %q7, ptr %q8, ptr %q9, ptr %q10, ptr %q11, ptr %q12, ptr %q13, ptr %q14, ptr %q15, ptr %q16, i64 %i, i64 %d) {
; CHECK-LABEL: @max_bases_to_check(
; CHECK: %x0 = getelementptr i8, ptr %p, i64 %i
  %x0 = getelementptr i8, ptr %p, i64 %i
  store i8 0, ptr %x0
  %t1 = getelementptr i8, ptr %q1, i64 %i
  store i8 1, ptr %t1
  %t2 = getelementptr i8, ptr %q2, i64 %i
  store i8 2, ptr %t2
  %t3 = getelementptr i8, ptr %q3, i64 %i
  store i8 3, ptr %t3
  %t4 = getelementptr i8, ptr %q4, i64 %i
  store i8 4, ptr %t4
  %t5 = getelementptr i8, ptr %q5, i64 %i
  store i8 5, ptr %t5
  %t6 = getelementptr i8, ptr %q6, i64 %i
  store i8 6, ptr %t6
  %t7 = getelementptr i8, ptr %q7, i64 %i
  store i8 7, ptr %t7
  %t8 = getelementptr i8, ptr %q8, i64 %i
  store i8 8, ptr %t8
  %t9 = getelementptr i8, ptr %q9, i64 %i
  store i8 9, ptr %t9
  %t10 = getelementptr i8, ptr %q10, i64 %i
  store i8 10, ptr %t10
  %t11 = getelementptr i8, ptr %q11, i64 %i
  store i8 11, ptr %t11
  %t12 = getelementptr i8, ptr %q12, i64 %i
  store i8 12, ptr %t12
  %t13 = getelementptr i8, ptr %q13, i64 %i
  store i8 13, ptr %t13
  %t14 = getelementptr i8, ptr %q14, i64 %i
  store i8 14, ptr %t14
  %t15 = getelementptr i8, ptr %q15, i64 %i
  store i8 15, ptr %t15
  %t16 = getelementptr i8, ptr %q16, i64 %i
  store i8 16, ptr %t16
  %pn = getelementptr i8, ptr %p, i64 %d
; LIMIT: %xn = getelementptr i8, ptr %pn, i64 %i
; NOLIMIT: %xn = getelementptr i8, ptr %x0, i64 %d
  %xn = getelementptr i8, ptr %pn, i64 %i
  store i8 17, ptr %xn
  ret void
}

