; RUN: llc -mtriple=nvptx64 < %s | FileCheck %s
; RUN: %if ptxas %{ llc -mtriple=nvptx64 < %s | %ptxas-verify %}

; Test that %c works with immediates
; CHECK-LABEL: test_inlineasm_c_output_template0
; CHECK: //TEST 42
define dso_local i32 @test_inlineasm_c_output_template0() {
  tail call void asm sideeffect "//TEST ${0:c}", "i"(i32 42)
  ret i32 42
}

@baz = internal global i32 0, align 4
; qux is dso_local (not internal) to check that the symbol is printed without
; an ELF "$local" suffix, which PTX has no notion of.
@qux = dso_local addrspace(1) global [4 x i32] zeroinitializer, align 4

; Test that %c works with global address
; CHECK-LABEL: test_inlineasm_c_output_template1
; CHECK: //TEST baz
define dso_local i32 @test_inlineasm_c_output_template1() {
  tail call void asm sideeffect "//TEST ${0:c}", "i"(ptr nonnull @baz)
  ret i32 42
}

; Test that "i" accepts the generic address of a global, as produced for
; "i"(&gv) in CUDA device code.
; CHECK-LABEL: test_inlineasm_generic_global
; CHECK: //TEST qux{{$}}
define dso_local i32 @test_inlineasm_generic_global() {
  tail call void asm sideeffect "//TEST $0", "i"(ptr addrspacecast (ptr addrspace(1) @qux to ptr))
  ret i32 42
}

; ... also under a constant offset, as produced for "i"(&arr[3]).
; CHECK-LABEL: test_inlineasm_generic_global_offset
; CHECK: //TEST qux+12{{$}}
define dso_local i32 @test_inlineasm_generic_global_offset() {
  tail call void asm sideeffect "//TEST $0", "i"(ptr getelementptr inbounds (i8, ptr addrspacecast (ptr addrspace(1) @qux to ptr), i64 12))
  ret i32 42
}

; Test that %n works with immediates
; CHECK-LABEL: test_inlineasm_c_output_template2
; CHECK: //TEST -42
define dso_local i32 @test_inlineasm_c_output_template2() {
  tail call void asm sideeffect "//TEST ${0:n}", "i"(i32 42)
  ret i32 42
}
