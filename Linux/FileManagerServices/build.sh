#!/bin/bash
# Linux/FileManagerServices/build.sh - builds and tests the file manager plug-ins for Command applet
# services: first the core they share (command-services-core.c: the services lists, the fit of a
# service to the selected files, an applet bundle's program), with its test, then each plug-in this
# machine has the file manager and the development files for, with its own test. A file manager that
# is not here is skipped, and said so: a build machine need not have any.
#
# - GNOME Files (Nautilus/): libcommand-services-nautilus.so, when libnautilus-extension.so.4 is
#   installed and its headers are: the libnautilus-extension-dev package, or --nautilus-headers
#   <folder holding libnautilus-extension/> (the installed version's headers from its source).
#
# Usage: build.sh <output folder> [--nautilus-headers <folder>]
#        (the core test in <output folder>/core, each plug-in in <output folder>/<file manager>)
# Needs a C compiler and GLib/GIO development files (pkg-config glib-2.0 gio-2.0).
# Exit status: 0 the core and every plug-in that could be built passed, 1 a step failed, 2 bad
# arguments.

out="$1"
nautilus_headers=""
if [ "$2" = "--nautilus-headers" ]; then
    nautilus_headers="$3"
fi
if [ -z "$out" ] || { [ "$2" = "--nautilus-headers" ] && [ -z "$nautilus_headers" ]; }; then
    printf 'Usage: %s <output folder> [--nautilus-headers <folder holding libnautilus-extension/>]\n' "$0" >&2
    exit 2
fi
here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
/bin/mkdir -p "$out/core"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$out/core" >&2
    exit 1
fi

glib_flags="$(/usr/bin/pkg-config --cflags --libs glib-2.0 gio-2.0)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'no GLib development files (pkg-config glib-2.0 gio-2.0)\n' >&2
    exit 1
fi
cc=/usr/bin/cc
warnings="-Wall -Wextra -Werror -Wno-unused-parameter"
# shellcheck disable=SC2086
"$cc" -std=gnu11 $warnings -O0 -g -o "$out/core/command-services-core-test" \
    "$here/command-services-core-test.c" "$here/command-services-core.c" $glib_flags
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the core test did not build\n' >&2
    exit 1
fi
"$out/core/command-services-core-test"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'the core tests failed\n' >&2
    exit 1
fi

# GNOME Files
nautilus_library="$(/bin/ls /usr/lib/*/libnautilus-extension.so.4 /usr/lib64/libnautilus-extension.so.4 2>/dev/null | /usr/bin/head -n 1)"
if [ -z "$nautilus_library" ]; then
    printf 'The GNOME Files plug-in is not built: GNOME Files is not installed here.\n'
else
    nautilus_args=("$out/nautilus")
    nautilus_ready=1
    if [ -n "$nautilus_headers" ]; then
        nautilus_args+=(--nautilus-headers "$nautilus_headers")
    else
        /usr/bin/pkg-config --exists libnautilus-extension-4 2>/dev/null
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'The GNOME Files plug-in is not built: no extension headers (install libnautilus-extension-dev, or give --nautilus-headers).\n'
            nautilus_ready=0
        fi
    fi
    if [ "$nautilus_ready" -eq 1 ]; then
        /bin/bash "$here/Nautilus/build.sh" "${nautilus_args[@]}"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'the GNOME Files plug-in did not build or its tests failed (Nautilus/build.sh status %s)\n' "$status" >&2
            exit 1
        fi
        printf 'The GNOME Files plug-in: %s (Nautilus/install.sh installs it)\n' "$out/nautilus/libcommand-services-nautilus.so"
    fi
fi
exit 0
