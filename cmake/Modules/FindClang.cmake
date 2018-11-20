# Adapted from: https://github.com/karelklic/canal/blob/master/FindClang.cmake
# Find Clang
#
# It defines the following variables
# CLANG_FOUND        - true if Clang is found
# CLANG_INCLUDE_DIRS - list of Clang include directories
# CLANG_RESOURCE_DIR - directory where Clang stores system libraries
# CLANG_LIBRARIES    - list of Clang libraries
# CLANG_EXECUTABLE   - Clang executable

if(NOT LLVM_INCLUDE_DIRS OR NOT LLVM_LIBRARY_DIRS)
  message(FATAL_ERROR "No LLVM and Clang support requires LLVM")
else()

macro(FIND_AND_ADD_CLANG_LIB _libname_)
  find_library(CLANG_${_libname_}_LIB ${_libname_} ${LLVM_LIBRARY_DIRS} ${CLANG_LIBRARY_DIRS})
  if(CLANG_${_libname_}_LIB)
    list(APPEND CLANG_LIBRARIES ${CLANG_${_libname_}_LIB})
  endif()
endmacro()

# Clang shared library provides just the limited C interface, so it
# can not be used.  We look for the static libraries.
FIND_AND_ADD_CLANG_LIB(clangFrontend)
FIND_AND_ADD_CLANG_LIB(clangDriver)
FIND_AND_ADD_CLANG_LIB(clangSerialization)
FIND_AND_ADD_CLANG_LIB(clangCodeGen)
FIND_AND_ADD_CLANG_LIB(clangParse)
FIND_AND_ADD_CLANG_LIB(clangSema)
FIND_AND_ADD_CLANG_LIB(clangAnalysis)
FIND_AND_ADD_CLANG_LIB(clangEdit)
FIND_AND_ADD_CLANG_LIB(clangAST)
FIND_AND_ADD_CLANG_LIB(clangLex)
FIND_AND_ADD_CLANG_LIB(clangBasic)

find_path(CLANG_INCLUDE_DIRS clang/Basic/Version.h HINTS ${LLVM_INCLUDE_DIRS})

find_program(CLANG_EXECUTABLE
  clang clang-3.4 clang-3.5 clang-3.6 clang-3.7 clang-3.8 clang-3.9 clang-4.0 clang-5.0 clang-6.0 clang-7.0
  HINTS ${LLVM_TOOLS_BINARY_DIRS}
)

set(CLANG_RESOURCE_DIR ${LLVM_INSTALL_PREFIX}/lib/clang/${LLVM_PACKAGE_VERSION})

if(CLANG_LIBRARIES AND CLANG_INCLUDE_DIRS AND CLANG_EXECUTABLE)
  message(STATUS "Clang libraries: ${CLANG_LIBRARIES}")
  set(CLANG_FOUND TRUE)
endif()

if(CLANG_FOUND)
  message(STATUS "Found Clang: ${CLANG_INCLUDE_DIRS}")
else()
  if(CLANG_FIND_REQUIRED)
    message(FATAL_ERROR "Could NOT find Clang")
  endif()
endif()

endif()
