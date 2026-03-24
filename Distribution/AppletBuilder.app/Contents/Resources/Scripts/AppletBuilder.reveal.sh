#!/bin/bash
# builder.reveal - Reveal the current project applet in Finder
# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    exit 1
fi

/usr/bin/open -R "$project_path"
