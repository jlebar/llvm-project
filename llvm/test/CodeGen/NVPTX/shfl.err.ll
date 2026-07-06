; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_70 -mattr=+ptx64 -filetype=null 2>&1 | FileCheck %s
; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_90 -mattr=+ptx80 -filetype=null 2>&1 | FileCheck %s

; The non-sync shfl instruction was removed for sm_70+ in PTX ISA 6.4, so the
; non-sync shfl intrinsics must be diagnosed on those targets rather than
; crashing instruction selection.

; CHECK: error: {{.*}}in function shfl_down_i32{{.*}}: 'llvm.nvvm.shfl.down.i32' is not supported on sm_70 and later with PTX ISA 6.4 and later; use the shfl.sync intrinsic instead
define i32 @shfl_down_i32(i32 %a, i32 %b, i32 %c) {
  %val = call i32 @llvm.nvvm.shfl.down.i32(i32 %a, i32 %b, i32 %c)
  ret i32 %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.down.f32' is not supported
define float @shfl_down_f32(float %a, i32 %b, i32 %c) {
  %val = call float @llvm.nvvm.shfl.down.f32(float %a, i32 %b, i32 %c)
  ret float %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.up.i32' is not supported
define i32 @shfl_up_i32(i32 %a, i32 %b, i32 %c) {
  %val = call i32 @llvm.nvvm.shfl.up.i32(i32 %a, i32 %b, i32 %c)
  ret i32 %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.up.f32' is not supported
define float @shfl_up_f32(float %a, i32 %b, i32 %c) {
  %val = call float @llvm.nvvm.shfl.up.f32(float %a, i32 %b, i32 %c)
  ret float %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.bfly.i32' is not supported
define i32 @shfl_bfly_i32(i32 %a, i32 %b, i32 %c) {
  %val = call i32 @llvm.nvvm.shfl.bfly.i32(i32 %a, i32 %b, i32 %c)
  ret i32 %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.bfly.f32' is not supported
define float @shfl_bfly_f32(float %a, i32 %b, i32 %c) {
  %val = call float @llvm.nvvm.shfl.bfly.f32(float %a, i32 %b, i32 %c)
  ret float %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.idx.i32' is not supported
define i32 @shfl_idx_i32(i32 %a, i32 %b, i32 %c) {
  %val = call i32 @llvm.nvvm.shfl.idx.i32(i32 %a, i32 %b, i32 %c)
  ret i32 %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.idx.f32' is not supported
define float @shfl_idx_f32(float %a, i32 %b, i32 %c) {
  %val = call float @llvm.nvvm.shfl.idx.f32(float %a, i32 %b, i32 %c)
  ret float %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.down.i32p' is not supported
define {i32, i1} @shfl_down_i32p(i32 %a, i32 %b, i32 %c) {
  %val = call {i32, i1} @llvm.nvvm.shfl.down.i32p(i32 %a, i32 %b, i32 %c)
  ret {i32, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.down.f32p' is not supported
define {float, i1} @shfl_down_f32p(float %a, i32 %b, i32 %c) {
  %val = call {float, i1} @llvm.nvvm.shfl.down.f32p(float %a, i32 %b, i32 %c)
  ret {float, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.up.i32p' is not supported
define {i32, i1} @shfl_up_i32p(i32 %a, i32 %b, i32 %c) {
  %val = call {i32, i1} @llvm.nvvm.shfl.up.i32p(i32 %a, i32 %b, i32 %c)
  ret {i32, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.up.f32p' is not supported
define {float, i1} @shfl_up_f32p(float %a, i32 %b, i32 %c) {
  %val = call {float, i1} @llvm.nvvm.shfl.up.f32p(float %a, i32 %b, i32 %c)
  ret {float, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.bfly.i32p' is not supported
define {i32, i1} @shfl_bfly_i32p(i32 %a, i32 %b, i32 %c) {
  %val = call {i32, i1} @llvm.nvvm.shfl.bfly.i32p(i32 %a, i32 %b, i32 %c)
  ret {i32, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.bfly.f32p' is not supported
define {float, i1} @shfl_bfly_f32p(float %a, i32 %b, i32 %c) {
  %val = call {float, i1} @llvm.nvvm.shfl.bfly.f32p(float %a, i32 %b, i32 %c)
  ret {float, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.idx.i32p' is not supported
define {i32, i1} @shfl_idx_i32p(i32 %a, i32 %b, i32 %c) {
  %val = call {i32, i1} @llvm.nvvm.shfl.idx.i32p(i32 %a, i32 %b, i32 %c)
  ret {i32, i1} %val
}

; CHECK: error: {{.*}}'llvm.nvvm.shfl.idx.f32p' is not supported
define {float, i1} @shfl_idx_f32p(float %a, i32 %b, i32 %c) {
  %val = call {float, i1} @llvm.nvvm.shfl.idx.f32p(float %a, i32 %b, i32 %c)
  ret {float, i1} %val
}
