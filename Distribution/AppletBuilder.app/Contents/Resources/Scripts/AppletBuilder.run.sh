#!/bin/bash
# builder.run - Launch the current project applet
# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_value "$BUILD_LOG_ID" "Error: No project loaded"
    exit 1
fi

# Scrub all OMC_ env vars so the child applet launches without AppletBuilder's context
for _omc_key in $(env | /usr/bin/grep '^OMC_' | /usr/bin/cut -d= -f1); do
    unset "$_omc_key"
done

# echo "env vars after scrubbing:"
# env | sort

/usr/bin/open "$project_path"
