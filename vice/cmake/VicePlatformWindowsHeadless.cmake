# VicePlatformWindowsHeadless.cmake
#
# The configuration profile for building VICE for Windows with the headless
# front-end: the values that `configure` would compute for that setup.
#
# Two tables are defined here, both consulted by AutomakeReader.cmake:
#
#  - the automake conditionals (`if FOO` in a Makefile.am), as AMP_COND_<NAME>
#  - the configure substitutions (`@FOO@` in a Makefile.am), as AMP_SUBST_<NAME>
#
# Every lookup miss is an error; nothing falls back to a default.
#
# A third table (AMP_FEATURE_DEFINES) lists the feature macros that
# ViceConfigH.cmake writes to config.h.

# The profile is that of `configure --enable-headlessui --without-residfp`
# (HAVE_RESIDFP is false, so reSID is the SID engine).

set(VICE_PROFILE_NAME "windows-headless")

# ---------------------------------------------------------------------------
# Conditionals
# ---------------------------------------------------------------------------

set(_amp_conditionals_true
    WINDOWS_COMPILE
    USE_HEADLESSUI
    HAVE_RESID
    NEW_8580_FILTER
    RESID_DIR_USED
    HAVE_REALDEVICE)

set(_amp_conditionals_false
    # top-level Makefile.am
    ENABLE_HTML_DOCS
    VICE_QUIET
    MAKE_BINDIST
    MAKE_INSTALL
    # host / front-end selection
    UNIX_COMPILE
    MACOS_COMPILE
    LINUX_COMPILE
    BSD_COMPILE
    BEOS_COMPILE
    DUMMY_COMPILE
    USE_GTK3UI
    USE_SDLUI
    USE_SDL2UI
    # optional features
    HAVE_DEBUG
    HAVE_USBSID
    HAVE_CATWEASELMKIII
    HAVE_PARSID
    HAVE_RESIDFP
    HAVE_LINUX_EVDEV
    SUPPORT_X64
    USE_SVN_REVISION
    USE_SVN_REVISION_OVERRIDE)

foreach(_c IN LISTS _amp_conditionals_true)
    set(AMP_COND_${_c} ON)
endforeach()
foreach(_c IN LISTS _amp_conditionals_false)
    set(AMP_COND_${_c} OFF)
endforeach()

# ---------------------------------------------------------------------------
# Substitutions
# ---------------------------------------------------------------------------
#
# Values may refer to $(top_srcdir), $(top_builddir) and other make variables;
# they are expanded when used.

set(AMP_SUBST_VICE_CPPFLAGS
    "-I$(top_srcdir)/src/arch/systemheaderoverride -DNDEBUG")
# The compiler flags come from the CMake preset, not from the profile.
set(AMP_SUBST_VICE_CFLAGS "")
set(AMP_SUBST_VICE_CXXFLAGS "")
set(AMP_SUBST_VICE_OBJCFLAGS "")
set(AMP_SUBST_VICE_LDFLAGS "")
set(AMP_SUBST_MONITOR_CFLAGS "")
set(AMP_SUBST_LINKCC "$(CXX)")

set(AMP_SUBST_ARCH_DIR "$(top_builddir)/src/arch/headless")
set(AMP_SUBST_ARCH_SRC_DIR "$(top_srcdir)/src/arch/headless")
set(AMP_SUBST_ARCH_INCLUDES
    "-I$(top_srcdir)/src/arch/headless -I$(top_srcdir)/src/arch/shared")
set(AMP_SUBST_ARCH_LIBS "$(top_builddir)/src/arch/headless/libarch.a")
set(AMP_SUBST_ENABLE_ARCH "")

# reSID
set(AMP_SUBST_RESID_DIR "resid")
set(AMP_SUBST_RESIDSUB "resid")
set(AMP_SUBST_RESID_DEP "libresid")
set(AMP_SUBST_RESID_LIBS "$(top_builddir)/src/resid/libresid.a")
set(AMP_SUBST_RESID_INCLUDES "-I$(top_builddir)/src/resid")
set(AMP_SUBST_RESID_CPPFLAGS "-DNDEBUG")
set(AMP_SUBST_RESID_DTV_DIR "")
set(AMP_SUBST_RESIDDTVSUB "")
set(AMP_SUBST_RESID_DTV_DEP "")
set(AMP_SUBST_RESID_DTV_LIBS "")
set(AMP_SUBST_RESID_DTV_INCLUDES "")

# reSIDfp (left out: --without-residfp)
set(AMP_SUBST_RESIDFP_INCLUDES "")
set(AMP_SUBST_RESIDFP_DEP "")
set(AMP_SUBST_RESIDFP_CXXFLAGS "")

