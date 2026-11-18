#!/bin/bash
# lib.build.sh - Applet build / rename / icon / codesign pipeline
#
# Sources lib.common.sh (common base), lib.plist.sh (plist_read / plist_write),
# and lib.validate.sh (the per-file validators used by the build's validate phase).
#
# Output goes through the reporters defined in lib.common.sh (ab_log / ab_report /
# ab_confirm); a GUI handler overrides them to drive its windows, the agent CLI
# leaves the stderr defaults in place. Build options that the GUI reads from form
# controls arrive as shell variables the caller sets before invoking applet_build:
#
#   AB_IDENTITY            codesigning identity (default "-" ad-hoc)
#   AB_THIN_ARCH           thin universal binaries to this arch ("none"/empty = skip)
#   AB_FORCE_UPDATE        "1" = force Command.framework/executable refresh
#   AB_WARNINGS_AS_ERRORS  "1" = treat validation warnings as build-halting errors
#   AB_ASSUME_YES          "1" = answer ab_confirm prompts "yes" (e.g. Python upgrade)
#   AB_NO_DESKTOP_ENTRY    "1" = Linux: do not add the applet to the desktop's app list
#                          (test runners, whose applets are temporary)
#   AB_UPDATE_PYTHON       "1" = allow replacing an existing, working embedded Python
#                          with AppletBuilder's runtime (off by default; a missing or
#                          broken runtime is always (re)installed regardless). Replacing
#                          overwrites Contents/Library/Python wholesale and wipes any
#                          packages pip-installed into its site-packages — install
#                          third-party modules into Contents/Library/Packages instead.
#
# The embedded-Python thinning phase at the bottom of this file reads a few more
# (AB_THIN_PYTHON_ACTION, AB_THIN_PLAN, AB_THIN_SKIP_VERIFY); they are documented
# there, next to the code that uses them.

[ -n "$__LIB_BUILD_SH" ] && return 0
__LIB_BUILD_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"
# For the thinning phase alone: where the last plan written for an applet went,
# which is what lets an apply on a distribution copy find the plan that was
# reviewed against the development one.
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

# Update bundle identifier
applet_set_bundle_id() {
    local app_path="$1"
    local bundle_id="$2"

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleIdentifier" "$bundle_id"
    fi
}

# Compile and install icon
applet_install_icon() {
    local icon_source="$1"
    local app_path="$2"

    if [ -z "$icon_source" ] || [ ! -e "$icon_source" ]; then
        return 1
    fi

    local icon_base=$(/usr/bin/basename "${icon_source%.*}")

    local resources_dir="$app_path/Contents/Resources"
    local plist="$app_path/Contents/Info.plist"
    local temp_dir
    temp_dir=$(/usr/bin/mktemp -d)
    if [ $? -ne 0 ] || [ -z "$temp_dir" ]; then
        return 1
    fi
    local success=0
    local source_extension="${icon_source##*.}"

    # macOS: the asset catalog and the .icns, compiled by Xcode's actool (from an .icon)
    if ab_on_macos && [ "$source_extension" != "png" ] && [ "$source_extension" != "svg" ]; then
        /usr/bin/xcrun actool "$icon_source" \
            --compile "$temp_dir" \
            --app-icon "$icon_base" \
            --platform macosx \
            --target-device mac \
            --output-format human-readable-text \
            --minimum-deployment-target 14.6 \
            --output-partial-info-plist "$temp_dir/partial.plist" \
            > "$temp_dir/actool.log" 2>&1

        if [ -f "$temp_dir/Assets.car" ]; then
            /bin/cp "$temp_dir/Assets.car" "$resources_dir/Assets.car"
            success=1
        fi

        if [ -f "$temp_dir/$icon_base.icns" ]; then
            /bin/cp "$temp_dir/$icon_base.icns" "$resources_dir/$icon_base.icns"
            success=1
        fi
    fi

    # Both systems: the icon a Linux applet carries (owner's Q5): an SVG as given; for one of
    # AppletBuilder's own icons the flat SVG it ships; else Resources/<icon>.png, from the .icns
    # just compiled where there is one, or from the source (icon_png.py takes an .icns, an .icon
    # with its .icns beside it, or a .png). Made on macOS too, as one bundle source serves both.
    if [ "$source_extension" = "svg" ]; then
        /bin/cp "$icon_source" "$resources_dir/$icon_base.svg"
        local svg_status=$?
        # On macOS an SVG is not the applet's icon (actool makes nothing from it), so it does
        # not count as installed there: the callers would delete the applet's .icns
        if [ "$svg_status" -eq 0 ] && ! ab_on_macos; then
            success=1
        fi
    else
        # The flat Linux icon shipped beside an .icon or .icns: AppletBuilder's Icons carry one
        # per icon, the rounded tile with the glyph on top (hand-composed until icedit makes
        # them, owner 2026-11-12). Without one, a PNG taken from the .icns.
        local flat_svg="$(ab_shipped_icon_svg "$icon_source")"
        if [ -n "$flat_svg" ]; then
            /bin/cp "$flat_svg" "$resources_dir/$icon_base.svg"
            local flat_status=$?
            if [ "$flat_status" -eq 0 ]; then
                if ! ab_on_macos; then
                    success=1
                fi
            else
                ab_log "Icon SVG not copied: $flat_svg"
            fi
        else
            local png_source="$icon_source"
            if [ -f "$temp_dir/$icon_base.icns" ]; then
                png_source="$temp_dir/$icon_base.icns"
            fi
            local png_output
            png_output=$("$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/icon_png.py" "$png_source" "$resources_dir/$icon_base.png" 2>&1)
            local png_status=$?
            if [ "$png_status" -eq 0 ]; then
                if ! ab_on_macos; then
                    success=1
                fi
            else
                ab_log "Icon PNG not made: ${png_output}"
            fi
        fi
        # Linux: the .icns that comes with the source goes in too (an .icon's sibling, or the
        # .icns itself), so the bundle keeps a macOS icon: the callers remove .icns files of
        # other names, and Linux has no actool to make one
        if ! ab_on_macos && [ "$success" -eq 1 ]; then
            local icns_source=""
            case "$icon_source" in
                *.icon) icns_source="${icon_source%.icon}.icns" ;;
                *.icns) icns_source="$icon_source" ;;
            esac
            if [ -n "$icns_source" ] && [ -f "$icns_source" ]; then
                /bin/cp "$icns_source" "$resources_dir/$icon_base.icns"
            fi
        fi
    fi

    # On macOS the keys are written as they always were; on Linux only for an icon that was
    # installed, so a failed one does not leave the applet pointing at a missing file
    if [ -f "$plist" ] && { ab_on_macos || [ "$success" -eq 1 ]; }; then
        plist_write "$plist" "CFBundleIconFile" "$icon_base"
        plist_write "$plist" "CFBundleIconName" "$icon_base"
    fi
    # The previous icon's PNG or SVG is left in place: Resources may hold images of the applet's
    # own under the same name, and a stale icon file costs only its size

    /bin/rm -rf "$temp_dir"
    return $( [ $success -eq 1 ] && echo 0 || echo 1 )
}

# Linux: adds the applet to the desktop's app list for the current user, or takes it off
# (<install|uninstall> <applet path>), with the framework's linux-app-entry.py (from ActionUI)
# run by AppletBuilder's Python, else the system's. Prints the tool's output and returns its
# status, or prints why and returns 2 when there is no tool or no python3 to run it.
applet_desktop_entry() {
    local action="$1"
    local app_path="$2"
    local entry_tool="$support_tools/linux-app-entry.py"
    if [ ! -f "$entry_tool" ]; then
        entry_tool="$own_support_tools/linux-app-entry.py"
    fi
    local entry_python="$python3"
    if [ ! -x "$entry_python" ]; then
        entry_python="/usr/bin/python3"
    fi
    if [ ! -f "$entry_tool" ] || [ ! -x "$entry_python" ]; then
        printf 'no linux-app-entry.py in the framework, or no python3\n'
        return 2
    fi
    "$entry_python" "$entry_tool" "$action" "$app_path" 2>&1
    local entry_status=$?
    # The applet's file services for the file manager's Services menu go on and off with its entry
    # (command-services.py beside linux-app-entry.py; a framework from before it has none). A services
    # error is said, the entry's status stands: the applet is on the app list either way.
    local services_tool="${entry_tool%/*}/command-services.py"
    if [ "$entry_status" -eq 0 ] && [ -f "$services_tool" ]; then
        local services_output
        services_output="$("$entry_python" "$services_tool" "$action" "$app_path" 2>&1)"
        local services_status=$?
        printf '%s\n' "$services_output"
        if [ "$services_status" -ne 0 ]; then
            printf 'Services not listed: %s\n' "$(printf '%s\n' "$services_output" | /usr/bin/tail -n 1)"
        fi
    fi
    return "$entry_status"
}

# Linux: brings the file managers' Services list of an applet on the desktop up to date with its
# Info.plist (command-services.py install, which also removes the list when no file service is
# left), after the General pane's Services were edited. Nothing on macOS or for an applet with no
# desktop entry: adding it to the desktop lists its services. Prints the tool's last line and
# returns its status; 0 when there is nothing to do.
applet_services_update() {
    local app_path="$1"
    if ab_on_macos; then
        return 0
    fi
    local existing_entry="$(applet_desktop_entry_file "$app_path")"
    if [ -z "$existing_entry" ]; then
        return 0
    fi
    local services_tool="$support_tools/command-services.py"
    if [ ! -f "$services_tool" ]; then
        services_tool="$own_support_tools/command-services.py"
    fi
    local services_python="$python3"
    if [ ! -x "$services_python" ]; then
        services_python="/usr/bin/python3"
    fi
    if [ ! -f "$services_tool" ] || [ ! -x "$services_python" ]; then
        printf 'no command-services.py in the framework, or no python3\n'
        return 2
    fi
    local services_output
    services_output="$("$services_python" "$services_tool" install "$app_path" 2>&1)"
    local services_status=$?
    printf '%s\n' "$services_output" | /usr/bin/tail -n 1
    return "$services_status"
}

