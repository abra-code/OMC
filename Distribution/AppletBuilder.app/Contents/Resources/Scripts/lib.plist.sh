#!/bin/bash
# lib.plist.sh - Info.plist / Command.plist read/write/edit helpers
#
# Sources lib.common.sh for: python3

[ -n "$__LIB_PLIST_SH" ] && return 0
__LIB_PLIST_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

# A top-level key's value (a string, number or bool as text); nothing when the key or file is not there
plist_read() {
    local plist="$1"
    local key="$2"
    "$plister_tool" get value "$plist" "/$key" 2>/dev/null
}

# Sets a top-level key to a string, adding it when it is not there (insert replaces an existing
# key). The file keeps its format (XML, binary or JSON).
plist_write() {
    local plist="$1"
    local key="$2"
    local value="$3"
    "$plister_tool" insert "$key" string "$value" "$plist" / > /dev/null 2>&1
}

# Generate a unique COMMAND_ID for a given prefix.
# Checks existing IDs in Command.plist and appends a numeric suffix if needed.
# Usage: unique_command_id "$cmd_plist" "$prefix"
# Output: prints the unique ID to stdout
unique_command_id() {
    local cmd_plist="$1"
    local prefix="$2"
    local plister="$plister_tool"
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

# Whether a string is a whole non-negative number (an array index or a count)
plist_is_index() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

# The Info.plist edits, made with plister alone, on macOS and Linux alike: they also show an
# applet with no Python how to change a property list from a shell script. plister keeps the
# file's format (XML or binary; a file with no extension, such as the temp copy plist_edit works
# on, is read by its content) and writes the keys of each dictionary in sorted order, as plutil
# does. Each function stops at the first failed step and returns 1; plist_edit works on a copy,
# so the original is never left half edited.

# Sets top-level keys to strings, adding those that are not there
#   info_plist_set_keys <file> <key> <value> [<key> <value> ...]
info_plist_set_keys() {
    local file="$1"
    shift
    if [ "$#" -lt 2 ]; then
        echo "plist_edit set_keys: a key and a value are needed" >&2
        return 1
    fi
    while [ "$#" -ge 2 ]; do
        "$plister_tool" insert "$1" string "$2" "$file" / > /dev/null || return 1
        shift 2
    done
    if [ "$#" -ne 0 ]; then
        echo "plist_edit set_keys: the key \"$1\" has no value" >&2
        return 1
    fi
    return 0
}

# Adds a service for files and folders at the end of NSServices (made when there is none)
#   info_plist_append_service <file> <menu title> <command id>
info_plist_append_service() {
    local file="$1"
    local title="$2"
    local command_id="$3"
    local services_type="$("$plister_tool" get type "$file" /NSServices 2> /dev/null)"
    if [ -z "$services_type" ]; then
        "$plister_tool" insert NSServices array "$file" / > /dev/null || return 1
    elif [ "$services_type" != "array" ]; then
        echo "plist_edit append_service: NSServices is not an array" >&2
        return 1
    fi
    local count
    count="$("$plister_tool" get count "$file" /NSServices)" || return 1
    plist_is_index "$count" || return 1
    "$plister_tool" append dict "$file" /NSServices > /dev/null || return 1
    local item="/NSServices/$count"
    # "dict" and "array" make empty containers and take no value
    "$plister_tool" insert NSMenuItem dict "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert default string "$title" "$file" "$item/NSMenuItem" > /dev/null || return 1
    "$plister_tool" insert NSMessage string runOMCService "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert NSPortName string OMCService "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert NSRequiredContext dict "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert NSReturnTypes array "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert NSSendTypes array "$file" "$item" > /dev/null || return 1
    "$plister_tool" append string NSFilenamesPboardType "$file" "$item/NSSendTypes" > /dev/null || return 1
    "$plister_tool" insert NSUserData string "$command_id" "$file" "$item" > /dev/null || return 1
    return 0
}

# Saves the Services pane's fields into the service at an index: its title and command, and its
# send types only when the Input picker changed from what the pane showed. The pane saves at
# every field change, so rewriting the types each time turned a folders-only service
# (NSSendFileTypes public.folder, which the picker cannot show) into one for any file or folder
# at a title edit. The kind is read by the pane's own rule (AppletBuilder.services.selected.sh):
# "text" when the first NSSendTypes entry is NSStringPboardType, else "files".
#   info_plist_update_service <file> <index> <menu title> <command id> <files|text>
info_plist_update_service() {
    local file="$1"
    local index="$2"
    local title="$3"
    local command_id="$4"
    local input_kind="$5"
    plist_is_index "$index" || return 1
    local item="/NSServices/$index"
    local item_type="$("$plister_tool" get type "$file" "$item" 2> /dev/null)"
    if [ "$item_type" != "dict" ]; then
        echo "plist_edit update_service: there is no service $index" >&2
        return 1
    fi
    # insert replaces a key that is there: a new NSMenuItem holds the title only
    "$plister_tool" insert NSMenuItem dict "$file" "$item" > /dev/null || return 1
    "$plister_tool" insert default string "$title" "$file" "$item/NSMenuItem" > /dev/null || return 1
    "$plister_tool" insert NSUserData string "$command_id" "$file" "$item" > /dev/null || return 1
    local first_type="$("$plister_tool" get value "$file" "$item/NSSendTypes/0" 2> /dev/null)"
    local shown_kind="files"
    if [ "$first_type" = "NSStringPboardType" ]; then
        shown_kind="text"
    fi
    # Only a picker value the pane has ("files", "text") changes the types: a save that came with
    # no value (in the Linux test box a folders-only service lost its types this way) keeps them
    local send_type
    case "$input_kind" in
        "$shown_kind") return 0 ;;
        text) send_type="NSStringPboardType" ;;
        files) send_type="NSFilenamesPboardType" ;;
        *) return 0 ;;
    esac
    # remove succeeds when the key is not there
    "$plister_tool" remove "$file" "$item/NSSendFileTypes" > /dev/null || return 1
    "$plister_tool" insert NSSendTypes array "$file" "$item" > /dev/null || return 1
    "$plister_tool" append string "$send_type" "$file" "$item/NSSendTypes" > /dev/null || return 1
    return 0
}

