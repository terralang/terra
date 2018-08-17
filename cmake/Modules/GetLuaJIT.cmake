include(FindPackageHandleStandardArgs)

set(LUAJIT_VERSION_BASE 2.0)
set(LUAJIT_VERSION_EXTRA .5)
set(LUAJIT_BASENAME "LuaJIT-${LUAJIT_VERSION_BASE}${LUAJIT_VERSION_EXTRA}")
set(LUAJIT_URL "https://luajit.org/download/${LUAJIT_BASENAME}.tar.gz")
set(LUAJIT_TAR "${PROJECT_BINARY_DIR}/${LUAJIT_BASENAME}.tar.gz")
set(LUAJIT_DIR "${PROJECT_BINARY_DIR}/${LUAJIT_BASENAME}")
set(LUAJIT_INCLUDE_DIR "${PROJECT_BINARY_DIR}/include/luajit-${LUAJIT_VERSION_BASE}")
set(LUAJIT_HEADER_BASENAMES lua.h lualib.h lauxlib.h luaconf.h)
set(LUAJIT_OBJECT_BASENAMES
  lib_aux.o
  lib_base.o
  lib_bit.o
  lib_debug.o
  lib_ffi.o
  lib_init.o
  lib_io.o
  lib_jit.o
  lib_math.o
  lib_os.o
  lib_package.o
  lib_string.o
  lib_table.o
  lj_alloc.o
  lj_api.o
  lj_asm.o
  lj_bc.o
  lj_bcread.o
  lj_bcwrite.o
  lj_carith.o
  lj_ccallback.o
  lj_ccall.o
  lj_cconv.o
  lj_cdata.o
  lj_char.o
  lj_clib.o
  lj_cparse.o
  lj_crecord.o
  lj_ctype.o
  lj_debug.o
  lj_dispatch.o
  lj_err.o
  lj_ffrecord.o
  lj_func.o
  lj_gc.o
  lj_gdbjit.o
  lj_ir.o
  lj_lex.o
  lj_lib.o
  lj_load.o
  lj_mcode.o
  lj_meta.o
  lj_obj.o
  lj_opt_dce.o
  lj_opt_fold.o
  lj_opt_loop.o
  lj_opt_mem.o
  lj_opt_narrow.o
  lj_opt_sink.o
  lj_opt_split.o
  lj_parse.o
  lj_record.o
  lj_snap.o
  lj_state.o
  lj_str.o
  lj_strscan.o
  lj_tab.o
  lj_trace.o
  lj_udata.o
  lj_vmevent.o
  lj_vmmath.o
  lj_vm.o
)
set(LUAJIT_OBJECT_DIR "${PROJECT_BINARY_DIR}/lua_objects")
set(LUAJIT_LIBRARY "${PROJECT_BINARY_DIR}/lib/libluajit-5.1.a")
set(LUAJIT_EXECUTABLE "${PROJECT_BINARY_DIR}/bin/luajit-${LUAJIT_VERSION_BASE}${LUAJIT_VERSION_EXTRA}")

file(DOWNLOAD "${LUAJIT_URL}" "${LUAJIT_TAR}")

add_custom_command(
  OUTPUT ${LUAJIT_DIR}
  DEPENDS ${LUAJIT_TAR}
  COMMAND ${CMAKE_COMMAND} -E tar xzf ${LUAJIT_TAR}
  WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
)

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  list(APPEND LUAJIT_INSTALL_HEADERS "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}")
endforeach()

add_custom_command(
  OUTPUT ${LUAJIT_LIBRARY} ${LUAJIT_EXECUTABLE} ${LUAJIT_INSTALL_HEADERS}
  DEPENDS ${LUAJIT_DIR}
  COMMAND make install "PREFIX=${PROJECT_BINARY_DIR}" "CC=${CMAKE_C_COMPILER}" "STATIC_CC=${CMAKE_C_COMPILER} -fPIC"
  WORKING_DIRECTORY ${LUAJIT_DIR}
)

add_custom_command(
  OUTPUT ${LUAJIT_OBJECT_DIR}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${LUAJIT_OBJECT_DIR}
)

foreach(LUAJIT_OBJECT ${LUAJIT_OBJECT_BASENAMES})
  list(APPEND LUAJIT_OBJECTS "${LUAJIT_OBJECT_DIR}/${LUAJIT_OBJECT}")
endforeach()

add_custom_command(
  OUTPUT ${LUAJIT_OBJECTS}
  DEPENDS ${LUAJIT_LIBRARY} ${LUAJIT_OBJECT_DIR}
  COMMAND ${CMAKE_AR} x ${LUAJIT_LIBRARY}
  WORKING_DIRECTORY ${LUAJIT_OBJECT_DIR}
)

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  list(APPEND LUAJIT_HEADERS "${PROJECT_SOURCE_DIR}/release/include/terra/${LUAJIT_HEADER}")
endforeach()

foreach(LUAJIT_HEADER ${LUAJIT_HEADER_BASENAMES})
  add_custom_command(
    OUTPUT "${PROJECT_SOURCE_DIR}/release/include/terra/${LUAJIT_HEADER}"
    DEPENDS "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}"
    COMMAND ${CMAKE_COMMAND} -E copy "${LUAJIT_INCLUDE_DIR}/${LUAJIT_HEADER}" "${PROJECT_SOURCE_DIR}/release/include/terra/"
  )
endforeach()

add_custom_target(
  LuaJIT
  DEPENDS ${LUAJIT_LIBRARY} ${LUAJIT_EXECUTABLE} ${LUAJIT_HEADERS} ${LUAJIT_OBJECTS}
)

set(LUAJIT_INCLUDE_DIRS ${LUAJIT_INCLUDE_DIR})
set(LUAJIT_LIBRARIES ${LUAJIT_LIBRARY})
mark_as_advanced(
  LUAJIT_VERSION_BASE
  LUAJIT_VERSION_EXTRA
  LUAJIT_BASENAME
  LUAJIT_URL
  LUAJIT_TAR
  LUAJIT_INCLUDE_DIR
  LUAJIT_LIBRARY
)
