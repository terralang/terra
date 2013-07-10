//===- InlinerPass.h - Code common to all inliners --------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// Modified version of llvm inliner that allows manual control
// User must manually determine the strongly connected components on which inlining is performed
// For best performance, you should still call the inliner in bottom up order
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_TRANSFORMS_IPO_INLINERPASS_H
#define LLVM_TRANSFORMS_IPO_INLINERPASS_H

#include "llvmheaders.h"

namespace llvm {
  class CallSite;
  class TARGETDATA();
  class InlineCost;
  template<class PtrType, unsigned SmallSize>
  class SmallPtrSet;

/// Inliner - This class contains all of the helper code which is used to
/// perform the inlining operations that do not depend on the policy.
///
struct ManualInliner {
  explicit ManualInliner(const TARGETDATA() * td);
  explicit ManualInliner(const TARGETDATA() * td, int Threshold, bool InsertLifetime);

  // Main run interface method, this implements the interface required by the
  // Pass class.
  virtual bool runOnSCC(ArrayRef<Function*> SCC);

  // doFinalization - Remove now-dead linkonce functions at the end of
  // processing to avoid breaking the SCC traversal.
  virtual bool doFinalization(ArrayRef<Function*> Funcs);

  /// This method returns the value specified by the -inline-threshold value,
  /// specified on the command line.  This is typically not directly needed.
  ///
  unsigned getInlineThreshold() const { return InlineThreshold; }

  /// Calculate the inline threshold for given Caller. This threshold is lower
  /// if the caller is marked with OptimizeForSize and -inline-threshold is not
  /// given on the comand line. It is higher if the callee is marked with the
  /// inlinehint attribute.
  ///
  unsigned getInlineThreshold(CallSite CS) const;

  /// getInlineCost - This method must be implemented by the subclass to
  /// determine the cost of inlining the specified call site.  If the cost
  /// returned is greater than the current inline threshold, the call site is
  /// not inlined.
  ///
  virtual InlineCost getInlineCost(CallSite CS) = 0;

  /// removeDeadFunctions - Remove dead functions.
  ///
  /// This also includes a hack in the form of the 'AlwaysInlineOnly' flag
  /// which restricts it to deleting functions with an 'AlwaysInline'
  /// attribute. This is useful for the InlineAlways pass that only wants to
  /// deal with that subset of the functions.
  bool removeDeadFunctions(ArrayRef<Function*> & Funcs, bool AlwaysInlineOnly = false);

  virtual bool doInitialization() = 0;
  virtual ~ManualInliner() {}
private:
  // InlineThreshold - Cache the value here for easy access.
  unsigned InlineThreshold;

  // InsertLifetime - Insert @llvm.lifetime intrinsics.
  bool InsertLifetime;
  const TARGETDATA() * TD;

  /// shouldInline - Return true if the inliner should attempt to
  /// inline at the given CallSite.
  bool shouldInline(CallSite CS);
};

} // End llvm namespace

llvm::ManualInliner * createManualFunctionInliningPass(llvm::TargetMachine * td);

llvm::ManualInliner * createManualFunctionInliningPass(llvm::TargetMachine * td, int Threshold);

#endif
