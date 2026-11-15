#!/bin/bash
# Linux/FileManagerServices/Thunar/install.sh - installs the Thunar plug-in for applet services
# (libcommand-services-thunar.so) into Thunar's extension folder, or removes it. Run as root
# (sudo): Thunar loads plug-ins only from that system folder. Thunar then needs a restart
# (thunar -q, as the user; it starts again with the next window).
#
# Usage: sudo install.sh <libcommand-services-thunar.so>
#        sudo install.sh --uninstall
# Exit status: 0 done, 1 a step failed, 2 bad arguments or not root.

plugin_name="libcommand-services-thunar.so"
if [ "$1" != "--uninstall" ] && { [ -z "$1" ] || [ ! -f "$1" ]; }; then
    printf 'Usage: sudo %s <%s> | --uninstall\n' "$0" "$plugin_name" >&2
    exit 2
fi
uid="$(/usr/bin/id -u)"
if [ "$uid" != "0" ]; then
    printf 'Run it as root (sudo): Thunar loads plug-ins only from a system folder.\n' >&2
    exit 2
fi

# The folder Thunar loads plug-ins from: its pkg-config variable where the development package is
# installed, else the folder beside its extension library (/usr/lib/<arch>/thunarx-3)
folder="$(/usr/bin/pkg-config --variable=extensionsdir thunarx-3 2>/dev/null)"
if [ -z "$folder" ]; then
    library="$(/bin/ls /usr/lib/*/libthunarx-3.so.0 /usr/lib64/libthunarx-3.so.0 /usr/lib/libthunarx-3.so.0 2>/dev/null | /usr/bin/head -n 1)"
    if [ -n "$library" ]; then
        folder="${library%/*}/thunarx-3"
    fi
fi
if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    printf 'No Thunar extension folder found (is Thunar installed?)\n' >&2
    exit 1
fi

# A plug-in a package installed (command-engine-files-thunar) is the package's: installed over, the
# package's next upgrade would undo it; removed, dpkg's records would be wrong. Use apt for it.
if [ -x /usr/bin/dpkg-query ]; then
    owner="$(/usr/bin/dpkg-query -S "$folder/$plugin_name" 2>/dev/null | /usr/bin/sed -n '1s/: .*//p')"
    if [ -n "$owner" ]; then
        printf '%s belongs to the %s package: use apt (apt install or apt remove %s), not this script\n' "$folder/$plugin_name" "$owner" "$owner" >&2
        exit 1
    fi
fi

if [ "$1" = "--uninstall" ]; then
    if [ -f "$folder/$plugin_name" ]; then
        /bin/rm -f -- "$folder/$plugin_name"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'Cannot remove %s\n' "$folder/$plugin_name" >&2
            exit 1
        fi
        printf 'Removed %s. Restart Thunar: thunar -q\n' "$folder/$plugin_name"
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
printf 'Installed %s. Restart Thunar: thunar -q\n' "$folder/$plugin_name"
exit 0
