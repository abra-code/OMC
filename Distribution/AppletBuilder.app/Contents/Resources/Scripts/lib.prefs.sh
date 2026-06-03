#!/bin/bash
# lib.prefs.sh - User preferences (defaults domain) for AppletBuilder
#
# Sources lib.common.sh (the common base) so clients need only source this lib.

[ -n "$__LIB_PREFS_SH" ] && return 0
__LIB_PREFS_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

prefs_domain="com.abracode.applet-builder"

get_bundle_id_prefix() {
    local prefix=$(/usr/bin/defaults read "$prefs_domain" BundleIDPrefix 2>/dev/null)
    if [ -z "$prefix" ]; then
        prefix="com.omc.applet."
    fi
    echo "$prefix"
}

save_bundle_id_prefix() {
    local bundle_id="$1"
    # Extract prefix: everything up to and including the last dot
    local prefix="${bundle_id%.*}."
    /usr/bin/defaults write "$prefs_domain" BundleIDPrefix "$prefix"
}

get_external_editor() {
    local editor=$(/usr/bin/defaults read "$prefs_domain" ExternalEditor 2>/dev/null)
    if [ -z "$editor" ]; then
        editor="/System/Applications/TextEdit.app"
    fi
    echo "$editor"
}

save_external_editor() {
    /usr/bin/defaults write "$prefs_domain" ExternalEditor "$1"
}
