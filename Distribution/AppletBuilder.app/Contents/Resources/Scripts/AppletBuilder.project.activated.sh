#!/bin/bash
# AppletBuilder.project.activated - Refresh lists and detect external file changes
# Called when the project window becomes key (gains focus)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
if [ -z "$project_path" ]; then
    exit 0
fi

# Refresh all three tables to pick up added/removed files
cmd_plist="$project_path/Contents/Resources/Command.plist"
scripts_dir="$project_path/Contents/Resources/Scripts"

if [ -f "$cmd_plist" ]; then
    refresh_commands_table "$cmd_plist"
fi

if [ -d "$scripts_dir" ]; then
    refresh_scripts_table "$scripts_dir"
fi

refresh_uifiles_table "$project_path"

# --- General tab (Info.plist) ---
plist="$project_path/Contents/Info.plist"
if [ -f "$plist" ]; then
    stored=$(pb_get "$PB_PLIST_HASH")
    if [ -n "$stored" ]; then
        current=$(file_hash "$plist")
        if [ "$stored" != "$current" ]; then
            set_value "$GEN_NAME_ID" "$(plist_read "$plist" CFBundleName)"
            set_value "$GEN_HEADER_NAME_ID" "$(plist_read "$plist" CFBundleName)"
            set_value "$GEN_BUNDLE_ID_ID" "$(plist_read "$plist" CFBundleIdentifier)"
            set_value "$GEN_VERSION_ID" "$(plist_read "$plist" CFBundleVersion)"
            icon_name=$(plist_read "$plist" CFBundleIconFile)
            icns_path="$project_path/Contents/Resources/${icon_name}.icns"
            if [ -f "$icns_path" ]; then
                set_value "$GEN_ICON_IMAGE_ID" "$icns_path"
            fi
            pb_set "$PB_PLIST_HASH" "$current"
            set_value "$GEN_STATUS_ID" "Reloaded (Info.plist changed externally)"
        fi
    fi
fi

# Check each editor for external modifications

# --- Scripts editor ---
scripts_path=$(pb_get "$PB_SCRIPTS_SELECTED")
if [ -n "$scripts_path" ] && [ -f "$scripts_path" ]; then
    stored=$(pb_get "$PB_SCRIPTS_HASH")
    if [ -n "$stored" ]; then
        current=$(file_hash "$scripts_path")
        if [ "$stored" != "$current" ]; then
            dirty=$(pb_get "$PB_SCRIPTS_DIRTY")
            if [ "$dirty" = "1" ]; then
                set_value "$SCRIPTS_EDITED_LABEL_ID" "⚠️ File changed externally (you have unsaved edits)"
            else
                # Not dirty — silently reload
                content=$(/bin/cat "$scripts_path")
                set_value "$SCRIPTS_DETAIL_ID" "$content
"
                pb_set "$PB_SCRIPTS_HASH" "$current"
                set_value "$SCRIPTS_EDITED_LABEL_ID" "Reloaded (changed externally)"
            fi
        fi
    fi
fi

# --- Commands editor ---
if [ -f "$cmd_plist" ]; then
    stored=$(pb_get "$PB_CMD_HASH")
    if [ -n "$stored" ]; then
        current=$(file_hash "$cmd_plist")
        if [ "$stored" != "$current" ]; then
            dirty=$(pb_get "$PB_CMD_DIRTY")
            if [ "$dirty" = "1" ]; then
                set_value "$CMD_EDITED_LABEL_ID" "⚠️ File changed externally (you have unsaved edits)"
            else
                # Not dirty — silently reload the selected command
                cmd_index=$(pb_get "$PB_CMD_SELECTED")
                if [ -n "$cmd_index" ]; then
                    cmd_xml=$(/usr/bin/plutil -extract "COMMAND_LIST.$cmd_index" xml1 -o - "$cmd_plist" 2>/dev/null \
                        | /usr/bin/sed '1,3d; $d')
                    set_value "$CMD_DETAIL_ID" "$cmd_xml
"
                fi
                pb_set "$PB_CMD_HASH" "$current"
                set_value "$CMD_EDITED_LABEL_ID" "Reloaded (changed externally)"
            fi
        fi
    fi
fi

# --- UI Files editor ---
uifiles_path=$(pb_get "$PB_UIFILES_SELECTED")
if [ -n "$uifiles_path" ] && [ -f "$uifiles_path" ]; then
    stored=$(pb_get "$PB_UIFILES_HASH")
    if [ -n "$stored" ]; then
        current=$(file_hash "$uifiles_path")
        if [ "$stored" != "$current" ]; then
            dirty=$(pb_get "$PB_UIFILES_DIRTY")
            if [ "$dirty" = "1" ]; then
                set_value "$UI_EDITED_LABEL_ID" "⚠️ File changed externally (you have unsaved edits)"
            else
                # Not dirty — silently reload
                content=$(/bin/cat "$uifiles_path")
                set_value "$UI_DETAIL_ID" "$content
"
                pb_set "$PB_UIFILES_HASH" "$current"
                set_value "$UI_EDITED_LABEL_ID" "Reloaded (changed externally)"
            fi
        fi
    fi
fi
