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

#if LLVM_VERSION < 170
#include "llvm/Support/Host.h"
#else
#include "llvm/TargetParser/Host.h"
#endif
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Scalar.h"
#if LLVM_VERSION >= 140
#include "llvm/MC/TargetRegistry.h"
#else
#include "llvm/Support/TargetRegistry.h"
#endif
#include "llvm/Support/FormattedStream.h"
#include "llvm/Support/Program.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/IPO.h"
#if LLVM_VERSION < 180
#include "llvm/Transforms/Vectorize.h"
#endif
#if LLVM_VERSION < 170
#include "llvm/Transforms/IPO/PassManagerBuilder.h"
#else
#include "llvm/Passes/PassBuilder.h"
#endif
#include "llvm/ExecutionEngine/JITEventListener.h"
#include "llvm/ExecutionEngine/SectionMemoryManager.h"
#include "llvm/Support/DynamicLibrary.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"

#include "llvm/Object/ObjectFile.h"
#include "llvm-c/Linker.h"

#if LLVM_VERSION < 120
#include "llvmheaders_110.h"
#elif LLVM_VERSION < 130
#include "llvmheaders_120.h"
#elif LLVM_VERSION < 140
#include "llvmheaders_130.h"
#elif LLVM_VERSION < 150
#include "llvmheaders_140.h"
#elif LLVM_VERSION < 160
#include "llvmheaders_150.h"
#elif LLVM_VERSION < 170
#include "llvmheaders_160.h"
#elif LLVM_VERSION < 180
#include "llvmheaders_170.h"
#elif LLVM_VERSION < 190
#include "llvmheaders_180.h"
#else
#error "unsupported LLVM version"
// for OSX code completion
#define LLVM_VERSION 180
#include "llvmheaders_180.h"
#endif

#define UNIQUEIFY(T, x) (std::unique_ptr<T>(x))
#define FD_ERRTYPE std::error_code
#define FD_ISERR(x) (x)
#define FD_ERRSTR(x) ((x).message().c_str())
#define METADATA_ROOT_TYPE llvm::Metadata

#if LLVM_VERSION < 170
using llvm::legacy::FunctionPassManager;
using llvm::legacy::PassManager;
typedef llvm::legacy::PassManager PassManagerT;
typedef llvm::legacy::FunctionPassManager FunctionPassManagerT;
#else
using llvm::FunctionPassManager;
#endif

typedef llvm::raw_pwrite_stream emitobjfile_t;
typedef llvm::DIFile* DIFileP;

inline void LLVMDisposeMessage(char* Message) { free(Message); }

#endif
