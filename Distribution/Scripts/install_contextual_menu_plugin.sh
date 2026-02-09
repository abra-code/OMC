#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTRIBUTION_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLUGIN_SOURCE="${DISTRIBUTION_DIR}/Products/Library/Contextual Menu Items/OnMyCommandCM.plugin"
PLUGIN_DEST_DIR="/Library/Contextual Menu Items"
PLUGIN_DEST="${PLUGIN_DEST_DIR}/OnMyCommandCM.plugin"

PREFS_SOURCE="${SCRIPT_DIR}/com.abracode.OnMyCommandCMPrefs.plist"
PREFS_DEST="${HOME}/Library/Preferences/com.abracode.OnMyCommandCMPrefs.plist"

compare_versions() {
    local v1="$1"
    local v2="$2"
    local IFS='.'
    local i nv1 nv2 max n1 n2

    nv1=($v1)
    nv2=($v2)

    if [ ${#nv1[@]} -gt ${#nv2[@]} ]; then
        max=${#nv1[@]}
    else
        max=${#nv2[@]}
    fi

    for ((i=0; i<max; i++)); do
        n1="${nv1[$i]:-0}"
        n2="${nv2[$i]:-0}"
        if [ "$n1" -gt "$n2" ] 2>/dev/null; then
            echo 1
            return
        elif [ "$n1" -lt "$n2" ] 2>/dev/null; then
            echo -1
            return
        fi
    done
    echo 0
}

get_bundle_version() {
    local plist="$1"
    if [ -f "$plist" ]; then
        /usr/bin/plutil -extract CFBundleVersion raw "$plist" 2>/dev/null || echo "unknown"
    else
        echo "none"
    fi
}

echo "=== OMC Contextual Menu Plugin Installer ==="
echo ""

INSTALLED_SOMETHING=false
PLUGIN_ACTION="install"

if [ -d "${PLUGIN_DEST}" ]; then
    SOURCE_VERSION=$(get_bundle_version "${PLUGIN_SOURCE}/Contents/Info.plist")
    DEST_VERSION=$(get_bundle_version "${PLUGIN_DEST}/Contents/Info.plist")

    if [ "$SOURCE_VERSION" = "none" ]; then
        echo "WARNING: New plugin Info.plist not found at ${PLUGIN_SOURCE}/Contents/Info.plist"
        echo "    Skipping plugin installation."
        PLUGIN_ACTION="skip"
    elif [ "$DEST_VERSION" = "unknown" ]; then
        echo "WARNING: Cannot read version of installed plugin at ${PLUGIN_DEST}"
        echo "    Skipping plugin installation."
        PLUGIN_ACTION="skip"
    else
        echo "New plugin version: ${SOURCE_VERSION}"
        echo "Installed plugin version: ${DEST_VERSION}"
        echo ""
        COMPARE=$(compare_versions "$SOURCE_VERSION" "$DEST_VERSION")
        if [ "$COMPARE" = "1" ]; then
            PLUGIN_ACTION="upgrade"
        elif [ "$COMPARE" = "-1" ]; then
            PLUGIN_ACTION="downgrade"
        else
            echo "Plugin already installed (version ${DEST_VERSION}): ${PLUGIN_DEST}"
            echo "    Skipping."
            PLUGIN_ACTION="skip"
        fi
    fi
else
    if [ ! -d "${PLUGIN_SOURCE}" ]; then
        echo "WARNING: Plugin source not found at ${PLUGIN_SOURCE}"
        echo "    Skipping plugin installation."
        PLUGIN_ACTION="skip"
    else
        SOURCE_VERSION=$(get_bundle_version "${PLUGIN_SOURCE}/Contents/Info.plist")
        echo "New plugin version: ${SOURCE_VERSION}"
        echo ""
    fi
fi

if [ "$PLUGIN_ACTION" != "skip" ]; then
    if [ "$(/usr/bin/id -u)" -ne 0 ]; then
        echo ""
        echo "ERROR: Installation to /Library requires administrator privileges."
        echo ""
        echo "To complete installation, run this command with sudo:"
        echo ""
        echo "    sudo ${BASH_SOURCE[0]}"
        echo ""
        exit 1
    fi

    case "$PLUGIN_ACTION" in
        "install")
            echo "Installing OnMyCommandCM.plugin to ${PLUGIN_DEST}..."
            ;;
        "upgrade")
            echo "Upgrading OnMyCommandCM.plugin (${DEST_VERSION} -> ${SOURCE_VERSION}) at ${PLUGIN_DEST}..."
            ;;
        "downgrade")
            echo "WARNING: Downgrading plugin (${DEST_VERSION} -> ${SOURCE_VERSION}) at ${PLUGIN_DEST}"
            echo ""
            echo -n "Continue with downgrade? (y/N) "
            read -r REPLY
            echo ""
            if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
                echo "    Aborted."
                PLUGIN_ACTION="skip"
            fi
            ;;
    esac

    if [ "$PLUGIN_ACTION" != "skip" ]; then
        /bin/mkdir -p "${PLUGIN_DEST_DIR}"
        /bin/rm -rf "${PLUGIN_DEST}"
        /bin/cp -R "${PLUGIN_SOURCE}" "${PLUGIN_DEST}"
        /usr/bin/xattr -dr com.apple.quarantine "${PLUGIN_DEST}" 2>/dev/null
        echo "    Installed: ${PLUGIN_DEST}"
        echo "    Version: ${SOURCE_VERSION}"
        INSTALLED_SOMETHING=true
    fi
fi

if [ ! -f "${PREFS_DEST}" ]; then
    if [ -f "${PREFS_SOURCE}" ]; then
        echo ""
        echo "Installing com.abracode.OnMyCommandCMPrefs.plist to ~/Library/Preferences/..."
        /bin/mkdir -p "${HOME}/Library/Preferences"
        /bin/cp "${PREFS_SOURCE}" "${PREFS_DEST}"
        echo "    Installed: ${PREFS_DEST}"
        INSTALLED_SOMETHING=true
    else
        echo ""
        echo "WARNING: Preferences plist source not found at ${PREFS_SOURCE}"
        echo "    Skipping preferences installation."
    fi
else
    echo ""
    echo "Preferences already exist: ${PREFS_DEST}"
    echo "    Skipping."
fi

echo ""
if [ "$INSTALLED_SOMETHING" = true ]; then
    echo "Installation complete!"
    echo ""
    echo "IMPORTANT: OnMyCommandCM.plugin requires Shortcuts.app."
    echo "Download Shortcuts.app from: https://github.com/abra-code/Shortcuts"
else
    echo "Nothing to install."
fi
