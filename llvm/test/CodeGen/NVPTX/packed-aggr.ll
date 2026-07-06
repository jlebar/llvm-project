; RUN: not --crash llc < %s -mtriple=nvptx -mcpu=sm_20 -mattr=+ptx70 2>&1 | \
; RUN:   FileCheck %s --check-prefix=ERROR

; RUN: llc < %s -mtriple=nvptx -mcpu=sm_20 -mattr=+ptx71 | \
; RUN:   FileCheck %s --check-prefixes=CHECK,CHECK32
; RUN: llc < %s -mtriple=nvptx64 -mcpu=sm_20 -mattr=+ptx71 | \
; RUN:   FileCheck %s --check-prefixes=CHECK,CHECK64
; RUN: %if ptxas-isa-7.1 && ptxas-ptr32 %{ llc < %s -mtriple=nvptx -mcpu=sm_20 -mattr=+ptx71 | %ptxas-verify %}
; RUN: %if ptxas-isa-7.1 %{ llc < %s -mtriple=nvptx64 -mcpu=sm_20 -mattr=+ptx71 | %ptxas-verify %}

;; Test that packed structs with symbol references are represented using the
;; mask() operator.

declare void @func()
@p = addrspace(1) global i8 0
; CHECK: .extern .func func
; CHECK: .u8 p;

%t1 = type <{ i16, ptr, i8, ptr, ptr, i32 }>
@s1 = addrspace(1) global %t1 <{
; ERROR: initialized packed aggregate with pointers 's1' requires at least PTX ISA version 7.1
; CHECK32: .global .align 1 .u8 s1[19] = {
; CHECK64: .global .align 1 .u8 s1[31] = {
    i16 12,
; CHECK-SAME:   12, 0,
    ptr addrspacecast (ptr addrspace(1) @p to ptr),
; CHECK-SAME:   0xFF(generic(p)), 0xFF00(generic(p)), 0xFF0000(generic(p)), 0xFF000000(generic(p)),
; CHECK64-SAME: 0xFF00000000(generic(p)), 0xFF0000000000(generic(p)), 0xFF000000000000(generic(p)), 0xFF00000000000000(generic(p)),
    i8 34,
; CHECK-SAME:   34
    ptr @func,
; CHECK-SAME:   0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func),
; CHECK64-SAME: 0xFF00000000(func), 0xFF0000000000(func), 0xFF000000000000(func), 0xFF00000000000000(func),
    ptr addrspacecast (ptr addrspace(1) getelementptr (i8, ptr addrspace(1) @p, i32 3) to ptr),
; CHECK-SAME:   0xFF(generic(p)+3), 0xFF00(generic(p)+3), 0xFF0000(generic(p)+3), 0xFF000000(generic(p)+3),
; CHECK64-SAME: 0xFF00000000(generic(p)+3), 0xFF0000000000(generic(p)+3), 0xFF000000000000(generic(p)+3), 0xFF00000000000000(generic(p)+3),
    i32 56 }>, align 1
; CHECK-SAME:   56, 0, 0, 0};

;; Test a case than an unaligned pointer is in a nested struct.

%t2i = type <{ ptr }>
%t2o = type { i8, %t2i, i32 }
@s2 = addrspace(1) global %t2o {
; CHECK32: .global .align 8 .u8 s2[12] = {
; CHECK64: .global .align 8 .u8 s2[16] = {
    i8 12,
; CHECK-SAME:   12,
    %t2i <{ ptr @func }>,
; CHECK-SAME:   0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func),
; CHECK64-SAME: 0xFF00000000(func), 0xFF0000000000(func), 0xFF000000000000(func), 0xFF00000000000000(func),
    i32 34}
; CHECK-SAME:   0, 0, 0,
; CHECK-SAME:   34, 0, 0, 0};

;; Test that a packed struct which size is not multiple of the pointer size
;; is printed in bytes and uses the mask() operator for pointers even though
;; the pointers are aligned.

%t3 = type <{ ptr, i8 }>
@s3 = addrspace(1) global %t3 <{
; CHECK32: .global .align 1 .u8 s3[5] = {
; CHECK64: .global .align 1 .u8 s3[9] = {
    ptr @func,
; CHECK-SAME:   0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func),
; CHECK64-SAME: 0xFF00000000(func), 0xFF0000000000(func), 0xFF000000000000(func), 0xFF00000000000000(func),
    i8 56 }>, align 1
; CHECK-SAME:   56};

;; Test that a packed struct with aligned pointers is printed in words.

%t4 = type <{ ptr, i64 }>
@s4 = addrspace(1) global %t4 <{
; CHECK32: .global .align 1 .u32 s4[3] = {
; CHECK64: .global .align 1 .u64 s4[2] = {
    ptr @func,
; CHECK-SAME:   func,
    i64 15}>, align 1
; CHECK32-SAME: 15, 0};
; CHECK64-SAME: 15};

