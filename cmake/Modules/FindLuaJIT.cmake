# - Try to find luajit
# Once done this will define
#  LUAJIT_FOUND - System has luajit
#  LUAJIT_INCLUDE_DIRS - The luajit include directories
#  LUAJIT_LIBRARIES - The libraries needed to use luajit
#  LUAJIT_OBJECTS

find_package(PkgConfig)
if (PKG_CONFIG_FOUND)
  pkg_check_modules(PC_LUAJIT QUIET luajit)
endif()

set(LUAJIT_DEFINITIONS ${PC_LUAJIT_CFLAGS_OTHER})

find_path(LUAJIT_INCLUDE_DIR luajit.h
          PATHS ${PC_LUAJIT_INCLUDEDIR} ${PC_LUAJIT_INCLUDE_DIRS}
          PATH_SUFFIXES luajit-2.0 luajit-2.1)
if(LUAJIT_INCLUDE_DIR-NOTFOUND)
  include(GetLuaJIT)
else()
  if(TERRA_SLIB_INCLUDE_LUAJIT)
    list(APPEND LUAJIT_AR_NAMES libluajit.a libluajit-5.1.a)
    find_library(LUAJIT_STATIC_LIBRARY NAMES ${LUAJIT_AR_NAMES}
                 PATHS ${PC_LUAJIT_LIBDIR} ${PC_LUAJIT_LIBRARY_DIRS})
    set(LUAJIT_OBJECT_DIR "${Terra_SOURCE_DIR}/build/LuaJIT_Objects")
    file(MAKE_DIRECTORY ${LUAJIT_OBJECT_DIR})
    execute_process(
      COMMAND "${CMAKE_AR}" x "${LUAJIT_STATIC_LIBRARY}"
      WORKING_DIRECTORY ${LUAJIT_OBJECT_DIR}
    )
    file(GLOB LUAJIT_OBJECTS
         LIST_DIRECTORIES false
         "${LUAJIT_OBJECT_DIR}/*.o"
    )
  endif()
  if(TERRA_STATIC_LINK_LUAJIT)
    list(APPEND LUAJIT_NAMES libluajit.a libluajit-5.1.a)
  else()
    if(MSVC)
      list(APPEND LUAJIT_NAMES lua51)
    elseif(MINGW)
      list(APPEND LUAJIT_NAMES libluajit libluajit-5.1)
    else()
      list(APPEND LUAJIT_NAMES luajit-5.1)
    endif()
  endif()

  find_library(LUAJIT_LIBRARY NAMES ${LUAJIT_NAMES}
               PATHS ${PC_LUAJIT_LIBDIR} ${PC_LUAJIT_LIBRARY_DIRS})

  set(LUAJIT_LIBRARIES ${LUAJIT_LIBRARY})
  set(LUAJIT_INCLUDE_DIRS ${LUAJIT_INCLUDE_DIR})

  add_custom_target(
    LuaJIT
    DEPENDS
      ${LUAJIT_OBJECTS}
  )

  mark_as_advanced(LUAJIT_INCLUDE_DIR LUAJIT_LIBRARY)
endif()

include(FindPackageHandleStandardArgs)
# handle the QUIETLY and REQUIRED arguments and set LUAJIT_FOUND to TRUE
# if all listed variables are defined.
find_package_handle_standard_args(LuaJIT DEFAULT_MSG
                                  LUAJIT_LIBRARY LUAJIT_INCLUDE_DIR)
