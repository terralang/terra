if("${LLVM_DEFINITIONS}" STREQUAL "@LLVM_DEFINITIONS@")
  # Some versions of LLVM produce broken CMake configurations, so
  # provide default definitions when this is the case.
  list(APPEND ALL_LLVM_DEFINITIONS
    -D_GNU_SOURCE
    -D__STDC_CONSTANT_MACROS
    -D__STDC_FORMAT_MACROS
    -D__STDC_LIMIT_MACROS
  )
else()
  # LLVM doesn't provide these as a list, so we have to make it ourselves.
  string(REGEX MATCHALL "[^ ;]+" LLVM_DEFINITIONS_LIST "${LLVM_DEFINITIONS}")
  list(APPEND ALL_LLVM_DEFINITIONS ${LLVM_DEFINITIONS_LIST})
endif()

# LLVM_AVAILABLE_LIBS can name libraries that this installation does not
# actually provide, in two different ways.
#
# The name may not be an imported target at all: Ubuntu 24.04's llvm-20-dev
# lists the BOLT libraries but exports no targets for them. Those have to be
# dropped before anything reads their properties, or every later loop over
# LLVM_AVAILABLE_LIBS errors out.
#
# Or the target may exist while its file does not. Ubuntu packages Polly, MLIR
# and the llvm-libc tools separately from llvm-N-dev but exports all of them.
# Dropping those is usually fine (Terra needs none of them by name), except
# when another library Terra does link pulls one in: LLVMExtensions lists Polly
# as a dependency, so without it the link fails on getPollyPluginInfo. So drop
# the ones nothing depends on, and report the ones that would break the link.
set(LLVM_EXPORTED_LIBS ${LLVM_AVAILABLE_LIBS})

# Remove BOLT by name, because Ubuntu 24.04's LLVM 18 ships it by default
# (within llvm-18-dev), and linking it with Clang creates conflicts over
# command-line arguments.
foreach(LLVM_LIB ${LLVM_EXPORTED_LIBS})
  if("${LLVM_LIB}" MATCHES "^LLVMBOLT")
    list(REMOVE_ITEM LLVM_AVAILABLE_LIBS ${LLVM_LIB})
  endif()
endforeach()

foreach(LLVM_LIB ${LLVM_EXPORTED_LIBS})
  if(NOT TARGET ${LLVM_LIB})
    message(STATUS "Skipping LLVM library ${LLVM_LIB}: no such target")
    list(REMOVE_ITEM LLVM_AVAILABLE_LIBS ${LLVM_LIB})
    list(REMOVE_ITEM LLVM_EXPORTED_LIBS ${LLVM_LIB})
    continue()
  endif()
  get_property(LLVM_LIB_TYPE TARGET ${LLVM_LIB} PROPERTY TYPE)
  if(${LLVM_LIB_TYPE} STREQUAL STATIC_LIBRARY OR ${LLVM_LIB_TYPE} STREQUAL SHARED_LIBRARY)
    get_property(LLVM_LIB_LOCATION TARGET ${LLVM_LIB} PROPERTY LOCATION)
    if(NOT EXISTS "${LLVM_LIB_LOCATION}")
      list(APPEND LLVM_MISSING_LIBS ${LLVM_LIB})
      list(REMOVE_ITEM LLVM_AVAILABLE_LIBS ${LLVM_LIB})
    endif()
  endif()
endforeach()

# Collect what the libraries we kept actually depend on, so we can tell an
# unreferenced library from one that is about to be needed.
foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS})
  get_property(LLVM_LIB_DEPENDENCIES TARGET ${LLVM_LIB} PROPERTY INTERFACE_LINK_LIBRARIES)
  list(APPEND LLVM_KEPT_DEPENDENCIES ${LLVM_LIB_DEPENDENCIES})
  get_property(LLVM_LIB_DEPENDENCIES TARGET ${LLVM_LIB}
               PROPERTY IMPORTED_LINK_INTERFACE_LIBRARIES)
  list(APPEND LLVM_KEPT_DEPENDENCIES ${LLVM_LIB_DEPENDENCIES})
endforeach()

