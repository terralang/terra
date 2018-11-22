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

# The official binary for 3.8 on macOS is buggy and lists LTO (a dynamic
# library) even though LLVMLTO (a static library) is already on the list.
list(REMOVE_ITEM LLVM_AVAILABLE_LIBS LTO)

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

  if(UNIX AND NOT APPLE)
    list(APPEND ALL_LLVM_LIBRARIES
      -Wl,-export-dynamic
      -Wl,--whole-archive
    )
  endif()

  foreach(LLVM_LIB_PATH ${LLVM_LIBRARIES} ${CLANG_LIBRARIES})
    if(APPLE)
      list(APPEND ALL_LLVM_LIBRARIES "-Wl,-force_load,${LLVM_LIB_PATH}")
    else()
      list(APPEND ALL_LLVM_LIBRARIES "${LLVM_LIB_PATH}")
    endif()
  endforeach()

  if(UNIX AND NOT APPLE)
    list(APPEND ALL_LLVM_LIBRARIES
      -Wl,--no-whole-archive
    )
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
list(REMOVE_ITEM LLVM_SYSTEM_LIBRARIES ${LLVM_AVAILABLE_LIBS})
list(REMOVE_DUPLICATES LLVM_SYSTEM_LIBRARIES)

mark_as_advanced(
  ALL_LLVM_LIBRARIES
  ALL_LLVM_OBJECTS
)
