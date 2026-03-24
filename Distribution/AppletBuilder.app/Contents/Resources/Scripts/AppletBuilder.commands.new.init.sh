#!/bin/bash
# AppletBuilder.commands.new.init - Populate New Command dialog with defaults

# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
# Dialog has its own window UUID — read project path from parent dialog's pasteboard
if [ -z "$project_path" ] && [ -n "$OMC_PARENT_DIALOG_GUID" ]; then
    project_path=$("$pasteboard_tool" "ProjectPath_${OMC_PARENT_DIALOG_GUID}" get)
    "$pasteboard_tool" "ProjectPath_${OMC_PARENT_DIALOG_GUID}" set ""
    if [ -n "$project_path" ] && [ -d "$project_path" ]; then
        save_project_path "$project_path"
    fi
fi

cmd_plist="$project_path/Contents/Resources/Command.plist"
plister="$OMC_OMC_SUPPORT_PATH/plister"

# Check if COMMAND_LIST is empty — suggest a main command
name=""
is_main=0
if [ -f "$cmd_plist" ]; then
    count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        is_main=1
    else
        last=$((count - 1))
        name=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$last/NAME" 2>/dev/null | /usr/bin/tr -d '\n')
    fi
fi

# Fallback to app bundle name
if [ -z "$name" ]; then
    name=$(/usr/bin/basename "${project_path%.app}")
fi

set_value "$NEWCMD_NAME_ID" "$name"

if [ "$is_main" -eq 1 ]; then
    # Main command: show NAME.main as hint but don't write COMMAND_ID
    set_value "$NEWCMD_COMMAND_ID_ID" "${name}.main"
else
    cmd_id_prefix=$(echo "$name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '.' | /usr/bin/tr -cd 'a-z0-9.')
    candidate=$(unique_command_id "$cmd_plist" "$cmd_id_prefix")
    set_value "$NEWCMD_COMMAND_ID_ID" "$candidate"
fi

set_value "$NEWCMD_EXECUTION_ID" "exe_script_file"
set_value "$NEWCMD_ACTIVATION_ID" "act_always"
set_value "$NEWCMD_SCRIPT_ID" "sh"
