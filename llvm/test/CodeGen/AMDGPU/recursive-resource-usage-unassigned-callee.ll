; RUN: llc -mtriple=amdgcn-amd-amdhsa -mcpu=gfx90a < %s | FileCheck %s

; Mutual recursion where flattening the cycle walks an expression that still
; references a not-yet-emitted function.
;
; SCC: qux -> {baz, foo}, baz -> qux, foo -> baz. The kernel calls baz.
; With this module order the DFS roots the SCC at foo, so functions are
; emitted in the order qux, baz, foo. When baz's callee expression for qux is
; flattened (qux's value refers back to baz), foo's resource symbols have no
; value yet. They must be kept in the flattened max rather than dropped:
; the kernel's only path to foo's v60/a30/s70 usage is through baz.

; CHECK-LABEL: {{^}}qux
; CHECK: .set .Lqux.num_vgpr, max(42, .Lbaz.num_vgpr, .Lfoo.num_vgpr)
; CHECK: .set .Lqux.num_agpr, max(0, .Lbaz.num_agpr, .Lfoo.num_agpr)
; CHECK: .set .Lqux.numbered_sgpr, max(54, .Lbaz.numbered_sgpr, .Lfoo.numbered_sgpr)

; CHECK-LABEL: {{^}}baz
; CHECK: .set .Lbaz.num_vgpr, max(42, max(42, .Lfoo.num_vgpr))
; CHECK: .set .Lbaz.num_agpr, max(0, max(0, .Lfoo.num_agpr))
; CHECK: .set .Lbaz.numbered_sgpr, max(54, max(54, .Lfoo.numbered_sgpr))

; CHECK-LABEL: {{^}}foo
; CHECK: .set .Lfoo.num_vgpr, max(61, 42)
; CHECK: .set .Lfoo.num_agpr, max(31, 0)
; CHECK: .set .Lfoo.numbered_sgpr, max(71, 54)

; CHECK-LABEL: {{^}}usebaz
; CHECK: .set .Lusebaz.num_vgpr, max(32, .Lbaz.num_vgpr)
; CHECK: .set .Lusebaz.num_agpr, max(0, .Lbaz.num_agpr)
; CHECK: .set .Lusebaz.numbered_sgpr, max(33, .Lbaz.numbered_sgpr)
; CHECK: NumVgprs: 61
; CHECK: NumAgprs: 31
; CHECK: TotalNumVgprs: 95

define void @foo() {
entry:
  call void asm sideeffect "", "~{v60},~{a30},~{s70}"()
  call void @baz()
  ret void
}

define void @qux() {
entry:
  call void @baz()
  call void @foo()
  ret void
}

define void @baz() {
entry:
  call void asm sideeffect "", "~{v35}"()
  call void @qux()
  ret void
}

define amdgpu_kernel void @usebaz() {
entry:
  call void @baz()
  ret void
}
