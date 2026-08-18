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

###
### Compute all LLVM dependencies
###

# Components Terra uses directly:
list(APPEND TERRA_LLVM_COMPONENTS
  analysis
  asmparser
  bitreader
  bitwriter
  codegen
  core
  debuginfodwarf
  executionengine
  instcombine
  ipo
  linker
  mc
  mcdisassembler
  mcjit
  mcparser
  object
  option
  orcjit
  passes
  runtimedyld
  scalaropts
  support
  target
  transformutils
  vectorize
)

# Components used via Clang:
list(APPEND TERRA_LLVM_COMPONENTS
  aggressiveinstcombine
  binaryformat
  bitstreamreader
  coroutines
  coverage
  demangle
  extensions
  frontendopenmp
  instrumentation
  irreader
  lto
  objcarcopts
  profiledata
  remarks
)
if(LLVM_VERSION_MAJOR GREATER 14)
  list(APPEND TERRA_LLVM_COMPONENTS windowsdriver)
endif()
if(LLVM_VERSION_MAJOR GREATER 15)
  list(APPEND TERRA_LLVM_COMPONENTS frontendhlsl irprinter targetparser)
endif()
if(LLVM_VERSION_MAJOR GREATER 16)
  list(APPEND TERRA_LLVM_COMPONENTS codegentypes)
endif()
if(LLVM_VERSION_MAJOR GREATER 17)
  list(APPEND TERRA_LLVM_COMPONENTS frontenddriver frontendoffloading hipstdpar)
endif()
if(LLVM_VERSION_MAJOR GREATER 21)
  list(APPEND TERRA_LLVM_COMPONENTS plugins)
endif()

# Always include all available backends.
list(APPEND TERRA_LLVM_COMPONENTS
  AllTargetsAsmParsers
  AllTargetsCodeGens
  AllTargetsDescs
  AllTargetsDisassemblers
  AllTargetsInfos
)

llvm_map_components_to_libnames(TERRA_LLVM_ROOT_LIBS ${TERRA_LLVM_COMPONENTS})

foreach(LLVM_LIB ${TERRA_LLVM_ROOT_LIBS})
  if(NOT TARGET ${LLVM_LIB})
    message(FATAL_ERROR "Terra needs the LLVM library ${LLVM_LIB}, but LLVM ${LLVM_PACKAGE_VERSION} does not export it")
  endif()
endforeach()

# Split out LLVM's own libraries from system libraries that LLVM depends on.
function(terra_expand_llvm_libraries out_llvm_libs out_system_libs)
  set(llvm_libs)
  set(system_libs)
  set(pending ${ARGN})

  while(pending)
    list(POP_FRONT pending lib)

    # Terra links everything privately, so private dependencies need no special
    # handling beyond unwrapping them.
    if(lib MATCHES "^\\$<LINK_ONLY:(.+)>$")
      set(lib "${CMAKE_MATCH_1}")
    endif()

    if(lib IN_LIST llvm_libs OR lib IN_LIST system_libs)
      continue()
    endif()

    if(lib MATCHES "::")
      if(NOT TARGET ${lib})
        message(FATAL_ERROR "LLVM's CMake configuration links against the imported target ${lib} but never defines it, which means the library it stands for is not installed. Install its development package and configure Terra again.")
      endif()
      list(APPEND system_libs ${lib})
      continue()
    endif()

    if(NOT TARGET ${lib})
      # A bare library name, linker flag, or absolute path.
      list(APPEND system_libs ${lib})
      continue()
    endif()

    list(APPEND llvm_libs ${lib})
    get_property(lib_dependencies TARGET ${lib} PROPERTY INTERFACE_LINK_LIBRARIES)
    list(APPEND pending ${lib_dependencies})
    get_property(lib_dependencies TARGET ${lib} PROPERTY IMPORTED_LINK_INTERFACE_LIBRARIES)
    list(APPEND pending ${lib_dependencies})
  endwhile()

  set(${out_llvm_libs} ${llvm_libs} PARENT_SCOPE)
  set(${out_system_libs} ${system_libs} PARENT_SCOPE)
endfunction()

terra_expand_llvm_libraries(TERRA_LLVM_LIBS LLVM_SYSTEM_LIBRARIES ${TERRA_LLVM_ROOT_LIBS})

