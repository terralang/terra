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
  VERBATIM
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
    VERBATIM
  )
endforeach()

# This header isn't generated but needs to be relocated to fit the
# build directory structure.
add_custom_command(
  OUTPUT ${PROJECT_BINARY_DIR}/include/terra/terra.h
  DEPENDS
    ${PROJECT_SOURCE_DIR}/release/include/terra/terra.h
  COMMAND "${CMAKE_COMMAND}" -E copy "${PROJECT_SOURCE_DIR}/release/include/terra/terra.h" "${PROJECT_BINARY_DIR}/include/terra/"
  VERBATIM
)

add_custom_target(
  TerraGeneratedFiles
  DEPENDS
    ${PROJECT_BINARY_DIR}/clangpaths.h
    ${PROJECT_BINARY_DIR}/internalizedfiles.h
    ${PROJECT_BINARY_DIR}/include/terra/terra.h
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

  ${PROJECT_BINARY_DIR}/include/terra/terra.h
)

list(APPEND TERRA_BIN_SRC
  main.cpp
  linenoise.cpp linenoise.h
)

add_library(TerraObjectFiles OBJECT ${TERRA_LIB_SRC})

target_include_directories(TerraObjectFiles
  PRIVATE
    ${PROJECT_BINARY_DIR}
    ${PROJECT_BINARY_DIR}/include/terra
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

if(NOT ${LLVM_ENABLE_ASSERTIONS})
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

add_dependencies(TerraLibrary BuildDirs)
add_dependencies(TerraLibrary LuaJIT)
add_dependencies(TerraLibrary LLVMObjectFiles)

add_dependencies(TerraLibraryShared BuildDirs)
add_dependencies(TerraLibraryShared LuaJIT)
add_dependencies(TerraLibraryShared LLVMObjectFiles)

set_target_properties(TerraLibrary PROPERTIES PREFIX "")
set_target_properties(TerraLibraryShared PROPERTIES PREFIX "")

set_target_properties(TerraLibrary PROPERTIES OUTPUT_NAME terra)
set_target_properties(TerraLibraryShared PROPERTIES OUTPUT_NAME terra)

set_target_properties(TerraLibrary PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")
set_target_properties(TerraLibraryShared PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")

target_link_libraries(TerraLibrary PRIVATE ${LLVM_SYSTEM_LIBRARIES})

target_link_libraries(TerraLibraryShared PRIVATE ${LLVM_SYSTEM_LIBRARIES})

if(APPLE)
  target_link_libraries(TerraLibraryShared PRIVATE -single_module)
endif()

###
### Terra Executable
###

list(APPEND TERRA_EXE_SRC
  main.cpp
  linenoise.cpp linenoise.h
)

add_executable(TerraExecutable ${TERRA_EXE_SRC})

set_target_properties(TerraExecutable PROPERTIES OUTPUT_NAME terra)
set_target_properties(TerraExecutable PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/bin")

target_include_directories(TerraExecutable
  PRIVATE
    ${PROJECT_BINARY_DIR}
    ${PROJECT_BINARY_DIR}/include/terra
)

if(APPLE)
  set_target_properties(TerraExecutable
    PROPERTIES
      # Makes LuaJIT happy (otherwise luaL_newstate returns NULL). Has to be
      # set as a property otherwise target_link_libraries thinks the arguments
      # are libraries.
      LINK_FLAGS "-pagezero_size 10000 -image_base 100000000"
  )
  target_link_libraries(TerraExecutable
    PRIVATE
      -Wl,-force_load,$<TARGET_LINKER_FILE:TerraLibrary>
      TerraLibrary # for transitive dependencies
  )
elseif(UNIX)
  target_link_libraries(TerraExecutable
    PRIVATE
      -Wl,-export-dynamic
      -Wl,--whole-archive
      TerraLibrary
      -Wl,--no-whole-archive
  )
else()
  target_link_libraries(TerraExecutable PRIVATE TerraLibrary)
endif()

install(
  TARGETS TerraLibrary TerraLibraryShared TerraExecutable
  EXPORT TerraExports
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(
  FILES ${PROJECT_BINARY_DIR}/include/terra/terra.h
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/terra
)

file(GLOB TERRA_TESTS
  RELATIVE ${PROJECT_SOURCE_DIR}/tests
  ${PROJECT_SOURCE_DIR}/tests/*.t
  ${PROJECT_SOURCE_DIR}/tests/fails/*.t
)

foreach(TERRA_TEST ${TERRA_TESTS})
  add_test(NAME ${TERRA_TEST}
    COMMAND $<TARGET_FILE:TerraExecutable> ${TERRA_TEST}
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}/tests
  )
endforeach()