;; Test that a packed struct with unaligned pointers inside an array is handled.

%t5 = type <{ ptr, i16 }>
@a5 = addrspace(1) global [2 x %t5] [%t5 <{ ptr @func, i16 5 }>, %t5 <{ ptr @func, i16 9 }> ]
; CHECK32: .global .align 8 .u8 a5[12] = {
; CHECK32-SAME: 0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func), 5, 0,
; CHECK32-SAME: 0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func), 9, 0};
; CHECK64: .global .align 8 .u8 a5[20] = {
; CHECK64-SAME: 0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func),
; CHECK64-SAME: 0xFF00000000(func), 0xFF0000000000(func), 0xFF000000000000(func), 0xFF00000000000000(func),
; CHECK64-SAME: 5, 0,
; CHECK64-SAME: 0xFF(func), 0xFF00(func), 0xFF0000(func), 0xFF000000(func),
; CHECK64-SAME: 0xFF00000000(func), 0xFF0000000000(func), 0xFF000000000000(func), 0xFF00000000000000(func),
; CHECK64-SAME: 9, 0};

;; Test that the buffered image of an aggregate initializer advances by each
;; field's full slot (including struct padding and the alloc size of odd-width
;; integers), and that symbols narrowed by ptrtoint only occupy the narrow
;; type's bytes.

@g = addrspace(1) global i32 0

;; Padding between a pointer field and an over-aligned field must be kept.
@padded = addrspace(1) global { ptr addrspace(1), <4 x i32> } {
; CHECK32: .global .align 16 .u32 padded[8] = {g, 0, 0, 0, 1, 2, 3, 4};
; CHECK64: .global .align 16 .u64 padded[4] = {g, 0, 8589934593, 17179869187};
    ptr addrspace(1) @g,
    <4 x i32> <i32 1, i32 2, i32 3, i32 4> }

;; A ptrtoint to an integer narrower than the pointer keeps only the low bytes
;; of the address; the following field must not be consumed. On 64-bit this
;; forces the byte form with per-byte mask() operators.
@trunc = addrspace(1) global { i32, i32 } {
; CHECK32: .global .align 8 .u32 trunc[2] = {g, 305419896};
; CHECK64: .global .align 8 .u8 trunc[8] = {0xFF(g), 0xFF00(g), 0xFF0000(g), 0xFF000000(g), 120, 86, 52, 18};
    i32 ptrtoint (ptr addrspace(1) @g to i32),
    i32 305419896 }

;; Same with the symbol at an unaligned position.
@truncpacked = addrspace(1) global <{ i16, i32, i16 }> <{
; CHECK: .global .align 8 .u8 truncpacked[8] = {35, 1, 0xFF(g), 0xFF00(g), 0xFF0000(g), 0xFF000000(g), 86, 4};
    i16 291,
    i32 ptrtoint (ptr addrspace(1) @g to i32),
    i16 1110 }>

;; A ptrtoint to an integer wider than the pointer zero-extends: the symbol
;; still prints as one word and the rest of the slot stays zero.
@ext = addrspace(1) global { i128, i64 } {
; CHECK32: .global .align 16 .u32 ext[8] = {g, 0, 0, 0, 305419896, 0, 0, 0};
; CHECK64: .global .align 16 .u64 ext[4] = {g, 0, 305419896, 0};
    i128 ptrtoint (ptr addrspace(1) @g to i128),
    i64 305419896 }

;; Elements of odd-width integer arrays are alloc-size (8 bytes for i48)
;; apart, not store-size (6 bytes) apart.
@oddarr = addrspace(1) global [2 x i48] [i48 1, i48 -1]
; CHECK: .global .align 8 .b8 oddarr[16] = {1, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 255, 255};

;; Vector elements, by contrast, are bit-packed: store-size (3 bytes for i24)
;; apart, with no padding between elements or after the last one.
@vec24 = addrspace(1) global <2 x i24> <i24 1, i24 2>
; CHECK: .global .align 8 .b8 vec24[6] = {1, 0, 0, 2};
@vec24z = addrspace(1) global <2 x i24> <i24 0, i24 5>
; CHECK: .global .align 8 .b8 vec24z[6] = {0, 0, 0, 5};

;; A ptrtoint to i48 keeps only the low 6 address bytes; the i48's tail
;; padding stays zero.
@oddtrunc = addrspace(1) global { i48, i16 } {
; CHECK32: .global .align 8 .u32 oddtrunc[4] = {g, 0, 7, 0};
; CHECK64: .global .align 8 .u8 oddtrunc[16] = {0xFF(g), 0xFF00(g), 0xFF0000(g), 0xFF000000(g), 0xFF00000000(g), 0xFF0000000000(g), 0, 0, 7, 0, 0, 0, 0, 0, 0, 0};
    i48 ptrtoint (ptr addrspace(1) @g to i48),
    i16 7 }
