; RUN: split-file %s %t
; RUN: not llc < %t/global.ll -mcpu=sm_50 2>&1 | FileCheck %t/global.ll
; RUN: not llc < %t/param-offset.ll -mcpu=sm_50 2>&1 | FileCheck %t/param-offset.ll

; For NVCL, image handles must be replaced with symbolic references, which is
; only possible when the handle is a kernel parameter or a texture/surface
; global. A handle loaded from anywhere else has no symbol to rewrite to, so
; the compiler must produce an error rather than assert (or silently emit a
; wrong symbol).

;--- global.ll
; The handle is loaded from a global i64 variable.
target triple = "nvptx64-nvidia-nvcl"

@handle = addrspace(1) global i64 0

declare i32 @llvm.nvvm.suld.1d.i32.trap(i64, i32)

; CHECK: LLVM ERROR: unable to replace image handle loaded from a non-parameter address in kernel with a symbol
define ptx_kernel void @kernel(ptr %out, i32 %idx) {
entry:
  %h = load i64, ptr addrspace(1) @handle
  %val = tail call i32 @llvm.nvvm.suld.1d.i32.trap(i64 %h, i32 %idx)
  store i32 %val, ptr %out
  ret void
}

;--- param-offset.ll
; The handle is a field at a nonzero offset inside an aggregate kernel
; parameter. The load's address is the param symbol plus 8, so the whole
; parameter is not an image and cannot be rewritten either. This used to be
; silently rewritten to the bare parameter symbol, dropping the offset.
target triple = "nvptx64-nvidia-nvcl"

declare i32 @llvm.nvvm.suld.1d.i32.trap(i64, i32)

; CHECK: LLVM ERROR: unable to replace image handle loaded from a non-parameter address in kernel with a symbol
define ptx_kernel void @kernel(ptr %out, i32 %idx, { i32, i64 } %agg) {
entry:
  %h = extractvalue { i32, i64 } %agg, 1
  %val = tail call i32 @llvm.nvvm.suld.1d.i32.trap(i64 %h, i32 %idx)
  store i32 %val, ptr %out
  ret void
}
