#!/bin/bash
# lib.prefs.sh - User preferences (defaults domain) for AppletBuilder
#
# Sources lib.common.sh (the common base) so clients need only source this lib.

[ -n "$__LIB_PREFS_SH" ] && return 0
__LIB_PREFS_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

# The defaults domain holding AppletBuilder's own settings.
#
# Overridable because `defaults` on a DOMAIN cannot be isolated by a test run:
# cfprefsd keys the user domain by uid, not by $HOME, so a handler that saves a
# setting under test rewrites the real preferences of whoever ran the suite.
# omctest reports the construct for exactly this reason. `defaults` also accepts
# a PATH in place of a domain, so the suite points AB_PREFS_DOMAIN at a plist
# inside its per-file fake home: the same code runs, against a file that dies
# with the test scratch. Nothing in production sets it, so shipped behavior is
# unchanged.
prefs_domain="${AB_PREFS_DOMAIN:-com.abracode.applet-builder}"

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
