# check-am-dump.cmake
#
# A self-test of the Makefile.am reader. Run it on the table that a configure
# with -DVICE_AM_DUMP=ON writes:
#
#   cmake -DDUMP=<build>/am-dump.txt -P cmake/check-am-dump.cmake
#
# It checks that
#   - x64sc links the 47 archives that src/Makefile.am lists for it and
#     c1541 the 11 it lists, and that each of them is a library with sources;
#   - none of the .c files that other sources #include (they are listed in
#     noinst_HEADERS or EXTRA_DIST) has been compiled on its own.

cmake_minimum_required(VERSION 3.21)

if(NOT DEFINED DUMP)
    message(FATAL_ERROR "usage: cmake -DDUMP=<am-dump.txt> -P check-am-dump.cmake")
endif()

file(READ "${DUMP}" _dump)
string(REPLACE "\n" ";" _lines "${_dump}")

# Parse into per-target sources and links.
set(_target "")
set(_targets "")
foreach(_l IN LISTS _lines)
    if(_l MATCHES "^target (.+)$")
        set(_target "${CMAKE_MATCH_1}")
        list(APPEND _targets "${_target}")
        set(SOURCES_${_target} "")
        set(LINKS_${_target} "")
        set(KIND_${_target} "")
    elseif(_l MATCHES "^  source (.+)$")
        list(APPEND SOURCES_${_target} "${CMAKE_MATCH_1}")
    elseif(_l MATCHES "^  link (.+)$")
        list(APPEND LINKS_${_target} "${CMAKE_MATCH_1}")
    elseif(_l MATCHES "^  kind (.+)$")
        set(KIND_${_target} "${CMAKE_MATCH_1}")
    endif()
endforeach()

set(_failures "")

function(_expect_archives program count)
    set(_n 0)
    foreach(_link IN LISTS LINKS_${program})
        if(NOT _link MATCHES "^vice_" OR _link STREQUAL "vice_zlib")
            continue()
        endif()
        math(EXPR _n "${_n} + 1")
        if(NOT "${_link}" IN_LIST _targets)
            list(APPEND _failures "${program} links ${_link}, which is not a defined target")
        elseif(NOT KIND_${_link} STREQUAL "static")
            list(APPEND _failures "${_link} is not a static library")
        elseif(NOT SOURCES_${_link})
            list(APPEND _failures "${_link} has no sources")
        endif()
    endforeach()
    if(NOT _n EQUAL ${count})
        list(APPEND _failures "${program} links ${_n} archives, expected ${count}")
    endif()
    set(_failures "${_failures}" PARENT_SCOPE)
endfunction()

foreach(_p x64sc c1541)
    if(NOT "${_p}" IN_LIST _targets)
        list(APPEND _failures "${_p} is not in the dump")
    endif()
endforeach()
_expect_archives(x64sc 47)
_expect_archives(c1541 11)

# the #included fragments must not be sources
set(_fragments
    src/maincpu.c src/mainc64cpu.c src/mainviccpu.c src/main65816cpu.c src/digimaxcore.c
    src/arch/shared/dynlib-win32.c src/arch/shared/rawnetarch_win32.c
    src/arch/shared/rs232-win32-dev.c src/arch/shared/console_none.c
    src/arch/shared/socket-win32-drv.c)
foreach(_t IN LISTS _targets)
    foreach(_s IN LISTS SOURCES_${_t})
        foreach(_f IN LISTS _fragments)
            if(_s MATCHES "/${_f}$")
                list(APPEND _failures "${_t} compiles the fragment ${_f}")
            endif()
        endforeach()
    endforeach()
endforeach()

# and the files that include them must be
foreach(_needed src/arch/shared/dynlib.c src/arch/shared/rawnetarch.c
        src/arch/shared/rs232dev.c src/arch/shared/console.c src/arch/shared/socketdrv/socketdrv.c)
    set(_found 0)
    foreach(_s IN LISTS SOURCES_vice_archdep SOURCES_vice_socketdrv)
        if(_s MATCHES "/${_needed}$")
            set(_found 1)
        endif()
    endforeach()
    if(NOT _found)
        list(APPEND _failures "${_needed} is not built")
    endif()
endforeach()

if(_failures)
    foreach(_f IN LISTS _failures)
        message("AM-DUMP: FAIL: ${_f}")
    endforeach()
    message(FATAL_ERROR "AM-DUMP: FAIL")
endif()
message("AM-DUMP: PASS")