foreach(LLVM_LIB ${LLVM_MISSING_LIBS})
  get_property(LLVM_LIB_LOCATION TARGET ${LLVM_LIB} PROPERTY LOCATION)
  if(${LLVM_LIB} IN_LIST LLVM_KEPT_DEPENDENCIES)
    message(FATAL_ERROR "LLVM's CMake configuration exports ${LLVM_LIB}, and other LLVM libraries depend on it, but ${LLVM_LIB_LOCATION} does not exist. Install the development package that provides it. (On Ubuntu, llvm-N-dev exports the Polly targets but Polly is packaged separately in libpolly-N-dev.)")
  endif()
  message(STATUS "Skipping LLVM library ${LLVM_LIB}: ${LLVM_LIB_LOCATION} does not exist")
endforeach()

if(TERRA_SLIB_INCLUDE_LLVM)
  set(LLVM_OBJECT_DIR "${PROJECT_BINARY_DIR}/llvm_objects")

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${LLVM_OBJECT_DIR}"
  )

  foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS})
    get_property(LLVM_LIB_TYPE TARGET ${LLVM_LIB} PROPERTY TYPE)
    if(${LLVM_LIB_TYPE} STREQUAL STATIC_LIBRARY)
      get_property(LLVM_LIB TARGET ${LLVM_LIB} PROPERTY LOCATION)
      list(APPEND LLVM_LIBRARIES ${LLVM_LIB})
    endif()
  endforeach()

  foreach(LLVM_LIB_PATH ${LLVM_LIBRARIES} ${CLANG_LIBRARIES})
    get_filename_component(LLVM_LIB_NAME "${LLVM_LIB_PATH}" NAME)
    execute_process(
      COMMAND "${CMAKE_AR}" t "${LLVM_LIB_PATH}"
      OUTPUT_VARIABLE LLVM_LIB_CONTENTS
    )
    string(REGEX MATCHALL "[^\n]+" LLVM_LIB_OBJECT_BASENAMES "${LLVM_LIB_CONTENTS}")
    unset(LLVM_OBJECTS)
    foreach(LLVM_OBJECT ${LLVM_LIB_OBJECT_BASENAMES})
      if(${LLVM_OBJECT} MATCHES \.o$)
        list(APPEND LLVM_OBJECTS "${LLVM_OBJECT_DIR}/${LLVM_LIB_NAME}/${LLVM_OBJECT}")
      endif()
    endforeach()
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${LLVM_OBJECT_DIR}/${LLVM_LIB_NAME}"
    )
    add_custom_command(
      OUTPUT ${LLVM_OBJECTS}
      DEPENDS ${LLVM_LIB_PATH}
      COMMAND "${CMAKE_AR}" x "${LLVM_LIB_PATH}"
      WORKING_DIRECTORY "${LLVM_OBJECT_DIR}/${LLVM_LIB_NAME}"
      VERBATIM
    )
    list(APPEND ALL_LLVM_OBJECTS ${LLVM_OBJECTS})
  endforeach()

  # Don't link libraries, since we're using the extracted object files.
  list(APPEND ALL_LLVM_LIBRARIES)
elseif(TERRA_STATIC_LINK_LLVM)
  foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS})
    get_property(LLVM_LIB_TYPE TARGET ${LLVM_LIB} PROPERTY TYPE)
    if(${LLVM_LIB_TYPE} STREQUAL STATIC_LIBRARY)
      get_property(LLVM_LIB TARGET ${LLVM_LIB} PROPERTY LOCATION)
      list(APPEND LLVM_LIBRARIES ${LLVM_LIB})
    endif()
  endforeach()

  if(UNIX AND NOT APPLE AND TERRA_WHOLE_ARCHIVE_LLVM)
    list(APPEND ALL_LLVM_LIBRARIES
      -Wl,-export-dynamic
    )
  endif()

  if(TERRA_WHOLE_ARCHIVE_LLVM)
    set(WHOLE_ARCHIVE_LIBRARIES ${LLVM_LIBRARIES} ${CLANG_LIBRARIES})
    list(JOIN WHOLE_ARCHIVE_LIBRARIES "," WHOLE_ARCHIVE_LIBRARIES)
    list(APPEND ALL_LLVM_LIBRARIES
      "$<LINK_LIBRARY:WHOLE_ARCHIVE,${WHOLE_ARCHIVE_LIBRARIES}>")
  else()
    list(APPEND ALL_LLVM_LIBRARIES ${LLVM_LIBRARIES} ${CLANG_LIBRARIES})
  endif()

  # Don't extract individual object files.
  list(APPEND ALL_LLVM_OBJECTS)
