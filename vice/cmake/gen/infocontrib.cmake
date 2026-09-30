# infocontrib.cmake
#
# Generates src/infocontrib.h -- the contributors' text compiled into the
# `info` command -- from the Acknowledgments chapter of doc/vice.texi and the
# name/mail substitutions of src/buildtools/infocontrib.sed. This is the
# `infocontrib.h` output of buildtools/geninfocontrib_h.sh, its sed pass, and
# the final ISO-8859-15 to UTF-8 conversion, expressed in CMake so that no
# shell tools are needed.
#
#   cmake -DTEXI=<vice.texi> -DSED=<infocontrib.sed> -DVICEDATE=<vicedate.h>
#         -DOUT=<infocontrib.h> -P infocontrib.cmake

cmake_minimum_required(VERSION 3.21)
include("${CMAKE_CURRENT_LIST_DIR}/write_file.cmake")

foreach(_v TEXI SED VICEDATE OUT)
    if(NOT DEFINED ${_v})
        message(FATAL_ERROR "infocontrib.cmake: -D${_v}=... is required")
    endif()
endforeach()

# Placeholders that keep CMake list syntax from touching the text.
set(PH_SEMI "<<IC-SEMI>>")
set(PH_LBRK "<<IC-LBRK>>")
set(PH_RBRK "<<IC-RBRK>>")

# Lines of a file as a list, with `;` `[` `]` protected. CR is dropped: the
# input is LF text whichever way it was checked out.
function(ic_read_lines file out)
    file(READ "${file}" _c)
    string(REPLACE "\r" "" _c "${_c}")
    string(REPLACE ";" "${PH_SEMI}" _c "${_c}")
    string(REPLACE "[" "${PH_LBRK}" _c "${_c}")
    string(REPLACE "]" "${PH_RBRK}" _c "${_c}")
    string(REPLACE "\n" ";" _l "${_c}")
    set(${out} "${_l}" PARENT_SCOPE)
endfunction()

function(ic_restore text out)
    string(REPLACE "${PH_SEMI}" ";" _t "${text}")
    string(REPLACE "${PH_LBRK}" "[" _t "${_t}")
    string(REPLACE "${PH_RBRK}" "]" _t "${_t}")
    set(${out} "${_t}" PARENT_SCOPE)
endfunction()

# The words a shell would split an unquoted expansion into.
function(ic_words text out)
    string(STRIP "${text}" _t)
    string(REGEX REPLACE "[ \t]+" ";" _t "${_t}")
    set(${out} "${_t}" PARENT_SCOPE)
endfunction()

function(ic_join_words words out)
    string(REPLACE ";" " " _t "${words}")
    set(${out} "${_t}" PARENT_SCOPE)
endfunction()

# `echo $* | sed -e "s/@b{//" -e "s/}//"`
function(ic_item text out)
    ic_words("${text}" _w)
    ic_join_words("${_w}" _t)
    string(FIND "${_t}" "@b{" _p)
    if(_p GREATER -1)
        string(SUBSTRING "${_t}" 0 ${_p} _a)
        math(EXPR _q "${_p} + 3")
        string(SUBSTRING "${_t}" ${_q} -1 _b)
        set(_t "${_a}${_b}")
    endif()
    string(FIND "${_t}" "}" _p)
    if(_p GREATER -1)
        string(SUBSTRING "${_t}" 0 ${_p} _a)
        math(EXPR _q "${_p} + 1")
        string(SUBSTRING "${_t}" ${_q} -1 _b)
        set(_t "${_a}${_b}")
    endif()
    set(${out} "${_t}" PARENT_SCOPE)
endfunction()

# years and name of a team line `Copyright @copyright{} <years> <name>`
function(ic_names text years_out name_out)
    ic_words("${text}" _w)
    list(LENGTH _w _n)
    set(_at 2)
    list(GET _w ${_at} _years)
    math(EXPR _at "${_at} + 1")
    if(_years STREQUAL "1993-1994,")
        list(GET _w ${_at} _more)
        set(_years "${_years} ${_more}")
        math(EXPR _at "${_at} + 1")
    endif()
    set(_name "")
    if(_at LESS _n)
        list(SUBLIST _w ${_at} -1 _rest)
        ic_join_words("${_rest}" _name)
    endif()
    set(${years_out} "${_years}" PARENT_SCOPE)
    set(${name_out} "${_name}" PARENT_SCOPE)
endfunction()

# year: `#define VICEDATE_YEAR 2025`
file(READ "${VICEDATE}" _vd)
if(NOT _vd MATCHES "#define VICEDATE_YEAR ([0-9]+)")
    message(FATAL_ERROR "VICEDATE_YEAR not found in ${VICEDATE}")
