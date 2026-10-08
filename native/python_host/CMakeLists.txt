cmake_minimum_required(VERSION 3.18.1)
project(addko_python_host LANGUAGES CXX)

add_library(
  addko_python_host
  SHARED
  src/addko_python_host.cpp
)

target_include_directories(
  addko_python_host
  PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(addko_python_host PRIVATE cxx_std_17)
target_compile_options(addko_python_host PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(addko_python_host PRIVATE ${CMAKE_DL_LIBS})
