# CMakeLists.txt - build VICE with the Microsoft compiler
#
# This builds the headless x64sc and c1541 for Windows. The source lists are
# not repeated here: cmake/AutomakeReader.cmake reads the Makefile.am files
# that the autotools build uses, and configure.ac supplies the version and the
# names config.h may define. What `configure` would decide for this setup is in
# cmake/VicePlatformWindowsHeadless.cmake.
#
# See doc/building/MSVC-CMake-Howto.txt.

cmake_minimum_required(VERSION 3.21)

project(VICE C CXX)

if(NOT MSVC)
    message(FATAL_ERROR
        "This build is for the Microsoft Visual C++ compiler (cl); "
        "found ${CMAKE_C_COMPILER_ID}.")
endif()

set(VICE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(VICE_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}")
if(VICE_SOURCE_DIR MATCHES " " OR VICE_BINARY_DIR MATCHES " ")
    message(FATAL_ERROR
        "The source and build directories must not contain spaces: they are "
        "written into compiler options taken from the Makefile.am files.")
endif()
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Only 64-bit builds are supported (run from an x64 developer prompt).")
endif()

option(VICE_BUNDLED_ZLIB "Build the zlib in src/lib/zlib instead of using a system one" ON)
option(VICE_AM_DUMP "Write am-dump.txt, the table of targets read from the Makefile.am files" OFF)
# negative-check aid for the reader's fragment exclusion; leave OFF
option(AM_NO_FRAGMENT_EXCLUSION "Compile .c files that Makefile.am lists as headers" OFF)
mark_as_advanced(AM_NO_FRAGMENT_EXCLUSION)

list(APPEND CMAKE_MODULE_PATH "${VICE_SOURCE_DIR}/cmake")

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${VICE_SOURCE_DIR}/configure.ac")

include(MsvcCompat)
include(VicePlatformWindowsHeadless)

# --- version, config.h, templated headers -----------------------------------
file(READ "${VICE_SOURCE_DIR}/configure.ac" VICE_CONFIGURE_AC)
include(ViceConfigH)
vice_read_version()
if(VICE_VERSION_build EQUAL 0)
    set(VICE_VERSION "${VICE_VERSION_major}.${VICE_VERSION_minor}")
else()
    set(VICE_VERSION "${VICE_VERSION_major}.${VICE_VERSION_minor}.${VICE_VERSION_build}")
endif()
vice_write_config_h()
vice_write_templated_headers()
vice_subpackage_defines(src/resid AMP_DIR_DEFINES_src_resid)

# --- zlib -------------------------------------------------------------------
if(VICE_BUNDLED_ZLIB)
    set(_zlib_dir "${VICE_SOURCE_DIR}/src/lib/zlib")
    add_library(vice_zlib STATIC
        ${_zlib_dir}/adler32.c ${_zlib_dir}/compress.c ${_zlib_dir}/crc32.c
        ${_zlib_dir}/deflate.c ${_zlib_dir}/gzclose.c ${_zlib_dir}/gzlib.c
        ${_zlib_dir}/gzread.c ${_zlib_dir}/gzwrite.c ${_zlib_dir}/infback.c
        ${_zlib_dir}/inffast.c ${_zlib_dir}/inflate.c ${_zlib_dir}/inftrees.c
        ${_zlib_dir}/trees.c ${_zlib_dir}/uncompr.c ${_zlib_dir}/zutil.c)
    target_include_directories(vice_zlib PUBLIC "${_zlib_dir}")
    target_compile_definitions(vice_zlib PRIVATE
        _CRT_SECURE_NO_DEPRECATE _CRT_NONSTDC_NO_DEPRECATE)
else()
    find_package(ZLIB REQUIRED)
    add_library(vice_zlib INTERFACE)
    target_link_libraries(vice_zlib INTERFACE ZLIB::ZLIB)
endif()

# --- the Makefile.am files ----------------------------------------------------
include(AutomakeReader)
am_walk(src)

# The programs of src/Makefile.am that this configuration builds.
set(VICE_PROGRAMS x64sc c1541)
foreach(_p IN LISTS VICE_PROGRAMS)
    am_define_program(${_p})
endforeach()

include(ViceGenerated)

if(VICE_AM_DUMP)
    am_dump("${VICE_BINARY_DIR}/am-dump.txt")
endif()

# --- run-time data --------------------------------------------------------------
# On Windows the emulator looks for its ROMs and other data next to the executable.
set(_data_dirs C64 DRIVES PRINTER)
set(_data_stamps "")
foreach(_d IN LISTS _data_dirs)
    add_custom_command(
        OUTPUT "${VICE_BINARY_DIR}/${_d}.stamp"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${VICE_SOURCE_DIR}/data/${_d}" "${VICE_BINARY_DIR}/${_d}"
        COMMAND ${CMAKE_COMMAND} -E touch "${VICE_BINARY_DIR}/${_d}.stamp"
        COMMENT "Copying data/${_d}"
        VERBATIM)
    list(APPEND _data_stamps "${VICE_BINARY_DIR}/${_d}.stamp")
endforeach()
add_custom_target(vice_data ALL DEPENDS ${_data_stamps})
