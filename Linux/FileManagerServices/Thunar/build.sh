#!/bin/bash
# Linux/FileManagerServices/Thunar/build.sh - builds the Thunar (Xfce) plug-in for Command applet
# services (libcommand-services-thunar.so, with the shared core in ..) and its test program, then
# runs the test. ../build.sh runs it after the core's own test, when the machine has Thunar's
# extension library and its development files.
#
# Usage: build.sh <output folder>
#
# Needs a C compiler, GLib/GIO development files, and Thunar's extension library's: the
# libthunarx-3-dev package (pkg-config thunarx-3).
# Exit status: 0 built and tests passed, 1 a step failed, 2 bad arguments.

out="$1"
if [ -z "$out" ]; then
    printf 'Usage: %s <output folder>\n' "$0" >&2
    exit 2
fi
here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
core="$here/.."
/bin/mkdir -p "$out"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$out" >&2
    exit 1
fi

glib_flags="$(/usr/bin/pkg-config --cflags --libs glib-2.0 gio-2.0 gobject-2.0 gmodule-2.0)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'no GLib development files (pkg-config glib-2.0 gio-2.0 gobject-2.0 gmodule-2.0)\n' >&2
    exit 1
fi
thunar_flags="$(/usr/bin/pkg-config --cflags --libs thunarx-3 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ] || [ -z "$thunar_flags" ]; then
    printf 'no thunarx-3 (install libthunarx-3-dev)\n' >&2
    exit 1
fi

cc=/usr/bin/cc
warnings="-Wall -Wextra -Werror -Wno-unused-parameter"
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O2 -fPIC -fvisibility=hidden -shared -o "$out/libcommand-services-thunar.so" \
    -I"$core" "$here/command-services-thunar.c" "$core/command-services-core.c" $thunar_flags $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in did not build\n' >&2
    exit 1
fi
# The plug-in loaded as Thunar loads it, asked for its menu with stand-in files
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O0 -g -o "$out/command-services-thunar-test" \
    "$here/command-services-thunar-test.c" $thunar_flags $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in test did not build\n' >&2
    exit 1
fi
"$out/command-services-thunar-test" "$out/libcommand-services-thunar.so"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the plug-in tests failed\n' >&2
    exit 1
fi
printf 'built %s\n' "$out/libcommand-services-thunar.so"
exit 0
