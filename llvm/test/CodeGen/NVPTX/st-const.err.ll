; RUN: not llc < %s -mtriple=nvptx64 -mcpu=sm_90 -filetype=null 2>&1 | FileCheck %s

; PTX has no encoding for stores to the constant address space, so a clean
; diagnostic must be emitted instead of an "st.const" that ptxas rejects.

@gc = addrspace(4) global i32 0
@vc = addrspace(4) global <2 x i32> zeroinitializer

; CHECK: error: {{.*}}: in function scalar void (): cannot store to pointer that points to constant memory space
define void @scalar() {
  store i32 1, ptr addrspace(4) @gc
  ret void
}

; CHECK: error: {{.*}}: in function vector void (<2 x i32>): cannot store to pointer that points to constant memory space
define void @vector(<2 x i32> %v) {
  store <2 x i32> %v, ptr addrspace(4) @vc
  ret void
}

; CHECK: error: {{.*}}: in function atomic void (): cannot store to pointer that points to constant memory space
define void @atomic() {
  store atomic i32 1, ptr addrspace(4) @gc monotonic, align 4
  ret void
}
