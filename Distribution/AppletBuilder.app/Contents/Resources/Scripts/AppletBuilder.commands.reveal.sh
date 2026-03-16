#!/bin/bash
# AppletBuilder.commands.reveal - Reveal Command.plist in Finder

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

if [ -f "$cmd_plist" ]; then
    /usr/bin/open -R "$cmd_plist"
fi
