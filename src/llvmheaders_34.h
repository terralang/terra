
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/Analysis/CallGraphSCCPass.h"
#include "llvm/DIBuilder.h"
#include "llvm/DebugInfo.h"
#include "llvm/ExecutionEngine/ObjectImage.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"


#define LLVM_PATH_TYPE std::string
#define RAW_FD_OSTREAM(x) sys::fs::x
#define HASFNATTR(attr) getAttributes().hasAttribute(AttributeSet::FunctionIndex, Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attributes
#define TARGETDATA(nm) nm##DataLayout
#define LLVM_VERSION "3.4"
#define TERRA_CAN_USE_MCJIT