endif()
set(YEAR "${CMAKE_MATCH_1}")

# Only two stretches of the manual contribute: the team tables (between the
# `vice-core-team` and `ex-team-end` markers) and the Acknowledgments chapter
# (up to `@node Copyright`). Everything between and after them has no effect
# on the output, so cut the text down to those, and insist that the markers
# are where they are expected to be.
#
# The manual holds a Ctrl-Z byte, which ends a plain file(READ) on Windows, so
# the file is searched as hex (binary safe) and the two stretches are then read
# by offset.
function(ic_offset hex needle out)
    string(HEX "${needle}" _nh)
    string(FIND "${hex}" "${_nh}" _p)
    if(_p EQUAL -1)
        message(FATAL_ERROR "${TEXI}: `${needle}` not found")
    endif()
    math(EXPR _o "${_p} / 2")
    set(${out} ${_o} PARENT_SCOPE)
endfunction()

file(READ "${TEXI}" _hex HEX)
ic_offset("${_hex}" "@c ---vice-core-team---" _a0)
ic_offset("${_hex}" "@c ---ex-team-end---" _a1)
ic_offset("${_hex}" "@chapter Acknowledgments" _b0)
ic_offset("${_hex}" "@node Copyright" _b1)
if(_a0 GREATER _a1 OR _a1 GREATER _b0 OR _b0 GREATER _b1)
    message(FATAL_ERROR "${TEXI}: the contributor sections are not where they were expected")
endif()

# each of the eight team markers occurs exactly once
foreach(_m vice-core-team vice-core-team-end ex-team ex-team-end
        translation-team translation-team-end documentation-team documentation-team-end)
    string(HEX "@c ---${_m}---" _mh)
    string(FIND "${_hex}" "${_mh}" _first)
    string(FIND "${_hex}" "${_mh}" _last REVERSE)
    if(_first EQUAL -1 OR NOT _first EQUAL _last)
        message(FATAL_ERROR "${TEXI}: marker `@c ---${_m}---` must occur exactly once")
    endif()
endforeach()
unset(_hex)

# (a text-mode read counts characters after CRLF conversion, so both reads
# ask for more than the stretch is long and are then cut at its last line)
math(EXPR _alen "${_a1} - ${_a0} + 64")
file(READ "${TEXI}" _region_a OFFSET ${_a0} LIMIT ${_alen})
math(EXPR _blen "${_b1} - ${_b0} + 64")
file(READ "${TEXI}" _region_b OFFSET ${_b0} LIMIT ${_blen})
string(REPLACE "\r" "" _region_a "${_region_a}")
string(REPLACE "\r" "" _region_b "${_region_b}")
string(FIND "${_region_a}" "@c ---ex-team-end---" _cut)
string(SUBSTRING "${_region_a}" 0 ${_cut} _region_a)
string(FIND "${_region_b}" "@node Copyright" _cut)
math(EXPR _cut "${_cut} + 15")
string(SUBSTRING "${_region_b}" 0 ${_cut} _region_b)
set(_reduced "${_region_a}@c ---ex-team-end---\n${_region_b}")

string(REPLACE ";" "${PH_SEMI}" _reduced "${_reduced}")
string(REPLACE "[" "${PH_LBRK}" _reduced "${_reduced}")
string(REPLACE "]" "${PH_RBRK}" _reduced "${_reduced}")
string(REPLACE "\n" ";" _lines "${_reduced}")
list(LENGTH _lines _n)

set(LF_ESC "\\n")   # the two characters backslash, n: a C escape in the output

set(_text [==[
/*
 * infocontrib.h - Text of contributors to VICE, as used in info.c
 *
 * Autogenerated by geninfocontrib_h.sh, DO NOT EDIT !!!
 *
 * edit vice.texi and infocontrib.sed to update the info
 *
 * Written by
 *  Marco van den Heuvel <blackystardust68@yahoo.com>
 *
 * This file is part of VICE, the Versatile Commodore Emulator.
 * See README for copyright notice.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
 *  02111-1307  USA.
 *
 */

#ifndef VICE_INFOCONTRIB_H
#define VICE_INFOCONTRIB_H

const char info_contrib_text[] =
]==])

set(_core "")
set(_ex "")
set(_trans "")
set(_doc "")
set(_outputok 0)
set(_done 0)
set(_core_on 0)
set(_ex_on 0)
set(_trans_on 0)
set(_doc_on 0)

