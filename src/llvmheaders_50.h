#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/InlineAsm.h"
#include "llvm/Analysis/CallGraphSCCPass.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Mangler.h"
//#include "llvm/ExecutionEngine/ObjectImage.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Linker/Linker.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/InstVisitor.h"
#include "llvm/Target/TargetSubtargetInfo.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"
#include "llvm/IR/DiagnosticPrinter.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/Object/SymbolSize.h"

#define LLVM_PATH_TYPE std::string
#define RAW_FD_OSTREAM_NONE sys::fs::F_None
#define RAW_FD_OSTREAM_BINARY sys::fs::F_None
#define HASFNATTR(attr) getAttributes().hasAttribute(AttributeSet::FunctionIndex, Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attributes
