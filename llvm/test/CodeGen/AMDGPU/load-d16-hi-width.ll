; RUN: llc -mtriple=amdgcn -mcpu=gfx1030 -O0 < %s | FileCheck %s

; The d16-load match in AMDGPUDAGToDAGISel::PreprocessISelDAG ties the other
; half of the build_vector into the load as a 32-bit value. When that half is
; the high 16 bits of the low dword of a *wider* value (element 1 of a v4i16,
; or trunc (srl i64, 16)), the source must not be reinterpreted as the 32-bit
; tied-in operand.

; hi operand comes from element 1 of a four-element vector: bits 16-31 of the
; low dword, but the source is 64 bits wide and must not be bitcast to the
; v2i16 tied-in operand.
; CHECK-LABEL: build_vector_hi_from_v4i16:
; CHECK: ds_read_u16 v
; CHECK: global_store_dword
define amdgpu_kernel void @build_vector_hi_from_v4i16(ptr addrspace(1) %p, ptr addrspace(3) %lds) {
  %lo = load i16, ptr addrspace(3) %lds
  %vec = load <4 x i16>, ptr addrspace(1) %p
  %hi = extractelement <4 x i16> %vec, i32 1
  %bv0 = insertelement <2 x i16> poison, i16 %lo, i32 0
  %bv = insertelement <2 x i16> %bv0, i16 %hi, i32 1
  store <2 x i16> %bv, ptr addrspace(1) %p
  ret void
}

; Same shape through trunc (srl i64, 16).
; CHECK-LABEL: build_vector_hi_from_i64_srl:
; CHECK: ds_read_u16 v
; CHECK: global_store_dword
define amdgpu_kernel void @build_vector_hi_from_i64_srl(ptr addrspace(1) %p, ptr addrspace(3) %lds) {
  %lo = load i16, ptr addrspace(3) %lds
  %wide = load i64, ptr addrspace(1) %p
  %srl = lshr i64 %wide, 16
  %hi = trunc i64 %srl to i16
  %bv0 = insertelement <2 x i16> poison, i16 %lo, i32 0
  %bv = insertelement <2 x i16> %bv0, i16 %hi, i32 1
  store <2 x i16> %bv, ptr addrspace(1) %p
  ret void
}

; Positive control: hi element from a v2i16 still forms a d16 load.
; CHECK-LABEL: build_vector_hi_from_v2i16:
; CHECK: ds_read_u16_d16 v
; CHECK: global_store_dword
define amdgpu_kernel void @build_vector_hi_from_v2i16(ptr addrspace(1) %p, ptr addrspace(3) %lds) {
  %lo = load i16, ptr addrspace(3) %lds
  %vec = load <2 x i16>, ptr addrspace(1) %p
  %hi = extractelement <2 x i16> %vec, i32 1
  %bv0 = insertelement <2 x i16> poison, i16 %lo, i32 0
  %bv = insertelement <2 x i16> %bv0, i16 %hi, i32 1
  store <2 x i16> %bv, ptr addrspace(1) %p
  ret void
}
