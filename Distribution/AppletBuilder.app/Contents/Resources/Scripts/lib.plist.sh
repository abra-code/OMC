#!/bin/bash
# lib.plist.sh - Info.plist / Command.plist read/write/edit helpers
#
# Sources lib.common.sh for: python3

[ -n "$__LIB_PLIST_SH" ] && return 0
__LIB_PLIST_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

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