# Removes the service at an index; nothing to do when there is none
#   info_plist_remove_service <file> <index>
info_plist_remove_service() {
    local file="$1"
    local index="$2"
    plist_is_index "$index" || return 1
    local item_type="$("$plister_tool" get type "$file" "/NSServices/$index" 2> /dev/null)"
    if [ -z "$item_type" ]; then
        return 0
    fi
    "$plister_tool" remove "$file" "/NSServices/$index" > /dev/null || return 1
    return 0
}

# Puts an edited temp copy in place of the original, with the original's permissions. mktemp
# creates 0600 and `cp` into an existing file keeps the destination's mode, so without this the
# mv silently turns a 0644 file owner-only on every save - and nothing later in the build or
# codesign path puts it back, so the applet stops being readable for anyone it is distributed to.
# chmod-then-mv rather than `cat >` keeps the replace atomic. The mode in octal: BSD stat on
# macOS, GNU stat on Linux.
#   plist_edit_replace <edited copy> <original>
plist_edit_replace() {
    local copy="$1"
    local original="$2"
    local mode
    case "${OSTYPE:-}" in
        darwin*) mode=$(/usr/bin/stat -f '%Lp' "$original" 2>/dev/null) ;;
        *) mode=$(/usr/bin/stat -c '%a' "$original" 2>/dev/null) ;;
    esac
    if [ -n "$mode" ]; then
        /bin/chmod "$mode" "$copy"
    fi
    /bin/mv "$copy" "$original"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        /bin/rm -f "$copy"
    fi
    return $rc
}

# Edit an Info.plist, or a command file.
#
# The Info.plist operations (set_keys, append_service, update_service, remove_service) are
# made with plister (the info_plist_* functions above), on macOS and Linux. The command file
# operations are plist_edit.py's: a .json file (Command.json) is edited as it is; a legacy
# Command.plist is round-tripped through JSON with plutil (plist -> json -> edit -> xml1), on
# macOS only. Every path edits a temp copy and only replaces the original on success, so a
# failed edit never corrupts the file.
#
# Usage:
#   plist_edit "$plist" set_keys CFBundleName "$name"
#   plist_edit "$plist" append_service "$title" "$cmd"
#   plist_edit "$cmd_file" replace_command "$index" "$json_file"
plist_edit() {
    local plist="$1"
    local operation="$2"
    shift 2
    local editor="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/plist_edit.py"
    # The X's must be TRAILING. BSD mktemp only substitutes a trailing run of
    # them, so "..._XXXXXX.json" is not a template at all - it creates that exact
    # name, and the next call fails with "File exists" and prints nothing. A temp
    # file left behind by an interrupted save would then wedge every later save
    # permanently. No extension is needed: nothing downstream reads one.
    #
    # Split from the declaration because `local` is itself a command and would
    # set $? to its own success, hiding a failed mktemp.
    local tmp
    tmp=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/plist_edit_XXXXXX")
    if [ $? -ne 0 ] || [ -z "$tmp" ]; then
        return 1
    fi

    local info_edit
    case "$operation" in
        set_keys|append_service|update_service|remove_service) info_edit="info_plist_$operation" ;;
        *) info_edit="" ;;
    esac
    if [ -n "$info_edit" ]; then
        /bin/cp "$plist" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        "$info_edit" "$tmp" "$@" || { /bin/rm -f "$tmp"; return 1; }
        plist_edit_replace "$tmp" "$plist"
        return $?
    fi

    if is_json_command_file "$plist"; then
        /bin/cp "$plist" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        "$python3" "$editor" "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
        plist_edit_replace "$tmp" "$plist"
        return $?
    fi

    # A legacy Command.plist: plutil, macOS only (a Linux applet's command file is Command.json)
    if ! ab_on_macos; then
        echo "plist_edit: $operation on a Command.plist needs macOS (plutil)" >&2
        /bin/rm -f "$tmp"
        return 1
    fi
    /usr/bin/plutil -convert json -o "$tmp" "$plist" || { /bin/rm -f "$tmp"; return 1; }
    "$python3" "$editor" "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
    /usr/bin/plutil -convert xml1 -o "$plist" "$tmp"
    local rc=$?
    /bin/rm -f "$tmp"
    return $rc
}

# One command of a command file as the command editor shows it: indented JSON (keys in file
# order) for a Command.json, read with Python, so it works on Linux too; the <dict> fragment of
# the XML for a legacy Command.plist (macOS only: plutil). Nothing when the file or the command
# is not there.
command_text() { # <command file> <index>
    if is_json_command_file "$1"; then
        "$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/plist_edit.py" "$1" print_command "$2" 2>/dev/null
        return $?
    fi
    /usr/bin/plutil -extract "COMMAND_LIST.$2" xml1 -o - "$1" 2>/dev/null | /usr/bin/sed '1,3d; $d'
}
