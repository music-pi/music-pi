cmake_minimum_required(VERSION 3.16)
project(mk3-mode-selector C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_subdirectory(../external/libmk3 libmk3 EXCLUDE_FROM_ALL)
add_executable(mk3-mode-selector mk3-mode-selector.c t9-input.c wifi.c)
target_link_libraries(mk3-mode-selector PRIVATE mk3)
target_compile_options(mk3-mode-selector PRIVATE -Wall -Wextra -Wpedantic)

include(CTest)
if(BUILD_TESTING)
  add_executable(selector-support-tests test-selector-support.c t9-input.c wifi.c)
  target_compile_options(selector-support-tests PRIVATE -Wall -Wextra -Wpedantic)
  add_test(NAME selector-support-tests COMMAND selector-support-tests)
endif()

install(TARGETS mk3-mode-selector RUNTIME DESTINATION sbin)
