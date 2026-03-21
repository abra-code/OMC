#!/bin/bash
# AppletBuilder.scripts.new.create - Create new script file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
scripts_dir="$project_path/Contents/Resources/Scripts"

name="${OMC_ACTIONUI_VIEW_821_VALUE}"
script_type="${OMC_ACTIONUI_VIEW_822_VALUE}"

if [ -z "$name" ]; then
    set_value "$NEWSCRIPT_STATUS_ID" "Name is required"
    exit 1
fi

/bin/mkdir -p "$scripts_dir"

# Determine extension
case "$script_type" in
    sh)          ext="sh" ;;
    bash)        ext="bash" ;;
    zsh)         ext="zsh" ;;
    py)          ext="py" ;;
    rb)          ext="rb" ;;
    pl)          ext="pl" ;;
    applescript) ext="applescript" ;;
esac

script_file="$scripts_dir/${name}.${ext}"

if [ -f "$script_file" ]; then
    alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
    "$alert_tool" --level critical --title "AppletBuilder" \
        --ok "OK" \
        "A script named \"${name}.${ext}\" already exists."
    set_value "$NEWSCRIPT_STATUS_ID" "Script already exists"
    exit 1
fi

# Create the script with appropriate template
case "$script_type" in
    sh)
        cat > "$script_file" <<SCRIPT
#!/bin/sh
# ${name}

SCRIPT
        ;;
    bash)
        cat > "$script_file" <<SCRIPT
#!/bin/bash
# ${name}

SCRIPT
        ;;
    zsh)
        cat > "$script_file" <<SCRIPT
#!/bin/zsh
# ${name}

SCRIPT
        ;;
    py)
        cat > "$script_file" <<SCRIPT
# ${name}

import os

SCRIPT
        ;;
    rb)
        cat > "$script_file" <<SCRIPT
#!/usr/bin/env ruby
# ${name}

SCRIPT
        ;;
    pl)
        cat > "$script_file" <<SCRIPT
#!/usr/bin/env perl
# ${name}

use strict;
use warnings;

SCRIPT
        ;;
    applescript)
        cat > "$script_file" <<SCRIPT
-- ${name}

SCRIPT
        ;;
esac

if [ -n "$script_file" ] && [ -f "$script_file" ]; then
    /bin/chmod +x "$script_file"
fi

# Refresh scripts table in the parent window
parent_uuid="$OMC_PARENT_DIALOG_GUID"

if [ -n "$parent_uuid" ]; then
    refresh_scripts_table "$scripts_dir" "$parent_uuid"
fi
