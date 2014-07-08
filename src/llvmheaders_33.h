
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/Analysis/CallGraphSCCPass.h"
#include "llvm/DIBuilder.h"
#include "llvm/DebugInfo.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"


#define LLVM_PATH_TYPE sys::Path
#define RAW_FD_OSTREAM(x) raw_fd_ostream::x
#define HASFNATTR(attr) getAttributes().hasAttribute(AttributeSet::FunctionIndex, Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attributes
#define TARGETDATA(nm) nm##DataLayout
#define LLVM_VERSION "3.3"