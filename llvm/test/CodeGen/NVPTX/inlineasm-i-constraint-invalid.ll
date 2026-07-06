; RUN: not llc -mtriple=nvptx64 < %s 2>&1 | FileCheck %s

; The generic address of a shared variable is not its window-relative address
; (cvta.shared is not the identity), so it cannot be substituted as a symbol
; immediate. Only global-to-generic casts may be looked through.

@shared_var = internal addrspace(3) global i32 0

; CHECK: error: invalid operand for inline asm constraint 'i'
define void @test_shared_rejected() {
  call void asm sideeffect "// TEST $0", "i"(ptr addrspacecast (ptr addrspace(3) @shared_var to ptr))
  ret void
}
