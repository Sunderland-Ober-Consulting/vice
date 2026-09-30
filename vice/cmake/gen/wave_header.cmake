# wave_header.cmake
#
# Turns a reSID waveform table (raw bytes) into the C fragment that
# wave.cc includes: `/* offset: */` followed by eight table entries per line,
# each byte shifted left by four bits.
#
#   cmake -DIN=<wave*.dat> -DOUT=<wave*.h> -P wave_header.cmake

cmake_minimum_required(VERSION 3.21)
include("${CMAKE_CURRENT_LIST_DIR}/write_file.cmake")

if(NOT DEFINED IN OR NOT DEFINED OUT)
    message(FATAL_ERROR "usage: cmake -DIN=<file> -DOUT=<file> -P wave_header.cmake")
endif()

file(READ "${IN}" _hex HEX)
string(LENGTH "${_hex}" _hex_len)
math(EXPR _size "${_hex_len} / 2")

set(_text [==[
//  ---------------------------------------------------------------------------
//  This file is part of reSID, a MOS6581 SID emulator engine.
//  Copyright (C) 2010  Dag Lem <resid@nimrod.no>
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//  ---------------------------------------------------------------------------

]==])
string(APPEND _text "{\n")

set(_i 0)
while(_i LESS _size)
    math(EXPR _offset "${_i}" OUTPUT_FORMAT HEXADECIMAL)
    string(SUBSTRING "${_offset}" 2 -1 _offset)
    string(LENGTH "${_offset}" _offset_len)
    while(_offset_len LESS 3)
        set(_offset "0${_offset}")
        math(EXPR _offset_len "${_offset_len} + 1")
    endwhile()
    string(APPEND _text "/* 0x${_offset}: */ ")

    math(EXPR _end "${_i} + 8")
    if(_end GREATER _size)
        set(_end ${_size})
    endif()
    set(_j ${_i})
    while(_j LESS _end)
        math(EXPR _at "${_j} * 2")
        string(SUBSTRING "${_hex}" ${_at} 2 _byte)
        # byte << 4 printed as three hex digits is the byte followed by 0
        string(APPEND _text " 0x${_byte}0,")
        math(EXPR _j "${_j} + 1")
    endwhile()
    string(APPEND _text "\n")
    math(EXPR _i "${_i} + 8")
endwhile()
string(APPEND _text "},\n")

vice_write_file("${OUT}" "${_text}")
