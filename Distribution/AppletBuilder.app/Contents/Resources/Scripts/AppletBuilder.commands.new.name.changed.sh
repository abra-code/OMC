#!/bin/bash
# AppletBuilder.commands.new.name.changed - Update Command ID when Name changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

name="${OMC_ACTIONUI_VIEW_801_VALUE}"

if [ -z "$name" ]; then
    exit 0
fi

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"
plister="$OMC_OMC_SUPPORT_PATH/plister"

# If no commands exist yet, this will be a main command — leave Command ID empty
count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
if [ -z "$count" ] || [ "$count" -eq 0 ]; then
    set_value "$NEWCMD_COMMAND_ID_ID" "${name}.main"
else
    cmd_id_prefix=$(echo "$name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '.' | /usr/bin/tr -cd 'a-z0-9.')
    candidate=$(unique_command_id "$cmd_plist" "$cmd_id_prefix")
    set_value "$NEWCMD_COMMAND_ID_ID" "$candidate"
fi
