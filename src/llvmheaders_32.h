
#include "llvm/DerivedTypes.h"
#include "llvm/LLVMContext.h"
#include "llvm/Module.h"
#include "llvm/IRBuilder.h"
#include "llvm/DataLayout.h"
#include "llvm/CallGraphSCCPass.h"
#include "llvm/Instructions.h"
#include "llvm/IntrinsicInst.h"
#include "llvm/InlineAsm.h"
#include "llvm/DIBuilder.h"
#include "llvm/DebugInfo.h"
#include "llvm/Analysis/Verifier.h"
#include "llvm/Linker.h"
#include "llvm/Support/system_error.h"
#include "llvm/Support/CFG.h"
#include "llvm/ExecutionEngine/JIT.h"
#include "llvm/ExecutionEngine/JITMemoryManager.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"


#define LLVM_PATH_TYPE llvm::sys::Path
#define RAW_FD_OSTREAM_NONE 0
#define RAW_FD_OSTREAM_BINARY raw_fd_ostream::F_Binary
#define HASFNATTR(attr) getFnAttributes().hasAttribute(Attributes :: attr)
#define ADDFNATTR(attr) addFnAttr(Attributes :: attr)
#define ATTRIBUTE Attributes
