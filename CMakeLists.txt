cmake_minimum_required(VERSION 3.5)
project(Terra)

list(INSERT CMAKE_MODULE_PATH 0 "${Terra_SOURCE_DIR}/cmake/Modules")

find_package(LLVM HINTS ${LLVM_HINTS} REQUIRED)
find_package(Clang REQUIRED)

if(TERRA_ENABLE_CUDA)
  find_package(CUDA REQUIRED)
elseif(NOT DEFINED TERRA_ENABLE_CUDA)
  find_package(CUDA)
endif()
set(TERRA_ENABLE_CUDA ${CUDA_FOUND} CACHE BOOL "Build Terra with support for CUDA")

set(TERRA_STATIC_LINK_LLVM ON CACHE BOOL "Statically link Terra against LLVM")

include(GNUInstallDirs)
include(BuildDirs)
include(GetLuaJIT)
include(ExtractLLVM)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

enable_testing()

add_subdirectory(src)
