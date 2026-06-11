#!/bin/bash
# AppletBuilder.commands.reveal - Reveal Command.plist in Finder

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")

if [ -f "$cmd_plist" ]; then
    /usr/bin/open -R "$cmd_plist"
fi
