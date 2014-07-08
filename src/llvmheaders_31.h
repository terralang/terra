
#include "llvm/DerivedTypes.h"
#include "llvm/LLVMContext.h"
#include "llvm/Module.h"
#include "llvm/Support/IRBuilder.h"
#include "llvm/Target/TargetData.h"
#include "llvm/Instructions.h"
#include "llvm/CallGraphSCCPass.h"
#include "llvm/IntrinsicInst.h"
#include "llvm/Analysis/DIBuilder.h"
#include "llvm/Analysis/DebugInfo.h"


#include "clang/Rewrite/Rewriter.h"
#include "clang/Rewrite/Rewriters.h"

#define LLVM_PATH_TYPE sys::Path
#define RAW_FD_OSTREAM(x) raw_fd_ostream::x
#define HASFNATTR(attr) hasFnAttr(Attribute :: attr)
#define ADDFNATTR(attr) addFnAttr(Attribute :: attr)
#define ATTRIBUTE Attribute
#define TARGETDATA(nm) nm##TargetData
#define LLVM_VERSION "3.1"