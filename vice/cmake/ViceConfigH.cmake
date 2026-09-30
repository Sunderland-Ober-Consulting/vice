# ViceConfigH.cmake
#
# Produces src/config.h and the templated headers (version.h, debug.h and
# resid's siddefs.h) in the build tree.
#
# configure computes config.h by running shell code whose outcome cannot be
# read off configure.ac statically, so this file takes *names* from
# configure.ac and *values* from probes of the compiler in use and from the
# profile (VicePlatformWindowsHeadless.cmake):
#
#   1. every macro name that configure.ac can define is collected: AC_DEFINE
#      names, and the HAVE_<X> / SIZEOF_<X> names implied by its
#      AC_CHECK_HEADERS / AC_CHECK_FUNCS / AC_CHECK_TYPES / AC_CHECK_SIZEOF
#      calls;
#   2. each checked header, function, type and size is probed with the
#      compiler that will build VICE;
#   3. the profile lists the feature macros of this configuration;
#   4. a name that is not in the set of step 1 is an error, which catches
#      typos in the profile.

include(CheckIncludeFile)
include(CheckIncludeFiles)
include(CheckSymbolExists)
include(CheckTypeSize)
include(CheckCSourceCompiles)

# `foo/bar-baz.h` -> `FOO_BAR_BAZ_H`
function(vice_macro_suffix text out)
    string(TOUPPER "${text}" _u)
    string(REGEX REPLACE "[^A-Z0-9]" "_" _u "${_u}")
    set(${out} "${_u}" PARENT_SCOPE)
endfunction()

# Arguments of every occurrence of <macro> in configure.ac: the first
# (comma-terminated) argument, split into words.
function(vice_ac_words macro charset out)
    string(REGEX MATCHALL "${macro}\\(${charset}" _m "${VICE_CONFIGURE_FLAT}")
    set(_all "")
    foreach(_x IN LISTS _m)
        string(REGEX REPLACE "^${macro}\\(" "" _b "${_x}")
        string(REPLACE "\\" " " _b "${_b}")
        string(REGEX REPLACE "[ \t\n]+" ";" _b "${_b}")
        list(REMOVE_ITEM _b "")
        list(APPEND _all ${_b})
    endforeach()
    list(REMOVE_DUPLICATES _all)
    set(${out} "${_all}" PARENT_SCOPE)
endfunction()

