; RUN: not llc -mtriple=amdgcn-amd-amdhsa -filetype=null %s 2>&1 | FileCheck %s

; StructurizeCFG does not structurize regions whose entry block terminates in
; a callbr, so the divergent exits of this callbr-headed cycle reach
; SIAnnotateControlFlow unstructured. Check that this fails with a proper
; error instead of crashing with a request to file a bug report. Note the
; plain "not" (no --crash) on the RUN line: the error must be a graceful
; exit, not an abort.
;
; From https://github.com/llvm/llvm-project/issues/170830.

; CHECK: LLVM ERROR: unstructured control flow with 'asm goto' (callbr) is not yet supported

define void @callbr_cycle_divergent_exit(i32 %c) {
entry:
  br label %callbr

callbr:
  callbr void asm sideeffect "", "!i"() to label %loop [label %callbr]

loop:
  switch i32 %c, label %exit [
    i32 0, label %loop
    i32 1, label %callbr
  ]

exit:
  ret void
}
