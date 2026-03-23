#!/bin/bash
# lib.builder.sh - Shared functions for AppletBuilder

echo "loading lib.builder.sh"

# ──────────────────────────────────────────────────────────────
# Dialog tool setup
# ──────────────────────────────────────────────────────────────

dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
python3="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python/bin/python3"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"

# ──────────────────────────────────────────────────────────────
# Control IDs
# ──────────────────────────────────────────────────────────────

# Project window (TabView)
TAB_VIEW_ID=10
GENERAL_TAB_VIEW_ID=101
BUILD_RUN_TAB_VIEW_ID=102
COMMANDS_TAB_VIEW_ID=103
SCRIPTS_TAB_VIEW_ID=104
UI_FILES_TAB_VIEW_ID=105

# New Applet form
NEW_TYPE_PICKER_ID=201
NEW_TEMPLATE_PATH_ID=202
NEW_NAME_ID=203
NEW_BUNDLE_ID_ID=204
NEW_ICON_ID=206
NEW_CLONE_SOURCE_ROW_ID=207
NEW_PYTHON_TOGGLE_ID=208
NEW_ICON_PICKER_ID=209
NEW_CUSTOM_ICON_ROW_ID=210
NEW_HEADER_IMAGE_ID=211
NEW_HEADER_NAME_ID=212
NEW_STATUS_ID=220
NEW_CREATE_BTN_ID=221

# General form
GEN_NAME_ID=302
GEN_BUNDLE_ID_ID=303
GEN_VERSION_ID=305
GEN_ICON_IMAGE_ID=307
GEN_HEADER_NAME_ID=308
GEN_STATUS_ID=320

# Commands tab
CMD_TABLE_ID=501
CMD_DETAIL_ID=502
CMD_ADD_BTN_ID=511
CMD_REMOVE_BTN_ID=512
CMD_REVEAL_BTN_ID=514
CMD_VALIDATE_BTN_ID=520
CMD_SAVE_BTN_ID=523
CMD_EDITED_LABEL_ID=524
CMD_EXT_EDIT_BTN_ID=525
CMD_TOOLBAR_ID=526

# Scripts tab
SCRIPTS_TABLE_ID=601
SCRIPTS_DETAIL_ID=602
SCRIPTS_ADD_BTN_ID=611
SCRIPTS_REMOVE_BTN_ID=612
SCRIPTS_REVEAL_BTN_ID=614
SCRIPTS_SAVE_BTN_ID=623
SCRIPTS_EDITED_LABEL_ID=624
SCRIPTS_EXT_EDIT_BTN_ID=625
SCRIPTS_TOOLBAR_ID=626

# UI Files tab
UI_TABLE_ID=701
UI_DETAIL_ID=702
UI_ADD_BTN_ID=711
UI_REMOVE_BTN_ID=712
UI_REVEAL_BTN_ID=714
UI_VALIDATE_BTN_ID=720
UI_PRETTIFY_BTN_ID=721
UI_PREVIEW_BTN_ID=722
UI_SAVE_BTN_ID=723
UI_EDITED_LABEL_ID=724
UI_EXT_EDIT_BTN_ID=725
UI_TOOLBAR_ID=726
UI_TEMPLATE_PICKER_ID=728

# Services (in General tab)
SVC_TABLE_ID=330
SVC_MENU_TITLE_ID=331
SVC_COMMAND_PICKER_ID=332
SVC_INPUT_PICKER_ID=333
SVC_ADD_BTN_ID=334
SVC_REMOVE_BTN_ID=335
SVC_SAVE_BTN_ID=336
SVC_STATUS_ID=337

# New Command dialog
NEWCMD_NAME_ID=801
NEWCMD_COMMAND_ID_ID=802
NEWCMD_EXECUTION_ID=803
NEWCMD_ACTIVATION_ID=804
NEWCMD_SCRIPT_ID=805
NEWCMD_STATUS_ID=810
NEWCMD_CREATE_BTN_ID=811

# New Script dialog
NEWSCRIPT_NAME_ID=821
NEWSCRIPT_TYPE_ID=822
NEWSCRIPT_STATUS_ID=830
NEWSCRIPT_CREATE_BTN_ID=831

# New UI File dialog
NEWUI_NAME_ID=841
NEWUI_TYPE_ID=842
NEWUI_STATUS_ID=850
NEWUI_CREATE_BTN_ID=851