# Linux: prints the applet's desktop entry file and returns 0 when it is on the desktop's app list
# (<data home>/applications/<CFBundleIdentifier>.desktop, the data home as linux-app-entry.py
# takes it: an absolute $XDG_DATA_HOME, else ~/.local/share); returns 1, printing nothing, when not.
applet_desktop_entry_file() {
    local app_path="$1"
    local identifier="$(plist_read "$app_path/Contents/Info.plist" CFBundleIdentifier)"
    if [ -z "$identifier" ]; then
        return 1
    fi
    local data_home="$HOME/.local/share"
    case "$XDG_DATA_HOME" in
        /*) data_home="$XDG_DATA_HOME" ;;
    esac
    local entry_file="$data_home/applications/${identifier}.desktop"
    if [ ! -f "$entry_file" ]; then
        return 1
    fi
    printf '%s\n' "$entry_file"
    return 0
}

# Build & Run's Linux button (after Show): "Remove From Desktop" when the applet is on the
# desktop's app list, else "Add To Desktop". macOS has no such button ("type:linux").
ab_desktop_button() { # <project-path>
    if ab_on_macos || [ -z "$1" ]; then
        return 0
    fi
    local entry_file="$(applet_desktop_entry_file "$1")"
    if [ -n "$entry_file" ]; then
        "$dialog_tool" "$window_uuid" "$BUILD_DESKTOP_BTN_ID" omc_set_property "title" "Remove From Desktop"
        "$dialog_tool" "$window_uuid" "$BUILD_DESKTOP_BTN_ID" omc_set_property "systemImage" "minus.square"
    else
        "$dialog_tool" "$window_uuid" "$BUILD_DESKTOP_BTN_ID" omc_set_property "title" "Add To Desktop"
        "$dialog_tool" "$window_uuid" "$BUILD_DESKTOP_BTN_ID" omc_set_property "systemImage" "plus.app"
    fi
}

# Finalize: touch + register with Launch Services (macOS). On Linux an applet that is on the
# desktop's app list (Build & Run's Add To Desktop) gets its entry written again, so the entry
# follows the applet's name and icon; one that is not is left off: builds and saves never add it.
# A failure there is a warning: the applet itself is built.
applet_finalize() {
    local app_path="$1"
    /usr/bin/touch -c "$app_path"
    if ab_on_macos; then
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
            -f -R -trusted "$app_path" 2>/dev/null
        return 0
    fi
    if [ "$AB_NO_DESKTOP_ENTRY" = "1" ]; then
        return 0
    fi
    local existing_entry="$(applet_desktop_entry_file "$app_path")"
    if [ -z "$existing_entry" ]; then
        return 0
    fi
    local entry_output
    entry_output="$(applet_desktop_entry install "$app_path")"
    local entry_status=$?
    if [ "$entry_status" -ne 0 ]; then
        ab_log "  Warning: the desktop entry was not updated: ${entry_output}"
    else
        ab_log "  Desktop entry updated: ${entry_output}"
    fi
    return 0
}

# Rename scripts to match new applet name
applet_rename_scripts() {
    local scripts_dir="$1"
    local old_name="$2"
    local new_name="$3"

    local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
    local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')

    # A loop variable needs declaring as much as any other: `for` assigns at
    # global scope otherwise, leaving a stale path behind for any function that
    # reads a variable of the same name without declaring its own.
    local script

    # Rename script files
    for script in "$scripts_dir"/*; do
        [ ! -f "$script" ] && continue
        local script_base=$(/usr/bin/basename "$script")
        if [[ "$script_base" == "${old_name}."* ]]; then
            local suffix="${script_base#${old_name}.}"
            /bin/mv "$script" "$scripts_dir/${new_name}.${suffix}"
        elif [[ "$script_base" == "${old_lower}."* ]]; then
            local suffix="${script_base#${old_lower}.}"
            /bin/mv "$script" "$scripts_dir/${new_lower}.${suffix}"
        fi
    done

    # Update script contents
    for script in "$scripts_dir"/*; do
        [ ! -f "$script" ] && continue
        sed_in_place "s/${old_name}/${new_name}/g" "$script"
        if [ "$old_lower" != "$old_name" ]; then
            sed_in_place "s/${old_lower}/${new_lower}/g" "$script"
        fi
    done
}

# Update Credits.md with new name
applet_update_credits() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local credits="$app_path/Contents/Resources/Credits.md"
    if [ -f "$credits" ]; then
        sed_in_place "s/${old_name}/${new_name}/g" "$credits"
        local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        if [ "$old_lower" != "$old_name" ]; then
            sed_in_place "s/${old_lower}/${new_lower}/g" "$credits"
        fi
    fi
}

# Derive a URL scheme from an applet name and print it. A scheme must start with a
# letter, then letters, digits, "+", "-" or "." (RFC 3986); this keeps to lowercase
# letters, digits and "-". Leading hyphens are dropped, a name starting with a digit
# gets an "applet-" prefix, and a name with nothing usable left (only non-ASCII, say)
# gets "applet-" plus a checksum of the name, so two such applets still differ.
applet_url_scheme_for_name() {
    local name="$1"
    local scheme=$(printf '%s' "$name" | LC_ALL=C /usr/bin/tr '[:upper:]' '[:lower:]' | LC_ALL=C /usr/bin/tr ' ' '-' | LC_ALL=C /usr/bin/tr -cd 'a-z0-9-')
    while [ "${scheme#-}" != "$scheme" ]; do
        scheme="${scheme#-}"
    done
    local name_sum
    case "$scheme" in
        "")
            name_sum=$(printf '%s' "$name" | /usr/bin/cksum | /usr/bin/awk '{print $1}')
            scheme="applet-$name_sum"
            ;;
        [0-9]*)
            scheme="applet-$scheme"
            ;;
    esac
    printf '%s\n' "$scheme"
}

# Update URL scheme in Info.plist. An applet with no URL type has nothing to update,
# which is not an error. Returns 1, after an ab_report, when Info.plist is unreadable
# or a write fails.
applet_update_url_scheme() {
    local plist="$1"
    local new_name="$2"

    # plister, not plutil: the same on Linux, which has no plutil
    local plister_out
    plister_out=$("$plister_tool" get type "$plist" / 2>&1)
    if [ $? -ne 0 ]; then
        # plister says nothing for a missing or empty file
        [ -n "$plister_out" ] || plister_out="$plist is missing, empty or not a property list"
        ab_report "Cannot update the URL scheme, Info.plist is not readable: $plister_out"
        return 1
    fi

    local url_type=$("$plister_tool" get type "$plist" /CFBundleURLTypes/0 2>/dev/null)
    if [ "$url_type" != "dict" ]; then
        return 0
    fi

    plister_out=$("$plister_tool" insert CFBundleURLName string "$new_name" "$plist" /CFBundleURLTypes/0 2>&1)
    if [ $? -ne 0 ]; then
        ab_report "Could not set the URL name in $plist: $plister_out"
        return 1
    fi

    # Replace the whole array, so the template's scheme does not stay behind: a new empty
    # array (insert replaces the old one), then the one scheme
    local url_scheme=$(applet_url_scheme_for_name "$new_name")
    local plister_status
    plister_out=$("$plister_tool" insert CFBundleURLSchemes array "$plist" /CFBundleURLTypes/0 2>&1)
    plister_status=$?
    if [ "$plister_status" -eq 0 ]; then
        plister_out=$("$plister_tool" add string "$url_scheme" "$plist" /CFBundleURLTypes/0/CFBundleURLSchemes 2>&1)
        plister_status=$?
    fi
    if [ "$plister_status" -ne 0 ]; then
        ab_report "Could not set the URL scheme \"$url_scheme\" in $plist: $plister_out"
        return 1
    fi
    return 0
}

# Full rename pipeline: renames all parts of an applet from old_name to new_name
# Does NOT rename the .app bundle directory or the executable — caller handles those
applet_rename_contents() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local plist="$app_path/Contents/Info.plist"

    # Update Info.plist
    plist_write "$plist" "CFBundleExecutable" "$new_name"
    plist_write "$plist" "CFBundleName" "$new_name"
    plist_write "$plist" "NSAppleEventsUsageDescription" \
        "$new_name sends AppleEvents to other apps to provide functionality unique to this applet."
    applet_update_url_scheme "$plist" "$new_name"
    local url_scheme_rc=$?

    # Update the command file: rename any string value equal to the old app name
    # (NAME, window titles, …). Done per-format so it works for Command.json too.
    local cmd_plist=$(command_file_path "$app_path")
    if [ -f "$cmd_plist" ]; then
        if is_json_command_file "$cmd_plist"; then
            "$python3" \
                "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/json_rename_value.py" \
                "$cmd_plist" "$old_name" "$new_name"
        else
            sed_in_place "s|<string>${old_name}</string>|<string>${new_name}</string>|" "$cmd_plist"
        fi
    fi

    # Rename and update scripts
    applet_rename_scripts "$app_path/Contents/Resources/Scripts" "$old_name" "$new_name"

    # Update Credits.md
    applet_update_credits "$app_path" "$old_name" "$new_name"

    # Only the URL scheme step is checked. Its failure (already reported) is returned
    # after the other steps have run, so the applet is not left half-renamed.
    return "$url_scheme_rc"
}

# Give the applet's executable a Mach-O UUID of its own, derived from the bundle
# identifier. The executable is a copy of AppletBuilder's, so without this every
# applet has the same UUID, and macOS, which identifies a program by it for Local
# Network privacy, asks about and lists whichever applet the Mac saw first. The UUID
# depends only on the bundle identifier, so it survives rebuilds and engine updates
# and the user is not asked again. See macho_set_uuid.py.
#
# Called from applet_codesign and nowhere else: rewriting the UUID breaks the
# signature, and an arm64 executable with a broken signature does not run, so the
# stamp may only happen where a signing follows. A failure is reported and is not
# fatal: the applet works as before, with the shared UUID.
applet_stamp_executable_uuid() {
    local app_path="$1"
    local bundle_id="$(plist_read "$app_path/Contents/Info.plist" CFBundleIdentifier)"
    local exe_name="$(plist_read "$app_path/Contents/Info.plist" CFBundleExecutable)"
    if [ -z "$bundle_id" ] || [ -z "$exe_name" ] || [ ! -f "$app_path/Contents/MacOS/$exe_name" ]; then
        ab_log "Executable UUID not set: no bundle identifier or executable in ${app_path}."
        return 1
    fi
    local stamp_output
    stamp_output=$("$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/macho_set_uuid.py" "$app_path/Contents/MacOS/$exe_name" "$bundle_id" 2>&1)
    local stamp_status=$?
    if [ "$stamp_status" -ne 0 ]; then
        ab_log "Warning: the executable's UUID could not be set (exit ${stamp_status}): ${stamp_output}"
        ab_log "The applet shares its UUID with other applets; macOS may name another applet when it asks for Local Network access."
        return 1
    fi
    ab_log "Executable UUID for ${bundle_id}:"
    ab_log "$stamp_output"
    # Whether bytes were written, for applet_codesign: an unchanged file still has
    # the signature it had.
    case "$stamp_output" in
        *" -> "*) AB_UUID_WRITTEN="$app_path/Contents/MacOS/$exe_name" ;;
    esac
    return 0
}

# Codesign using the standalone script, after giving the executable its own UUID. On Linux an
# applet is not signed and its ELF executable has no Mach-O UUID: nothing to do (owner's Q3).
applet_codesign() {
    local app_path="$1"
    local identity="$2"
    AB_UUID_WRITTEN=""
    if ! ab_on_macos; then
        ab_log "Not code signed: Linux applets carry no signature."
        return 0
    fi
    applet_stamp_executable_uuid "$app_path"
    /bin/sh "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/codesign_applet.sh" "$app_path" "$identity"
    local sign_status=$?
    # A failed signing (a wrong identity, a locked keychain) after the UUID was written
    # leaves an executable whose old signature no longer matches, which macOS kills at
    # launch on Apple silicon. Before the stamp existed such an applet still launched
    # on the signature it came with, so give the executable an ad hoc one: the applet
    # is not signed as asked, and the failure is still returned, but it runs.
    if [ "$sign_status" -ne 0 ] && [ -n "$AB_UUID_WRITTEN" ]; then
        /usr/bin/codesign --force --sign - "$AB_UUID_WRITTEN" > /dev/null 2>&1
        local adhoc_status=$?
        if [ "$adhoc_status" -eq 0 ]; then
            ab_log "Signing failed; the executable was signed ad hoc so that the applet still launches."
        else
            ab_log "Signing failed, and the executable could not be signed ad hoc either: the applet will not launch until a build signs it."
        fi
    fi
    return "$sign_status"
}

# ──────────────────────────────────────────────────────────────
# Build pipeline
#
# Validate the project, refresh the framework/executable/Python runtime from
# AppletBuilder, thin and codesign. Shared by the GUI Build & Run pane and the
# agent CLI; see the AB_* variables documented at the top of this file. All
# progress/error output goes through ab_log / ab_report / ab_confirm.
# ──────────────────────────────────────────────────────────────

# Compare two version strings: prints "newer", "older", or "same"
compare_versions() {
    local v1="$1"
    local v2="$2"
    local v1_major=$(echo "$v1" | /usr/bin/cut -d. -f1)
    local v1_minor=$(echo "$v1" | /usr/bin/cut -d. -f2)
    local v1_patch=$(echo "$v1" | /usr/bin/cut -d. -f3)
    local v2_major=$(echo "$v2" | /usr/bin/cut -d. -f1)
    local v2_minor=$(echo "$v2" | /usr/bin/cut -d. -f2)
    local v2_patch=$(echo "$v2" | /usr/bin/cut -d. -f3)
    v1_major=${v1_major:-0}; v1_minor=${v1_minor:-0}; v1_patch=${v1_patch:-0}
    v2_major=${v2_major:-0}; v2_minor=${v2_minor:-0}; v2_patch=${v2_patch:-0}

    if [ "$v1_major" -gt "$v2_major" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_major" -lt "$v2_major" ] 2>/dev/null; then echo "older"; return; fi
    if [ "$v1_minor" -gt "$v2_minor" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_minor" -lt "$v2_minor" ] 2>/dev/null; then echo "older"; return; fi
    if [ "$v1_patch" -gt "$v2_patch" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_patch" -lt "$v2_patch" ] 2>/dev/null; then echo "older"; return; fi
    echo "same"
}

# Strip the com.apple.quarantine attribute Gatekeeper attaches to files brought
# in from another machine (e.g. an applet codesigned locally elsewhere). Left in
# place it makes codesign / launch report the applet as "damaged". Best-effort
# and recursive over the whole bundle; runs before anything else.
strip_quarantine() {
    local target_path="$1"
    # macOS's download quarantine; Linux has none
    if ! ab_on_macos; then
        return 0
    fi
    ab_log "Stripping quarantine attribute..."
    /usr/bin/xattr -r -d com.apple.quarantine "$target_path" 2>/dev/null
    return 0
}

# Heuristic: return 0 (true) if a JSON file looks like an ActionUI declaration.
# ActionUI JSON has a root dictionary whose values are element dicts containing
# a "type" key.  Non-ActionUI JSON (e.g. Info.plist-style arrays, bare values,
# or unrelated dictionaries) will return 1.
is_actionui_json() {
    local file="$1"
    local checker="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/is_actionui_json.py"
    "$python3" "$checker" "$file" 2>/dev/null
}

# Copy the app executable from AppletBuilder to target (with proper name)
copy_executable() {
    local target_path="$1"
    local src_exe_name="$(plist_read "${OMC_APP_BUNDLE_PATH}/Contents/Info.plist" CFBundleExecutable)"
    local dst_exe_name="$(plist_read "$target_path/Contents/Info.plist" CFBundleExecutable)"
    local exe_folder="$(applet_executable_folder "$target_path")"
    /bin/mkdir -p "$exe_folder"
    # Remove the old executable first, so the copy is a new file. Copied over, the file is rewritten
    # in place: a running copy of the applet then fails its code signature checks, and macOS kills
    # every process that maps the file afterwards (lipo, codesign), so the build fails at thinning.
    # A running applet keeps the removed file until it quits.
    if [ -n "$dst_exe_name" ]; then
        /bin/rm -f "$exe_folder/$dst_exe_name"
    fi
    /bin/cp -p "$(applet_executable_folder "$OMC_APP_BUNDLE_PATH")/$src_exe_name" \
               "$exe_folder/$dst_exe_name"
    ab_log "Executable updated: $dst_exe_name"
}

# Linux: the applet's install script, Contents/Linux/install-applet.sh (it checks what the applet
# needs from the system and adds it to the desktop, also before the applet can start), copied from
# AppletBuilder's own Resources/Linux on every build, so an applet always has the newest. Nothing on
# macOS.
update_linux_installer() {
    local target_path="$1"
    if ab_on_macos; then
        return 0
    fi
    local installer_source="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Linux/install-applet.sh"
    local exe_folder="$(applet_executable_folder "$target_path")"
    if [ ! -f "$installer_source" ]; then
        ab_log "No install script in AppletBuilder ($installer_source): the applet gets none"
        return 0
    fi
    /bin/mkdir -p "$exe_folder"
    /bin/cp -- "$installer_source" "$exe_folder/install-applet.sh"
    local copy_status=$?
    if [ "$copy_status" -ne 0 ]; then
        ab_log "Cannot copy the install script into $exe_folder"
        return 1
    fi
    /bin/chmod 755 "$exe_folder/install-applet.sh"
    return 0
}

# What an applet needs from a Linux system beyond the command-engine and Swift runtime packages,
# which it lists in its Info.plist (CommandEngineLinuxRequires, sonames) for its Linux install script
# (install-applet.sh --check, --install-packages), added to the list, so a library the author lists by
# hand stays (one the author no longer needs is not taken away):
# - the libraries ActionUI loads by name for the elements its documents use: a WebView needs
#   WebKitGTK, a Map libshumate. Found from every ActionUI document in the bundle's Resources (any
#   *.json, also in *.lproj; not in a Documentation folder, whose element documents are examples). On
#   both systems: the list must be right when an applet built on a Mac is made into a Linux bundle.
# - on Linux, what the applet's own programs link (linux_program_requires).
update_linux_requires() {
    local target_path="$1"
    local resources="$target_path/Contents/Resources"
    local info_plist="$target_path/Contents/Info.plist"
    if [ ! -d "$resources" ] || [ ! -f "$info_plist" ]; then
        return 0
    fi
    # One "<soname><TAB><why>" line per library
    local tab="$(printf '\t')"
    local wanted=""
    local element
    local soname
    local found
    # "type:linux" too: ActionUI's platform filter makes it the element's type on Linux
    for element in WebView:libwebkitgtk-6.0.so.4 Map:libshumate-1.0.so.1; do
        found="$(/usr/bin/grep -rlE --include='*.json' --exclude-dir=Documentation "\"type(:linux)?\"[[:space:]]*:[[:space:]]*\"${element%%:*}\"" "$resources" 2>/dev/null | /usr/bin/head -n 1)"
        if [ -n "$found" ]; then
            wanted="$wanted${element#*:}${tab}a ${element%%:*}
"
        fi
    done
    if ! ab_on_macos; then
        wanted="$wanted$(linux_program_requires "$target_path")"
    fi
    if [ -z "$wanted" ]; then
        return 0
    fi
    local key_type="$("$plister_tool" get type "$info_plist" /CommandEngineLinuxRequires 2> /dev/null)"
    if [ -z "$key_type" ]; then
        "$plister_tool" insert CommandEngineLinuxRequires array "$info_plist" / > /dev/null
        local insert_status=$?
        if [ "$insert_status" -ne 0 ]; then
            ab_log "Cannot add CommandEngineLinuxRequires to the Info.plist"
            return 1
        fi
    elif [ "$key_type" != "array" ]; then
        ab_log "CommandEngineLinuxRequires in the Info.plist is not a list: left as it is"
        return 0
    fi
    local listed=" "
    local count="$("$plister_tool" get count "$info_plist" /CommandEngineLinuxRequires 2> /dev/null)"
    case "$count" in
        ''|*[!0-9]*) count=0 ;;
    esac
    local index=0
    while [ "$index" -lt "$count" ]; do
        listed="$listed$("$plister_tool" get value "$info_plist" "/CommandEngineLinuxRequires/$index" 2> /dev/null) "
        index=$((index + 1))
    done
    local why
    local line
    local append_status
    # A pipe, not process substitution, which bash in POSIX mode refuses when it reads this file;
    # the loop's subshell reports a failed append through its exit status. The lines come on
    # descriptor 3 and the loop's standard input is /dev/null: plister reads its standard input,
    # and would take the rest of the lines
    printf '%s\n' "$wanted" | while IFS= read -r line <&3; do
        if [ -z "$line" ]; then
            continue
        fi
        soname="${line%%"$tab"*}"
        why="${line#*"$tab"}"
        case "$listed" in
            *" $soname "*) continue ;;
        esac
        "$plister_tool" append string "$soname" "$info_plist" /CommandEngineLinuxRequires > /dev/null
        append_status=$?
        if [ "$append_status" -ne 0 ]; then
            ab_log "Cannot add $soname to CommandEngineLinuxRequires"
            exit 1
        fi
        listed="$listed$soname "
        ab_log "Linux: the applet needs $soname ($why); listed in CommandEngineLinuxRequires"
    done 3<&0 < /dev/null
    local loop_status="${PIPESTATUS[1]}"
    if [ "$loop_status" != "0" ]; then
        return 1
    fi
    return 0
}

# Linux only: what the applet's own programs and libraries link (ELF NEEDED) that neither the bundle
# nor the command-engine and Swift runtime packages provide, one "<soname><TAB><why>" line each. Its
# own: every file outside the engine's (Contents/Linux, Contents/Frameworks/Command.framework) and
# the macOS folders that is executable or named *.so*: its helpers (Contents/Helpers), programs and
# libraries in Resources and Library, an embedded Python's modules. Those packages provide what the
# engine programs link (the command-engine package depends on exactly those) and the Swift runtime
# libraries (in the folders on the engine programs' library search path); a library inside the
# bundle needs nothing from the system, and glibc's own libraries are on every system. Read with
# Resources/Linux/elf-needed.py (python3, which the command-engine package brings; no readelf on a
# user's machine).
linux_program_requires() { # <applet bundle>
    local contents="$1/Contents"
    local reader="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Linux/elf-needed.py"
    if [ ! -f "$reader" ] || [ ! -x /usr/bin/python3 ]; then
        ab_log "Linux: no $reader or /usr/bin/python3: the applet's programs' libraries are not listed"
        return 0
    fi
    local file
    local needed
    needed="$(/usr/bin/find "$contents" \( -path "$contents/Linux" -o -path "$contents/Frameworks/Command.framework" -o -path "$contents/MacOS" -o -path "$contents/_CodeSignature" \) -prune -o -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) -exec /usr/bin/python3 -I "$reader" needed {} +)"
    local read_status=$?
    if [ "$read_status" -ne 0 ]; then
        ab_log "Linux: some of the applet's programs could not be read (above); their libraries may be missing from the list"
    fi
    if [ -z "$needed" ]; then
        return 0
    fi

    # What is there without the applet's list: glibc's, the bundle's own, the engine's, the runtime's
    local provided=" libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libutil.so.1 libresolv.so.2 libanl.so.1 libmvec.so.1 ld-linux-aarch64.so.1 ld-linux-x86-64.so.2 "
    provided="$provided$(/usr/bin/find "$contents" \( -name '*.so' -o -name '*.so.*' \) -printf '%f ' 2>/dev/null) "
    local engine_programs=()
    for file in "$contents/Linux"/* "$contents/Frameworks/Command.framework/Support"/*; do
        if [ -f "$file" ]; then
            engine_programs+=("$file")
        fi
    done
    local engine_needed=""
    local runpath=""
    if [ ${#engine_programs[@]} -gt 0 ]; then
        engine_needed="$(/usr/bin/python3 -I "$reader" needed "${engine_programs[@]}" | /usr/bin/cut -f 1 | /usr/bin/sort -u | /usr/bin/tr '\n' ' ')"
        for file in "${engine_programs[@]}"; do
            runpath="$(/usr/bin/python3 -I "$reader" runpath "$file")"
            if [ -n "$runpath" ]; then
                break
            fi
        done
    fi
    provided="$provided$engine_needed "
    local folder
    local old_ifs="$IFS"
    IFS=":"
    local folders=($runpath)
    IFS="$old_ifs"
    for folder in "${folders[@]}"; do
        if [ -d "$folder" ]; then
            for file in "$folder"/*.so*; do
                if [ -f "$file" ]; then
                    provided="$provided${file##*/} "
                fi
            done
        fi
    done

    local tab="$(printf '\t')"
    local bundle="$1"
    local line
    local soname
    local listed=" "
    printf '%s\n' "$needed" | while IFS= read -r line; do
        soname="${line%%"$tab"*}"
        file="${line#*"$tab"}"
        case "$provided$listed" in
            *" $soname "*) continue ;;
        esac
        listed="$listed$soname "
        printf '%s\t%s\n' "$soname" "needed by ${file#"$bundle/"}"
    done
    return 0
}

