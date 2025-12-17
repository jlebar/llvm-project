; RUN: not %lli -jit-kind=mcjit -force-interpreter=true -executionengine-model-poison-ub %s 2>&1 | FileCheck %s
; CHECK: execution hit undefined behavior

define i32 @main() {
entry:
  %shift = lshr exact i64 1, 64
  %trunc = trunc i64 %shift to i32
  ret i32 %trunc
}
