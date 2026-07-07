; Verify that __nvvm_reflect("__CUDA_PREC_DIV") is answered from the
; nvvm-reflect-prec-div module flag, and defaults to 1 (use the IEEE
; round-to-nearest division, like nvcc's -prec-div=true) when the flag is
; absent.

; RUN: opt < %s -S -mtriple=nvptx-nvidia-cuda -passes='nvvm-reflect,simplifycfg' \
; RUN:   | FileCheck %s --check-prefix=PREC

; RUN: cat %s > %t.approx
; RUN: echo '!llvm.module.flags = !{!0}' >> %t.approx
; RUN: echo '!0 = !{i32 4, !"nvvm-reflect-prec-div", i32 0}' >> %t.approx
; RUN: opt < %t.approx -S -mtriple=nvptx-nvidia-cuda -passes='nvvm-reflect,simplifycfg' \
; RUN:   | FileCheck %s --check-prefix=APPROX

; RUN: cat %s > %t.prec
; RUN: echo '!llvm.module.flags = !{!0}' >> %t.prec
; RUN: echo '!0 = !{i32 4, !"nvvm-reflect-prec-div", i32 1}' >> %t.prec
; RUN: opt < %t.prec -S -mtriple=nvptx-nvidia-cuda -passes='nvvm-reflect,simplifycfg' \
; RUN:   | FileCheck %s --check-prefix=PREC

@str = private unnamed_addr addrspace(1) constant [16 x i8] c"__CUDA_PREC_DIV\00"

declare i32 @__nvvm_reflect(ptr)
declare float @llvm.nvvm.div.approx.f(float, float)

; PREC-LABEL: @foo
; APPROX-LABEL: @foo
define i32 @foo() {
; PREC: ret i32 1
; APPROX: ret i32 0
  %reflect = call i32 @__nvvm_reflect(ptr addrspacecast (ptr addrspace(1) @str to ptr))
  ret i32 %reflect
}

; This is the division-selection pattern used by libdevice's math functions.

; PREC-LABEL: @div
; APPROX-LABEL: @div
define float @div(float %x, float %y) {
; PREC: fdiv float
; PREC-NOT: call float @llvm.nvvm.div.approx.f
; APPROX-NOT: fdiv float
; APPROX: call float @llvm.nvvm.div.approx.f
; APPROX-NOT: fdiv float
  %reflect = call i32 @__nvvm_reflect(ptr addrspacecast (ptr addrspace(1) @str to ptr))
  %cond = icmp ne i32 %reflect, 0
  br i1 %cond, label %prec, label %approx

prec:
  %rn = fdiv float %x, %y
  ret float %rn

approx:
  %ap = call float @llvm.nvvm.div.approx.f(float %x, float %y)
  ret float %ap
}
