#ifndef _llvmheaders_h
#define _llvmheaders_h

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/Diagnostic.h"
#include "clang/Basic/FileManager.h"
#include "clang/Basic/SourceManager.h"
#include "clang/Basic/TargetInfo.h"
#include "clang/Basic/TargetOptions.h"
#include "clang/CodeGen/CodeGenAction.h"
#include "clang/CodeGen/ModuleBuilder.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Lex/Preprocessor.h"
#include "clang/Parse/ParseAST.h"
#include "clang/AST/ASTContext.h"
#include "llvm/Analysis/Passes.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"

#include "llvm/IR/LegacyPassManager.h"

#include "llvm/Support/Host.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Scalar.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Support/FormattedStream.h"
#include "llvm/Support/Program.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/IPO.h"
#include "llvm/Transforms/Vectorize.h"
#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#include "llvm/ExecutionEngine/JITEventListener.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/Support/DynamicLibrary.h"

#if LLVM_VERSION >= 40
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#else
#include "llvm/Bitcode/ReaderWriter.h"
#endif

#include "llvm/Object/ObjectFile.h"
#include "llvm-c/Linker.h"

#if LLVM_VERSION == 38
#include "llvmheaders_38.h"
#elif LLVM_VERSION == 39
#include "llvmheaders_39.h"
#elif LLVM_VERSION == 50
#include "llvmheaders_50.h"
#elif LLVM_VERSION == 60
#include "llvmheaders_60.h"
#elif LLVM_VERSION >= 70 && LLVM_VERSION < 80
#include "llvmheaders_70.h"
#elif LLVM_VERSION == 80
#include "llvmheaders_80.h"
#elif LLVM_VERSION == 90
#include "llvmheaders_90.h"
#elif LLVM_VERSION == 100
#include "llvmheaders_100.h"
#elif LLVM_VERSION >= 110 && LLVM_VERSION < 120
#include "llvmheaders_110.h"
#else
#error "unsupported LLVM version"
// for OSX code completion
#define LLVM_VERSION 100
#include "llvmheaders_100.h"
#endif

#define UNIQUEIFY(T, x) (std::unique_ptr<T>(x))
#define FD_ERRTYPE std::error_code
#define FD_ISERR(x) (x)
#define FD_ERRSTR(x) ((x).message().c_str())
#define METADATA_ROOT_TYPE llvm::Metadata

using llvm::legacy::FunctionPassManager;
using llvm::legacy::PassManager;
typedef llvm::raw_pwrite_stream emitobjfile_t;
typedef llvm::DIFile* DIFileP;

inline void LLVMDisposeMessage(char* Message) { free(Message); }
typedef llvm::legacy::PassManager PassManagerT;
typedef llvm::legacy::FunctionPassManager FunctionPassManagerT;

#endif
