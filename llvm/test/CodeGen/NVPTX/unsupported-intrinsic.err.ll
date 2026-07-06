; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_90 -mattr=+ptx87 -filetype=null 2>&1 | FileCheck %s

; Target intrinsics whose selection patterns are all gated on subtarget
; predicates the current target doesn't satisfy must be diagnosed rather than
; crashing instruction selection with "Cannot select". One representative
; intrinsic per gated family, all unsupported on sm_90 with PTX ISA 8.7.

; CHECK: error: {{.*}}in function tcgen05_alloc{{.*}}: 'llvm.nvvm.tcgen05.alloc.cg1' is not supported on sm_90 with PTX ISA version 8.7
define void @tcgen05_alloc(ptr %addr) {
  call void @llvm.nvvm.tcgen05.alloc.cg1(ptr %addr, i32 32)
  ret void
}

; CHECK: error: {{.*}}'llvm.nvvm.wgmma.fence.sync.aligned' is not supported on sm_90 with PTX ISA version 8.7
define void @wgmma_fence() {
  call void @llvm.nvvm.wgmma.fence.sync.aligned()
  ret void
}

; CHECK: error: {{.*}}'llvm.nvvm.setmaxnreg.inc.sync.aligned.u32' is not supported on sm_90 with PTX ISA version 8.7
define void @setmaxnreg() {
  call void @llvm.nvvm.setmaxnreg.inc.sync.aligned.u32(i32 96)
  ret void
}

; CHECK: error: {{.*}}'llvm.nvvm.redux.sync.fmin' is not supported on sm_90 with PTX ISA version 8.7
define float @redux_fmin(float %src, i32 %mask) {
  %v = call float @llvm.nvvm.redux.sync.fmin(float %src, i32 %mask)
  ret float %v
}

; CHECK: error: {{.*}}'llvm.nvvm.f2tf32.rn.satfinite' is not supported on sm_90 with PTX ISA version 8.7
define i32 @f2tf32_rn_satfinite(float %f) {
  %v = call i32 @llvm.nvvm.f2tf32.rn.satfinite(float %f)
  ret i32 %v
}

; CHECK: error: {{.*}}'llvm.nvvm.st.bulk' is not supported on sm_90 with PTX ISA version 8.7
define void @st_bulk(ptr %dest, i64 %size) {
  call void @llvm.nvvm.st.bulk(ptr %dest, i64 %size, i64 0)
  ret void
}

; The legacy non-sync shfl instruction was removed for sm_70+ in PTX ISA 6.4,
; so this diagnoses on newer targets too.
; CHECK: error: {{.*}}'llvm.nvvm.shfl.bfly.f32' is not supported on sm_90 with PTX ISA version 8.7
define float @shfl_bfly(float %a, i32 %b, i32 %c) {
  %v = call float @llvm.nvvm.shfl.bfly.f32(float %a, i32 %b, i32 %c)
  ret float %v
}
