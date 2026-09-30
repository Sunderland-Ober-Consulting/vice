/*
 * msvc_compat.h - settings VICE needs from the Microsoft C/C++ compiler
 *
 * This file is force-included (/FI) into every C and C++ source when VICE is
 * built with MSVC, and into the compiler probes that produce config.h.
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

#ifndef VICE_MSVC_COMPAT_H
#define VICE_MSVC_COMPAT_H

#ifdef _MSC_VER

/* In conforming mode (/std:c17) the compiler predefines __STDC__ as 1, and
 * the C runtime then hides the POSIX-style names VICE uses (off_t,
 * struct stat, strdup, ...) unless it is asked to declare them. */
#ifndef _CRT_DECLARE_NONSTDC_NAMES
#define _CRT_DECLARE_NONSTDC_NAMES 1
#endif

/* VICE uses the traditional C library functions throughout. */
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS 1
#endif
#ifndef _CRT_NONSTDC_NO_WARNINGS
#define _CRT_NONSTDC_NO_WARNINGS 1
#endif

/* Keep <windows.h> from pulling in headers of its own that clash with
 * <winsock2.h>. */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#endif /* _MSC_VER */

#endif