# Link in the order LLVM declares its libraries, which is the order Terra has
# always used. Anything LLVM exports without declaring, such as Ubuntu's
# PollyISL, goes last.
set(TERRA_LLVM_ORDERED_LIBS)
foreach(LLVM_LIB ${LLVM_AVAILABLE_LIBS} ${TERRA_LLVM_LIBS})
  if(LLVM_LIB IN_LIST TERRA_LLVM_LIBS AND NOT LLVM_LIB IN_LIST TERRA_LLVM_ORDERED_LIBS)
    list(APPEND TERRA_LLVM_ORDERED_LIBS ${LLVM_LIB})
  endif()
endforeach()
set(TERRA_LLVM_LIBS ${TERRA_LLVM_ORDERED_LIBS})

foreach(LLVM_LIB ${TERRA_LLVM_LIBS})
  get_property(LLVM_LIB_TYPE TARGET ${LLVM_LIB} PROPERTY TYPE)
  if(LLVM_LIB_TYPE STREQUAL SHARED_LIBRARY)
    list(APPEND LLVM_SHARED_LIBRARIES ${LLVM_LIB})
  elseif(LLVM_LIB_TYPE STREQUAL STATIC_LIBRARY)
    get_property(LLVM_LIB_LOCATION TARGET ${LLVM_LIB} PROPERTY LOCATION)
    if(TERRA_STATIC_LINK_LLVM AND NOT EXISTS "${LLVM_LIB_LOCATION}")
      message(FATAL_ERROR "LLVM's CMake configuration exports ${LLVM_LIB}, and Terra needs it, but ${LLVM_LIB_LOCATION} does not exist. Install the package that provides it. (On Ubuntu, llvm-${LLVM_VERSION_MAJOR}-dev exports the Polly targets but Polly is packaged in libpolly-${LLVM_VERSION_MAJOR}-dev.)")
    endif()
    list(APPEND LLVM_STATIC_LIBRARIES ${LLVM_LIB_LOCATION})
  endif()
endforeach()

###
### Link LLVM dependencies
###

if(TERRA_STATIC_LINK_LLVM AND NOT LLVM_STATIC_LIBRARIES)
  message(FATAL_ERROR "Terra was configured to statically link LLVM, but this LLVM installation provides no static libraries")
endif()

if(TERRA_SLIB_INCLUDE_LLVM)
  set(LLVM_OBJECT_DIR "${PROJECT_BINARY_DIR}/llvm_objects")

  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${LLVM_OBJECT_DIR}"
  )

  foreach(LLVM_LIB_PATH ${LLVM_STATIC_LIBRARIES} ${CLANG_LIBRARIES})
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
  if(UNIX AND NOT APPLE AND TERRA_WHOLE_ARCHIVE_LLVM)
    list(APPEND ALL_LLVM_LIBRARIES
      -Wl,-export-dynamic
    )
  endif()

  if(TERRA_WHOLE_ARCHIVE_LLVM)
    set(WHOLE_ARCHIVE_LIBRARIES ${LLVM_STATIC_LIBRARIES} ${CLANG_LIBRARIES})
    list(JOIN WHOLE_ARCHIVE_LIBRARIES "," WHOLE_ARCHIVE_LIBRARIES)
    list(APPEND ALL_LLVM_LIBRARIES
      "$<LINK_LIBRARY:WHOLE_ARCHIVE,${WHOLE_ARCHIVE_LIBRARIES}>")
  else()
    list(APPEND ALL_LLVM_LIBRARIES ${LLVM_STATIC_LIBRARIES} ${CLANG_LIBRARIES})
  endif()

  # Don't extract individual object files.
  list(APPEND ALL_LLVM_OBJECTS)
else()
  # LLVM can be distributed as a single shared object or as a shared object per
  # component; use whichever we have here:
  if(TARGET LLVM)
    list(APPEND ALL_LLVM_LIBRARIES LLVM)
  elseif(LLVM_SHARED_LIBRARIES)
    list(APPEND ALL_LLVM_LIBRARIES ${LLVM_SHARED_LIBRARIES})
  else()
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

mark_as_advanced(
  ALL_LLVM_LIBRARIES
  ALL_LLVM_OBJECTS
)
