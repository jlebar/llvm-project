// Checks that a CUDA compilation defaults to a precise (IEEE round-to-nearest)
// single-precision sqrt in device code, that -ffast-math flips that default,
// and that -f[no-]gpu-prec-sqrt overrides it either way.

// RUN: %clang -### --target=x86_64-linux-gnu -c --cuda-gpu-arch=sm_70 \
// RUN:   -nocudainc -nocudalib %s 2>&1 | FileCheck -check-prefix=PREC %s
// RUN: %clang -### --target=x86_64-linux-gnu -c --cuda-gpu-arch=sm_70 \
// RUN:   -fgpu-prec-sqrt -nocudainc -nocudalib %s 2>&1 | FileCheck -check-prefix=PREC %s
// RUN: %clang -### --target=x86_64-linux-gnu -c --cuda-gpu-arch=sm_70 \
// RUN:   -fno-gpu-prec-sqrt -nocudainc -nocudalib %s 2>&1 | FileCheck -check-prefix=APPROX %s
// RUN: %clang -### --target=x86_64-linux-gnu -c --cuda-gpu-arch=sm_70 \
// RUN:   -ffast-math -nocudainc -nocudalib %s 2>&1 | FileCheck -check-prefix=APPROX %s
// RUN: %clang -### --target=x86_64-linux-gnu -c --cuda-gpu-arch=sm_70 \
// RUN:   -ffast-math -fgpu-prec-sqrt -nocudainc -nocudalib %s 2>&1 | FileCheck -check-prefix=PREC %s

// APPROX: "-fno-gpu-prec-sqrt"
// PREC-NOT: "-fno-gpu-prec-sqrt"