# Install or update Command.framework and executable
update_framework() {
    local target_path="$1"
    local src_fw="${OMC_APP_BUNDLE_PATH}/Contents/Frameworks/Command.framework"
    local dst_fw="$target_path/Contents/Frameworks/Command.framework"
    local src_version=$(plist_read "$(framework_info_plist "$src_fw")" CFBundleVersion)

    # Before 6.0 the engine was Abracode.framework, and the applet's executable links that name: the
    # old framework goes, and the new one and a new executable come in below (the executable's
    # signature and the Linux install script follow in the rest of the build). A Command.framework
    # beside the old one goes too, so the install below always brings the new executable: the
    # version check would otherwise keep the old executable, which then finds no engine.
    local old_fw="$target_path/Contents/Frameworks/Abracode.framework"
    if [ -d "$old_fw" ]; then
        ab_log "Replacing Abracode.framework (before 6.0) with Command.framework v${src_version}"
        /bin/rm -rf "$old_fw" "$dst_fw"
        local old_status=$?
        if [ "$old_status" -ne 0 ]; then
            ab_log "Cannot remove $old_fw"
        fi
    fi

    if [ ! -d "$dst_fw" ]; then
        ab_log "Command.framework missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Frameworks"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local dst_version=$(plist_read "$(framework_info_plist "$dst_fw")" CFBundleVersion)
    local force_update="$AB_FORCE_UPDATE"

    if [ "$force_update" = "1" ] || [ "$force_update" = "true" ]; then
        ab_log "Updating Command.framework: v${dst_version} -> v${src_version} (forced)"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local cmp=$(compare_versions "$src_version" "$dst_version")

    if [ "$cmp" = "newer" ]; then
        ab_log "Updating Command.framework: v${dst_version} -> v${src_version}"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
    else
        ab_log "Command.framework v${dst_version} is current"
    fi
}

# Get Python major.minor version string from a Python install directory
python_version() {
    local python_dir="$1"
    "$python_dir/bin/python3" --version 2>/dev/null | /usr/bin/awk '{print $2}'
}

# Install or update embedded Python runtime for Python applets
update_python() {
    local target_path="$1"
    local src_python="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python"
    local dst_python="$target_path/Contents/Library/Python"

    # Check if target has Python scripts
    if ! /usr/bin/find "$target_path/Contents/Resources/Scripts" -name "*.py" -print -quit 2>/dev/null | /usr/bin/grep -q .; then
        return
    fi

    if [ ! -d "$src_python" ]; then
        return
    fi

    local src_version=$(python_version "$src_python")

    if [ ! -d "$dst_python" ]; then
        ab_log "Python runtime missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Library"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    local dst_version=$(python_version "$dst_python")

    if [ -z "$dst_version" ]; then
        ab_log "Python runtime broken — reinstalling v${src_version}"
        /bin/rm -rf "$dst_python"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    if [ "$src_version" = "$dst_version" ]; then
        ab_log "Python v${dst_version} is current"
        return
    fi

    local cmp=$(compare_versions "$src_version" "$dst_version")

    # Applet already has a newer Python than AppletBuilder (older builder).
    # Replacing would DOWNGRADE the runtime and likely break the applet's
    # scripts and site-packages — never do that automatically.
    if [ "$cmp" = "older" ]; then
        ab_log "Applet has newer Python v${dst_version} than AppletBuilder (v${src_version}) — keeping the applet's runtime."
        ab_log "Update AppletBuilder to manage this applet's Python."
        return
    fi

    # Replacing a working runtime is opt-in: it overwrites Contents/Library/Python
    # wholesale, wiping anything pip-installed into its site-packages. Off by default
    # so inline-installed modules survive a rebuild. It is independent of the binary
    # refresh (AB_FORCE_UPDATE / --force): enable the "Update Embedded Python" build
    # option (CLI: --update-python) to allow it. The rebuild-safe place for
    # third-party modules is Contents/Library/Packages, which OMC adds to PYTHONPATH
    # and this build step never touches.
    if [ "${AB_UPDATE_PYTHON:-0}" != "1" ]; then
        ab_log "Embedded Python v${dst_version} kept (AppletBuilder has v${src_version}; enable \"Update Embedded Python\" to replace it)."
        return
    fi

    # From here AppletBuilder's Python is newer than the applet's.
    local src_major=$(echo "$src_version" | /usr/bin/cut -d. -f1-2)
    local dst_major=$(echo "$dst_version" | /usr/bin/cut -d. -f1-2)

    if [ "$src_major" != "$dst_major" ]; then
        # Major/minor upgrade — confirm, since it may break dependencies.
        if ab_confirm "Applet has Python ${dst_version}. AppletBuilder has newer Python ${src_version}. Upgrading may break dependencies. Upgrade?"; then
            ab_log "Upgrading Python: v${dst_version} -> v${src_version}"
            /bin/rm -rf "$dst_python"
            /bin/cp -Rp "$src_python" "$dst_python"
        else
            ab_log "Keeping Python v${dst_version} (user choice)"
        fi
        return
    fi

    # Same major.minor, builder has newer patch — upgrade silently.
    ab_log "Updating Python: v${dst_version} -> v${src_version}"
    /bin/rm -rf "$dst_python"
    /bin/cp -Rp "$src_python" "$dst_python"
}

# Install the OMC-supplied Python modules into an applet that has Python handlers.
#
# Contents/Library/Packages is the applet's own module directory: the engine prepends it to
# PYTHONPATH whenever the applet embeds Python, and update_python never touches it, so these
# survive a runtime upgrade that wipes Contents/Library/Python wholesale. A developer's own
# pip --target installs sit alongside them.
#
# Requires BOTH a Python handler and an embedded runtime. Without the runtime the engine does not
# put Packages on PYTHONPATH at all, so copying there would ship modules the applet cannot import.
# Overwrites unconditionally: these ship with OMC and are versioned with it, like the framework.
#
# Returns 1 when an applet that SHOULD have the modules could not get them, and applet_build halts
# on that. Signing an applet whose handlers will fail with ModuleNotFoundError on first run, after
# reporting "Build succeeded", is worse than refusing to sign it.
update_python_packages() {
    local target_path="$1"
    local src_packages="${OMC_APP_BUNDLE_PATH}/Contents/Library/Packages"
    local dst_packages="$target_path/Contents/Library/Packages"

    local _py_handlers=$(/usr/bin/find "$target_path/Contents/Resources/Scripts" -name "*.py" -print -quit 2>/dev/null)
    if [ -z "$_py_handlers" ]; then
        return
    fi

    if [ ! -d "$target_path/Contents/Library/Python" ]; then
        # External-interpreter applet. The engine only puts Packages on PYTHONPATH for an embedded
        # runtime, so the modules would be unimportable; say so rather than skipping in silence.
        ab_log "Python handlers but no embedded runtime - skipping the Command Workshop Python modules (they would not be importable)"
        return 0
    fi

    if [ ! -d "$src_packages" ]; then
        ab_report "Error: Command Workshop Python modules not found at $src_packages"
        ab_report "       This AppletBuilder predates them; rerun update_appletbuilder.sh."
        return 1
    fi

    /bin/mkdir -p "$dst_packages"
    local _mkdir_rc=$?
    if [ "$_mkdir_rc" -ne 0 ]; then
        ab_report "Error: could not create $dst_packages"
        return 1
    fi

    local module
    local copied=0
    local failed=0
    local _cp_rc
    for module in actionui_remote.py omc.py; do
        if [ ! -f "$src_packages/$module" ]; then
            ab_report "Error: $module is missing from AppletBuilder; rerun update_appletbuilder.sh"
            failed=$((failed + 1))
            continue
        fi

        /bin/cp "$src_packages/$module" "$dst_packages/$module"
        _cp_rc=$?
        if [ "$_cp_rc" -ne 0 ]; then
            ab_report "Error: could not copy $module to $dst_packages"
            failed=$((failed + 1))
            continue
        fi
        copied=$((copied + 1))
    done

    if [ "$copied" -gt 0 ]; then
        ab_log "Installed $copied Command Workshop Python module(s) into Contents/Library/Packages"
    fi

    if [ "$failed" -gt 0 ]; then
        return 1
    fi
    return 0
}

