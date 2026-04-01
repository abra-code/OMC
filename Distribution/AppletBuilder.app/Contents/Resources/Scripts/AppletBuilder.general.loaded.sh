#!/bin/bash
# AppletBuilder.general.loaded - Populate General tab when its LoadableView finishes loading

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

# If project.init hasn't saved the path yet (race), read from the pending pasteboard
# and save it ourselves so subsequent tabs find it
if [ -z "$project_path" ]; then
    project_path=$("$pasteboard_tool" "appletbuilder_pending_project" get)
    if [ -n "$project_path" ]; then
        "$pasteboard_tool" "appletbuilder_pending_project" set ""
        if [ -d "$project_path" ]; then
            save_project_path "$project_path"
        fi
    fi
fi

if [ -n "$project_path" ] && [ -f "$project_path/Contents/Info.plist" ]; then
    plist="$project_path/Contents/Info.plist"
    pb_set "$PB_PLIST_HASH" "$(file_hash "$plist")"

    app_name=$(plist_read "$plist" CFBundleName)
    set_value "$GEN_NAME_ID" "$app_name"
    set_value "$GEN_HEADER_NAME_ID" "$app_name"
    set_value "$GEN_BUNDLE_ID_ID" "$(plist_read "$plist" CFBundleIdentifier)"
    set_value "$GEN_VERSION_ID" "$(plist_read "$plist" CFBundleVersion)"

    # Set header icon
    icon_name=$(plist_read "$plist" CFBundleIconFile)
    icns_path="$project_path/Contents/Resources/${icon_name}.icns"
    if [ -f "$icns_path" ]; then
        set_value "$GEN_ICON_IMAGE_ID" "$icns_path"
    fi

    # Populate command ID picker from Command.plist
    cmd_plist="$project_path/Contents/Resources/Command.plist"
    plister="$OMC_OMC_SUPPORT_PATH/plister"
    cmd_options='['
    cmd_first=""
    if [ -f "$cmd_plist" ]; then
        count=$("$plister" get count "$cmd_plist" /COMMAND_LIST 2>/dev/null)
        i=0
        while [ "$i" -lt "${count:-0}" ]; do
            cmd_id=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/COMMAND_ID" 2>/dev/null)
            name=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/$i/NAME" 2>/dev/null | /usr/bin/tr -d '\n')
            if [ -n "$cmd_id" ]; then
                label="$cmd_id"
            elif [ -n "$name" ]; then
                label="$name"
            else
                label="Command $i"
            fi
            [ "$i" -gt 0 ] && cmd_options="${cmd_options},"
            # Escape quotes in label
            escaped=$(echo "$label" | /usr/bin/sed 's/"/\\"/g')
            cmd_options="${cmd_options}{\"title\":\"${escaped}\",\"tag\":\"${escaped}\"}"
            [ -z "$cmd_first" ] && cmd_first="$label"
            i=$((i + 1))
        done
    fi
    cmd_options="${cmd_options}]"
    "$dialog_tool" "$window_uuid" "$SVC_COMMAND_PICKER_ID" omc_set_property "options" "$cmd_options"

    # Load existing NSServices into the table
    svc_count=$("$plister" get count "$plist" /NSServices 2>/dev/null)
    if [ -n "$svc_count" ] && [ "$svc_count" -gt 0 ]; then
        buffer=""
        i=0
        while [ "$i" -lt "$svc_count" ]; do
            menu_title=$(/usr/bin/plutil -extract "NSServices.${i}.NSMenuItem.default" raw "$plist" 2>/dev/null)
            user_data=$(/usr/bin/plutil -extract "NSServices.${i}.NSUserData" raw "$plist" 2>/dev/null)
            [ -z "$menu_title" ] && menu_title="$user_data"
            [ -z "$menu_title" ] && menu_title="Service $i"
            buffer="${buffer}${menu_title}	${i}
"
            i=$((i + 1))
        done
        printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$SVC_TABLE_ID" omc_table_set_rows_from_stdin
    fi
fi
