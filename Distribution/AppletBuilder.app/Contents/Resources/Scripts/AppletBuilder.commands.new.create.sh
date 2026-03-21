#!/bin/bash
# AppletBuilder.commands.new.create - Create new command entry and optionally a script file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

name="${OMC_ACTIONUI_VIEW_801_VALUE}"
command_id="${OMC_ACTIONUI_VIEW_802_VALUE}"
execution="${OMC_ACTIONUI_VIEW_803_VALUE}"
activation="${OMC_ACTIONUI_VIEW_804_VALUE}"
script_type="${OMC_ACTIONUI_VIEW_805_VALUE}"

# Detect main command hint: NAME.main means no COMMAND_ID
if [ "$command_id" = "${name}.main" ]; then
    command_id=""
fi

if [ -z "$name" ]; then
    set_value "$NEWCMD_STATUS_ID" "Name is required"
    exit 1
fi

if [ ! -f "$cmd_plist" ]; then
    set_value "$NEWCMD_STATUS_ID" "No Command.plist found"
    exit 1
fi

plister="$OMC_OMC_SUPPORT_PATH/plister"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# Check for duplicate COMMAND_ID (only if command_id is set)
if [ -n "$command_id" ]; then
    count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        i=0
        while [ "$i" -lt "$count" ]; do
            cid=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/COMMAND_ID" 2>/dev/null)
            if [ "$cid" = "$command_id" ]; then
                "$alert_tool" --level critical --title "AppletBuilder" \
                    --ok "OK" \
                    "A command with ID \"${command_id}\" already exists."
                set_value "$NEWCMD_STATUS_ID" "Duplicate Command ID"
                exit 1
            fi
            i=$((i + 1))
        done
    fi
fi

# Add command entry to Command.plist
plist_edit "$cmd_plist" append_command_full "$name" "$command_id" "$execution" "$activation"
if [ $? -ne 0 ]; then
    set_value "$NEWCMD_STATUS_ID" "Error adding command"
    exit 1
fi

# Create script file if requested
if [ "$script_type" != "none" ]; then
    scripts_dir="$project_path/Contents/Resources/Scripts"
    /bin/mkdir -p "$scripts_dir"

    # Determine the file path first to check for existing files
    case "$script_type" in
        sh)          ext="sh" ;;
        bash)        ext="bash" ;;
        zsh)         ext="zsh" ;;
        py)          ext="py" ;;
        rb)          ext="rb" ;;
        pl)          ext="pl" ;;
        applescript) ext="applescript" ;;
    esac

    # Script base name: COMMAND_ID if set, otherwise NAME.main
    if [ -n "$command_id" ]; then
        script_base="$command_id"
    else
        script_base="${name}.main"
    fi

    script_file="$scripts_dir/${script_base}.${ext}"

    if [ -f "$script_file" ]; then
        set_value "$NEWCMD_STATUS_ID" "Script ${script_base}.${ext} already exists"
        exit 1
    fi

    case "$script_type" in
        sh)
            cat > "$script_file" <<SCRIPT
#!/bin/sh
# ${script_base}

SCRIPT
            ;;
        bash)
            cat > "$script_file" <<SCRIPT
#!/bin/bash
# ${script_base}

SCRIPT
            ;;
        zsh)
            cat > "$script_file" <<SCRIPT
#!/bin/zsh
# ${script_base}

SCRIPT
            ;;
        py)
            cat > "$script_file" <<SCRIPT
# ${script_base}

import os

SCRIPT
            ;;
        rb)
            cat > "$script_file" <<SCRIPT
#!/usr/bin/env ruby
# ${script_base}

SCRIPT
            ;;
        pl)
            cat > "$script_file" <<SCRIPT
#!/usr/bin/env perl
# ${script_base}

use strict;
use warnings;

SCRIPT
            ;;
        applescript)
            cat > "$script_file" <<SCRIPT
-- ${script_base}

SCRIPT
            ;;
    esac

    if [ -n "$script_file" ] && [ -f "$script_file" ]; then
        /bin/chmod +x "$script_file"
    fi
fi

# Refresh commands table in the parent window
# OMC_PARENT_DIALOG_GUID is the parent dialog's UUID (main window)
parent_uuid="$OMC_PARENT_DIALOG_GUID"

if [ -n "$parent_uuid" ]; then
    refresh_commands_table "$cmd_plist" "$parent_uuid"

    # Refresh scripts table if a script was created
    if [ "$script_type" != "none" ] && [ -n "$script_file" ] && [ -f "$script_file" ]; then
        refresh_scripts_table "$project_path/Contents/Resources/Scripts" "$parent_uuid"
    fi
fi