# The ActionUI remote bridge's shell clients, into Contents/Library/Packages beside the Python
# one. Gated on a shell handler rather than on a Python runtime, because a shell handler needs no
# runtime - and it is the one kind of handler that can hold the bridge's token without showing it
# to `ps`, every Apple shell carrying CS_RESTRICT where python3 and node do not.
#
# All four files or none: actionui_remote.zsh sources actionui_remote.sh from its own directory,
# and actionui_remote.sh reads its two awk programs from there and refuses to load without them.
# Overwritten unconditionally, like the Python modules: these ship with OMC and version with it.
#
# Not fatal to a build. A shell handler that never touches the bridge - which is most of them -
# is not broken by their absence, so a missing client is reported and the build goes on. That is
# the opposite of update_python_packages, where the modules ARE the handler's imports.
update_shell_clients() {
    local target_path="$1"
    local src_packages="${OMC_APP_BUNDLE_PATH}/Contents/Library/Packages"
    local dst_packages="$target_path/Contents/Library/Packages"

    # Named once: the rollback below has to remove exactly what the copy loop writes, and two
    # lists that have to agree are a list that eventually will not.
    local clients="actionui_remote.sh actionui_remote.zsh actionui_remote_escape.awk actionui_remote_walk.awk"

    local _sh_handlers=$(/usr/bin/find "$target_path/Contents/Resources/Scripts" \
                   \( -name "*.sh" -o -name "*.zsh" \) -print -quit 2>/dev/null)
    if [ -z "$_sh_handlers" ]; then
        return 0
    fi

    # Installing into the directory the files are read from is a no-op, and must be treated as
    # one: cp refuses identical files, and the rollback below would then take AppletBuilder's own
    # copies out. Physical paths, so that a symlinked route to the same directory counts as same.
    # CDPATH cleared for the same reason the client clears it: the destination arrives from the
    # command line unresolved, so it can be a relative path, and a CDPATH hit would send cd
    # somewhere else and print where it went into the capture.
    local _src_real=$(CDPATH= cd -P -- "$src_packages" 2>/dev/null && pwd -P)
    local _dst_real=$(CDPATH= cd -P -- "$dst_packages" 2>/dev/null && pwd -P)
    if [ -n "$_src_real" ] && [ "$_src_real" = "$_dst_real" ]; then
        return 0
    fi

    local client
    local missing=0
    for client in $clients; do
        if [ ! -f "$src_packages/$client" ]; then
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        ab_log "ActionUI shell client(s) missing from AppletBuilder - skipping (rerun update_appletbuilder.sh)"
        return 0
    fi

    /bin/mkdir -p "$dst_packages"
    local _mkdir_rc=$?
    if [ "$_mkdir_rc" -ne 0 ]; then
        ab_log "Could not create $dst_packages - skipping the ActionUI shell clients"
        return 0
    fi

    local copied=0
    local incomplete=0
    local _cp_rc
    local _chmod_rc
    local _mode
    for client in $clients; do
        /bin/cp "$src_packages/$client" "$dst_packages/$client"
        _cp_rc=$?
        if [ "$_cp_rc" -ne 0 ]; then
            ab_log "Could not copy $client to $dst_packages"
            incomplete=1
            break
        fi

        # A client is sourced, and may also be run as a command; an awk program is read by awk
        # and never run, so it stays data.
        case "$client" in
            *.awk) _mode=644 ;;
            *)     _mode=755 ;;
        esac
        /bin/chmod "$_mode" "$dst_packages/$client"
        _chmod_rc=$?
        if [ "$_chmod_rc" -ne 0 ]; then
            ab_log "Could not set mode $_mode on $client in $dst_packages"
            incomplete=1
            break
        fi
        copied=$((copied + 1))
    done

    # All four or none applies to what lands, not only to what was there to copy. Three of four
    # is a client that refuses to load, which is worse for the handler than never having one, so
    # an install that does not complete takes the whole set out again. Note what that means when
    # the applet already had a good set and the first copy failed: it loses that set too. A stale
    # set is not what this build would have shipped either, and the alternative is deciding which
    # of the four on disk are each other's version - which nothing here can tell.
    if [ "$incomplete" -ne 0 ]; then
        for client in $clients; do
            /bin/rm -f "$dst_packages/$client"
        done
        ab_log "Removed the ActionUI shell client set from $dst_packages - the install did not complete"
        return 0
    fi

    if [ "$copied" -gt 0 ]; then
        ab_log "Installed $copied ActionUI shell client file(s) into $dst_packages"
    fi
    return 0
}

# Remove development junk from the applet.
#
# Must run immediately before codesigning: almost anything still present is
# sealed into CodeResources, and deleting it afterward invalidates the
# signature. (.DS_Store is the lone exception - codesign carries an omit rule
# for it - but nothing else on these lists is forgiven.)
#
# An OMC applet is edited in place - the .app bundle IS the project - and the
# copy that gets signed and notarized is made from it. So junk left here does
# not just clutter a working directory, it ships. Editor and agent config
# (.claude, .idea, .vscode), tool caches and Finder, Windows and KDE droppings are all removed
# outright; anything worth keeping belongs outside the bundle.
#
# .git is deliberately NOT swept: deleting a versioned applet's history during
# a routine build would be unrecoverable, which is a different order of harm
# than losing a settings file. It is reported instead, because a versioned
# applet still carries its whole repository into the signed copy.
#
# Internal, not a caller option: AB_ABORTING="1" says the build is already halting,
# so a surviving-junk warning must not talk about what will be signed. Initialized
# here rather than left to the environment, or `AB_ABORTING=1 appletbuilder build`
# would quietly downgrade that report for a whole ordinary build.
#
# Returns 1 only when junk survived the sweep and AB_WARNINGS_AS_ERRORS is set;
# a surviving item is a permanent defect in the signed artifact, so that case
# halts the build rather than signing over it.
AB_ABORTING=0

