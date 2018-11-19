#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/InstVisitor.h"
#include "llvm/Analysis/CallGraphSCCPass.h"
#include "llvm/DIBuilder.h"
#include "llvm/DebugInfo.h"
#include "llvm/ExecutionEngine/ObjectImage.h"
#include "llvm/Analysis/Verifier.h"
#include "llvm/Linker.h"
#include "llvm/Support/system_error.h"
#include "llvm/Support/CFG.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/ExecutionEngine/JITMemoryManager.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"

#define LLVM_PATH_TYPE std::string
#define RAW_FD_OSTREAM_NONE sys::fs::F_None
#define RAW_FD_OSTREAM_BINARY sys::fs::F_Binary
#define HASFNATTR(attr) getAttributes().hasAttribute(AttributeSet::FunctionIndex, Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attributes