# Settings dialog
SETTINGS_EDITOR_PATH_ID=861
SETTINGS_EDITOR_NAME_ID=862

# Help Viewer
HELP_BACK_BTN_ID=901
HELP_FORWARD_BTN_ID=902
HELP_TITLE_ID=903
HELP_WEBVIEW_ID=910

# Build & Run
BUILD_IDENTITY_PICKER_ID=402
BUILD_LOG_ID=401

# ──────────────────────────────────────────────────────────────
# State management (temp files keyed by window UUID)
# ──────────────────────────────────────────────────────────────

state_dir="/tmp/appletbuilder_${OMC_ACTIONUI_WINDOW_UUID}"

get_state_dir() {
    /bin/mkdir -p "$state_dir"
    echo "$state_dir"
}

save_project_path() {
    local dir=$(get_state_dir)
    echo "$1" > "$dir/project_path"
}

load_project_path() {
    local dir=$(get_state_dir)
    if [ -f "$dir/project_path" ]; then
        cat "$dir/project_path"
    fi
}

cleanup_state() {
    /bin/rm -rf "$state_dir"
}

# ──────────────────────────────────────────────────────────────
# Error display
# ──────────────────────────────────────────────────────────────

APPLET_BUILDER_ERRORS_PB="APPLET_BUILDER_ERRORS"

# Show error details in an output window via private pasteboard
show_errors() {
    local error_text="$1"
    "$pasteboard_tool" "$APPLET_BUILDER_ERRORS_PB" set "$error_text"
    "$next_cmd" "$cmd_guid" "AppletBuilder.show.errors"
}

# ──────────────────────────────────────────────────────────────
# UI helpers
# ──────────────────────────────────────────────────────────────

set_value() {
    local view_id="$1"
    local value="$2"
    "$dialog_tool" "$window_uuid" "$view_id" "$value"
}

set_status() {
    local view_id="$1"
    local message="$2"
    set_value "$view_id" "$message"
}

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

set_window_title() {
    local title="$1"
    "$dialog_tool" "$window_uuid" omc_window "$title"
}

set_enabled() {
    local view_id="$1"
    local enabled="$2"
    if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_enable
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_disable
    fi
}