clean_build_junk() {
    local target_path="$1"

    # find descends nothing when handed a symlink as its start path, so a
    # symlinked project would sweep zero files and still report success - the
    # one false green this function's before/after accounting cannot catch.
    # Resolve to the physical path first. (The CLI's own `[ ! -d ]` guard
    # follows symlinks, so `appletbuilder build ~/link-to-MyApp.app` reaches
    # here.)
    # CDPATH= : cd searches $CDPATH for a relative operand, and this function runs
    # rm under whatever it resolves to.
    target_path=$(CDPATH= cd -P -- "$target_path" >/dev/null 2>&1 && /bin/pwd -P)
    if [ -z "$target_path" ]; then
        ab_report "Error: could not resolve the project path to sweep for junk"
        return 1
    fi

    # Every pattern is quoted individually, and that - not the array - is what
    # keeps it literal: array construction globs like any other word expansion,
    # so a bare *.pyc here would expand against the current directory before
    # find saw it. Containers are listed before __pycache__ so nested junk
    # inside a swept container is not counted twice.
    local junk_dirs=( ".claude" ".idea" ".vscode" ".pytest_cache" ".mypy_cache" ".ruff_cache" "__pycache__" )
    # *.thin.tmp is thin_distribution.sh's scratch file, left beside a real
    # Mach-O if lipo is interrupted rather than merely failing. .directory is
    # KDE's folder settings file: a Linux applet writes one at its bundle root
    # for its Dolphin folder icon (Linux/install-applet.sh), and a file there,
    # outside Contents, makes codesign refuse the bundle ("unsealed contents
    # present in the bundle root"). Removing it costs nothing on Linux, where
    # the applet's next launch writes it again.
    local junk_files=( ".DS_Store" "._*" "*.pyc" "*.pyo" "*.thin.tmp" "Thumbs.db" ".directory" )
    # Losing one of these costs developer config rather than a regenerable
    # cache, and rm does not use the Trash, so name each path instead of
    # folding it into a count.
    local loud_dirs=" .claude .idea .vscode "

    local junk before after removed path
    local stuck=0
    local header=0

    # Counts are the difference between a scan before and a scan after the
    # delete, never the pre-scan alone: rm and -delete have their errors
    # discarded here, so a sweep that fails on a locked or root-owned path
    # would otherwise report success and let the junk be signed in anyway.
    for junk in "${junk_dirs[@]}"; do
        # -prune keeps find from descending into a directory it is about to
        # delete and then complaining about the paths that just vanished.
        # -type l alongside -type d for the same reason the file sweep needs it:
        # a symlink named __pycache__ or .claude is sealed just like a real
        # directory, and -type d walks straight past it. rm -rf on a symlink
        # removes the link, never the target.
        before=$(/usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        if [ "$header" -eq 0 ]; then
            ab_log ""
            ab_log "Removing development junk..."
            header=1
        fi
        case "$loud_dirs" in
            *" $junk "*)
                /usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | while read -r path; do
                    ab_log "  removing ${path#"$target_path"/}"
                done
                ;;
        esac
        /usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune -exec /bin/rm -rf {} + 2>/dev/null
        after=$(/usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        removed=$((before - after))
        if [ "$removed" -gt 0 ]; then
            ab_log "Removed ${removed} ${junk} director$([ "$removed" -eq 1 ] && echo "y" || echo "ies")"
        fi
        if [ "$after" -gt 0 ]; then
            ab_log "WARNING: ${junk}: ${after} of ${before} could not be removed"
            stuck=$((stuck + after))
        fi
    done

    # -type l as well as -type f: a symlink named ._x or stale.pyc is junk that
    # gets sealed just the same, and -type f alone walks straight past it.
    # -iname because a Windows SMB client writes thumbs.db onto a
    # case-insensitive volume and -name "Thumbs.db" would miss it.
    for junk in "${junk_files[@]}"; do
        before=$(/usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        if [ "$header" -eq 0 ]; then
            ab_log ""
            ab_log "Removing development junk..."
            header=1
        fi
        /usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" -delete 2>/dev/null
        after=$(/usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        removed=$((before - after))
        if [ "$removed" -gt 0 ]; then
            ab_log "Removed ${removed} ${junk} file$([ "$removed" -eq 1 ] && echo "" || echo "s")"
        fi
        if [ "$after" -gt 0 ]; then
            ab_log "WARNING: ${junk}: ${after} of ${before} could not be removed"
            stuck=$((stuck + after))
        fi
    done

    # Never deleted, only reported - losing a versioned applet's history to a
    # routine build is not a tradeoff this function gets to make for anyone.
    local vcs
    for vcs in ".git" ".svn"; do
        before=$(/usr/bin/find "$target_path" -type d -name "$vcs" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        # ab_log, not ab_report: this fires on every build of a versioned
        # applet, and in the GUI ab_report is an error window. A recurring
        # popup the developer learns to dismiss would devalue the one report
        # below that actually means the artifact is broken.
        ab_log "WARNING: ${vcs} left in place (not removed); it will be sealed into the signed copy"
    done

    if [ "$stuck" -gt 0 ]; then
        # AB_ABORTING is set by a caller that is already halting the build. The
        # sweep still runs and still says what survived, but "will be signed into
        # the applet" would be a claim about a signing that is not going to happen -
        # and in the GUI ab_report is an error window, which would reach the user
        # ahead of the caller's own report of why the build stopped.
        if [ "$AB_ABORTING" = "1" ]; then
            ab_log "WARNING: ${stuck} junk item(s) survived the sweep"
        else
            ab_report "WARNING: ${stuck} junk item(s) survived and will be signed into the applet"
        fi
        [ "$AB_WARNINGS_AS_ERRORS" = "1" ] && return 1
    fi
    return 0
}

# Thin universal binaries to a single architecture (AB_THIN_ARCH).
# Must run before codesigning — modifying binaries invalidates their signatures.
thin_binaries() {
    local target_path="$1"
    local arch="$AB_THIN_ARCH"

    if [ -z "$arch" ] || [ "$arch" = "none" ]; then
        return
    fi
    # A Linux applet holds one executable for one architecture, as the Linux build makes it, and
    # its Python is single-architecture too: nothing to slice (owner's Q4)
    if ! ab_on_macos; then
        ab_log ""
        ab_log "Thinning to ${arch} skipped: a Linux applet already holds one architecture."
        return 0
    fi

    ab_log ""
    ab_log "Thinning universal executables to ${arch}..."
    local thin_output
    thin_output=$(/bin/bash "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/thin_distribution.sh" --arch "$arch" "$target_path" 2>&1)
    local thin_status=$?
    ab_log "$thin_output"
    # The status was thrown away here, and the tool exits 1 on an arch it does not
    # recognize - so a typo used to print one error line into the log and go on to
    # sign a universal applet, reporting success. Split assignment because `local`
    # is a command: `local x=$(cmd)` sets $? from the declaration.
    if [ "$thin_status" -ne 0 ]; then
        ab_log "Thinning to ${arch} failed (exit ${thin_status})."
        return 1
    fi

    # thin_distribution.sh treats a failed `lipo -thin` as a warning and still exits
    # 0 - fair for a tool run by hand, wrong for a build that is about to sign the
    # result: the applet keeps the architecture the developer asked to drop, the plan
    # or the release notes say otherwise, and nothing downstream contradicts them. It
    # only attempts binaries it found to be universal, so this means a fat binary that
    # does not carry ${arch} at all.
    # Matched on the wording thin_distribution.sh prints - both for a failed lipo and
    # for a failed mv after a good one. If that text ever changes, this stops halting
    # builds it should halt; there is a matching note at the other end.
    case "$thin_output" in
        *"Warning: lipo -thin"*)
            ab_log "Thinning to ${arch} left at least one universal binary in place (see the warning above)."
            return 1
            ;;
    esac
    return 0
}

# Run all bundled validators (command file, scripts, ActionUI JSON) against the
# target applet. Logs a per-file summary. Hard errors return 1 so the build
# aborts before codesigning a broken applet; warnings are reported but don't block.
validate_project() {
    local target_path="$1"
    local resources_dir="$target_path/Contents/Resources"
    local error_count=0
    local warning_count=0
    local report=""

    ab_log ""
    ab_log "Validating project..."

    # Info.plist: it parses (plister, which Linux has too; plutil -lint is macOS's)
    local info_plist="$target_path/Contents/Info.plist"
    if [ -f "$info_plist" ]; then
        local info_out
        info_out=$("$plister_tool" get type "$info_plist" / 2>&1)
        if [ $? -eq 0 ]; then
            ab_log "  Info.plist: OK"
        else
            ab_log "  Info.plist: INVALID"
            error_count=$((error_count + 1))
            # plister says nothing for an empty file
            [ -n "$info_out" ] || info_out="empty or not a property list"
            report="${report}Info.plist:
${info_out}

"
        fi
    else
        ab_log "  Info.plist: MISSING"
        error_count=$((error_count + 1))
        report="${report}Info.plist: missing (Contents/Info.plist not found)

"
    fi

    # Credits.md: the engine's About window shows it, as Markdown, on macOS and Linux. Without it
    # the About window has nothing to tell who made the applet, so a missing one is a warning (not
    # an error: it does not stop a build). Credits.rtf (what macOS's standard About panel read) is
    # not shown any more.
    local credits_md="$resources_dir/Credits.md"
    local credits_rtf="$resources_dir/Credits.rtf"
    if [ -f "$credits_md" ]; then
        ab_log "  Credits.md: OK"
        if [ -f "$credits_rtf" ]; then
            ab_log "  Credits.rtf: warning (not shown)"
            warning_count=$((warning_count + 1))
            report="${report}Credits.rtf: no longer shown; the About window shows Credits.md. Delete Contents/Resources/Credits.rtf.

"
        fi
    elif [ -f "$credits_rtf" ]; then
        ab_log "  Credits.md: warning (missing; Credits.rtf is no longer shown)"
        warning_count=$((warning_count + 1))
        report="${report}Credits.md: missing. The About window shows Contents/Resources/Credits.md (Markdown); Credits.rtf is no longer shown. On macOS, Build writes Credits.md from Credits.rtf; check it, then delete Credits.rtf.

"
    else
        ab_log "  Credits.md: warning (missing)"
        warning_count=$((warning_count + 1))
        report="${report}Credits.md: missing. The About window shows Contents/Resources/Credits.md (Markdown): who made the applet, its license, and what it uses. Add one.

"
    fi

    # Command file (Command.json or Command.plist) — shared validator: fast syntax
    # gate, then the advanced command_verifier (Layer 1 + bundle Layer 2).
    local cmd_plist=$(command_file_path "$target_path")
    local cmd_label=$(/usr/bin/basename "$cmd_plist")
    if [ -f "$cmd_plist" ]; then
        validate_command_file "$target_path"
        local cmd_vrc=$?
        if [ "$cmd_vrc" -eq 0 ]; then
            ab_log "  $cmd_label: OK"
        elif [ "$cmd_vrc" -eq 2 ]; then
            ab_log "  $cmd_label: warnings"
            warning_count=$((warning_count + 1))
            report="${report}${cmd_label} (warnings):
${COMMAND_VALIDATE_OUTPUT}

"
        elif [ "$cmd_vrc" -eq 3 ]; then
            ab_log "  $cmd_label: INVALID"
            error_count=$((error_count + 1))
            report="${report}${cmd_label}:
${COMMAND_VALIDATE_OUTPUT}

"
        else
            ab_log "  $cmd_label: VALIDATION ERROR"
            error_count=$((error_count + 1))
            report="${report}${cmd_label}:
${COMMAND_VALIDATE_OUTPUT}

"
        fi
    fi

    # Scripts — per-type syntax check (skips files with no validator)
    local scripts_dir="$resources_dir/Scripts"
    if [ -d "$scripts_dir" ]; then
        local script_ok=0
        local sf sname srci
        for sf in "$scripts_dir"/*; do
            [ ! -f "$sf" ] && continue
            sname=$(/usr/bin/basename "$sf")
            validate_script_file "$sf"
            srci=$?
            if [ "$srci" -eq 0 ]; then
                script_ok=$((script_ok + 1))
                if [ -n "$SCRIPT_VALIDATE_WARNINGS" ]; then
                    ab_log "  Script ${sname}: warnings (bash 4+ syntax)"
                    warning_count=$((warning_count + 1))
                    report="${report}Script ${sname} (warnings — macOS ships bash 3.2; these constructs fail at runtime):
${SCRIPT_VALIDATE_WARNINGS}

"
                fi
            elif [ "$srci" -ne 99 ]; then
                ab_log "  Script ${sname}: SYNTAX ERROR"
                error_count=$((error_count + 1))
                report="${report}Script ${sname}:
${SCRIPT_VALIDATE_OUTPUT}

"
            fi
        done
        ab_log "  Scripts: ${script_ok} OK"
    fi

    # ActionUI JSON — bundled verifier (rc 0 = valid, 2 = warnings, else errors)
    # Only files matching the ActionUI heuristic (root dict with "type" elements)
    # are validated; unrelated JSON is skipped.
    if actionui_verifier_available; then
        local jf jname vrc
        local ui_ok=0
        # Scan every localized .lproj (Base.lproj / English.lproj / en.lproj / …)
        # plus the Resources root.
        for jf in "$resources_dir"/*.lproj/*.json "$resources_dir"/*.json; do
            [ ! -f "$jf" ] && continue
            if ! is_actionui_json "$jf"; then
                continue
            fi
            jname=$(/usr/bin/basename "$jf")
            validate_actionui_file "$jf"
            vrc=$?
            if [ "$vrc" -eq 0 ]; then
                ab_log "  UI ${jname}: OK"
                ui_ok=$((ui_ok + 1))
            elif [ "$vrc" -eq 2 ]; then
                ab_log "  UI ${jname}: warnings"
                ui_ok=$((ui_ok + 1))
                warning_count=$((warning_count + 1))
                report="${report}UI ${jname} (warnings):
${ACTIONUI_VALIDATE_OUTPUT}

"
            else
                ab_log "  UI ${jname}: VALIDATION ERROR"
                error_count=$((error_count + 1))
                report="${report}UI ${jname}:
${ACTIONUI_VALIDATE_OUTPUT}

"
            fi
        done
        ab_log "  ActionUI JSON: ${ui_ok} validated"
    fi

    # Build/profiling droppings — an LLVM coverage-instrumented binary dumps default.profraw
    # into its CWD at exit, so running one with CWD inside the bundle (a build script's verify
    # step, say) plants the file IN the bundle; ship nothing of the kind. Warned, not errored:
    # the applet still runs, it is just carrying dead weight.
    local droppings=$(/usr/bin/find "$target_path" \( -name "*.profraw" -o -name "*.profdata" \) 2>/dev/null)
    if [ -n "$droppings" ]; then
        ab_log "  Profiling droppings: warning"
        warning_count=$((warning_count + 1))
        report="${report}Profiling droppings (delete before shipping; if they reappear, an instrumented binary is being run with CWD inside the bundle):
${droppings}

"
    fi

    # A nudge, never an error: it does not touch either counter, so it cannot
    # change the exit status here or halt a build. This runs inside
    # validate_project, which applet_build also calls, so the line appears
    # during a plain build of a test-less applet too - accepted, because one
    # advisory line is cheap and keeping the check in the shared path is what
    # makes the CLI and the GUI say the same thing.
    local tests_dir=$(applet_tests_dir "$target_path")
    if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
        ab_log "  [INFO] no Tests/ directory - consider the Test button or 'appletbuilder test' (see omctest_guide.md)"
    fi

    finish_validation "Validation" "$error_count" "$warning_count" "$report"
}

# Sanity-check Info.plist *content* against the on-disk bundle. Runs AFTER the
# framework/executable are copied so CFBundleExecutable can be verified against
# the real binary. A missing executable is an error (halt); an NSMainNibFile left from
# before 6.0 and icon problems are warnings (unless AB_WARNINGS_AS_ERRORS is on).
validate_info_content() {
    local target_path="$1"
    local contents_dir="$target_path/Contents"
    local resources_dir="$contents_dir/Resources"
    local info_plist="$contents_dir/Info.plist"
    local error_count=0
    local warning_count=0
    local report=""

    ab_log ""
    ab_log "Checking Info.plist content..."

    if [ ! -f "$info_plist" ]; then
        # Absence already reported by validate_project; nothing to check against.
        ab_log "  Info.plist: MISSING"
        return 0
    fi

    # CFBundleExecutable: <executable folder>/<exe> must exist (checked post-copy); the folder is
    # Contents/MacOS on macOS, Contents/Linux on Linux.
    local exe
    local exe_folder="$(applet_executable_folder "$target_path")"
    exe=$(plist_read "$info_plist" CFBundleExecutable)
    if [ -z "$exe" ]; then
        ab_log "  CFBundleExecutable: NOT SET"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable: not set in Info.plist

"
    elif [ ! -f "$exe_folder/$exe" ]; then
        ab_log "  CFBundleExecutable '${exe}': MISSING"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable '${exe}': Contents/${exe_folder##*/}/${exe} not found

"
    else
        ab_log "  CFBundleExecutable '${exe}': OK"
    fi

    # NSMainNibFile: since 6.0 the applet's executable never loads a main nib; it builds the
    # standard macOS menu bar (App/File/Edit/Format/Window/Help) in code, and an optional
    # MainMenu.json layers additions/mutations/removals on top. An applet made before 6.0
    # still has the key and a MainMenu.nib: a warning, as both are ignored.
    local nib=$(plist_read "$info_plist" NSMainNibFile)
    if [ -n "$nib" ]; then
        ab_log "  NSMainNibFile '${nib}': ignored since 6.0"
        warning_count=$((warning_count + 1))
        report="${report}NSMainNibFile '${nib}' (warning): ignored since 6.0, which builds the menu bar in code (the standard bar plus an optional MainMenu.json). Remove the key from Info.plist and the ${nib%.nib}.nib file; see nib_to_actionui_migration.md.

"
    fi

    # Menu source: note which one is in effect (informational, no warning either way).
    local menu_json_found=""
    if [ -e "$resources_dir/MainMenu.json" ] || [ -e "$resources_dir/Base.lproj/MainMenu.json" ]; then
        menu_json_found="yes"
    else
        local mlproj
        for mlproj in "$resources_dir"/*.lproj; do
            [ -d "$mlproj" ] || continue
            if [ -e "$mlproj/MainMenu.json" ]; then
                menu_json_found="yes"
                break
            fi
        done
    fi
    if [ -n "$menu_json_found" ]; then
        ab_log "  Menu source: standard bar + MainMenu.json overrides"
    else
        ab_log "  Menu source: standard bar (programmatic; no MainMenu.json overrides)"
    fi

    # CFBundleIconFile -> Resources/<icon>.icns should exist (warning only). On Linux the icon is
    # Resources/<icon>.png or .svg (owner's Q5), and there is no asset catalog to check.
    local iconfile=$(plist_read "$info_plist" CFBundleIconFile)
    if [ -n "$iconfile" ] && ! ab_on_macos; then
        local linux_icon_base="${iconfile%.icns}"
        if [ -f "$resources_dir/${linux_icon_base}.png" ] || [ -f "$resources_dir/${linux_icon_base}.svg" ]; then
            ab_log "  CFBundleIconFile '${iconfile}': OK (${linux_icon_base}.png or .svg)"
        else
            ab_log "  CFBundleIconFile '${iconfile}': missing .png or .svg"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconFile '${iconfile}' (warning): neither ${linux_icon_base}.png nor ${linux_icon_base}.svg found in Resources (set the icon again in AppletBuilder: it writes one on either system)

"
        fi
        iconfile=""
    fi
    if [ -n "$iconfile" ]; then
        local icon_base="${iconfile%.icns}"
        if [ -f "$resources_dir/${icon_base}.icns" ]; then
            ab_log "  CFBundleIconFile '${iconfile}': OK"
        else
            ab_log "  CFBundleIconFile '${iconfile}': missing .icns"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconFile '${iconfile}' (warning): ${icon_base}.icns not found in Resources

"
        fi
    fi

    # CFBundleIconName → asset-catalog icon; requires Assets.car. When assetutil
    # is available we confirm the named asset is actually inside it (warning only).
    local iconname=$(plist_read "$info_plist" CFBundleIconName)
    if [ -n "$iconname" ] && ab_on_macos; then
        local assets="$resources_dir/Assets.car"
        if [ ! -f "$assets" ]; then
            ab_log "  CFBundleIconName '${iconname}': Assets.car missing"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconName '${iconname}' (warning): Assets.car not found in Resources

"
        elif [ -x /usr/bin/assetutil ]; then
            if /usr/bin/assetutil --info "$assets" 2>/dev/null | /usr/bin/grep -Fq "\"Name\" : \"${iconname}\""; then
                ab_log "  CFBundleIconName '${iconname}': OK"
            else
                ab_log "  CFBundleIconName '${iconname}': not found in Assets.car"
                warning_count=$((warning_count + 1))
                report="${report}CFBundleIconName '${iconname}' (warning): no asset named '${iconname}' found in Assets.car

"
            fi
        else
            # Assets.car present but no assetutil to inspect it — can't confirm.
            ab_log "  CFBundleIconName '${iconname}': Assets.car present (not inspected)"
        fi
    fi

    finish_validation "Info.plist content" "$error_count" "$warning_count" "$report"
}

# Summarize a validation phase and decide whether the build may continue.
# Args: label  error_count  warning_count  report_text
# Reads AB_WARNINGS_AS_ERRORS ("1" = treat warnings as errors).
# Returns 0 = passed / continue, 1 = halt the build.
finish_validation() {
    local label="$1"
    local errs="$2"
    local warns="$3"
    local rep="$4"

    if [ "$errs" -eq 0 ] && [ "$warns" -eq 0 ]; then
        ab_log "${label} passed."
        return 0
    fi

    ab_log "${label}: ${errs} error(s), ${warns} warning(s)."

    if [ "$errs" -gt 0 ]; then
        ab_report "Build halted — ${label} found ${errs} error(s) and ${warns} warning(s):

${rep}"
        return 1
    fi

    if [ "$AB_WARNINGS_AS_ERRORS" = "1" ]; then
        ab_log "  Treating warnings as errors."
        ab_report "Build halted — ${label} found ${warns} warning(s), treated as errors:

${rep}"
        return 1
    fi

    ab_report "${label} found ${warns} warning(s); the build will continue:

${rep}"
    return 0
}

# Codesign and report result. Reads AB_IDENTITY (default "-" ad-hoc).
do_codesign() {
    local target_path="$1"
    ab_log ""

    local identity="$AB_IDENTITY"
    if [ -z "$identity" ]; then
        identity="-"
    fi

    if ! ab_on_macos; then
        : # applet_codesign says the applet is not signed
    elif [ "$identity" = "-" ]; then
        ab_log "Codesigning (ad-hoc)..."
    else
        ab_log "Codesigning with \"${identity}\"..."
    fi

    # log_output is declared apart from its assignment on purpose: `local x=$(cmd)`
    # runs the substitution as part of `local`, so the next $? reads local's own
    # status - always 0 - which reported every codesigning failure as "Build
    # succeeded" and returned 0 to applet_build, whose contract is to return 1
    # when signing fails. Nothing may run between the assignment and the $? read,
    # so the timestamp below is deliberately taken after it.
    local log_output
    log_output=$(applet_codesign "$target_path" "$identity" 2>&1)
    local status=$?
    local timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

    ab_log ""
    ab_log "$log_output"
    ab_log ""
    # Linux: the desktop entry again, when the applet has one, now with the icon the build made;
    # macOS registers with Launch Services on create and save, as before
    if [ $status -eq 0 ] && ! ab_on_macos; then
        applet_finalize "$target_path"
    fi
    if [ $status -eq 0 ]; then
        ab_log "Build succeeded. (${timestamp})"
    else
        ab_log "Build FAILED (exit code: ${status}) (${timestamp})"
    fi
    return $status
}

# Top-level build orchestrator. Validates, refreshes runtime, cleans junk, thins,
# codesigns.
# Reads the AB_* options documented at the top of this file. Returns 0 on success,
# 1 if the build is halted by validation or fails to codesign.
# Credits.md from Credits.rtf, once, on macOS. An applet made before 6.0 has only Credits.rtf, which
# the About window no longer shows: textutil reads it and credits_rtf_to_md.py writes the Markdown
# beside it (links, italic and bold kept; alignment, fonts and colors dropped). Credits.rtf stays, and
# validation then warns that it can be deleted. An existing Credits.md is never touched. Not on Linux,
# which has no textutil: validation warns about the missing Credits.md there.
# Returns 0 when there was nothing to do or Credits.md was written, 1 when the conversion failed.
convert_credits_rtf() {
    local target_path="$1"
    local resources_dir="$target_path/Contents/Resources"
    local credits_md="$resources_dir/Credits.md"
    local credits_rtf="$resources_dir/Credits.rtf"
    if [ -f "$credits_md" ] || [ ! -f "$credits_rtf" ]; then
        return 0
    fi
    if ! ab_on_macos; then
        return 0
    fi
    local convert_output
    convert_output=$("$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/credits_rtf_to_md.py" "$credits_rtf" "$credits_md" 2>&1)
    local convert_status=$?
    if [ "$convert_status" -ne 0 ]; then
        ab_log "Credits.md not made from Credits.rtf: ${convert_output}"
        return 1
    fi
    ab_log "Credits.md made from Credits.rtf: check it, then delete Credits.rtf"
    return 0
}

applet_build() {
    local project_path="$1"

    if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
        ab_report "Error: No project loaded"
        return 1
    fi

    local app_name=$(/usr/bin/basename "$project_path")
    ab_log "Building ${app_name}..."

    strip_quarantine "$project_path"
    convert_credits_rtf "$project_path"

    if ! validate_project "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted — fix validation errors and try again. (${ts})"
        return 1
    fi

    update_framework "$project_path"
    update_linux_installer "$project_path"
    update_linux_requires "$project_path"
    update_python "$project_path"

    update_python_packages "$project_path"
    local packages_rc=$?
    if [ "$packages_rc" -ne 0 ]; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted - the Command Workshop Python modules could not be installed. (${ts})"
        return 1
    fi

    update_shell_clients "$project_path"

    if ! thin_binaries "$project_path"; then
        # Sweep on the way out. The junk sweep further down exists partly for the
        # *.thin.tmp a killed lipo leaves beside a binary, and returning straight
        # from here would jump past it - leaving that debris in the bundle after
        # exactly the failure most likely to produce it. Its own status is not worth
        # a second verdict: the build is already halting, and AB_ABORTING keeps it
        # from announcing a signing that is no longer going to happen.
        # Set around the call rather than prefixed to it: a var assignment in front
        # of a FUNCTION persists in the shell afterwards, which is not what a reader
        # expects from that form.
        AB_ABORTING=1
        clean_build_junk "$project_path"
        AB_ABORTING=0
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        # Says what state the bundle is in, because it is not the state it was in
        # before: thin_distribution.sh carries on past a binary it could not slice,
        # so the others have already been rewritten - and rewriting a Mach-O breaks
        # its signature, which is why an unsigned half-thinned bundle must not be
        # mistaken for an untouched one.
        ab_log "Build halted - one or more binaries could not be sliced to ${AB_THIN_ARCH}."
        ab_log "The bundle has been modified and is NOT signed. Fix the architecture or"
        ab_log "clear the thinning option, then build again. (${ts})"
        return 1
    fi

    if ! validate_info_content "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted — fix Info.plist and try again. (${ts})"
        return 1
    fi

    # --test, and only --test: tests are applet-authored code with arbitrary
    # runtime, and a developer mid-refactor must be able to rebuild an app whose
    # tests are momentarily red.
    #
    # Placed here on purpose - after the framework, executable and Python have
    # been refreshed, and before signing. That order is the point of running
    # them at all in a build: it tests the tool versions that will actually
    # ship, and it halts in the same place a validation error halts, so nothing
    # unsigned-but-broken ever reaches the signing step.
    if [ "$AB_RUN_TESTS" = "1" ]; then
        if ! applet_run_tests "$project_path"; then
            local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
            ab_log ""
            ab_log "Build halted - tests failed. (${ts})"
            return 1
        fi
    fi

    # Last thing before signing, deliberately. thin_binaries leaves a
    # *.thin.tmp beside a binary if lipo is interrupted, and applet-authored
    # tests are arbitrary code with write access to their own bundle - both
    # happen after the old call site, so sweeping earlier let their leavings
    # get sealed.
    if ! clean_build_junk "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted - junk could not be removed and would be signed in. (${ts})"
        return 1
    fi

    do_codesign "$project_path"
}

# Where an applet's omctest suite lives: a Tests/ directory NEXT TO the bundle,
# never inside it (tests in the bundle would bloat the shipped app and dirty its
# code signature). Prints the path; returns non-zero if the parent directory
# cannot be resolved, in which case nothing is printed.
applet_tests_dir() { # <project-path>
    local parent
    # CDPATH= only. No -P: this path is printed and compared as the logical one the
    # caller passed (/var/..., not /private/var/...), and resolving symlinks here
    # would change what the Test button reports as much as what it finds.
    parent=$(CDPATH= cd -- "$(/usr/bin/dirname "$1")" >/dev/null 2>&1 && pwd) || return 1
    [ -n "$parent" ] || return 1
    printf '%s/Tests\n' "$parent"
}

# The integration test files (*.itest.sh) in the applet's Tests/ directory, one
# path per line; nothing when there are none.
applet_itest_files() { # <project-path>
    local tests_dir test_file
    tests_dir=$(applet_tests_dir "$1")
    [ -n "$tests_dir" ] && [ -d "$tests_dir" ] || return 0
    for test_file in "$tests_dir"/*.itest.sh; do
        [ -f "$test_file" ] && printf '%s\n' "$test_file"
    done
    return 0
}

# Running applications with the same bundle identifier as <App.app>, wherever
# they were started from, one "<pid> <bundle path>" line each; nothing when none
# runs. Asked of Launch Services (lsappinfo), where every applet checks in at
# launch, so a copy at another path counts too: it shares the preferences.
applet_running_instances() { # <App.app>
    local bundle_id=$("$plister_tool" get value "$1/Contents/Info.plist" /CFBundleIdentifier 2>/dev/null)
    [ -n "$bundle_id" ] || return 0
    if ! ab_on_macos; then
        applet_running_instances_linux "$bundle_id"
        return 0
    fi
    local found=$(/usr/bin/lsappinfo find bundleid="$bundle_id" 2>/dev/null)
    # One full "info" per entry, read for its "pid = " and "bundle path=" lines,
    # instead of "-only pid" and "-only bundlepath": what -only prints has not
    # stayed the same across macOS releases.
    local asn info pid bundle_path
    for asn in $(printf '%s\n' "$found" | /usr/bin/grep -oE 'ASN:0x[0-9a-fA-F]+-0x[0-9a-fA-F]+'); do
        info=$(/usr/bin/lsappinfo info "$asn" 2>/dev/null)
        pid=$(printf '%s\n' "$info" | /usr/bin/sed -nE 's/^ *pid = ([0-9]+).*/\1/p' | /usr/bin/head -1)
        case "$pid" in
            ''|*[!0-9]*|0) continue ;;
        esac
        bundle_path=$(printf '%s\n' "$info" | /usr/bin/sed -nE 's/^ *bundle path="(.*)" *$/\1/p' | /usr/bin/head -1)
        printf '%s %s\n' "$pid" "${bundle_path:-?}"
    done
    return 0
}

# applet_running_instances on Linux (owner's Q7): no registry of running applications, so every
# process of this user whose executable lies in an applet bundle (<bundle>/Contents/Linux/<name>)
# is asked for that bundle's identifier, so a copy at another path counts too, as on macOS (it
# shares the settings). An executable replaced while it runs (a build copies a new one) reads
# "<path> (deleted)" in /proc; the bundle path is still right.
applet_running_instances_linux() { # <bundle identifier>
    local proc_exe pid exe_path bundle_path running_id
    for proc_exe in /proc/[0-9]*/exe; do
        pid="${proc_exe#/proc/}"
        pid="${pid%/exe}"
        # This user's processes only: as root, readlink would succeed for every user's
        [ -O "/proc/$pid" ] || continue
        exe_path="$(/usr/bin/readlink -- "$proc_exe" 2>/dev/null)"
        exe_path="${exe_path% (deleted)}"
        case "$exe_path" in
            */Contents/Linux/*) ;;
            *) continue ;;
        esac
        bundle_path="${exe_path%/Contents/Linux/*}"
        # The applet's executable itself, not a helper in a folder below Contents/Linux
        case "${exe_path#"$bundle_path/Contents/Linux/"}" in
            */*) continue ;;
        esac
        running_id=$("$plister_tool" get value "$bundle_path/Contents/Info.plist" /CFBundleIdentifier 2>/dev/null)
        if [ "$running_id" = "$1" ]; then
            printf '%s %s\n' "$pid" "$bundle_path"
        fi
    done
    return 0
}

