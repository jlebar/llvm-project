; RUN: not llc -mtriple=nvptx64 < %s 2>&1 | FileCheck %s

; llvm.nvvm.bf2h.rn{,.ftz} never had a lowering and have been removed, so
; uses are diagnosed like any other unknown intrinsic instead of crashing
; instruction selection.

; CHECK: error: {{.*}}call to unknown intrinsic 'llvm.nvvm.bf2h.rn' cannot be lowered by the NVPTX backend
; CHECK: error: {{.*}}call to unknown intrinsic 'llvm.nvvm.bf2h.rn.ftz' cannot be lowered by the NVPTX backend

declare i16 @llvm.nvvm.bf2h.rn(bfloat)
declare i16 @llvm.nvvm.bf2h.rn.ftz(bfloat)

define i16 @test_bf2h(bfloat %a) {
  %r1 = call i16 @llvm.nvvm.bf2h.rn(bfloat %a)
  %r2 = call i16 @llvm.nvvm.bf2h.rn.ftz(bfloat %a)
  %s = add i16 %r1, %r2
  ret i16 %s
}
