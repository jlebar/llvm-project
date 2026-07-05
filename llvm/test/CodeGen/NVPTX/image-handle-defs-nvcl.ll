; RUN: not llc < %s -mcpu=sm_50 2>&1 | FileCheck %s

; For NVCL, image handles must be replaced with symbolic references. A handle
; that is a field of an aggregate kernel parameter is loaded with a vectorized
; load and has no symbol of its own, so the compiler must produce an error
; rather than hang (see #166167).

target triple = "nvptx64-nvidia-nvcl"

%aggr = type { { i64, i64 }, <4 x i32> }

declare void @llvm.nvvm.sust.b.2d.v4i32.zero(i64, i32, i32, i32, i32, i32, i32)

; CHECK: LLVM ERROR: unable to replace image handle defined by LDV_i64_v2 in handle_in_aggregate with a symbol
define ptx_kernel void @handle_in_aggregate(%aggr %desc) {
entry:
  %pair = extractvalue %aggr %desc, 0
  %handle = extractvalue { i64, i64 } %pair, 0
  tail call void @llvm.nvvm.sust.b.2d.v4i32.zero(i64 %handle, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0)
  ret void
}