# Libraries. Names are those `-l` words a link would need; AutomakeReader.cmake
# maps them to CMake link items through AMP_LIBRARY_MAP below.
set(AMP_SUBST_SOUND_DRIVERS "soundwmm.o sounddx.o")
set(AMP_SUBST_SOUND_LIBS "-ldsound")
set(AMP_SUBST_GFXOUTPUT_DRIVERS "")
set(AMP_SUBST_GFXOUTPUT_LIBS "")
set(AMP_SUBST_ZLIB_LIBS "-lz")
set(AMP_SUBST_DYNLIB_LIBS "")
set(AMP_SUBST_JOY_LIBS "")
set(AMP_SUBST_JOYSTICK_DRIVERS "")
set(AMP_SUBST_UI_LIBS "")
set(AMP_SUBST_SDL_EXTRA_LIBS "")
set(AMP_SUBST_TFE_LIBS "")
set(AMP_SUBST_NETPLAY_LIBS "")
set(AMP_SUBST_LIBOBJS "")

# Names that appear in Makefile.am files that are not built here.
set(AMP_SUBST_AR "lib")
set(AMP_SUBST_FW_DIR "")
set(AMP_SUBST_GLIB_CFLAGS "")
set(AMP_SUBST_GTK_CFLAGS "")
set(AMP_SUBST_VTE_CXXFLAGS "")
set(AMP_SUBST_INLINE_UNIT_GROWTH "")
set(AMP_SUBST_PROGRAM_PREFIX "")
set(AMP_SUBST_PROGRAM_SUFFIX "")
set(AMP_SUBST_SVN_REVISION_OVERRIDE "")
set(AMP_SUBST_UNZIPBIN "unzip")
set(AMP_SUBST_VICE_PDF_FILE_NAME "vice.pdf")

# Per-program linker flags (MSVC options come from the preset).
foreach(_p c1541 cartconv petcat vsid x64 x128 xcbm2 xpet xplus4 xscpu64 xvic)
    set(AMP_SUBST_${_p}_LDFLAGS "")
endforeach()

# Configure-output variables that Makefile.am files use without assigning.
set(AMP_SUBST_PERL "perl")
set(AMP_SUBST_XA "xa")
set(AMP_SUBST_SVNVERSION ":")
set(AMP_SUBST_LN_S "ln -s")

# Directory names configure derives from its prefix. On Windows the emulator
# finds its data directory relative to the executable, so these are only the
# defaults compiled into the build.
set(AMP_BUILTIN_prefix "/usr/local")
set(AMP_BUILTIN_datadir "/usr/local/share")
set(AMP_BUILTIN_docdir "/usr/local/share/doc/vice")
set(AMP_CONFIGURE_FLAGS "--enable-headlessui (CMake build)")

# Library word -> CMake link item. A `-lfoo` outside this table is an error.
set(AMP_LIBRARY_MAP_dsound dsound)
set(AMP_LIBRARY_MAP_winmm winmm)
set(AMP_LIBRARY_MAP_ntdll ntdll)
set(AMP_LIBRARY_MAP_ws2_32 ws2_32)
set(AMP_LIBRARY_MAP_ole32 ole32)
set(AMP_LIBRARY_MAP_z vice_zlib)

# Libraries that a Windows link of the whole emulator always carries (the
# `LIBS` that configure accumulates), in addition to the per-program -l words.
set(AMP_PLATFORM_LIBRARIES winmm ntdll ws2_32 ole32)

# ---------------------------------------------------------------------------
# config.h feature macros
# ---------------------------------------------------------------------------
#
# Macros defined for this configuration, beyond what the probes find. Each
# name must be one that configure.ac itself defines (ViceConfigH.cmake checks).

set(AMP_FEATURE_DEFINES
    WINDOWS_COMPILE
    USE_HEADLESSUI
    HAVE_NETWORK
    HAVE_HTONL
    HAVE_HTONS
    HAVE_RS232NET
    HAVE_RS232DEV
    HAVE_HARDSID
    HAVE_ZLIB
    HAVE_DYNLIB_SUPPORT
    HAVE_REALDEVICE
    HAVE_RESID
    HAVE_RESID_DTV
    HAVE_NEW_8580_FILTER
    FEATURE_CPUMEMHISTORY
    HAVE_MOUSE
    HAVE_LIGHTPEN
    HAVE_SOCKLEN_T
    USE_DXSOUND
    HAVE_DSOUND_LIB)