else()
  foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS})
    get_property(LLVM_LIB_TYPE TARGET ${LLVM_LIB} PROPERTY TYPE)
    if(${LLVM_LIB_TYPE} STREQUAL SHARED_LIBRARY)
      list(APPEND ALL_LLVM_LIBRARIES ${LLVM_LIB})
    endif()
  endforeach()
  list(LENGTH ALL_LLVM_LIBRARIES NUM_LLVM_LIBRARIES)
  if(NUM_LLVM_LIBRARIES EQUAL 0)
    message(FATAL_ERROR "Terra was configured to dynamically link LLVM, but no LLVM dynamic libraries are available")
  endif()

  # For now, statically link Clang.
  list(APPEND ALL_LLVM_LIBRARIES ${CLANG_LIBRARIES})

  # Don't extract individual object files.
  list(APPEND ALL_LLVM_OBJECTS)
endif()

add_custom_target(
  LLVMObjectFiles
  DEPENDS ${ALL_LLVM_OBJECTS}
)

foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS})
  get_property(LLVM_IMPORT_LINK_LIBRARIES TARGET ${LLVM_LIB} PROPERTY IMPORTED_LINK_INTERFACE_LIBRARIES)
  list(APPEND LLVM_SYSTEM_LIBRARIES ${LLVM_IMPORT_LINK_LIBRARIES})
  unset(LLVM_IMPORT_LINK_LIBRARIES)

  get_property(LLVM_LINK_LIBRARIES TARGET ${LLVM_LIB} PROPERTY INTERFACE_LINK_LIBRARIES)
  list(APPEND LLVM_SYSTEM_LIBRARIES ${LLVM_LINK_LIBRARIES})
  unset(LLVM_LINK_LIBRARIES)
endforeach()

# Unwrap libraries in $<LINK_ONLY:...> so that they can be filtered properly.
unset(LLVM_UNWRAPPED_SYSTEM_LIBRARIES)
foreach(LLVM_SYSTEM_LIB ${LLVM_SYSTEM_LIBRARIES})
  if("${LLVM_SYSTEM_LIB}" MATCHES "^\\$<LINK_ONLY:([^<>]+)>$")
    list(APPEND LLVM_UNWRAPPED_SYSTEM_LIBRARIES "${CMAKE_MATCH_1}")
  else()
    list(APPEND LLVM_UNWRAPPED_SYSTEM_LIBRARIES "${LLVM_SYSTEM_LIB}")
  endif()
endforeach()
set(LLVM_SYSTEM_LIBRARIES ${LLVM_UNWRAPPED_SYSTEM_LIBRARIES})

list(REMOVE_ITEM LLVM_SYSTEM_LIBRARIES ${LLVM_EXPORTED_LIBS})
list(REMOVE_DUPLICATES LLVM_SYSTEM_LIBRARIES)

# LLVM's exported targets can name imported targets that LLVMConfig.cmake
# never defines. (LLVM 16 has LLVMLineEditor link against LibEdit::LibEdit,
# but never calls find_package(LibEdit).) Find those packages ourselves so
# that linking against LLVM works.
foreach(LLVM_SYSTEM_LIB ${LLVM_SYSTEM_LIBRARIES})
  if(NOT TARGET ${LLVM_SYSTEM_LIB} AND "${LLVM_SYSTEM_LIB}" MATCHES "^([A-Za-z0-9_]+)::")
    set(LLVM_SYSTEM_LIB_PACKAGE "${CMAKE_MATCH_1}")
    message(STATUS "LLVM references undefined target ${LLVM_SYSTEM_LIB}, searching for ${LLVM_SYSTEM_LIB_PACKAGE}")
    find_package(${LLVM_SYSTEM_LIB_PACKAGE})
    if(NOT TARGET ${LLVM_SYSTEM_LIB})
      message(FATAL_ERROR "LLVM's exported targets reference ${LLVM_SYSTEM_LIB}, but LLVM's CMake configuration does not define it and package ${LLVM_SYSTEM_LIB_PACKAGE} was not found. Install the development package that provides it (e.g., libedit-dev for LibEdit).")
    endif()
  endif()
endforeach()

mark_as_advanced(
  ALL_LLVM_LIBRARIES
  ALL_LLVM_OBJECTS
)