# Ask the application with <pid> to quit, as its Quit menu item would (it may
# ask about unsaved work, or decline), and wait up to <seconds> for it to end.
# On Linux the request is SIGTERM, which a Linux applet takes as Quit (it runs
# app.will.terminate). Returns 0 once it is gone, 1 if it is still running.
applet_quit_instance() { # <pid> <seconds>
    local pid="$1" seconds="$2"
    case "$seconds" in
        ''|*[!0-9]*) seconds=60 ;;
    esac
    local reply
    if ab_on_macos; then
        reply=$(/usr/bin/osascript -l JavaScript "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/ab_quit_application.js" "$pid" 2>&1)
    else
        kill -TERM "$pid" 2>/dev/null
        local kill_status=$?
        if [ "$kill_status" -eq 0 ]; then
            reply="sent (SIGTERM)"
        else
            reply="gone"
        fi
    fi
    ab_log "  Quit request for process $pid: ${reply:-no reply}"
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge $((seconds * 2)) ]; then
            return 1
        fi
        /bin/sleep 0.5
        waited=$((waited + 1))
    done
    return 0
}

# Run the applet's omctest suite. Returns non-zero when the suite fails or when
# it was asked for and there is nothing to run.
applet_run_tests() {
    local project_path="$1"
    local tests_dir omctest_lib rc

    tests_dir=$(applet_tests_dir "$project_path")
    if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
        # Running tests is always an explicit request - the --test flag or the
        # Test button. Failing loudly beats a silent skip, which would let a
        # release flow believe tests had run.
        ab_report "No Tests/ directory beside the applet: ${tests_dir:-$project_path}"
        return 1
    fi

    omctest_lib="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Agents/omctest.sh"
    if [ ! -f "$omctest_lib" ]; then
        ab_report "The omctest harness is missing at $omctest_lib"
        return 1
    fi

    ab_log "Running tests..."
    export OMCTEST_RUNNER=1
    export OMCTEST_LIB="$omctest_lib"
    # shellcheck source=../Agents/omctest.sh
    source "$omctest_lib"

    # The suite reports for itself: per-check detail on stderr, one
    # machine-readable summary line on stdout. Merge both and hand the stream to
    # ab_log_stream, which is what puts the whole transcript in the GUI's log
    # pane while leaving the CLI's live stderr streaming exactly as it was.
    #
    # A ( ) SUBSHELL, not a { } group. On bash 3.2 - which is what /bin/sh is,
    # and what the engine runs handlers under - an EXIT trap set inside a brace
    # group used as a pipeline element never runs. omctest_run_suite's only
    # cleanup for the scratch tree it creates is exactly such a trap, so with a
    # brace group here every test run leaked a whole scratch tree (a stub
    # support/ directory and a copy of every fixture, per test file). zsh runs
    # the trap in both shapes, so this does not reproduce in an interactive
    # shell.
    ( omctest_run_suite "$project_path" "$tests_dir" 2>&1 ) | ab_log_stream
    # Read on the very next line: any command in between overwrites PIPESTATUS,
    # and plain $? here is the reader's status, not the suite's.
    rc=${PIPESTATUS[0]}
    # A missing or garbled status is a failure, not a pass: the alternative is
    # reporting green for a suite whose result was never read.
    case "$rc" in
        ''|*[!0-9]*) rc=1 ;;
    esac
    return "$rc"
}

