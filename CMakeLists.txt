cmake_minimum_required(VERSION 3.5)
project(Terra)

list(INSERT CMAKE_MODULE_PATH 0 "${Terra_SOURCE_DIR}/cmake/Modules")

find_package(LLVM HINTS ${LLVM_HINTS} REQUIRED)
find_package(Clang REQUIRED)
find_package(Git) # for version number

if(TERRA_ENABLE_CUDA)
  find_package(CUDA REQUIRED)
elseif(NOT DEFINED TERRA_ENABLE_CUDA)
  find_package(CUDA)
endif()
set(TERRA_ENABLE_CUDA ${CUDA_FOUND} CACHE BOOL "Build Terra with support for CUDA")

if(DEFINED TERRA_STATIC_LINK_LLVM)
  set(DEFAULT_TERRA_SLIB_INCLUDE_LLVM ${TERRA_STATIC_LINK_LLVM})
else()
  set(DEFAULT_TERRA_SLIB_INCLUDE_LLVM ON)
endif()
set(TERRA_SLIB_INCLUDE_LLVM ${DEFAULT_TERRA_SLIB_INCLUDE_LLVM} CACHE BOOL "Include LLVM in Terra static libraries")
set(TERRA_STATIC_LINK_LLVM ON CACHE BOOL "Statically link Terra against LLVM")

if(TERRA_SLIB_INCLUDE_LLVM AND NOT TERRA_STATIC_LINK_LLVM)
  message(FATAL_ERROR "TERRA_SLIB_INCLUDE_LLVM requires TERRA_STATIC_LINK_LLVM to be set")
endif()

if(DEFINED TERRA_STATIC_LINK_LUAJIT)
  set(DEFAULT_TERRA_SLIB_INCLUDE_LUAJIT ${TERRA_STATIC_LINK_LUAJIT})
else()
  set(DEFAULT_TERRA_SLIB_INCLUDE_LUAJIT ON)
endif()
set(TERRA_SLIB_INCLUDE_LUAJIT ${DEFAULT_TERRA_SLIB_INCLUDE_LUAJIT} CACHE BOOL "Include LuaJIT in Terra static libraries")
set(TERRA_STATIC_LINK_LUAJIT ON CACHE BOOL "Statically link Terra against LuaJIT")

if(TERRA_SLIB_INCLUDE_LUAJIT AND NOT TERRA_STATIC_LINK_LUAJIT)
  message(FATAL_ERROR "TERRA_SLIB_INCLUDE_LUAJIT requires TERRA_STATIC_LINK_LUAJIT to be set")
endif()

include(GNUInstallDirs)
include(VersionNumber)
include(BuildDirs)
include(GetLuaJIT)
include(ExtractLLVM)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

enable_testing()

add_subdirectory(src)
