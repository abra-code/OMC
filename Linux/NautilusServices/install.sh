#!/bin/bash
# Linux/NautilusServices/install.sh - installs the GNOME Files plug-in for applet services
# (libcommand-services-nautilus.so) into Nautilus's extension folder, or removes it. Run as root
# (sudo): Nautilus loads plug-ins only from that system folder. GNOME Files then needs a restart
# (nautilus -q, as the user; it starts again with the next window).
#
# Usage: sudo install.sh <libcommand-services-nautilus.so>
#        sudo install.sh --uninstall
# Exit status: 0 done, 1 a step failed, 2 bad arguments or not root.

plugin_name="libcommand-services-nautilus.so"
if [ "$1" != "--uninstall" ] && { [ -z "$1" ] || [ ! -f "$1" ]; }; then
    printf 'Usage: sudo %s <%s> | --uninstall\n' "$0" "$plugin_name" >&2
    exit 2
fi
uid="$(/usr/bin/id -u)"
if [ "$uid" != "0" ]; then
    printf 'Run it as root (sudo): Nautilus loads plug-ins only from a system folder.\n' >&2
    exit 2
fi

# The folder Nautilus loads plug-ins from: its pkg-config variable where the development package
# is installed, else the folder beside its extension library (/usr/lib/<arch>/nautilus/extensions-4)
folder="$(/usr/bin/pkg-config --variable=extensiondir libnautilus-extension-4 2>/dev/null)"
if [ -z "$folder" ]; then
    library="$(/bin/ls /usr/lib/*/libnautilus-extension.so.4 /usr/lib64/libnautilus-extension.so.4 2>/dev/null | /usr/bin/head -n 1)"
    if [ -n "$library" ]; then
        folder="${library%/*}/nautilus/extensions-4"
    fi
fi
if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    printf 'No Nautilus extension folder found (is GNOME Files installed?)\n' >&2
    exit 1
fi

if [ "$1" = "--uninstall" ]; then
    if [ -f "$folder/$plugin_name" ]; then
        /bin/rm -f -- "$folder/$plugin_name"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'Cannot remove %s\n' "$folder/$plugin_name" >&2
            exit 1
        fi
        printf 'Removed %s. Restart GNOME Files: nautilus -q\n' "$folder/$plugin_name"
    else
        printf 'Not installed: %s\n' "$folder/$plugin_name"
    fi
    exit 0
fi

/usr/bin/install -m 644 -- "$1" "$folder/$plugin_name"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot install %s into %s\n' "$1" "$folder" >&2
    exit 1
fi
printf 'Installed %s. Restart GNOME Files: nautilus -q\n' "$folder/$plugin_name"
exit 0
