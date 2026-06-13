#!/bin/bash
# lib.tables.sh - Table refresh helpers for AppletBuilder
#
# Sources lib.common.sh for: dialog_tool, window_uuid, and the
# CMD_TABLE_ID / SCRIPTS_TABLE_ID / UI_TABLE_ID control IDs.

[ -n "$__LIB_TABLES_SH" ] && return 0
__LIB_TABLES_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

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
            is_command_file_name "$json_name" && continue
            buffer="${buffer}${json_name}	${json}
"
        done
    fi
    for json in "$resources_dir"/*.json; do
        [ ! -f "$json" ] && continue
        local json_name=$(/usr/bin/basename "$json")
        is_command_file_name "$json_name" && continue
        buffer="${buffer}${json_name}	${json}
"
    done
    printf "%s" "$buffer" | "$dialog_tool" "$target" "$UI_TABLE_ID" omc_table_set_rows_from_stdin
}
