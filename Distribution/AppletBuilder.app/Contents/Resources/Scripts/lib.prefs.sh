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

# ──────────────────────────────────────────────────────────────
# Where an applet's last Python thinning plan was written
# ──────────────────────────────────────────────────────────────
#
# Keyed by applet IDENTITY rather than by path, because the whole point is to
# survive the copy: a plan written from ~/dev/MyApp.app is what an apply on
# ~/Release/MyApp.app needs, and the two share no path. lib.build.sh builds the
# key (applet_plan_key) - the bundle identifier where there is one, the applet's
# name otherwise - so two unrelated applets both called MyApp do not share an
# entry. It is still only a fallback: it is consulted only when no plan sits
# beside the bundle, and the run says in its log that it was.

get_thinning_plan() { # <plan key, from applet_plan_key>
    /usr/bin/defaults read "$prefs_domain" "ThinningPlan:$1" 2>/dev/null
}

save_thinning_plan() { # <plan key, from applet_plan_key> <plan path>
    # Errors not silenced, like the two setters above: a failed write disables
    # the fallback, and a run that then cannot find its own plan should have
    # something in the transcript explaining why.
    # -string: an untyped value is PARSED, and a plan path containing {, ( or "
    # fails with "Could not parse" rather than being stored.
    /usr/bin/defaults write "$prefs_domain" "ThinningPlan:$1" -string "$2"
}
