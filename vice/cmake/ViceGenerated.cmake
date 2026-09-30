# ViceGenerated.cmake
#
# Sources that are generated during the build, and the `vice_generated`
# target that every VICE target depends on.
#
#   reSID waveform tables   cmake/gen/wave_header.cmake
#   infocontrib.h           cmake/gen/infocontrib.cmake
#   monitor grammar/lexer   bison and flex (found with find_package)
#
# Each script under cmake/gen is run with `cmake -P`, so building needs no
# shell, Perl or sed. svnversion.h, keysymtable.h and c64/psiddrv.h are not
# generated: the first is only used with USE_SVN_REVISION, and the others feed
# targets that this configuration does not build.

set(_gen_outputs "")

# --- reSID waveform tables: <name>.dat -> <name>.h -------------------------
am_var_words("src/resid" noinst_DATA _wave_data)
foreach(_dat IN LISTS _wave_data)
    string(REGEX REPLACE "\\.dat$" "" _name "${_dat}")
    set(_out "${VICE_BINARY_DIR}/src/resid/${_name}.h")
    add_custom_command(
        OUTPUT "${_out}"
        COMMAND ${CMAKE_COMMAND}
            "-DIN=${VICE_SOURCE_DIR}/src/resid/${_dat}" "-DOUT=${_out}"
            -P "${VICE_SOURCE_DIR}/cmake/gen/wave_header.cmake"
        DEPENDS "${VICE_SOURCE_DIR}/src/resid/${_dat}"
                "${VICE_SOURCE_DIR}/cmake/gen/wave_header.cmake"
                "${VICE_SOURCE_DIR}/cmake/gen/write_file.cmake"
        COMMENT "Generating ${_name}.h"
        VERBATIM)
    list(APPEND _gen_outputs "${_out}")
endforeach()

# --- infocontrib.h ----------------------------------------------------------
set(_ic_out "${VICE_BINARY_DIR}/src/infocontrib.h")
add_custom_command(
    OUTPUT "${_ic_out}"
    COMMAND ${CMAKE_COMMAND}
        "-DTEXI=${VICE_SOURCE_DIR}/doc/vice.texi"
        "-DSED=${VICE_SOURCE_DIR}/src/buildtools/infocontrib.sed"
        "-DVICEDATE=${VICE_SOURCE_DIR}/src/vicedate.h"
        "-DOUT=${_ic_out}"
        -P "${VICE_SOURCE_DIR}/cmake/gen/infocontrib.cmake"
    DEPENDS "${VICE_SOURCE_DIR}/doc/vice.texi"
            "${VICE_SOURCE_DIR}/src/buildtools/infocontrib.sed"
            "${VICE_SOURCE_DIR}/src/vicedate.h"
            "${VICE_SOURCE_DIR}/cmake/gen/infocontrib.cmake"
            "${VICE_SOURCE_DIR}/cmake/gen/write_file.cmake"
    COMMENT "Generating infocontrib.h"
    VERBATIM)
list(APPEND _gen_outputs "${_ic_out}")

# --- monitor grammar and lexer ---------------------------------------------
get_property(_yacc GLOBAL PROPERTY AM_YACC)
get_property(_lex GLOBAL PROPERTY AM_LEX)
if(_yacc OR _lex)
    find_package(BISON REQUIRED)
    find_package(FLEX REQUIRED)
endif()
foreach(_entry IN LISTS _yacc)
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _dir)
    list(GET _parts 1 _base)
    # the directory's own yacc flags (AM_YFLAGS), run in yacc mode
    am_var_words("${_dir}" AM_YFLAGS _yflags)
    file(MAKE_DIRECTORY "${VICE_BINARY_DIR}/${_dir}")
    add_custom_command(
        OUTPUT "${VICE_BINARY_DIR}/${_dir}/${_base}.c" "${VICE_BINARY_DIR}/${_dir}/${_base}.h"
        COMMAND ${BISON_EXECUTABLE} -y ${_yflags}
            -o "${VICE_BINARY_DIR}/${_dir}/${_base}.c"
            "${VICE_SOURCE_DIR}/${_dir}/${_base}.y"
        DEPENDS "${VICE_SOURCE_DIR}/${_dir}/${_base}.y"
        COMMENT "Generating ${_base}.c"
        VERBATIM)
    list(APPEND _gen_outputs
        "${VICE_BINARY_DIR}/${_dir}/${_base}.c" "${VICE_BINARY_DIR}/${_dir}/${_base}.h")
endforeach()
foreach(_entry IN LISTS _lex)
    string(REPLACE "|" ";" _parts "${_entry}")
    list(GET _parts 0 _dir)
    list(GET _parts 1 _base)
    file(MAKE_DIRECTORY "${VICE_BINARY_DIR}/${_dir}")
    # the lexer includes the parser's header
    add_custom_command(
        OUTPUT "${VICE_BINARY_DIR}/${_dir}/${_base}.c"
        COMMAND ${FLEX_EXECUTABLE}
            -o "${VICE_BINARY_DIR}/${_dir}/${_base}.c"
            "${VICE_SOURCE_DIR}/${_dir}/${_base}.l"
        DEPENDS "${VICE_SOURCE_DIR}/${_dir}/${_base}.l"
        COMMENT "Generating ${_base}.c"
        VERBATIM)
    list(APPEND _gen_outputs "${VICE_BINARY_DIR}/${_dir}/${_base}.c")
endforeach()

add_custom_target(vice_generated DEPENDS ${_gen_outputs})
