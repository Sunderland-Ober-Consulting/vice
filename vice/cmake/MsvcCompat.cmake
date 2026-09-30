# MsvcCompat.cmake
#
# Compiler settings for building VICE with Microsoft's C and C++ compilers.

if(NOT MSVC)
    message(FATAL_ERROR
        "This build is for the Microsoft Visual C++ compiler (cl); "
        "found ${CMAKE_C_COMPILER_ID}.")
endif()

# C17 and C++17, the conforming preprocessor, and warnings at the default
# level. Warnings are not errors, and there is no /utf-8: some sources are
# Latin-1.
string(APPEND CMAKE_C_FLAGS " /std:c17 /Zc:preprocessor /W3")
string(APPEND CMAKE_CXX_FLAGS " /std:c++17 /EHsc /W3")

set(VICE_COMPAT_HEADER "${VICE_SOURCE_DIR}/src/arch/msvc/msvc_compat.h")

# Settings every VICE target shares: the force-included compat header, and an
# order-only dependency on the generated headers.
function(vice_configure_target target)
    target_compile_options(${target} PRIVATE "/FI${VICE_COMPAT_HEADER}")
    if(VICE_BUNDLED_ZLIB)
        target_include_directories(${target} PRIVATE "${VICE_SOURCE_DIR}/src/lib/zlib")
    endif()
    add_dependencies(${target} vice_generated)
endfunction()