set_visible() {
    local view_id="$1"
    local visible="$2"
    if [ "$visible" = "1" ] || [ "$visible" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_show
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_hide
    fi
}

# ──────────────────────────────────────────────────────────────
# Table refresh helpers
# ──────────────────────────────────────────────────────────────

# Rebuild and populate the commands table from Command.plist
# Usage: refresh_commands_table "$cmd_plist" [target_uuid]
refresh_commands_table() {
    local cmd_plist="$1"
    local target="${2:-$window_uuid}"
    local plister="$OMC_OMC_SUPPORT_PATH/plister"
    local count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
    local buffer=""
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        local i=0
        while [ "$i" -lt "$count" ]; do
            local cname=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/NAME" 2>/dev/null | /usr/bin/tr -d '\n')
            local cid=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/COMMAND_ID" 2>/dev/null)
            local label
            if [ -n "$cid" ]; then
                label="$cid"
            elif [ -n "$cname" ]; then
                label="$cname.main"
            else
                label="Command $i"
            fi
            buffer="${buffer}${label}	${i}
"
            i=$((i + 1))
        done
    fi
    printf "%s" "$buffer" | "$dialog_tool" "$target" "$CMD_TABLE_ID" omc_table_set_rows_from_stdin
}

# Rebuild and populate the scripts table from the Scripts directory
# Usage: refresh_scripts_table "$scripts_dir" [target_uuid]
refresh_scripts_table() {
    local scripts_dir="$1"
    local target="${2:-$window_uuid}"
    local buffer=""
    for sf in "$scripts_dir"/*; do
        [ ! -f "$sf" ] && continue
        local sname=$(/usr/bin/basename "$sf")
        buffer="${buffer}${sname}	${sf}
"
    done
    printf "%s" "$buffer" | "$dialog_tool" "$target" "$SCRIPTS_TABLE_ID" omc_table_set_rows_from_stdin
}

# Rebuild and populate the UI files table from Base.lproj and Resources
# Usage: refresh_uifiles_table "$project_path" [target_uuid]
refresh_uifiles_table() {
    local project_path="$1"
    local target="${2:-$window_uuid}"
    local resources_dir="$project_path/Contents/Resources"
    local lproj_dir="$resources_dir/Base.lproj"
    local buffer=""
    if [ -d "$lproj_dir" ]; then
        for nib in "$lproj_dir"/*.nib; do
            [ ! -d "$nib" ] && continue
            local nib_name=$(/usr/bin/basename "$nib")
            buffer="${buffer}${nib_name}	${nib}
"
        done
        for json in "$lproj_dir"/*.json; do
            [ ! -f "$json" ] && continue
            local json_name=$(/usr/bin/basename "$json")
            buffer="${buffer}${json_name}	${json}
"
        done
    fi
    for json in "$resources_dir"/*.json; do
        [ ! -f "$json" ] && continue
        local json_name=$(/usr/bin/basename "$json")
        buffer="${buffer}${json_name}	${json}
"
    done
    printf "%s" "$buffer" | "$dialog_tool" "$target" "$UI_TABLE_ID" omc_table_set_rows_from_stdin
}

# ──────────────────────────────────────────────────────────────
# Help documentation
# ──────────────────────────────────────────────────────────────

HELP_HTML_DIR="/tmp/appletbuilder_help"

ensure_help_docs_converted() {
    local docs_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Documentation"
    local html_dir="$HELP_HTML_DIR"
    local needs_convert=0

    if [ ! -d "$html_dir" ]; then
        needs_convert=1
    else
        for src in "$docs_dir"/*.md "$docs_dir"/Schemas/*.md "$docs_dir"/Elements/*.json; do
            [ ! -f "$src" ] && continue
            local rel="${src#$docs_dir/}"
            local out
            case "$src" in
                *.md) out="$html_dir/${rel%.md}.html" ;;
                *)    out="$html_dir/$rel" ;;
            esac
            if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
                needs_convert=1
                break
            fi
        done
    fi

    if [ "$needs_convert" -eq 1 ]; then
        "$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/md2html.py" --dir "$docs_dir" "$html_dir"
    fi
}

# ──────────────────────────────────────────────────────────────
# Plist helpers
# ──────────────────────────────────────────────────────────────

plist_read() {
    local plist="$1"
    local key="$2"
    /usr/bin/plutil -extract "$key" raw "$plist" 2>/dev/null
}

plist_write() {
    local plist="$1"
    local key="$2"
    local value="$3"
    /usr/bin/plutil -replace "$key" -string "$value" "$plist" 2>/dev/null
}

# Generate a unique COMMAND_ID for a given prefix.
# Checks existing IDs in Command.plist and appends a numeric suffix if needed.
# Usage: unique_command_id "$cmd_plist" "$prefix"
# Output: prints the unique ID to stdout
unique_command_id() {
    local cmd_plist="$1"
    local prefix="$2"
    local plister="$OMC_OMC_SUPPORT_PATH/plister"
    local existing_ids=""
    if [ -f "$cmd_plist" ]; then
        local count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
        if [ -n "$count" ] && [ "$count" -gt 0 ]; then
            local i=0
            while [ "$i" -lt "$count" ]; do
                local cid=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/COMMAND_ID" 2>/dev/null)
                existing_ids="${existing_ids}${cid}
"
                i=$((i + 1))
            done
        fi
    fi
    local candidate="${prefix}.new.command"
    local suffix=2
    while echo "$existing_ids" | /usr/bin/grep -qx "$candidate"; do
        candidate="${prefix}.new.command.${suffix}"
        suffix=$((suffix + 1))
    done
    echo "$candidate"
}

# Edit a plist via JSON round-trip with Python.
# Converts plist to JSON, calls plist_edit.py with the operation and args,
# then converts back to xml1 plist.
#
# Usage:
#   plist_edit "$plist" set_keys CFBundleName "$name"
#   plist_edit "$plist" append_service "$title" "$cmd"
#   plist_edit "$plist" replace_command "$index" "$json_file"
plist_edit() {
    local plist="$1"
    local operation="$2"
    shift 2
    local tmp=$(/usr/bin/mktemp /tmp/plist_edit_XXXXXX.json)
    /usr/bin/plutil -convert json -o "$tmp" "$plist" || { /bin/rm -f "$tmp"; return 1; }
    "$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/plist_edit.py" "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
    /usr/bin/plutil -convert xml1 -o "$plist" "$tmp"
    local rc=$?
    /bin/rm -f "$tmp"
    return $rc
}

# ──────────────────────────────────────────────────────────────
# Build functions (extracted from build_applet.sh)
# ──────────────────────────────────────────────────────────────

# Compile and install icon
applet_install_icon() {
    local icon_source="$1"
    local app_path="$2"

    if [ -z "$icon_source" ] || [ ! -e "$icon_source" ]; then
        return 1
    fi

    local icon_base=$(/usr/bin/basename "${icon_source%.*}")

    local resources_dir="$app_path/Contents/Resources"
    local temp_dir=$(/usr/bin/mktemp -d) || return 1

    /usr/bin/xcrun actool "$icon_source" \
        --compile "$temp_dir" \
        --app-icon "$icon_base" \
        --platform macosx \
        --target-device mac \
        --output-format human-readable-text \
        --minimum-deployment-target 14.6 \
        --output-partial-info-plist "$temp_dir/partial.plist" \
        > "$temp_dir/actool.log" 2>&1

    local success=0

    if [ -f "$temp_dir/Assets.car" ]; then
        /bin/cp "$temp_dir/Assets.car" "$resources_dir/Assets.car"
        success=1
    fi

    if [ -f "$temp_dir/$icon_base.icns" ]; then
        /bin/cp "$temp_dir/$icon_base.icns" "$resources_dir/$icon_base.icns"
        success=1
    fi

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleIconFile" "$icon_base"
        plist_write "$plist" "CFBundleIconName" "$icon_base"
    fi

    /bin/rm -rf "$temp_dir"
    return $( [ $success -eq 1 ] && echo 0 || echo 1 )
}

# Update creator code in PkgInfo and Info.plist
applet_set_creator_code() {
    local app_path="$1"
    local creator="$2"

    if [ -z "$creator" ] || [ ${#creator} -ne 4 ]; then
        return 1
    fi

    local pkginfo="$app_path/Contents/PkgInfo"
    if [ -f "$pkginfo" ]; then
        printf 'APPL%s' "$creator" > "$pkginfo"
    fi

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleSignature" "$creator"
    fi
}

# Update bundle identifier
applet_set_bundle_id() {
    local app_path="$1"
    local bundle_id="$2"

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleIdentifier" "$bundle_id"
    fi
}

# Recompile MainMenu.nib with new name
applet_recompile_nib() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local nib_dir="$app_path/Contents/Resources/Base.lproj/MainMenu.nib"
    local designable="$nib_dir/designable.nib"

    if [ ! -f "$designable" ]; then
        return 0
    fi

    /usr/bin/sed -i '' "s/$old_name/$new_name/g" "$designable"

    local temp_nib="$app_path/Contents/Resources/Base.lproj/temp.nib"
    /usr/bin/xcrun ibtool --compile "$temp_nib" --flatten NO "$nib_dir"

    /bin/rm -rf "$nib_dir"
    /bin/mv "$temp_nib" "$nib_dir"
}

# Finalize: touch + register with Launch Services
applet_finalize() {
    local app_path="$1"
    /usr/bin/touch -c "$app_path"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "$app_path" 2>/dev/null
}

# Install runtime binaries (executable + Abracode.framework) from AppletBuilder
applet_install_binaries() {
    local app_path="$1"
    local app_name="$2"

    local builder_exe="${OMC_APP_BUNDLE_PATH}/Contents/MacOS/$(/usr/bin/basename "${OMC_APP_BUNDLE_PATH%.app}")"
    local builder_fw="${OMC_APP_BUNDLE_PATH}/Contents/Frameworks/Abracode.framework"

    # Copy executable, renamed to match the applet
    /bin/mkdir -p "$app_path/Contents/MacOS"
    /bin/cp "$builder_exe" "$app_path/Contents/MacOS/$app_name"
    /bin/chmod +x "$app_path/Contents/MacOS/$app_name"

    # Copy framework if AppletBuilder's is newer or destination doesn't have one
    local dest_fw="$app_path/Contents/Frameworks/Abracode.framework"
    if [ -d "$builder_fw" ]; then
        local need_copy=0
        if [ ! -d "$dest_fw" ]; then
            need_copy=1
        else
            local src_ver=$(/usr/bin/plutil -extract CFBundleVersion raw "$builder_fw/Resources/Info.plist" 2>/dev/null)
            local dst_ver=$(/usr/bin/plutil -extract CFBundleVersion raw "$dest_fw/Resources/Info.plist" 2>/dev/null)
            if [ "$src_ver" != "$dst_ver" ]; then
                need_copy=1
            fi
        fi
        if [ "$need_copy" -eq 1 ]; then
            /bin/mkdir -p "$app_path/Contents/Frameworks"
            /bin/rm -rf "$dest_fw"
            /bin/cp -Rp "$builder_fw" "$dest_fw"
        fi
    fi

}

# Install Python runtime from AppletBuilder into target applet
applet_install_python() {
    local app_path="$1"
    local src="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python"
    if [ -d "$src" ]; then
        /bin/mkdir -p "$app_path/Contents/Library"
        /bin/cp -Rp "$src" "$app_path/Contents/Library/Python"
    fi
}

# Rename scripts to match new applet name
applet_rename_scripts() {
    local scripts_dir="$1"
    local old_name="$2"
    local new_name="$3"

    local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
    local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')

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
        /usr/bin/sed -i '' "s/${old_name}/${new_name}/g" "$script"
        if [ "$old_lower" != "$old_name" ]; then
            /usr/bin/sed -i '' "s/${old_lower}/${new_lower}/g" "$script"
        fi
    done
}

# Recompile all non-MainMenu nibs
applet_recompile_other_nibs() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local lproj_dir="$app_path/Contents/Resources/Base.lproj"
    for nib_dir in "$lproj_dir"/*.nib; do
        [ ! -d "$nib_dir" ] && continue
        local nib_base=$(/usr/bin/basename "${nib_dir%.nib}")
        [ "$nib_base" = "MainMenu" ] && continue
        local designable="$nib_dir/designable.nib"
        if [ -f "$designable" ]; then
            /usr/bin/sed -i '' "s/$old_name/$new_name/g" "$designable"
            local temp_nib="$lproj_dir/temp_recompile.nib"
            /usr/bin/xcrun ibtool --compile "$temp_nib" --flatten NO "$nib_dir" 2>/dev/null
            if [ -d "$temp_nib" ]; then
                /bin/rm -rf "$nib_dir"
                /bin/mv "$temp_nib" "$nib_dir"
            fi
        fi
    done
}

# Update Credits.rtf with new name
applet_update_credits() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local credits="$app_path/Contents/Resources/Credits.rtf"
    if [ -f "$credits" ]; then
        /usr/bin/sed -i '' "s/${old_name}/${new_name}/g" "$credits"
        local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        if [ "$old_lower" != "$old_name" ]; then
            /usr/bin/sed -i '' "s/${old_lower}/${new_lower}/g" "$credits"
        fi
    fi
}

# Update URL scheme in Info.plist
applet_update_url_scheme() {
    local plist="$1"
    local new_name="$2"

    local url_scheme=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '-' | /usr/bin/tr -cd 'a-z0-9-')
    /usr/bin/plutil -replace "CFBundleURLTypes.0.CFBundleURLName" -string "$new_name" "$plist" 2>/dev/null
    /usr/bin/plutil -replace "CFBundleURLTypes.0.CFBundleURLSchemes.0" -string "$url_scheme" "$plist" 2>/dev/null
}

# Remove stale .icns files that don't match the given name
applet_cleanup_icons() {
    local app_path="$1"
    local keep_name="$2"

    for old_icns in "$app_path/Contents/Resources/"*.icns; do
        [ ! -f "$old_icns" ] && continue
        local old_base=$(/usr/bin/basename "${old_icns%.icns}")
        if [ "$old_base" != "$keep_name" ]; then
            /bin/rm -f "$old_icns"
        fi
    done
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

    # Recompile nibs
    applet_recompile_nib "$app_path" "$old_name" "$new_name"
    applet_recompile_other_nibs "$app_path" "$old_name" "$new_name"

    # Update Command.plist NAME
    local cmd_plist="$app_path/Contents/Resources/Command.plist"
    if [ -f "$cmd_plist" ]; then
        /usr/bin/sed -i '' "s|<string>${old_name}</string>|<string>${new_name}</string>|" "$cmd_plist"
    fi

    # Rename and update scripts
    applet_rename_scripts "$app_path/Contents/Resources/Scripts" "$old_name" "$new_name"

    # Update Credits.rtf
    applet_update_credits "$app_path" "$old_name" "$new_name"
}

# Ad-hoc codesign using the standalone script
applet_codesign() {
    local app_path="$1"
    local identity="$2"
    /bin/sh "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/codesign_applet.sh" "$app_path" "$identity"
}
