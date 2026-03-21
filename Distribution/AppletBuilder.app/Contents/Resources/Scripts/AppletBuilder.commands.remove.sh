#!/bin/bash
# AppletBuilder.commands.remove - Remove selected command from Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

# Get selected command index from hidden column 2
cmd_index="$OMC_ACTIONUI_TABLE_501_COLUMN_2_VALUE"
cmd_label="$OMC_ACTIONUI_TABLE_501_COLUMN_1_VALUE"

if [ -z "$cmd_index" ] || [ ! -f "$cmd_plist" ]; then
    exit 0
fi

# Check if this command uses a script file and if one exists
plister="$OMC_OMC_SUPPORT_PATH/plister"
exe_mode=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$cmd_index/EXECUTION_MODE" 2>/dev/null)
cmd_id=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$cmd_index/COMMAND_ID" 2>/dev/null)

script_file=""
if [[ "$exe_mode" == exe_script_file* ]]; then
    scripts_dir="$project_path/Contents/Resources/Scripts"
    # Determine the script base name: COMMAND_ID if set, otherwise NAME.main
    script_base="$cmd_id"
    if [ -z "$script_base" ]; then
        cmd_name=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$cmd_index/NAME" 2>/dev/null | /usr/bin/tr -d '\n')
        if [ -n "$cmd_name" ]; then
            script_base="${cmd_name}.main"
        fi
    fi
    # Find the script file (any extension) matching the base name
    if [ -n "$script_base" ]; then
        for f in "$scripts_dir/${script_base}."*; do
            if [ -f "$f" ]; then
                script_file="$f"
                break
            fi
        done
    fi
fi

# Confirm before removing
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

if [ -n "$script_file" ]; then
    script_name=$(/usr/bin/basename "$script_file")
    "$alert_tool" --level caution --title "AppletBuilder" \
        --ok "Remove Both" --cancel "Cancel" --other "Keep Script" \
        "Remove command \"${cmd_label}\"?

Script \"${script_name}\" was found. Remove it too?"
    result=$?
    # 0 = Remove Both, 1 = Cancel, 2 = Keep Script (other)
    if [ "$result" -eq 1 ]; then
        exit 0
    fi
    delete_script=0
    if [ "$result" -eq 0 ]; then
        delete_script=1
    fi
else
    "$alert_tool" --level caution --title "AppletBuilder" \
        --ok "Remove" --cancel "Cancel" \
        "Remove command \"${cmd_label}\" from Command.plist?"
    result=$?
    if [ "$result" -ne 0 ]; then
        exit 0
    fi
    delete_script=0
fi

# Remove the command at the given index
plist_edit "$cmd_plist" remove_command "$cmd_index"

# Delete script if requested
if [ "$delete_script" -eq 1 ] && [ -n "$script_file" ]; then
    /bin/rm -f "$script_file"
fi

# Disable buttons (no selection after removal)
set_enabled "$CMD_REMOVE_BTN_ID" false
set_enabled "$CMD_REVEAL_BTN_ID" false
set_enabled "$CMD_VALIDATE_BTN_ID" false
set_enabled "$CMD_SAVE_BTN_ID" false
set_value "$CMD_DETAIL_ID" ""
set_value "$CMD_EDITED_LABEL_ID" ""

# Refresh the commands table
refresh_commands_table "$cmd_plist"

# Refresh scripts table if a script was deleted
if [ "$delete_script" -eq 1 ]; then
    refresh_scripts_table "$project_path/Contents/Resources/Scripts"
fi
