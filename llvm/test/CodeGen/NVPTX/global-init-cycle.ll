; RUN: split-file %s %t
; RUN: not llc < %t/self.ll -mtriple=nvptx64 2>&1 | FileCheck %s --check-prefix=SELF
; RUN: not llc < %t/mutual.ll -mtriple=nvptx64 2>&1 | FileCheck %s --check-prefix=MUTUAL
; RUN: not llc < %t/struct.ll -mtriple=nvptx64 2>&1 | FileCheck %s --check-prefix=STRUCT
; RUN: not llc < %t/multipath.ll -mtriple=nvptx64 2>&1 | FileCheck %s --check-prefix=MULTIPATH

; PTX initializers may only reference variables defined earlier in the module,
; so a global whose initializer refers to its own address (directly, through a
; cycle of globals, or from within an aggregate) cannot be emitted. Check that
; we produce a proper error instead of crashing.

; SELF: error: initializer of global variable 'p' refers to the variable's own address
;--- self.ll
@p = addrspace(1) global ptr addrspace(1) @p

; MUTUAL: error: initializer of global variable 'a' refers to the variable's own address
;--- mutual.ll
@a = addrspace(1) global ptr addrspace(1) @b
@b = addrspace(1) global ptr addrspace(1) @a

; STRUCT: error: initializer of global variable 's' refers to the variable's own address
;--- struct.ll
@s = addrspace(1) global { i32, ptr addrspace(1) } { i32 42, ptr addrspace(1) @s }

; A cycle reachable along two paths (directly from @x and again through @y) is
; diagnosed only once.
; MULTIPATH: error: initializer of global variable 'x' refers to the variable's own address
; MULTIPATH-NOT: error:
;--- multipath.ll
@x = addrspace(1) global { ptr addrspace(1), ptr addrspace(1) } { ptr addrspace(1) @x, ptr addrspace(1) @y }
@y = addrspace(1) global ptr addrspace(1) @x
