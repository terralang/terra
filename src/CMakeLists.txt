###
### Terra Generated Source Files
###

list(APPEND PACKAGE_DEPS
  ${LUAJIT_LIBRARIES}
)

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/clangpaths.h"
  DEPENDS
    dummy.c
    ${PACKAGE_DEPS}
    "${CMAKE_CURRENT_SOURCE_DIR}/genclangpaths.lua"
    LuaJIT
  COMMAND ${LUAJIT_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/genclangpaths.lua" ${PROJECT_BINARY_DIR}/clangpaths.h ${CLANG_EXECUTABLE} ${CUDA_INCLUDE_DIRS}
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
)

add_custom_command(
  OUTPUT "${PROJECT_BINARY_DIR}/internalizedfiles.h"
  DEPENDS
    ${PACKAGE_DEPS}
    "${CMAKE_CURRENT_SOURCE_DIR}/geninternalizedfiles.lua"
    "${PROJECT_SOURCE_DIR}/lib/std.t"
    "${PROJECT_SOURCE_DIR}/lib/parsing.t"
    LuaJIT
  COMMAND ${LUAJIT_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/geninternalizedfiles.lua" ${PROJECT_BINARY_DIR}/internalizedfiles.h ${CLANG_RESOURCE_DIR} "%.h$" ${CLANG_RESOURCE_DIR} "%.modulemap$" lib "%.t$"
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  VERBATIM
)

list(APPEND TERRA_LIB_LUA_SRC
  terralib.lua
  strict.lua
  cudalib.lua
  asdl.lua
)

foreach(LUA_SRC ${TERRA_LIB_LUA_SRC})
  get_filename_component(LUA_BASE ${LUA_SRC} NAME_WE)
  set(LUA_GEN "${LUA_BASE}.h")
  list(APPEND TERRA_LIB_LUA_GEN "${PROJECT_BINARY_DIR}/${LUA_GEN}")
  add_custom_command(
    OUTPUT "${PROJECT_BINARY_DIR}/${LUA_GEN}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${LUA_SRC}" LuaJIT
    COMMAND ${LUAJIT_EXECUTABLE} -bg "${CMAKE_CURRENT_SOURCE_DIR}/${LUA_SRC}" -t h - | sed "s/char/unsigned char/" > "${PROJECT_BINARY_DIR}/${LUA_GEN}"
  )
endforeach()

add_custom_target(
  TerraGeneratedFiles
  DEPENDS
    "${PROJECT_BINARY_DIR}/clangpaths.h"
    "${PROJECT_BINARY_DIR}/internalizedfiles.h"
    ${TERRA_LIB_LUA_GEN}
)

###
### Terra Library
###

list(APPEND TERRA_LIB_SRC
  tkind.cpp        tkind.h
  tcompiler.cpp    tcompiler.h
  tcompilerstate.h
  tllvmutil.cpp    tllvmutil.h
  tcwrapper.cpp    tcwrapper.h
  tinline.cpp      tinline.h
  terra.cpp
  lparser.cpp      lparser.h
  lstring.cpp      lstring.h
  lobject.cpp      lobject.h
  lzio.cpp         lzio.h
  llex.cpp         llex.h
  lctype.cpp       lctype.h
  treadnumber.c    treadnumber.h
  tcuda.cpp        tcuda.h
  tdebug.cpp       tdebug.h
  tinternalizedfiles.cpp
  lj_strscan.c     lj_strscan.h

  ${PROJECT_SOURCE_DIR}/release/include/terra/terra.h
)

list(APPEND TERRA_BIN_SRC
  main.cpp
  linenoise.cpp linenoise.h
)

add_library(TerraObjectFiles OBJECT ${TERRA_LIB_SRC})

target_include_directories(TerraObjectFiles
  PRIVATE
    "${PROJECT_SOURCE_DIR}/release/include/terra"
    ${PROJECT_BINARY_DIR}
    ${LLVM_INCLUDE_DIRS}
    ${CLANG_INCLUDE_DIRS}
)

target_compile_definitions(TerraObjectFiles
  PRIVATE
    LLVM_VERSION=${LLVM_VERSION_MAJOR}${LLVM_VERSION_MINOR}
    # FIXME: Find portable ways to do all these
    _GNU_SOURCE
    __STDC_CONSTANT_MACROS
    __STDC_FORMAT_MACROS
    __STDC_LIMIT_MACROS
)

target_compile_options(TerraObjectFiles
  PRIVATE
    # FIXME: Find portable ways to do all these
    -fno-common
    -Wcast-qual
    $<$<COMPILE_LANGUAGE:CXX>:-Woverloaded-virtual>
    $<$<COMPILE_LANGUAGE:CXX>:-fvisibility-inlines-hidden>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
)

if(${LLVM_ENABLE_ASSERTIONS} EQUAL 0)
  target_compile_definitions(TerraObjectFiles
    PRIVATE
      TERRA_LLVM_HEADERS_HAVE_NDEBUG
  )
endif()

set_target_properties(TerraObjectFiles PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_dependencies(TerraObjectFiles TerraGeneratedFiles)

add_library(TerraLibrary
  STATIC
    $<TARGET_OBJECTS:TerraObjectFiles>
    ${ALL_LLVM_OBJECTS}
    ${LUAJIT_OBJECTS}
)
add_library(TerraLibraryShared
  SHARED
    $<TARGET_OBJECTS:TerraObjectFiles>
    ${ALL_LLVM_OBJECTS}
    ${LUAJIT_OBJECTS}
)

set_source_files_properties(
  ${ALL_LLVM_OBJECTS}
  ${LUAJIT_OBJECTS}
  PROPERTIES
    EXTERNAL_OBJECT true
    GENERATED true)

add_dependencies(TerraLibrary LuaJIT)
add_dependencies(TerraLibrary LLVMObjectFiles)

add_dependencies(TerraLibraryShared LuaJIT)
add_dependencies(TerraLibraryShared LLVMObjectFiles)

set_target_properties(TerraLibrary PROPERTIES PREFIX "")
set_target_properties(TerraLibraryShared PROPERTIES PREFIX "")

set_target_properties(TerraLibrary PROPERTIES OUTPUT_NAME terra)
set_target_properties(TerraLibraryShared PROPERTIES OUTPUT_NAME terra)

target_link_libraries(TerraLibrary PRIVATE ${LLVM_SYSTEM_LIBRARIES})

target_link_libraries(TerraLibraryShared PRIVATE ${LLVM_SYSTEM_LIBRARIES})

if(APPLE)
  target_link_libraries(TerraLibraryShared PRIVATE -single_module)
endif()

install(TARGETS TerraLibrary TerraLibraryShared
  DESTINATION ${PROJECT_SOURCE_DIR}/release/lib
)

###
### Terra Executable
###

list(APPEND TERRA_EXE_SRC
  main.cpp
  linenoise.cpp linenoise.h
)

add_executable(TerraExecutable
  ${TERRA_EXE_SRC}
  # No portable way to use --whole-archive, so just list all the objects again
  # https://gitlab.kitware.com/cmake/cmake/issues/16947
  $<TARGET_OBJECTS:TerraObjectFiles>
  ${ALL_LLVM_OBJECTS}
  ${LUAJIT_OBJECTS}
)

add_dependencies(TerraExecutable LuaJIT)
add_dependencies(TerraExecutable LLVMObjectFiles)

set_target_properties(TerraExecutable PROPERTIES OUTPUT_NAME terra)

target_link_libraries(TerraExecutable PRIVATE ${LLVM_SYSTEM_LIBRARIES})

if(APPLE)
  target_link_libraries(TerraExecutable PRIVATE -pagezero_size 10000 -image_base 100000000)
endif()

target_include_directories(TerraExecutable
  PRIVATE
    "${PROJECT_SOURCE_DIR}/release/include/terra"
)

install(TARGETS TerraExecutable
  DESTINATION ${PROJECT_SOURCE_DIR}/release/bin
)

install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink ${PROJECT_SOURCE_DIR}/release/bin/terra ${PROJECT_SOURCE_DIR}/terra )")
