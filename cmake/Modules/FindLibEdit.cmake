# Find libedit and define the LibEdit::LibEdit imported target.
#
# LLVM's exported CMake targets reference LibEdit::LibEdit (LLVMLineEditor
# links against it), but some LLVM installations do not ship a FindLibEdit
# module and never call find_package(LibEdit) from LLVMConfig.cmake. This
# module fills that gap; it mirrors the one in LLVM upstream.
#
# Defines:
#   LibEdit_FOUND        - true if libedit was found
#   LibEdit_INCLUDE_DIRS - include search path
#   LibEdit_LIBRARIES    - libraries to link

find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
  pkg_check_modules(PC_LIBEDIT QUIET libedit)
endif()

find_path(LibEdit_INCLUDE_DIRS NAMES histedit.h HINTS ${PC_LIBEDIT_INCLUDE_DIRS})
find_library(LibEdit_LIBRARIES NAMES edit HINTS ${PC_LIBEDIT_LIBRARY_DIRS})

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LibEdit
  FOUND_VAR LibEdit_FOUND
  REQUIRED_VARS LibEdit_INCLUDE_DIRS LibEdit_LIBRARIES
)

if(LibEdit_FOUND AND NOT TARGET LibEdit::LibEdit)
  add_library(LibEdit::LibEdit UNKNOWN IMPORTED)
  set_target_properties(LibEdit::LibEdit PROPERTIES
    IMPORTED_LOCATION "${LibEdit_LIBRARIES}"
    INTERFACE_INCLUDE_DIRECTORIES "${LibEdit_INCLUDE_DIRS}"
  )
endif()

mark_as_advanced(LibEdit_INCLUDE_DIRS LibEdit_LIBRARIES)