set(_i 0)
while(_i LESS _n)
    list(GET _lines ${_i} _data)
    math(EXPR _i "${_i} + 1")

    if("${_data}" STREQUAL "@c ---vice-core-team-end---")
        set(_core_on 0)
    endif()
    if("${_data}" STREQUAL "@c ---ex-team-end---")
        set(_ex_on 0)
    endif()
    if("${_data}" STREQUAL "@c ---translation-team-end---")
        set(_trans_on 0)
    endif()
    if("${_data}" STREQUAL "@c ---documentation-team-end---")
        set(_doc_on 0)
    endif()

    if(_core_on)
        ic_names("${_data}" _years _name)
        string(APPEND _core "    { \"${_years}\", \"${_name}\", \"@b{${_name}}\" },\n")
    endif()

    if(_ex_on)
        ic_names("${_data}" _years _name)
        string(APPEND _ex "    { \"${_years}\", \"${_name}\", \"@b{${_name}}\" },\n")
    endif()

    if(_trans_on)
        ic_item("${_data}" _item)
        string(APPEND _text "\"  ${_data}${LF_ESC}\"\n")
        list(GET _lines ${_i} _data)
        math(EXPR _i "${_i} + 1")
        ic_words("${_data}" _w)
        list(GET _w 2 _years)
        string(APPEND _text "\"  ${_data}${LF_ESC}\"\n")
        list(GET _lines ${_i} _data)
        math(EXPR _i "${_i} + 1")
        ic_words("${_data}" _w)
        list(GET _w 2 _language)
        string(APPEND _text "\"  ${_data}${LF_ESC}\"\n")
        list(GET _lines ${_i} _data)
        math(EXPR _i "${_i} + 1")
        string(APPEND _trans
            "    { \"${_years}\", \"${_item}\", \"${_language}\", \"@b{${_item}}\" },\n")
    endif()

    if(_doc_on)
        ic_item("${_data}" _item)
        string(APPEND _text "\"  ${_data}${LF_ESC}\"\n")
        list(GET _lines ${_i} _data)
        math(EXPR _i "${_i} + 1")
        string(APPEND _doc "    \"${_item}\",\n")
    endif()

    if("${_data}" STREQUAL "@c ---vice-core-team---")
        set(_core_on 1)
    endif()
    if("${_data}" STREQUAL "@c ---ex-team---")
        set(_ex_on 1)
    endif()
    if("${_data}" STREQUAL "@c ---translation-team---")
        set(_trans_on 1)
    endif()
    if("${_data}" STREQUAL "@c ---documentation-team---")
        set(_doc_on 1)
    endif()

    if("${_data}" STREQUAL "@node Copyright")
        string(APPEND _text "\"${LF_ESC}\";\n")
        set(_done 1)
        break()
    endif()
    if(_outputok)
        # lines the shell script leaves out of the text: `@c*`, `@itemize @bullet`,
        # `@item`, `@end itemize`
        if(NOT "${_data}" MATCHES "^@c" AND NOT "${_data}" STREQUAL "@itemize @bullet"
           AND NOT "${_data}" STREQUAL "@item" AND NOT "${_data}" STREQUAL "@end itemize")
            if("${_data}" STREQUAL "")
                string(APPEND _text "\"${LF_ESC}\"\n")
            else()
                string(APPEND _text "\"  ${_data}${LF_ESC}\"\n")
            endif()
        endif()
    endif()
    if("${_data}" STREQUAL "@chapter Acknowledgments")
        set(_outputok 1)
    endif()
endwhile()

if(NOT _done)
    message(FATAL_ERROR "${TEXI}: Acknowledgments chapter did not end at `@node Copyright`")
endif()

string(REPLACE "__VICE_CURRENT_YEAR__" "${YEAR}" _core "${_core}")
string(REPLACE "__VICE_CURRENT_YEAR__" "${YEAR}" _ex "${_ex}")
string(REPLACE "__VICE_CURRENT_YEAR__" "${YEAR}" _trans "${_trans}")

string(APPEND _text "\nvice_team_t core_team[] = {\n${_core}    { NULL, NULL, NULL }\n};\n")
string(APPEND _text "\nvice_team_t ex_team[] = {\n${_ex}    { NULL, NULL, NULL }\n};\n")
string(APPEND _text "\nchar *doc_team[] = {\n${_doc}    NULL\n};\n")
string(APPEND _text "\nvice_trans_t trans_team[] = {\n${_trans}    { NULL, NULL, NULL, NULL }\n};\n")
string(APPEND _text "#endif\n")

ic_restore("${_text}" _text)

