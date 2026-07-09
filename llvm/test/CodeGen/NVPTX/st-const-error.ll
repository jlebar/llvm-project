; RUN: split-file %s %t
; RUN: not --crash llc < %t/scalar.ll -mtriple=nvptx64 2>&1 | FileCheck %s
; RUN: not --crash llc < %t/vector.ll -mtriple=nvptx64 2>&1 | FileCheck %s
; RUN: not --crash llc < %t/atomic-store.ll -mtriple=nvptx64 2>&1 | FileCheck %s
; RUN: not --crash llc < %t/atomicrmw.ll -mtriple=nvptx64 2>&1 | FileCheck %s
; RUN: not --crash llc < %t/cmpxchg.ll -mtriple=nvptx64 2>&1 | FileCheck %s

; The const space is read-only and PTX has no instructions that write to it,
; so stores and atomics on addrspace(4) pointers must be rejected. They used
; to be silently emitted as "st.const.b32 [c], 1" / "atom.const.add.u32",
; which ptxas rejects (only the vector-store path had a check).

; CHECK: Cannot store to pointer that points to constant memory space

;--- scalar.ll
@c = addrspace(4) global i32 0
define void @st_const_scalar() {
  store i32 1, ptr addrspace(4) @c
  ret void
}

;--- vector.ll
@c = addrspace(4) global <2 x i32> zeroinitializer
define void @st_const_vector() {
  store <2 x i32> <i32 1, i32 2>, ptr addrspace(4) @c
  ret void
}

;--- atomic-store.ll
@c = addrspace(4) global i32 0
define void @st_const_atomic() {
  store atomic i32 1, ptr addrspace(4) @c monotonic, align 4
  ret void
}

;--- atomicrmw.ll
@c = addrspace(4) global i32 0
define i32 @rmw_const() {
  %v = atomicrmw add ptr addrspace(4) @c, i32 1 monotonic
  ret i32 %v
}

;--- cmpxchg.ll
@c = addrspace(4) global i32 0
define i32 @cas_const() {
  %r = cmpxchg ptr addrspace(4) @c, i32 0, i32 1 monotonic monotonic
  %v = extractvalue { i32, i1 } %r, 0
  ret i32 %v
}
