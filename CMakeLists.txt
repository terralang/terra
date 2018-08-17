cmake_minimum_required(VERSION 3.5)
project(Terra)

list(INSERT CMAKE_MODULE_PATH 0 "${Terra_SOURCE_DIR}/cmake/Modules")

# Try to locate LLVM based on location of LLVM_CONFIG and/or CLANG
if(DEFINED ENV{LLVM_CONFIG})
  get_filename_component(LLVM_CONFIG_DIR "$ENV{LLVM_CONFIG}" DIRECTORY)
  get_filename_component(LLVM_CONFIG_DIR "${LLVM_CONFIG_DIR}" DIRECTORY)
  list(APPEND LLVM_HINTS "${LLVM_CONFIG_DIR}")
endif()
if(DEFINED ENV{CLANG})
  get_filename_component(CLANG_DIR "$ENV{CLANG}" DIRECTORY)
  get_filename_component(CLANG_DIR "${CLANG_DIR}" DIRECTORY)
  list(APPEND LLVM_HINTS "${CLANG_DIR}")
endif()

find_package(LLVM REQUIRED HINTS ${LLVM_HINTS})
find_package(Clang REQUIRED)
find_package(CUDA)

include(GetLuaJIT)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(src)
