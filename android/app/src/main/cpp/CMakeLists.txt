cmake_minimum_required(VERSION 3.22.1)
project("llm_infer")

set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)

add_subdirectory(
    ${CMAKE_SOURCE_DIR}/../../../../../third_party/llama.cpp
    ${CMAKE_BINARY_DIR}/llama_build
)

add_library(llm_native SHARED LlmNative.cpp)

target_include_directories(llm_native PRIVATE
    ${CMAKE_SOURCE_DIR}/../../../../../third_party/llama.cpp/include
)

target_link_libraries(llm_native
    llama
    android
    log
)
