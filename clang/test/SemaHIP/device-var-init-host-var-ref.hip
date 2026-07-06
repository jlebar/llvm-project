// RUN: %clang_cc1 -triple amdgcn-amd-amdhsa -fcuda-is-device -fgpu-allow-device-init -fsyntax-only -verify=dev %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -fgpu-allow-device-init -fsyntax-only -verify=host %s

// host-no-diagnostics

// Diagnostics against device code outside of any function (e.g. in the
// initializer of a device-side global) must be emitted, not deferred/dropped.
// -fgpu-allow-device-init disables the dynamic-initialization error that
// would otherwise also fire here.

#define __device__ __attribute__((device))
#define __constant__ __attribute__((constant))

int HostVar;      // dev-note 2 {{host variable declared here}}
__device__ int *DevPtr = &HostVar;        // dev-error {{reference to __host__ variable 'HostVar' in __device__ function}}
__constant__ int *ConstPtr = &HostVar;    // dev-error {{reference to __host__ variable 'HostVar' in __device__ function}}

// A host global's initializer is not device code; the device compilation must
// not reject it.
int *HostPtr = &HostVar;

// Declarations nested inside the initializer are separate entities that the
// initializer's device context does not cover: S is never constructed, so its
// member initializer is not device code and must not be diagnosed.
__device__ int Nested = ([] { struct S { int i = (throw 0, 1); }; return 2; })();
