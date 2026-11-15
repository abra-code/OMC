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

# The Services pane's Input kind of the service at an index, the value its Input picker shows
# (AppletBuilder.services.selected.sh) and the one update_service compares a save with:
#   text     no file types, and NSSendTypes names a text type (NSStringPboardType,
#            public.utf8-plain-text, public.plain-text, public.text, NSPasteboardTypeString)
#   folders  NSSendFileTypes is exactly public.folder, and NSSendTypes names no text type
#   files    NSSendFileTypes is exactly public.item (and no text type), or no file types and
#            NSSendTypes names NSFilenamesPboardType or public.file-url, or nothing at all
#   other    any other NSSendFileTypes (public.image, public.folder with more, ...), or file types
#            together with a text type: the picker shows it and a save keeps it, since the pane
#            cannot write such a list
# A non-empty NSSendFileTypes makes a file service whatever NSSendTypes says, as the engine
# (OMCService.m, OMCApplet.cpp) and Linux/command-services.py take it.
#   info_plist_service_kind <file> <index>
info_plist_service_kind() {
    local file="$1"
    local item="/NSServices/$2"
    # A count of an entry that is not an array is 0, of one that is not there empty
    local send_count="$("$plister_tool" get count "$file" "$item/NSSendTypes" 2> /dev/null)"
    case "$send_count" in
        ''|*[!0-9]*) send_count=0 ;;
    esac
    local has_text=false
    local send_type
    local i=0
    # By the count: an entry that is not a string reads as nothing and must not end the scan
    while [ "$i" -lt "$send_count" ]; do
        send_type="$("$plister_tool" get value "$file" "$item/NSSendTypes/$i" 2> /dev/null)"
        case "$send_type" in
            NSStringPboardType|public.utf8-plain-text|public.plain-text|public.text|NSPasteboardTypeString)
                has_text=true
                break
                ;;
        esac
        i=$((i + 1))
    done
    local file_type_count="$("$plister_tool" get count "$file" "$item/NSSendFileTypes" 2> /dev/null)"
    case "$file_type_count" in
        ''|*[!0-9]*) file_type_count=0 ;;
    esac
    if [ "$file_type_count" -eq 0 ]; then
        if [ "$has_text" = true ]; then
            printf 'text'
        else
            printf 'files'
        fi
        return 0
    fi
    local first_file_type="$("$plister_tool" get value "$file" "$item/NSSendFileTypes/0" 2> /dev/null)"
    if [ "$has_text" = true ] || [ "$file_type_count" -ne 1 ]; then
        printf 'other'
    elif [ "$first_file_type" = "public.folder" ]; then
        printf 'folders'
    elif [ "$first_file_type" = "public.item" ]; then
        printf 'files'
    else
        printf 'other'
    fi
    return 0
}

# Saves the Services pane's fields into the service at an index: its title and command, and its
# send types only when the Input picker changed from the kind the service has
# (info_plist_service_kind, the value the pane shows). The pane saves at every field change, so
# the types are rewritten only for a different kind the pane can write: "files" (NSSendTypes
# NSFilenamesPboardType), "folders" (NSSendFileTypes public.folder) or "text" (NSSendTypes
# NSStringPboardType). "other" and anything else (a save with no Input value) keep them.
#   info_plist_update_service <file> <index> <menu title> <command id> <files|folders|text|other>
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
    local shown_kind="$(info_plist_service_kind "$file" "$index")"
    case "$input_kind" in
        "$shown_kind") return 0 ;;
        files|text)
            local send_type="NSFilenamesPboardType"
            if [ "$input_kind" = "text" ]; then
                send_type="NSStringPboardType"
            fi
            # remove succeeds when the key is not there
            "$plister_tool" remove "$file" "$item/NSSendFileTypes" > /dev/null || return 1
            "$plister_tool" insert NSSendTypes array "$file" "$item" > /dev/null || return 1
            "$plister_tool" append string "$send_type" "$file" "$item/NSSendTypes" > /dev/null || return 1
            ;;
        folders)
            "$plister_tool" remove "$file" "$item/NSSendTypes" > /dev/null || return 1
            "$plister_tool" insert NSSendFileTypes array "$file" "$item" > /dev/null || return 1
            "$plister_tool" append string public.folder "$file" "$item/NSSendFileTypes" > /dev/null || return 1
            ;;
        *) return 0 ;;
    esac
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
# Command.plist is round-tripped through JSON (plist -> json -> edit -> xml1; plutil on macOS,
# plist_convert.py on Linux). Every path edits a temp copy: the Info.plist and Command.json
# paths replace the original only on success; the Command.plist path writes its last step, the
# conversion back to XML, onto the original (plist_convert.py builds the whole result before it
# opens the file, so a failed conversion leaves it as it was).
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

    # A legacy Command.plist: round-tripped through JSON (plist -> json -> edit -> xml1)
    command_plist_to_json "$plist" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
    "$python3" "$editor" "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
    command_plist_from_json "$tmp" "$plist"
    local rc=$?
    /bin/rm -f "$tmp"
    return $rc
}

# A legacy Command.plist's conversions, which its editing is built on: plutil on macOS; on Linux,
# which has no plutil, plist_convert.py does the same with Python's plistlib.
command_plist_convert_tool="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/plist_convert.py"

# The plist as JSON, in a file
#   command_plist_to_json <plist> <json out>
command_plist_to_json() {
    if ab_on_macos; then
        /usr/bin/plutil -convert json -o "$2" "$1"
        return $?
    fi
    "$python3" "$command_plist_convert_tool" to-json "$1" "$2"
    return $?
}

# JSON back to an XML plist
#   command_plist_from_json <json> <plist out>
command_plist_from_json() {
    if ab_on_macos; then
        /usr/bin/plutil -convert xml1 -o "$2" "$1"
        return $?
    fi
    "$python3" "$command_plist_convert_tool" to-xml "$1" "$2"
    return $?
}

# Whether a file is a valid plist; what is wrong with it is printed (plutil's text on macOS)
#   command_plist_lint <plist>
command_plist_lint() {
    if ab_on_macos; then
        /usr/bin/plutil -lint "$1"
        return $?
    fi
    "$python3" "$command_plist_convert_tool" lint "$1"
    return $?
}

# One command of a command file as the command editor shows it: indented JSON (keys in file
# order) for a Command.json, read with Python; the <dict> fragment of the XML for a legacy
# Command.plist (plutil on macOS, plist_convert.py on Linux). Nothing when the file or the
# command is not there.
command_text() { # <command file> <index>
    if is_json_command_file "$1"; then
        "$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/plist_edit.py" "$1" print_command "$2" 2>/dev/null
        return $?
    fi
    if ! ab_on_macos; then
        "$python3" "$command_plist_convert_tool" extract-command "$1" "$2" 2>/dev/null
        return $?
    fi
    /usr/bin/plutil -extract "COMMAND_LIST.$2" xml1 -o - "$1" 2>/dev/null | /usr/bin/sed '1,3d; $d'
}