# ──────────────────────────────────────────────────────────────
# Embedded Python thinning (plan / apply)
# ──────────────────────────────────────────────────────────────
#
# An applet that bundles its own Python ships a full universal distribution -
# some 60 MB - of which a typical handler set imports a small slice. The
# Python-Embedding toolkit removes the rest in two phases with a reviewable JSON
# plan in between, and thin_applet_python.py is the front end that knows where an
# OMC bundle keeps its interpreter, its handlers and its Packages. Both are
# vendored into AppletBuilder (Contents/Library/python_thinning), so neither the
# pane's Execute button nor `appletbuilder thin-python` needs a Python-Embedding
# checkout on the machine.
#
# Options the caller sets, like every other phase in this file:
#
#   AB_THIN_PYTHON_ACTION  plan | apply | apply-dry | plan-apply |
#                          plan-apply-dry (default: plan)
#   AB_THIN_PLAN           explicit plan file; empty = resolved (see below)
#   AB_THIN_ARCH           reused from the build options - a plan written while
#                          the pane says "Apple Silicon" records that slice, so
#                          the interpreter is thinned the same way the applet's
#                          other universal binaries are
#   AB_THIN_SKIP_VERIFY    "1" = do not re-run the workload after applying. CLI
#                          only, and rarely right: that re-run is what restores
#                          the interpreter when the plan removed too much.
#
# Only `plan` is safe to run without thinking: it clones the bundle and executes
# only the clone, and the real applet is never written to. Everything that
# removes modules goes through ab_confirm first.

# The front end, named through a variable so a test can point the phase at a
# recorder and assert on the arguments it assembles. Running the real thing takes
# minutes and needs a whole applet with a working interpreter. Bound when this
# library is sourced, so an override has to be exported before that.
thin_python_tool="${AB_THIN_PYTHON_TOOL:-${OMC_APP_BUNDLE_PATH}/Contents/Library/python_thinning/thin_applet_python.py}"

# The bundle name without its extension - what the plan and keep files are named
# after.
applet_short_name() { # <project-path>
    local base=$(/usr/bin/basename "$1")
    printf '%s' "${base%.app}"
}

# What the remembered plan is filed under. The applet's bundle identifier when it
# has one, because that is the only thing about an applet that survives being
# copied to a release directory AND distinguishes it from somebody else's applet
# of the same name - and the plan file itself records nothing about which applet
# or which build it was written for, so a mistaken match is not caught later.
# Falls back to the name, prefixed apart so the two spaces cannot collide.
applet_plan_key() { # <project-path>
    local bundle_id=$(plist_read "$1/Contents/Info.plist" "CFBundleIdentifier")
    if [ -n "$bundle_id" ]; then
        printf 'id:%s' "$bundle_id"
    else
        printf 'name:%s' "$(applet_short_name "$1")"
    fi
}

# The interpreter an applet bundles. Absent from an applet that has none, which
# is the case applet_thin_python refuses on.
applet_python_bin() { # <project-path>
    printf '%s/Contents/Library/Python/bin/python3' "$1"
}

# The directory an applet's plan and keep file live in - its parent, ABSOLUTE.
#
# Absolute is load-bearing, not tidiness. `appletbuilder thin-python plan
# MyApp.app` from the applet's own directory would otherwise produce
# "./MyApp.thinning-plan.json", which is correct for that run and wrong forever
# after: the path is recorded for the fallback below, and a later apply resolves
# it against ITS working directory, where a same-named plan for an entirely
# different applet may well be sitting. Confirmed by reproduction, not theory.
applet_plan_dir() { # <project-path>
    local dir=$(/usr/bin/dirname "$1")
    # CDPATH= and --, not a bare cd: `cd` searches $CDPATH for any operand that
    # does not begin with /, ./ or ../, so an exported CDPATH silently resolves
    # "sub/MyApp.app" somewhere else entirely - and this path is then written to,
    # remembered, and applied from. The same guard is on update_shell_clients
    # above, for the same reason.
    local abs=$(CDPATH= cd -P -- "$dir" >/dev/null 2>&1 && pwd -P)
    if [ -n "$abs" ]; then
        printf '%s' "$abs"
    else
        # Unresolvable (deleted out from under us, or no search permission).
        # Degrade to what the caller gave rather than to an empty string, which
        # would silently build a plan path at the filesystem root.
        printf '%s' "$dir"
    fi
}

# <App>.thinning-plan.json BESIDE the bundle: the front end's own default, and
# where a plan belongs in version control - next to the applet it describes, not
# inside it, where it would be signed in and wiped by the next Python install.
applet_plan_path() { # <project-path>
    printf '%s/%s.thinning-plan.json' \
        "$(applet_plan_dir "$1")" "$(applet_short_name "$1")"
}

# Optional per-applet force-keep list, named to match: <App>.thinning-keep.txt,
# one module name per line. It is the escape hatch for a module no analysis can
# discover - one imported under a name built at runtime, or loaded by a plugin
# host - and it sits beside the plan so the two are committed together.
applet_keep_file() { # <project-path>
    printf '%s/%s.thinning-keep.txt' \
        "$(applet_plan_dir "$1")" "$(applet_short_name "$1")"
}

# Which plan an apply should use. Sets THIN_PLAN_PATH and THIN_PLAN_SOURCE
# (explicit | beside | remembered; plan-apply sets "written" itself) and returns 1 when there is no plan to use.
#
# The remembered fallback is for the flow this feature exists to serve: the plan
# is written and reviewed against the development copy, then a distribution copy
# is made elsewhere and that is what gets thinned. The copy has no plan beside
# it, and putting one there by hand is exactly the step that gets forgotten. So a
# successful plan run records where it wrote, keyed by the applet's identity (see
# applet_plan_key), and an apply that finds nothing beside the bundle falls back
# to it - naming the file
# in the log, because a plan carried over from a different build of the applet is
# the one way this can remove the wrong set of modules.
applet_resolve_plan() { # <project-path>
    THIN_PLAN_PATH=""
    THIN_PLAN_SOURCE=""

    if [ -n "$AB_THIN_PLAN" ]; then
        THIN_PLAN_PATH="$AB_THIN_PLAN"
        THIN_PLAN_SOURCE="explicit"
        # An explicit path that does not exist is the caller's mistake, and
        # saying so here beats the front end's own "plan not found" - this one
        # can say which of the three routes chose the path.
        if [ ! -f "$THIN_PLAN_PATH" ]; then
            return 1
        fi
        return 0
    fi

    local beside=$(applet_plan_path "$1")
    if [ -f "$beside" ]; then
        THIN_PLAN_PATH="$beside"
        THIN_PLAN_SOURCE="beside"
        return 0
    fi

    local remembered=$(get_thinning_plan "$(applet_plan_key "$1")")
    # Absolute only. A relative entry can only have come from a version of this
    # code that stored one, and resolving it here would mean resolving it against
    # whatever directory this run happens to start in.
    case "$remembered" in
        /*) ;;
        *)  remembered="" ;;
    esac
    if [ -n "$remembered" ] && [ -f "$remembered" ]; then
        THIN_PLAN_PATH="$remembered"
        THIN_PLAN_SOURCE="remembered"
        return 0
    fi

    return 1
}

# Run the front end, streaming its transcript through ab_log_stream, and return
# ITS status. The subshell and the PIPESTATUS read on the very next line are the
# same requirements applet_run_tests documents.
thin_python_exec() { # <front-end args...>
    local rc
    # -u because this output is a PIPE. Python block-buffers stdout when it is
    # not a terminal, so without it the front end's whole progress transcript -
    # which phase is running, which entry point is being traced - arrives in one
    # burst when the run ends, minutes after it would have been useful, and out
    # of order against the stderr it is merged with here.
    ( "$python3" -u "$thin_python_tool" "$@" 2>&1 ) | ab_log_stream
    rc=${PIPESTATUS[0]}
    case "$rc" in
        ''|*[!0-9]*) rc=1 ;;
    esac
    return "$rc"
}

# Analyze the applet and write a plan. Never modifies the bundle: the front end
# clones it and runs only the clone, under a sandbox profile with no network and
# no writes outside the staging area.
thin_python_plan() { # <project-path>
    local project_path="$1"
    local plan_path="$AB_THIN_PLAN"
    if [ -z "$plan_path" ]; then
        plan_path=$(applet_plan_path "$project_path")
    fi

    set -- plan "$project_path" --plan "$plan_path"

    # The pane's "Thin Universal Executables" choice, reused: an applet thinned to
    # one architecture has no use for the other slice of its interpreter, and
    # recording the arch IN the plan keeps a re-apply after a Python reinstall
    # doing what the first one did.
    case "$AB_THIN_ARCH" in
        arm64|x86_64) set -- "$@" --arch "$AB_THIN_ARCH" ;;
    esac

    local keep_file=$(applet_keep_file "$project_path")
    if [ -f "$keep_file" ]; then
        ab_log "Force-keeping the modules listed in $(/usr/bin/basename "$keep_file")"
        set -- "$@" --keep-file "$keep_file"
    fi

    ab_log ""
    ab_log "Writing a thinning plan (the applet itself is not modified)..."

    local rc
    thin_python_exec "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        ab_report "Writing the thinning plan failed. The analyzer's output is in the log."
        return "$rc"
    fi

    # Recorded only for a plan that is really on disk. The front end reporting
    # success without having written one would be a bug, but the record outlives
    # this run and is what a later apply on a COPY of the applet resolves to, so
    # it is checked rather than assumed.
    if [ -f "$plan_path" ]; then
        save_thinning_plan "$(applet_plan_key "$project_path")" "$plan_path"
    fi
    ab_log ""
    ab_log "Review remove.modules in the plan and commit it next to the applet."
    return 0
}
# What an apply should say when there is no plan to use. One function, because
# the resolution now happens before the confirmation for a plain apply and after
# the plan for plan-apply, and two copies of this message would drift.
thin_python_report_no_plan() { # <project-path>
    if [ "$THIN_PLAN_SOURCE" = "explicit" ]; then
        ab_report "Thinning plan not found: ${THIN_PLAN_PATH}"
        return 0
    fi
    ab_report "No thinning plan for $(applet_short_name "$1").

Looked beside the applet at:
  $(applet_plan_path "$1")

Write one first - tick \"Write Thinning Plan\" in the Build & Run pane, or
\"appletbuilder thin-python plan\" - review it, and commit it next to the applet."
}

# Does this plan's third-party Packages section point INSIDE the applet being
# thinned? Prints "<inside|outside|none|unreadable>\t<count>\t<dir>".
#
# It has to be asked, because a plan records packages.dir as an absolute path
# into the bundle it was planned against, and the applier resolves
# packages.remove against THAT path rather than against the applet named on the
# command line. Carry a plan to a copy - which is exactly what the remembered
# fallback is for - and a non-empty packages.remove would back up and delete out
# of the ORIGINAL bundle, invalidating its signature, with nothing in the
# transcript naming it. packages.remove is emitted empty and only a human editing
# the plan makes it non-empty, which is why this refuses rather than rewrites:
# the entries are someone's deliberate choice about a specific bundle.
thin_python_packages_check() { # <plan-file> <project-path>
    "$python3" - "$1" "$2" <<'PYCHECK'
import json, os, sys

try:
    with open(sys.argv[1]) as f:
        plan = json.load(f)
except (OSError, ValueError):
    print("unreadable\t0\t")
    raise SystemExit(0)

pkgs = plan.get("packages") or {}
directory = pkgs.get("dir") or ""
count = len(pkgs.get("remove") or [])
if not directory:
    print("none\t%d\t" % count)
    raise SystemExit(0)

app = os.path.realpath(sys.argv[2])
where = "inside" if os.path.realpath(directory).startswith(app + os.sep) else "outside"
print("%s\t%d\t%s" % (where, count, directory))
PYCHECK
}

# Perform a plan's removal against the applet's real interpreter, then verify by
# re-running the plan's workload - a failure there restores the backup the
# applier took.
#
# Resolution has usually happened already, in applet_thin_python, so that the
# confirmation could name the plan. plan-apply is the exception: its plan does
# not exist until the phase before this one has run.
thin_python_apply() { # <project-path> <dry-run: 0|1>
    local project_path="$1"
    local dry_run="$2"

    if [ -z "$THIN_PLAN_PATH" ]; then
        if ! applet_resolve_plan "$project_path"; then
            thin_python_report_no_plan "$project_path"
            return 1
        fi
    fi

    ab_log ""
    ab_log "Plan: ${THIN_PLAN_PATH}"
    if [ "$THIN_PLAN_SOURCE" = "remembered" ]; then
        ab_log "  No plan beside the applet; using the one last written for $(applet_short_name "$project_path")."
        ab_log "  Copy it next to the bundle to make this repeatable, and launch the applet"
        ab_log "  afterwards: a plan written for a different build verifies against itself."
    fi

    local pkg_check=$(thin_python_packages_check "$THIN_PLAN_PATH" "$project_path")
    local pkg_where=$(printf '%s' "$pkg_check" | /usr/bin/cut -f1)
    local pkg_count=$(printf '%s' "$pkg_check" | /usr/bin/cut -f2)
    local pkg_dir=$(printf '%s' "$pkg_check" | /usr/bin/cut -f3)

    case "$pkg_where" in
        inside|none|unreadable)
            # unreadable is left to the applier, which reports a malformed plan
            # far better than this check could.
            ;;
        outside)
            # Shape-tested before it is compared. A non-numeric count makes `[ -gt ]`
            # exit 2, and an `if` reads that as "not greater than zero" - fail-open on
            # the one guard standing between this apply and a deletion inside another
            # bundle. "Could not tell" is refused here for the same reason as below.
            case "$pkg_count" in
                ''|*[!0-9]*)
                    ab_report "The plan's Packages section could not be checked against this applet.

  Plan: ${THIN_PLAN_PATH}

Its audit names a directory in a different bundle, but the number of packages it
removes came back as \"${pkg_count}\" rather than a count, so there is no telling
whether applying it would delete anything there.

Re-plan against this applet, or edit the plan's packages.dir to match it."
                    return 1
                    ;;
            esac
            if [ "$pkg_count" -gt 0 ]; then
                ab_report "This plan's Packages section names a directory in a DIFFERENT bundle:
  ${pkg_dir}

It lists ${pkg_count} package(s) to remove, and the applier resolves them against that
path - so applying it here would delete from that bundle, not from
$(/usr/bin/basename "$project_path").

Re-plan against this applet, or edit the plan's packages.dir to match it."
                return 1
            fi
            ab_log "  (the plan's Packages audit refers to ${pkg_dir}; nothing there is removed)"
            ;;
        *)
            # No answer at all: the interpreter failed, or a packages.dir with a
            # newline in it split the reply. Refuse. The only thing this guard
            # protects is deletion from another bundle, and "could not tell" is
            # not "it is fine" - the previous shape read an empty answer as one.
            ab_report "The plan's Packages section could not be checked against this applet.

  Plan: ${THIN_PLAN_PATH}

Refusing rather than applying: a plan whose packages.dir points into another
bundle removes files from THAT bundle. Check the plan is well-formed JSON and
that AppletBuilder's own Python is working."
            return 1
            ;;
    esac

    set -- apply "$project_path" --plan "$THIN_PLAN_PATH"
    if [ "$dry_run" = "1" ]; then
        set -- "$@" --dry-run
        ab_log "Dry run - nothing will be removed."
    fi
    if [ "$AB_THIN_SKIP_VERIFY" = "1" ]; then
        set -- "$@" --skip-verify
        ab_log "WARNING: verification disabled - a plan that removes too much will not be caught."
    fi

    ab_log ""

    local rc
    thin_python_exec "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        # Deliberately not promising a restore. The applier does restore the
        # interpreter it backed up when verification fails, but it is not the
        # only way to get here: it refuses outright when a .thinbak is already
        # there, and the front end can fail before it ever runs.
        ab_report "Thinning failed - read the log for which phase, and check whether the
applet's interpreter was restored before shipping it."
        return "$rc"
    fi
    return 0
}

# Enable or disable the Build & Run pane's Embedded Python group to match the
# applet in front of the user, and say why when it is off.
#
# Disabling the GROUP rather than each control: SwiftUI's disabled state
# propagates to descendants and an ancestor's "off" wins, so this also keeps
# ab_actions_release from re-enabling the group's Execute button at the end of a
# build on an applet that has nothing to thin.
#
# GUI-only, and a no-op with lib.common.sh's stderr reporters, so the agent CLI
# can call the phase without it.
ab_thin_python_availability() { # <project-path>
    # No project yet - the pane can load before one is open - so there is nothing
    # to answer. Leaving the group alone beats asserting "this applet has no
    # embedded Python" about an applet nobody has chosen, which would then sit
    # there until the pane was reloaded.
    if [ -z "$1" ]; then
        return 0
    fi

    if [ -x "$(applet_python_bin "$1")" ]; then
        set_enabled "$BUILD_THIN_GROUP_ID" true
        set_visible "$BUILD_THIN_NOTE_ID" false
        return 0
    fi

    set_enabled "$BUILD_THIN_GROUP_ID" false
    set_value "$BUILD_THIN_NOTE_ID" "This applet has no embedded Python."
    set_visible "$BUILD_THIN_NOTE_ID" true
    return 1
}

# The version of an applet's embedded Python, read from its files - never by running
# it. Opening a project or bringing its window forward must not execute code from it:
# it may be an applet nobody has built here, and a quarantined interpreter would put
# up a Gatekeeper prompt on every activation. Three sources, most precise first,
# because thinning can remove the first two:
#   lib/pythonX.Y/_sysconfig_vars_*.json  "py_version": "3.15.2"   (3.14 and later)
#   include/pythonX.Y/patchlevel.h        #define PY_VERSION "3.15.2"
#   the lib/pythonX.Y directory name      3.15
# Prints nothing when the runtime has no lib/python3.* at all.
applet_python_version() { # <project-path>
    local _ab_stdlib _ab_vars _ab_header
    local _ab_found=""
    for _ab_stdlib in "$1"/Contents/Library/Python/lib/python3.*; do
        if [ -d "$_ab_stdlib" ]; then
            _ab_found="$_ab_stdlib"
            break
        fi
    done
    if [ -z "$_ab_found" ]; then
        return 0
    fi

    local _ab_version=""
    for _ab_vars in "$_ab_found"/_sysconfig_vars_*.json; do
        if [ -f "$_ab_vars" ]; then
            # sed, not jq: /usr/bin/jq ships with macOS 15, and AppletBuilder runs on
            # 14.6. The file is written one key per line.
            _ab_version=$(/usr/bin/sed -n 's/^[[:space:]]*"py_version":[[:space:]]*"\([^"]*\)".*/\1/p' "$_ab_vars")
            break
        fi
    done
    if [ -z "$_ab_version" ]; then
        _ab_header="$1/Contents/Library/Python/include/${_ab_found##*/}/patchlevel.h"
        if [ -f "$_ab_header" ]; then
            _ab_version=$(/usr/bin/sed -n 's/^#define PY_VERSION[[:space:]]*"\([^"]*\)".*/\1/p' "$_ab_header")
        fi
    fi
    if [ -z "$_ab_version" ]; then
        _ab_version="${_ab_found##*/python}"
    fi
    printf '%s\n' "$_ab_version"
}

