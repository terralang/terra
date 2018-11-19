add_custom_command(
  OUTPUT ${PROJECT_BINARY_DIR}/bin
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/bin"
  VERBATIM
)

add_custom_command(
  OUTPUT ${PROJECT_BINARY_DIR}/lib
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/lib"
  VERBATIM
)

add_custom_command(
  OUTPUT ${PROJECT_BINARY_DIR}/include/terra
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/include/terra"
  VERBATIM
)

add_custom_target(
  BuildDirs
  DEPENDS
    ${PROJECT_BINARY_DIR}/bin
    ${PROJECT_BINARY_DIR}/lib
    ${PROJECT_BINARY_DIR}/include/terra
)