# ---------------------------------------------------------------------------
# infocontrib.sed: `s/pattern/replacement/g` lines. Most are literal; the
# few with a `\(...\)` group become regular expressions.
# ---------------------------------------------------------------------------
ic_read_lines("${SED}" _rules)
foreach(_r IN LISTS _rules)
    ic_restore("${_r}" _r)
    string(STRIP "${_r}" _s)
    if(_s STREQUAL "" OR _s MATCHES "^#")
        continue()
    endif()
    if(NOT _r MATCHES "^s/(.*)/g$")
        message(FATAL_ERROR "${SED}: unrecognized line: ${_r}")
    endif()
    set(_body "${CMAKE_MATCH_1}")
    string(FIND "${_body}" "/" _slash)
    if(_slash EQUAL -1)
        message(FATAL_ERROR "${SED}: cannot split the rule: ${_r}")
    endif()
    string(SUBSTRING "${_body}" 0 ${_slash} _pat)
    math(EXPR _after "${_slash} + 1")
    string(SUBSTRING "${_body}" ${_after} -1 _rep)
    if(_rep MATCHES "/")
        message(FATAL_ERROR "${SED}: `/` inside a pattern is not supported: ${_r}")
    endif()
    if(_rep MATCHES "&")
        message(FATAL_ERROR "${SED}: `&` in a replacement is not supported: ${_r}")
    endif()

    if(_pat MATCHES "\\\\\\(")
        # regular expression rule: BRE groups become ERE groups
        string(REPLACE "\\(" "(" _pat "${_pat}")
        string(REPLACE "\\)" ")" _pat "${_pat}")
        string(REGEX REPLACE "${_pat}" "${_rep}" _text "${_text}")
    else()
        string(REPLACE "\\\"" "\"" _pat "${_pat}")
        if(_pat MATCHES "[*^$\\\\]")
            message(FATAL_ERROR "${SED}: unsupported pattern: ${_r}")
        endif()
        # replacement: `\\` is a backslash, `\"` a quote
        string(REPLACE "\\\\" "<<IC-BS>>" _rep "${_rep}")
        string(REPLACE "\\\"" "\"" _rep "${_rep}")
        string(REPLACE "<<IC-BS>>" "\\" _rep "${_rep}")
        string(REPLACE "${_pat}" "${_rep}" _text "${_text}")
    endif()
endforeach()

# ---------------------------------------------------------------------------
# ISO-8859-15 to UTF-8. Bytes 0x80..0xff go through ASCII placeholders so that
# a converted byte is never converted again.
# ---------------------------------------------------------------------------
set(_hexdigits 0 1 2 3 4 5 6 7 8 9 a b c d e f)
set(_special_a4 "e282ac")
set(_special_a6 "c5a0")
set(_special_a8 "c5a1")
set(_special_b4 "c5bd")
set(_special_b8 "c5be")
set(_special_bc "c592")
set(_special_bd "c593")
set(_special_be "c5b8")

set(_codes "")
foreach(_hi RANGE 8 15)
    foreach(_lo RANGE 0 15)
        list(GET _hexdigits ${_hi} _h)
        list(GET _hexdigits ${_lo} _l)
        list(APPEND _codes "${_h}${_l}")
    endforeach()
endforeach()

foreach(_code IN LISTS _codes)
    math(EXPR _b "0x${_code}")
    string(ASCII ${_b} _ch)
    string(REPLACE "${_ch}" "<<IC-B${_code}>>" _text "${_text}")
endforeach()

foreach(_code IN LISTS _codes)
    math(EXPR _b "0x${_code}")
    if(DEFINED _special_${_code})
        set(_utf8 "${_special_${_code}}")
    elseif(_b LESS 192)
        set(_utf8 "c2${_code}")
    else()
        math(EXPR _second "${_b} - 64" OUTPUT_FORMAT HEXADECIMAL)
        string(SUBSTRING "${_second}" 2 -1 _second)
        set(_utf8 "c3${_second}")
    endif()
    # turn the hex pairs of _utf8 into bytes
    set(_bytes "")
    string(LENGTH "${_utf8}" _ul)
    set(_p 0)
    while(_p LESS _ul)
        string(SUBSTRING "${_utf8}" ${_p} 2 _pair)
        math(EXPR _val "0x${_pair}")
        string(ASCII ${_val} _byte)
        string(APPEND _bytes "${_byte}")
        math(EXPR _p "${_p} + 2")
    endwhile()
    string(REPLACE "<<IC-B${_code}>>" "${_bytes}" _text "${_text}")
endforeach()

vice_write_file("${OUT}" "${_text}")