# Version and package name, read from configure.ac.
function(vice_read_version)
    foreach(_part major minor build)
        if(NOT VICE_CONFIGURE_AC MATCHES "m4_define\\(vice_version_${_part}, *([0-9]+)\\)")
            message(FATAL_ERROR "configure.ac: vice_version_${_part} not found")
        endif()
        set(VICE_VERSION_${_part} "${CMAKE_MATCH_1}" PARENT_SCOPE)
    endforeach()
    if(NOT VICE_CONFIGURE_AC MATCHES "AC_INIT\\(\\[([a-z0-9]+)\\]")
        message(FATAL_ERROR "configure.ac: AC_INIT not found")
    endif()
    set(VICE_PACKAGE "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

# A directory that has a configure script of its own (reSID) passes the macros
# of its AC_INIT to the compiler as -D options ("DEFS" in its Makefile). This
# reads them from <dir>/configure.in.
function(vice_subpackage_defines dir out)
    file(READ "${VICE_SOURCE_DIR}/${dir}/configure.in" _c)
    string(REPLACE "[" "" _c "${_c}")
    string(REPLACE "]" "" _c "${_c}")
    if(NOT _c MATCHES "AC_INIT\\(([^,)]*),([^,)]*),([^,)]*)\\)")
        message(FATAL_ERROR "${dir}/configure.in: AC_INIT not found")
    endif()
    string(STRIP "${CMAKE_MATCH_1}" _name)
    string(STRIP "${CMAKE_MATCH_2}" _version)
    string(STRIP "${CMAKE_MATCH_3}" _bugreport)
    string(TOLOWER "${_name}" _tarname)
    set(_defs
        "PACKAGE_NAME=\"${_name}\""
        "PACKAGE_TARNAME=\"${_tarname}\""
        "PACKAGE_VERSION=\"${_version}\""
        "PACKAGE_STRING=\"${_name} ${_version}\""
        "PACKAGE_BUGREPORT=\"${_bugreport}\""
        "PACKAGE_URL=\"\"")
    if(_c MATCHES "AM_INIT_AUTOMAKE")
        list(APPEND _defs "PACKAGE=\"${_tarname}\"" "VERSION=\"${_version}\"")
    endif()
    set(${out} "${_defs}" PARENT_SCOPE)
endfunction()

function(vice_write_config_h)
    set(_dest "${VICE_BINARY_DIR}/src/config.h")

    # -- 1. names ----------------------------------------------------------
    # Square brackets are m4 quoting; leave them out, so that the matches below
    # never contain one (an unbalanced `[` would swallow list separators).
    string(REPLACE "[" "" VICE_CONFIGURE_FLAT "${VICE_CONFIGURE_AC}")
    string(REPLACE "]" "" VICE_CONFIGURE_FLAT "${VICE_CONFIGURE_FLAT}")

    set(_known "")
    string(REGEX MATCHALL "AC_DEFINE(_UNQUOTED)?\\([A-Za-z0-9_]+" _defs "${VICE_CONFIGURE_FLAT}")
    foreach(_d IN LISTS _defs)
        string(REGEX REPLACE "^AC_DEFINE(_UNQUOTED)?\\(" "" _n "${_d}")
        list(APPEND _known "${_n}")
    endforeach()

    set(_hdr_charset "[A-Za-z0-9_/. \t\n\\\\-]*")
    vice_ac_words("AC_CHECK_HEADERS?" "${_hdr_charset}" _headers)
    vice_ac_words("AC_CHECK_FUNCS?" "[A-Za-z0-9_ ]*" _funcs)
    string(REGEX MATCHALL "AC_CHECK_TYPES\\([A-Za-z0-9_]+" _tm "${VICE_CONFIGURE_FLAT}")
    set(_types "")
    foreach(_t IN LISTS _tm)
        string(REGEX REPLACE "^AC_CHECK_TYPES\\(" "" _n "${_t}")
        list(APPEND _types "${_n}")
    endforeach()
    list(REMOVE_DUPLICATES _types)
    string(REGEX MATCHALL "AC_CHECK_SIZEOF\\([A-Za-z0-9_ ]+" _sm "${VICE_CONFIGURE_FLAT}")
    set(_sizes "")
    foreach(_s IN LISTS _sm)
        string(REGEX REPLACE "^AC_CHECK_SIZEOF\\(" "" _n "${_s}")
        string(STRIP "${_n}" _n)
        list(APPEND _sizes "${_n}")
    endforeach()
    list(REMOVE_DUPLICATES _sizes)

    foreach(_h IN LISTS _headers)
        vice_macro_suffix("${_h}" _x)
        list(APPEND _known "HAVE_${_x}")
    endforeach()
    foreach(_f IN LISTS _funcs)
        vice_macro_suffix("${_f}" _x)
        list(APPEND _known "HAVE_${_x}")
    endforeach()
    foreach(_t IN LISTS _types)
        vice_macro_suffix("${_t}" _x)
        list(APPEND _known "HAVE_${_x}")
    endforeach()
    foreach(_s IN LISTS _sizes)
        vice_macro_suffix("${_s}" _x)
        list(APPEND _known "SIZEOF_${_x}")
    endforeach()
    list(APPEND _known PACKAGE VERSION PACKAGE_NAME PACKAGE_STRING PACKAGE_VERSION
        PACKAGE_TARNAME PACKAGE_BUGREPORT PACKAGE_URL)
    if(VICE_CONFIGURE_AC MATCHES "AC_TYPE_SIGNAL")
        list(APPEND _known RETSIGTYPE)
    endif()
    list(REMOVE_DUPLICATES _known)

    # -- 2. probes ---------------------------------------------------------
    set(_msvc_compat "/FI${VICE_SOURCE_DIR}/src/arch/msvc/msvc_compat.h")
    set(CMAKE_REQUIRED_FLAGS "${_msvc_compat}")
    set(_out "")

    set(_needs_windows_h commctrl.h shlobj.h winioctl.h winsock.h)
    foreach(_h IN LISTS _headers)
        vice_macro_suffix("${_h}" _x)
        if("${_h}" IN_LIST _needs_windows_h)
            check_include_files("windows.h;${_h}" VICE_HAVE_${_x})
        else()
            check_include_file("${_h}" VICE_HAVE_${_x})
        endif()
        if(VICE_HAVE_${_x})
            string(APPEND _out "#define HAVE_${_x} 1\n")
        endif()
    endforeach()

    set(_fn_headers stdio.h stdlib.h string.h time.h math.h io.h direct.h process.h
        sys/types.h sys/stat.h fcntl.h errno.h signal.h limits.h winsock2.h ws2tcpip.h)
    foreach(_f IN LISTS _funcs)
        vice_macro_suffix("${_f}" _x)
        check_symbol_exists("${_f}" "${_fn_headers}" VICE_HAVE_${_x})
        if(VICE_HAVE_${_x})
            string(APPEND _out "#define HAVE_${_x} 1\n")
        endif()
    endforeach()

    set(CMAKE_EXTRA_INCLUDE_FILES time.h sys/types.h stdio.h)
    foreach(_s IN LISTS _sizes)
        vice_macro_suffix("${_s}" _x)
        check_type_size("${_s}" VICE_SIZEOF_${_x} LANGUAGE C)
        string(APPEND _out "#define SIZEOF_${_x} ${VICE_SIZEOF_${_x}}\n")
    endforeach()
    foreach(_t IN LISTS _types)
        vice_macro_suffix("${_t}" _x)
        check_type_size("${_t}" VICE_TYPE_${_x} LANGUAGE C)
        if(HAVE_VICE_TYPE_${_x})
            string(APPEND _out "#define HAVE_${_x} 1\n")
        endif()
    endforeach()
    unset(CMAKE_EXTRA_INCLUDE_FILES)

    # time_t and off_t placement, as configure asks it
    check_c_source_compiles("#include <time.h>\nint main(void) { time_t i; (void)i; return 0; }"
        VICE_TIME_T_IN_TIME_H)
    if(VICE_TIME_T_IN_TIME_H)
        string(APPEND _out "#define HAVE_TIME_T_IN_TIME_H 1\n")
    endif()
    check_c_source_compiles("#include <sys/types.h>\nint main(void) { time_t i; (void)i; return 0; }"
        VICE_TIME_T_IN_TYPES_H)
    if(VICE_TIME_T_IN_TYPES_H)
        string(APPEND _out "#define HAVE_TIME_T_IN_TYPES_H 1\n")
    endif()
    if(VICE_SIZEOF_TIME_T EQUAL 4)
        string(APPEND _out "#define TIME_T_IS_32BIT 1\n")
    elseif(VICE_SIZEOF_TIME_T EQUAL 8)
        string(APPEND _out "#define TIME_T_IS_64BIT 1\n")
    else()
        message(FATAL_ERROR "can not figure type of time_t")
    endif()
    check_c_source_compiles("#include <sys/types.h>\nint main(void) { off_t i; (void)i; return 0; }"
        VICE_OFF_T_IN_SYS_TYPES)
    if(VICE_OFF_T_IN_SYS_TYPES)
        string(APPEND _out "#define HAVE_OFF_T_IN_SYS_TYPES 1\n")
    endif()

    # -- 3. the profile's feature macros -------------------------------------
    foreach(_m IN LISTS AMP_FEATURE_DEFINES)
        if(NOT "${_m}" IN_LIST _known)
            message(FATAL_ERROR
                "${VICE_PROFILE_NAME} profile: ${_m} is not a configure.ac name")
        endif()
        string(APPEND _out "#define ${_m} 1\n")
    endforeach()
    if(VICE_CONFIGURE_AC MATCHES "AC_TYPE_SIGNAL")
        string(APPEND _out "#define RETSIGTYPE void\n")
    endif()
    string(APPEND _out "#define CONFIGURE_FLAGS \"${AMP_CONFIGURE_FLAGS}\"\n")
    string(APPEND _out "#define PREFIX \"${AMP_BUILTIN_prefix}\"\n")

    # -- 4. identity ---------------------------------------------------------
    foreach(_m PACKAGE VERSION PACKAGE_NAME PACKAGE_STRING PACKAGE_VERSION PACKAGE_TARNAME)
        if(NOT "${_m}" IN_LIST _known)
            message(FATAL_ERROR "config.h: ${_m} is not a configure.ac name")
        endif()
    endforeach()
    string(APPEND _out "#define PACKAGE \"${VICE_PACKAGE}\"\n")
    string(APPEND _out "#define PACKAGE_NAME \"${VICE_PACKAGE}\"\n")
    string(APPEND _out "#define PACKAGE_TARNAME \"${VICE_PACKAGE}\"\n")
    string(APPEND _out "#define PACKAGE_VERSION \"${VICE_VERSION}\"\n")
    string(APPEND _out "#define PACKAGE_STRING \"${VICE_PACKAGE} ${VICE_VERSION}\"\n")
    string(APPEND _out "#define VERSION \"${VICE_VERSION}\"\n")

    # every macro written must be one that configure.ac can define
    string(REGEX MATCHALL "#define [A-Za-z0-9_]+" _written "${_out}")
    foreach(_w IN LISTS _written)
        string(REPLACE "#define " "" _w "${_w}")
        if(NOT "${_w}" IN_LIST _known)
            message(FATAL_ERROR "config.h: ${_w} is not a configure.ac name")
        endif()
    endforeach()

    set(_text "/* config.h: written by ViceConfigH.cmake */\n#ifndef VICE_CONFIG_H\n#define VICE_CONFIG_H\n\n${_out}\n#endif\n")
    file(WRITE "${_dest}.tmp" "${_text}")
    configure_file("${_dest}.tmp" "${_dest}" COPYONLY)
endfunction()

# version.h, debug.h and resid's siddefs.h, from their .in templates.
function(vice_write_templated_headers)
    set(VICE_VERSION_MAJOR ${VICE_VERSION_major})
    set(VICE_VERSION_MINOR ${VICE_VERSION_minor})
    set(VICE_VERSION_BUILD ${VICE_VERSION_build})
    set(VERSION "${VICE_VERSION}")
    set(VERSION_RC "${VICE_VERSION_major},${VICE_VERSION_minor},${VICE_VERSION_build},0")
    set(PACKAGE "${VICE_PACKAGE}")
    configure_file("${VICE_SOURCE_DIR}/src/version.h.in"
        "${VICE_BINARY_DIR}/src/version.h" @ONLY)

    set(DEBUGBUILD 0)
    configure_file("${VICE_SOURCE_DIR}/src/debug.h.in"
        "${VICE_BINARY_DIR}/src/debug.h" @ONLY)

    set(CMAKE_REQUIRED_FLAGS "/FI${VICE_SOURCE_DIR}/src/arch/msvc/msvc_compat.h")
    check_symbol_exists(log1p "math.h" VICE_RESID_HAVE_LOG1P)
    if(VICE_RESID_HAVE_LOG1P)
        set(HAVE_LOG1P 1)
    else()
        set(HAVE_LOG1P 0)
    endif()
    set(RESID_INLINING 1)
    set(RESID_INLINE inline)
    set(RESID_BRANCH_HINTS 1)
    set(NEW_8580_FILTER 1)
    set(HAVE_BOOL 1)
    set(HAVE_BUILTIN_EXPECT 0)
    configure_file("${VICE_SOURCE_DIR}/src/resid/siddefs.h.in"
        "${VICE_BINARY_DIR}/src/resid/siddefs.h" @ONLY)
endfunction()
