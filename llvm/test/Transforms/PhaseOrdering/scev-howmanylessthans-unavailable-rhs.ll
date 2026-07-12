; RUN: opt -passes='default<O2>' -disable-output %s
; REQUIRES: asserts
;
; Reduced from a fuzzer-generated CUDA kernel.  During loop-unroll's exact
; trip count query, howManyLessThans sees an exit compare whose RHS is
; loop-invariant but built from values that do not dominate the loop header,
; and asserted `isAvailableAtLoopEntry(OrigRHS, L) && "Must be!"` before the
; guard was tightened from isLoopInvariant to isAvailableAtLoopEntry.
target datalayout = "e-p6:32:32-i64:64-i128:128-i256:256-v16:16-v32:32-n16:32:64"
target triple = "nvptx64-nvidia-cuda"

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.nvvm.prmt(i32, i32, i32) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.ctpop.i32(i32) #0

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i16 @llvm.bswap.i16(i16) #0

; Function Attrs: convergent mustprogress noinline norecurse nounwind
define ptx_kernel void @_Z2k3PmPKhht(ptr noundef %out, ptr noalias noundef %in, i8 noundef zeroext %v0, i16 noundef zeroext %v1) #1 {
entry:
  %v0.addr = alloca i8, align 1
  %v1.addr = alloca i16, align 2
  %acc = alloca i64, align 8
  %x = alloca i64, align 8
  %facc = alloca float, align 4
  %t8 = alloca i32, align 4
  %it8 = alloca i32, align 4
  %t0 = alloca i32, align 4
  %it0 = alloca i32, align 4
  %t1 = alloca i32, align 4
  %it1 = alloca i32, align 4
  store i8 %v0, ptr %v0.addr, align 1
  store i16 %v1, ptr %v1.addr, align 2
  %0 = load i16, ptr %v1.addr, align 2
  %conv = zext i16 %0 to i32
  %conv2 = sext i32 %conv to i64
  %1 = load i16, ptr %v1.addr, align 2
  %conv4 = zext i16 %1 to i32
  %shr = lshr i32 32, %conv4
  %conv5 = sext i32 %shr to i64
  %mul = mul nsw i64 %conv2, %conv5
  store i64 %mul, ptr %acc, align 8
  %2 = load i64, ptr %acc, align 8
  %conv13 = trunc i64 %2 to i8
  %conv14 = zext i8 %conv13 to i32
  %and = and i32 %conv14, 15
  %add20 = add i32 %and, 2
  store i32 %add20, ptr %t8, align 4
  store i32 0, ptr %it8, align 4
  br label %for.cond

for.cond:                                         ; preds = %for.body, %entry
  %3 = load i32, ptr %it8, align 4
  %4 = load i32, ptr %t8, align 4
  %cmp21 = icmp ult i32 %3, %4
  br i1 %cmp21, label %for.body, label %for.end

for.body:                                         ; preds = %for.cond
  %5 = load i32, ptr %it8, align 4
  %conv26 = zext i32 %5 to i64
  %6 = load i64, ptr %x, align 8
  %xor27 = xor i64 %conv26, %6
  store i64 %xor27, ptr %x, align 8
  %7 = load i64, ptr %x, align 8
  %mul35 = mul i64 %7, -2083806936087476171
  %8 = load i32, ptr %it8, align 4
  %conv36 = zext i32 %8 to i64
  %add37 = add i64 %mul35, %conv36
  store i64 %add37, ptr %x, align 8
  %9 = load i32, ptr %it8, align 4
  %inc = add i32 %9, 1
  store i32 %inc, ptr %it8, align 4
  br label %for.cond

for.end:                                          ; preds = %for.cond
  %10 = load i64, ptr %acc, align 8
  %conv63 = trunc i64 %10 to i32
  %conv64 = zext i32 %conv63 to i64
  %11 = load i64, ptr %x, align 8
  %conv65 = trunc i64 %11 to i32
  %conv66 = zext i32 %conv65 to i64
  %mul67 = mul i64 %conv64, %conv66
  %and69 = and i64 %mul67, 15
  %conv70 = trunc i64 %and69 to i32
  %add71 = add i32 %conv70, 1
  store i32 %add71, ptr %t0, align 4
  br label %for.cond72

