
#include "llvm/DerivedTypes.h"
#include "llvm/LLVMContext.h"
#include "llvm/Module.h"
#include "llvm/IRBuilder.h"
#include "llvm/DataLayout.h"
#include "llvm/CallGraphSCCPass.h"
#include "llvm/Instructions.h"
#include "llvm/IntrinsicInst.h"

#include "clang/Rewrite/Core/Rewriter.h"
#include "clang/Rewrite/Frontend/Rewriters.h"

#define HASFNATTR(attr) getFnAttributes().hasAttribute(Attributes :: attr)
#define ADDFNATTR(attr) addFnAttr(Attributes :: attr)
#define ATTRIBUTE Attributes
#define TARGETDATA(nm) nm##DataLayout
