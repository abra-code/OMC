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

# Edit a plist or JSON file via plist_edit.py.
#
# A .json file (e.g. Command.json) is edited in place — plist_edit.py already
# operates on JSON, so no format conversion is needed. Any other file (Info.plist,
# Command.plist) is round-tripped through JSON on macOS: plist -> json -> edit -> xml1;
# on Linux (no plutil) plist_edit.py edits it as a plist with plistlib (--plist).
# Both paths edit a temp copy and only replace the original on success, so a
# failed edit never corrupts the file.
#
# Usage:
#   plist_edit "$plist" set_keys CFBundleName "$name"
#   plist_edit "$plist" append_service "$title" "$cmd"
#   plist_edit "$plist" replace_command "$index" "$json_file"
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

    if is_json_command_file "$plist"; then
        /bin/cp "$plist" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        "$python3" "$editor" "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
        # Carry the original's permissions onto the replacement. mktemp creates
        # 0600 and `cp` into an existing file keeps the destination's mode, so
        # without this the mv silently turns a 0644 Command.json owner-only on
        # every save - and nothing later in the build or codesign path puts it
        # back, so the applet stops being readable for anyone it is distributed
        # to. chmod-then-mv rather than `cat >` keeps the replace atomic.
        # The mode in octal: BSD stat on macOS, GNU stat on Linux.
        local mode
        case "${OSTYPE:-}" in
            darwin*) mode=$(/usr/bin/stat -f '%Lp' "$plist" 2>/dev/null) ;;
            *) mode=$(/usr/bin/stat -c '%a' "$plist" 2>/dev/null) ;;
        esac
        if [ -n "$mode" ]; then
            /bin/chmod "$mode" "$tmp"
        fi
        /bin/mv "$tmp" "$plist"
        return $?
    fi

    # A property list on Linux (an applet's Info.plist): no plutil there, so plist_edit.py reads and
    # writes it with plistlib (--plist), in the format it has; replaced as the JSON file above
    if ! ab_on_macos; then
        /bin/cp "$plist" "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        "$python3" "$editor" --plist "$tmp" "$operation" "$@" || { /bin/rm -f "$tmp"; return 1; }
        local plist_mode
        plist_mode=$(/usr/bin/stat -c '%a' "$plist" 2>/dev/null)
        if [ -n "$plist_mode" ]; then
            /bin/chmod "$plist_mode" "$tmp"
        fi
        /bin/mv "$tmp" "$plist"
        return $?
    fi

    # A plist on macOS (an Info.plist, a legacy Command.plist): plutil
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
