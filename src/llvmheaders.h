#ifndef _llvmheaders_h
#define _llvmheaders_h

#ifndef NDEBUG
#define NDEBUG
#include "llvm/Support/Valgrind.h"
#undef NDEBUG
#else
#include "llvm/Support/Valgrind.h"
#endif

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
#include "llvm/Analysis/Verifier.h"
#include "llvm/DerivedTypes.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/LLVMContext.h"
#include "llvm/Linker.h"
#include "llvm/Module.h"
#include "llvm/PassManager.h"
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

#if LLVM_3_2

#include "llvm/IRBuilder.h"
#include "llvm/DataLayout.h"
#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"

#define HASFNATTR(attr) getFnAttributes().hasAttribute(Attributes :: attr)
#define ADDFNATTR(attr) addFnAttr(Attributes :: attr)
#define ATTRIBUTE Attributes
#define TARGETDATA(nm) nm##DataLayout

#else


#include "llvm/Support/IRBuilder.h"
#include "llvm/Target/TargetData.h"
#include "clang/Rewrite/Rewriter.h"
#include "clang/Rewrite/Rewriters.h"

#define HASFNATTR(attr) hasFnAttr(Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attribute
#define TARGETDATA(nm) nm##TargetData

#endif

#endif