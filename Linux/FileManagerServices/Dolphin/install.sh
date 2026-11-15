#!/bin/bash
# Linux/FileManagerServices/Dolphin/install.sh - installs the Dolphin plug-in for applet services
# (command-services-dolphin.so) into KIO's file item action folder, or removes it. Run as root
# (sudo): KIO loads these plug-ins only from Qt's system plug-in folder. Dolphin shows it in its next
# menu; Settings, Configure Dolphin, Context Menu lists it as "Command applet services".
#
# Usage: sudo install.sh <command-services-dolphin.so>
#        sudo install.sh --uninstall
# Exit status: 0 done, 1 a step failed, 2 bad arguments or not root.

plugin_name="command-services-dolphin.so"
if [ "$1" != "--uninstall" ] && { [ -z "$1" ] || [ ! -f "$1" ]; }; then
    printf 'Usage: sudo %s <%s> | --uninstall\n' "$0" "$plugin_name" >&2
    exit 2
fi
uid="$(/usr/bin/id -u)"
if [ "$uid" != "0" ]; then
    printf 'Run it as root (sudo): KIO loads plug-ins only from a system folder.\n' >&2
    exit 2
fi

# The folder KIO loads file item actions from: kf6/kfileitemaction in Qt 6's plug-in folder, which
# KIO itself made (its own two plug-ins are there)
folder="$(/bin/ls -d /usr/lib/*/qt6/plugins/kf6/kfileitemaction /usr/lib64/qt6/plugins/kf6/kfileitemaction /usr/lib/qt6/plugins/kf6/kfileitemaction 2>/dev/null | /usr/bin/head -n 1)"
if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    printf 'No KIO file item action folder found (is Dolphin installed?)\n' >&2
    exit 1
fi

# A plug-in a package installed (command-engine-files-dolphin) is the package's: installed over, the
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
        printf 'Removed %s.\n' "$folder/$plugin_name"
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
printf 'Installed %s. Dolphin shows it in its next menu.\n' "$folder/$plugin_name"
exit 0
