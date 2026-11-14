#!/bin/bash
# lib.prefs.sh - User preferences (defaults domain) for AppletBuilder
#
# Sources lib.common.sh (the common base) so clients need only source this lib.

[ -n "$__LIB_PREFS_SH" ] && return 0
__LIB_PREFS_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

# The defaults domain holding AppletBuilder's own settings, read and written with
# the engine's defaults tool ($defaults_tool, lib.common.sh): on macOS the user's
# preferences through /usr/bin/defaults, as before; on Linux a JSON file in
# ~/.config; under a test runner that sets OMC_DEFAULTS_PATH (omctest API 8,
# omcitest), a JSON file in the test's private home.
#
# Overridable because /usr/bin/defaults on a DOMAIN cannot be isolated by a test
# run: cfprefsd keys the user domain by uid, not by $HOME, so a handler that
# saves a setting under test rewrites the real preferences of whoever ran the
# suite. A PATH is accepted in place of a domain, so the suite points
# AB_PREFS_DOMAIN at a plist inside its per-file fake home: the same code runs,
# against a file that dies with the test scratch. Nothing in production sets
# it, so shipped behavior is unchanged.
prefs_domain="${AB_PREFS_DOMAIN:-com.abracode.applet-builder}"

get_bundle_id_prefix() {
    local prefix=$("$defaults_tool" read "$prefs_domain" BundleIDPrefix 2>/dev/null)
    if [ -z "$prefix" ]; then
        prefix="com.omc.applet."
    fi
    echo "$prefix"
}

save_bundle_id_prefix() {
    local bundle_id="$1"
    # Extract prefix: everything up to and including the last dot
    local prefix="${bundle_id%.*}."
    "$defaults_tool" write "$prefs_domain" BundleIDPrefix "$prefix"
}

# The external editor the user chose; with none chosen TextEdit on macOS, and nothing on Linux,
# where a file then opens in the system's default application for its type
get_external_editor() {
    local editor=$("$defaults_tool" read "$prefs_domain" ExternalEditor 2>/dev/null)
    if [ -z "$editor" ]; then
        case "${OSTYPE:-}" in
            darwin*) editor="/System/Applications/TextEdit.app" ;;
        esac
    fi
    echo "$editor"
}

save_external_editor() {
    "$defaults_tool" write "$prefs_domain" ExternalEditor "$1"
}

# The editor's name as Settings shows it
external_editor_name() { # <editor path, or empty>
    if [ -z "$1" ]; then
        echo "System default"
    else
        /usr/bin/basename "${1%.app}"
    fi
}

# Opens a file in the external editor (the engine's open tool, the same on both systems)
open_in_external_editor() { # <file>
    local editor=$(get_external_editor)
    if [ -n "$editor" ]; then
        "$open_tool" -a "$editor" "$1"
    else
        "$open_tool" "$1"
    fi
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
    "$defaults_tool" read "$prefs_domain" "ThinningPlan:$1" 2>/dev/null
}

save_thinning_plan() { # <plan key, from applet_plan_key> <plan path>
    # Errors not silenced, like the two setters above: a failed write disables
    # the fallback, and a run that then cannot find its own plan should have
    # something in the transcript explaining why.
    # -string: an untyped value is PARSED, and a plan path containing {, ( or "
    # fails with "Could not parse" rather than being stored.
    "$defaults_tool" write "$prefs_domain" "ThinningPlan:$1" -string "$2"
}

# The recent applets, most recent first, one bundle path per line: the ones opened in a project
# window, made or cloned here. Kept by AppletBuilder (the Welcome window lists them), the same on
# both systems. A path no longer there is dropped from the next list written.
AB_RECENT_LIMIT=12

recent_applets() {
    "$defaults_tool" read "$prefs_domain" RecentApplets 2>/dev/null
    return 0
}

# Puts an applet first on the list; with an empty path it only drops the paths no longer there
recent_applets_add() { # <applet bundle, or "">
    local path="${1%/}"
    local list
    list="$( { printf '%s\n' "$path"; recent_applets; } \
        | while IFS= read -r line; do [ -d "$line" ] && printf '%s\n' "$line"; done \
        | /usr/bin/awk -v limit="$AB_RECENT_LIMIT" '!seen[$0]++ && n < limit { print; n++ }' )"
    # -string: an untyped value is parsed, and a path with {, ( or " would fail to store
    "$defaults_tool" write "$prefs_domain" RecentApplets -string "$list"
}