# What the applet runs on, in the Build & Run pane: its OMC engine (the version of
# its Command.framework) and its embedded Python. Refreshed wherever the Embedded
# Python group is, because a build changes both: it updates an older framework and
# installs a missing runtime. The engine line says what Build will do about it, since
# that is the reason to look; the Python line does not, because Build replaces a
# working runtime only when asked to.
ab_applet_versions() { # <project-path>
    # No project yet: as for the Embedded Python group, no answer beats one about an
    # applet nobody has chosen.
    if [ -z "$1" ]; then
        return 0
    fi

    local _ab_fw="$1/Contents/Frameworks/Command.framework"
    local _ab_engine="$(plist_read "$(framework_info_plist "$_ab_fw")" CFBundleVersion)"
    local _ab_own_engine="$(plist_read "$(framework_info_plist "${OMC_APP_BUNDLE_PATH}/Contents/Frameworks/Command.framework")" CFBundleVersion)"
    local _ab_engine_cmp="$(compare_versions "$_ab_own_engine" "$_ab_engine")"
    # update_framework's three outcomes: install when the folder is missing, update
    # when ours compares newer (which an unreadable version always does), else keep.
    # An applet built before 6.0 carries the engine as Abracode.framework: Build replaces it
    local _ab_old_fw="$1/Contents/Frameworks/Abracode.framework"
    if [ ! -d "$_ab_fw" ] && [ -d "$_ab_old_fw" ]; then
        local _ab_old_engine="$(plist_read "$(framework_info_plist "$_ab_old_fw")" CFBundleVersion)"
        set_value "$BUILD_ENGINE_VERSION_ID" "${_ab_old_engine:-Unknown} (Abracode.framework) - Build replaces it with Command.framework ${_ab_own_engine}"
    elif [ ! -d "$_ab_fw" ]; then
        set_value "$BUILD_ENGINE_VERSION_ID" "Not installed - Build installs ${_ab_own_engine}"
    elif [ -z "$_ab_engine" ]; then
        set_value "$BUILD_ENGINE_VERSION_ID" "Version unknown - Build updates it to ${_ab_own_engine}"
    elif [ -n "$_ab_own_engine" ] && [ "$_ab_engine_cmp" = "newer" ]; then
        set_value "$BUILD_ENGINE_VERSION_ID" "${_ab_engine} - Build updates it to ${_ab_own_engine}"
    else
        set_value "$BUILD_ENGINE_VERSION_ID" "$_ab_engine"
    fi

    # The same test as the Embedded Python group, so the two never disagree.
    if [ ! -x "$(applet_python_bin "$1")" ]; then
        set_value "$BUILD_PYTHON_VERSION_ID" "None"
        return 0
    fi
    local _ab_python="$(applet_python_version "$1")"
    if [ -z "$_ab_python" ]; then
        set_value "$BUILD_PYTHON_VERSION_ID" "Present, version unknown"
    else
        set_value "$BUILD_PYTHON_VERSION_ID" "$_ab_python"
    fi
    return 0
}

# The Python thinning action, as the pane and the CLI both drive it. Returns 0 on
# success, 2 when the user declined the confirmation, and 1 (or the front end's
# own status) when the applet cannot be thinned or a phase failed. Declining is
# its own code because it is not a failure: the pane says so in orange rather
# than reporting a build-style error over an applet nothing touched.
applet_thin_python() { # <project-path>
    local project_path="$1"
    local action="${AB_THIN_PYTHON_ACTION:-plan}"

    if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
        ab_report "Error: No project loaded"
        return 1
    fi

    local app_name=$(/usr/bin/basename "$project_path")

    # Before the guards, not after them. This is the first ab_log of the run, and
    # in the GUI it is what replaces the previous run's transcript in the log
    # control - so a guard that reported and returned without logging would leave
    # the pane showing an older, successful run under a red verdict.
    ab_log "Thinning the embedded Python of ${app_name}..."

    case "$action" in
        plan|apply|apply-dry|plan-apply|plan-apply-dry) ;;
        *)
            ab_report "Unknown thinning action: ${action}"
            return 1
            ;;
    esac

    # Every route into the toolkit goes through this interpreter, including the
    # plan reader below. Naming it beats an exit code of 127 out of a pipeline.
    if [ ! -x "$python3" ]; then
        ab_report "AppletBuilder's own Python is missing or not executable:
  ${python3}

This bundle is incomplete; rerun update_appletbuilder.sh."
        return 1
    fi

    # An applet with no embedded interpreter has nothing to thin, and the front
    # end's own refusal names a path rather than the reason.
    if [ ! -x "$(applet_python_bin "$project_path")" ]; then
        ab_report "${app_name} does not bundle its own Python, so there is nothing to thin.

An applet gets an embedded interpreter from the New Applet panel's Python option,
or from a build with \"Update Embedded Python\" checked."
        return 1
    fi

    if [ ! -f "$thin_python_tool" ]; then
        ab_report "AppletBuilder's Python thinning toolkit is missing:
  ${thin_python_tool}

Rerun update_appletbuilder.sh to vendor it back in."
        return 1
    fi

    # Not on itself. The front end runs under $python3, which IS this bundle's
    # interpreter, so an apply here would delete modules out from under the
    # running process - and the verification hook then relaunches that same,
    # now-thinned interpreter to import json, shlex and argparse.
    #
    # Removal is the whole reason, so the two actions that remove nothing are not
    # refused: planning only ever executes a clone, and a dry run stops before the
    # backup, listing what an apply would take (thin_with_plan.sh returns before
    # it copies anything). Inspecting AppletBuilder's own bloat is a fair question
    # to ask of AppletBuilder.
    case "$action" in
        apply|plan-apply)
            # CDPATH= on both, or the comparison is defeated by an exported
            # CDPATH that resolves a relative "AppletBuilder.app" to some other
            # bundle: the two sides then differ and the guard waves through the
            # one case it exists to stop. Reproduced.
            local target_real=$(CDPATH= cd -P -- "$project_path" >/dev/null 2>&1 && pwd -P)
            local self_real=$(CDPATH= cd -P -- "$OMC_APP_BUNDLE_PATH" >/dev/null 2>&1 && pwd -P)
            if [ -n "$target_real" ] && [ "$target_real" = "$self_real" ]; then
                ab_report "This is AppletBuilder itself, and the thinning runs under its interpreter -
applying here would remove modules from the Python that is doing the removing.

Write a plan from here if you like, then apply it with the standalone script:
  Contents/Library/python_thinning/thin_applet_python.py apply <AppletBuilder.app>"
                return 1
            fi
            ;;
    esac

    # Resolved BEFORE the confirmation, so the alert can name the plan that is
    # about to be applied and where it came from. Which plan it is decides
    # whether saying yes is safe, and it used to reach the log only afterwards.
    # plan-apply resolves later, in thin_python_apply: its plan does not exist yet.
    THIN_PLAN_PATH=""
    THIN_PLAN_SOURCE=""
    case "$action" in
        apply|apply-dry)
            if ! applet_resolve_plan "$project_path"; then
                thin_python_report_no_plan "$project_path"
                return 1
            fi
            ;;
    esac

    # Every path that actually removes modules asks first. A dry run does not: it
    # writes nothing, and having to confirm a preview would train people to
    # confirm without reading.
    local confirm_plan
    case "$action" in
        apply|plan-apply)
            if [ "$action" != "apply" ]; then
                confirm_plan="$AB_THIN_PLAN"
                if [ -z "$confirm_plan" ]; then
                    confirm_plan=$(applet_plan_path "$project_path")
                fi
                confirm_plan="a plan about to be written to
${confirm_plan}"
            else
                confirm_plan="the plan at
${THIN_PLAN_PATH}"
                if [ "$THIN_PLAN_SOURCE" = "remembered" ]; then
                    confirm_plan="${confirm_plan}
(no plan beside the applet - this is the one last written for $(applet_short_name "$project_path"))"
                fi
            fi

            if ! ab_confirm "Remove unused Python modules from ${app_name}?

This rewrites the applet's embedded interpreter in place, using ${confirm_plan}

Thinning is usually done on a distribution copy prepared for release, not on the
development copy the plan is written from."; then
                ab_log ""
                ab_log "Thinning canceled."
                return 2
            fi
            ;;
    esac

    local rc
    case "$action" in
        plan)
            thin_python_plan "$project_path"
            rc=$?
            ;;
        apply)
            thin_python_apply "$project_path" 0
            rc=$?
            ;;
        apply-dry)
            thin_python_apply "$project_path" 1
            rc=$?
            ;;
        plan-apply|plan-apply-dry)
            # One plan, then the apply that plan authorizes. A failed plan stops
            # here rather than applying whatever older plan happens to be on
            # disk - which is precisely what the resolution fallback would find.
            thin_python_plan "$project_path"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                # Hand the apply the plan this run just wrote, through the
                # resolution globals rather than by writing back into
                # AB_THIN_PLAN. That is the CALLER's option: a phase that
                # modifies its own input leaves it modified for the next call in
                # the same shell, where a later "plan Beta.app" would have
                # overwritten Alpha's reviewed plan. Not reachable from either
                # front door today, and not a trap worth leaving set.
                THIN_PLAN_PATH="$AB_THIN_PLAN"
                if [ -z "$THIN_PLAN_PATH" ]; then
                    THIN_PLAN_PATH=$(applet_plan_path "$project_path")
                fi
                THIN_PLAN_SOURCE="written"
                if [ "$action" = "plan-apply-dry" ]; then
                    thin_python_apply "$project_path" 1
                else
                    thin_python_apply "$project_path" 0
                fi
                rc=$?
            fi
            ;;
    esac

    # 2 is this function's "the user declined" code, and it is also what the
    # front end's argparse exits with on a usage error - which would be a bug in
    # the argument assembly above, not anything the user did. Normalizing it
    # keeps the pane from reporting a canceled run over one that really failed.
    if [ "$rc" -eq 2 ]; then
        rc=1
    fi

    return "$rc"
}