for.cond72:                                       ; preds = %if.end, %for.end
  %12 = load i32, ptr %it0, align 4
  %13 = load i32, ptr %t0, align 4
  %cmp73 = icmp ult i32 %12, %13
  br i1 %cmp73, label %for.body74, label %for.end146

for.body74:                                       ; preds = %for.cond72
  %14 = load i8, ptr %v0.addr, align 1
  %conv88 = zext i8 %14 to i32
  %cmp89 = icmp sge i32 0, %conv88
  br i1 %cmp89, label %if.else, label %if.then

if.then:                                          ; preds = %for.body74
  br label %if.end

if.else:                                          ; preds = %for.body74
  %15 = load i32, ptr inttoptr (i64 24 to ptr), align 4
  %and111 = and i32 %15, 16
  %16 = load i32, ptr %it0, align 4
  %conv112 = trunc i32 %16 to i16
  %conv113 = sext i16 %conv112 to i32
  %17 = load i8, ptr inttoptr (i64 60 to ptr), align 1
  %conv115 = zext i8 %17 to i32
  %and116 = and i32 %conv113, %conv115
  %conv117 = sext i32 %and116 to i64
  %18 = load i64, ptr inttoptr (i64 40 to ptr), align 8
  %19 = load i8, ptr inttoptr (i64 63 to ptr), align 1
  %conv120 = sext i8 %19 to i64
  %and121 = and i64 %18, %conv120
  %add122 = add i64 %conv117, %and121
  %conv123 = trunc i64 %add122 to i32
  %and124 = and i32 %conv123, 15
  %add125 = add nsw i32 %and124, 1
  %div = sdiv i32 %and111, %add125
  %conv126 = sext i32 %div to i64
  store i64 %conv126, ptr %acc, align 8
  br label %if.end

if.end:                                           ; preds = %if.else, %if.then
  %20 = load i64, ptr %acc, align 8
  %mul141 = mul i64 %20, 8167746799575284783
  %21 = load i32, ptr %it0, align 4
  %conv142 = zext i32 %21 to i64
  %add143 = add i64 %mul141, %conv142
  store i64 %add143, ptr %acc, align 8
  %22 = load i32, ptr %it0, align 4
  %inc145 = add i32 %22, 1
  store i32 %inc145, ptr %it0, align 4
  br label %for.cond72

for.end146:                                       ; preds = %for.cond72
  %23 = load i64, ptr %acc, align 8
  %24 = load i8, ptr %v0.addr, align 1
  %conv147 = zext i8 %24 to i64
  %mul148 = mul i64 %23, %conv147
  %and153 = and i64 %mul148, 7
  %conv154 = trunc i64 %and153 to i32
  %add155 = add i32 %conv154, 1
  store i32 %add155, ptr %t1, align 4
  store i32 0, ptr %it1, align 4
  br label %for.cond156

for.cond156:                                      ; preds = %for.body158, %for.end146
  %25 = load i32, ptr %it1, align 4
  %26 = load i32, ptr %t1, align 4
  %cmp157 = icmp ult i32 %25, %26
  br i1 %cmp157, label %for.body158, label %for.end193

for.body158:                                      ; preds = %for.cond156
  %27 = load float, ptr %facc, align 4
  %mul190 = fmul float %27, 0.000000e+00
  store float %mul190, ptr %facc, align 4
  %28 = load i32, ptr %it1, align 4
  %inc192 = add i32 %28, 1
  store i32 %inc192, ptr %it1, align 4
  br label %for.cond156

for.end193:                                       ; preds = %for.cond156
  %29 = load i32, ptr %facc, align 4
  %conv785 = zext i32 %29 to i64
  store i64 %conv785, ptr inttoptr (i64 16 to ptr), align 8
  ret void
}

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.bswap.i32(i32) #0

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.ctlz.i32(i32, i1 immarg) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.cttz.i32(i32, i1 immarg) #2

attributes #0 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
attributes #1 = { convergent mustprogress noinline norecurse nounwind "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="sm_90" "target-features"="+sm_90" "uniform-work-group-size" }
attributes #2 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
