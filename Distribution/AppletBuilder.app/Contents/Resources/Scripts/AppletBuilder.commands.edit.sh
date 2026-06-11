#!/bin/bash
# AppletBuilder.commands.edit - Open Command.plist in external editor

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")

if [ -f "$cmd_plist" ]; then
    editor=$(get_external_editor)
    /usr/bin/open -a "$editor" "$cmd_plist"
fi
