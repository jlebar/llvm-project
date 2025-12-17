set(LLVM_LINK_COMPONENTS
  Analysis
  Core
  ExecutionEngine
  FuzzerCLI
  InstCombine
  Interpreter
  Passes
  Support
  Target
  TargetParser
  TransformUtils
  )

add_llvm_fuzzer(llvm-fuzzer
  llvm-fuzzer.cpp
  )
