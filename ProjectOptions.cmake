include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(net_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(net_setup_options)
  option(net_ENABLE_HARDENING "Enable hardening" ON)
  option(net_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    net_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    net_ENABLE_HARDENING
    OFF)

  net_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR net_PACKAGING_MAINTAINER_MODE)
    option(net_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(net_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(net_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(net_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(net_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(net_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(net_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(net_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(net_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(net_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(net_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(net_ENABLE_PCH "Enable precompiled headers" OFF)
    option(net_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(net_ENABLE_IPO "Enable IPO/LTO" ON)
    option(net_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(net_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(net_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(net_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(net_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(net_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(net_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(net_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(net_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(net_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(net_ENABLE_PCH "Enable precompiled headers" OFF)
    option(net_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      net_ENABLE_IPO
      net_WARNINGS_AS_ERRORS
      net_ENABLE_USER_LINKER
      net_ENABLE_SANITIZER_ADDRESS
      net_ENABLE_SANITIZER_LEAK
      net_ENABLE_SANITIZER_UNDEFINED
      net_ENABLE_SANITIZER_THREAD
      net_ENABLE_SANITIZER_MEMORY
      net_ENABLE_UNITY_BUILD
      net_ENABLE_CLANG_TIDY
      net_ENABLE_CPPCHECK
      net_ENABLE_COVERAGE
      net_ENABLE_PCH
      net_ENABLE_CACHE)
  endif()

  net_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (net_ENABLE_SANITIZER_ADDRESS OR net_ENABLE_SANITIZER_THREAD OR net_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(net_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(net_global_options)
  if(net_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    net_enable_ipo()
  endif()

  net_supports_sanitizers()

  if(net_ENABLE_HARDENING AND net_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR net_ENABLE_SANITIZER_UNDEFINED
       OR net_ENABLE_SANITIZER_ADDRESS
       OR net_ENABLE_SANITIZER_THREAD
       OR net_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${net_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${net_ENABLE_SANITIZER_UNDEFINED}")
    net_enable_hardening(net_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(net_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(net_warnings INTERFACE)
  add_library(net_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  net_set_project_warnings(
    net_warnings
    ${net_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(net_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(net_options)
  endif()

  include(cmake/Sanitizers.cmake)
  net_enable_sanitizers(
    net_options
    ${net_ENABLE_SANITIZER_ADDRESS}
    ${net_ENABLE_SANITIZER_LEAK}
    ${net_ENABLE_SANITIZER_UNDEFINED}
    ${net_ENABLE_SANITIZER_THREAD}
    ${net_ENABLE_SANITIZER_MEMORY})

  set_target_properties(net_options PROPERTIES UNITY_BUILD ${net_ENABLE_UNITY_BUILD})

  if(net_ENABLE_PCH)
    target_precompile_headers(
      net_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(net_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    net_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(net_ENABLE_CLANG_TIDY)
    net_enable_clang_tidy(net_options ${net_WARNINGS_AS_ERRORS})
  endif()

  if(net_ENABLE_CPPCHECK)
    net_enable_cppcheck(${net_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(net_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    net_enable_coverage(net_options)
  endif()

  if(net_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(net_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(net_ENABLE_HARDENING AND NOT net_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR net_ENABLE_SANITIZER_UNDEFINED
       OR net_ENABLE_SANITIZER_ADDRESS
       OR net_ENABLE_SANITIZER_THREAD
       OR net_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    net_enable_hardening(net_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
