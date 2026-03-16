#!/bin/bash
# AppletBuilder.commands.loaded - Populate Commands table from Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_DETAIL_ID" "No Command.plist found"
    exit 0
fi

# Extract command names and populate the table
# Column 1 (visible): command label
# Column 2 (hidden): plist array index
count=$(/usr/bin/plutil -extract COMMAND_LIST raw "$cmd_plist" 2>/dev/null)
if [ -z "$count" ] || [ "$count" -eq 0 ]; then
    set_value "$CMD_DETAIL_ID" "No commands found in Command.plist"
    exit 0
fi

buffer=""
i=0
while [ "$i" -lt "$count" ]; do
    name=$(/usr/bin/plutil -extract "COMMAND_LIST.$i.NAME" raw "$cmd_plist" 2>/dev/null)
    cmd_id=$(/usr/bin/plutil -extract "COMMAND_LIST.$i.COMMAND_ID" raw "$cmd_plist" 2>/dev/null)

    if [ -n "$cmd_id" ]; then
        label="$cmd_id"
    elif [ -n "$name" ]; then
        label="$name (main)"
    else
        label="Command $i"
    fi

    buffer="${buffer}${label}	${i}
"
    i=$((i + 1))
done

printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$CMD_TABLE_ID" omc_table_set_rows_from_stdin
