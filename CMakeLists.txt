cmake_minimum_required(VERSION 3.5)
project(Terra)

list(INSERT CMAKE_MODULE_PATH 0 "${Terra_SOURCE_DIR}/cmake/Modules")

find_package(LLVM HINTS ${LLVM_HINTS} REQUIRED)
find_package(Clang REQUIRED)
find_package(CUDA)

# The official binary for 3.8 on macOS is buggy and lists LTO (a dynamic
# library) even though LLVMLTO (a static library) is already on the list.
list(REMOVE_ITEM LLVM_AVAILABLE_LIBS LTO)

include(GetLuaJIT)
include(ExtractLLVM)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src)
