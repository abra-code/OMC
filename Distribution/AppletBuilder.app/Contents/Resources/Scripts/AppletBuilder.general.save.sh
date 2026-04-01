#!/bin/bash
# AppletBuilder.general.save - Apply changes from General form to the applet

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_status "$GEN_STATUS_ID" "No project loaded"
    exit 1
fi

plist="$project_path/Contents/Info.plist"

if [ ! -f "$plist" ]; then
    set_status "$GEN_STATUS_ID" "Info.plist not found"
    exit 1
fi

# Read form values
new_name="${OMC_ACTIONUI_VIEW_302_VALUE}"
new_bundle_id="${OMC_ACTIONUI_VIEW_303_VALUE}"
new_version="${OMC_ACTIONUI_VIEW_305_VALUE}"

# Validate
if [ -z "$new_name" ]; then
    set_status "$GEN_STATUS_ID" "Name is required"
    exit 1
fi

# Get current values for comparison
old_name=$(plist_read "$plist" CFBundleName)
old_exe=$(plist_read "$plist" CFBundleExecutable)
old_icon=$(plist_read "$plist" CFBundleIconFile)
name_changed=0

# ── Handle name change (full rename) ──

if [ -n "$new_name" ] && [ "$new_name" != "$old_name" ]; then
    name_changed=1
    set_status "$GEN_STATUS_ID" "Renaming applet..."

    # Rename executable
    /bin/mv "$project_path/Contents/MacOS/$old_exe" \
            "$project_path/Contents/MacOS/$new_name" 2>/dev/null

    # Full rename pipeline (plist, nibs, scripts, credits, URL scheme)
    applet_rename_contents "$project_path" "$old_exe" "$new_name"

    # Update bundle ID to match new name
    old_bundle_id=$(plist_read "$project_path/Contents/Info.plist" CFBundleIdentifier)
    if [ -n "$old_bundle_id" ]; then
        # Replace last component of bundle ID with new name
        bundle_prefix="${old_bundle_id%.*}"
        applet_set_bundle_id "$project_path" "${bundle_prefix}.${new_name}"
    fi

    # Rename the .app bundle itself
    parent_dir=$(/usr/bin/dirname "$project_path")
    new_app_path="${parent_dir}/${new_name}.app"
    if [ ! -e "$new_app_path" ]; then
        /bin/mv "$project_path" "$new_app_path"
        project_path="$new_app_path"
        save_project_path "$project_path"
    fi
fi

# ── Apply other changes ──

if [ "$name_changed" -eq 0 ] && [ -n "$new_bundle_id" ]; then
    applet_set_bundle_id "$project_path" "$new_bundle_id"
    save_bundle_id_prefix "$new_bundle_id"
fi

if [ -n "$new_version" ]; then
    plist_write "$project_path/Contents/Info.plist" "CFBundleVersion" "$new_version"
fi

# Finalize
applet_finalize "$project_path"

pb_set "$PB_PLIST_HASH" "$(file_hash "$project_path/Contents/Info.plist")"

if [ "$name_changed" -eq 1 ]; then
    set_status "$GEN_STATUS_ID" "Renamed to ${new_name}.app — reopening..."

    # Close current window and reopen with new path
    "$dialog_tool" "$window_uuid" omc_window omc_terminate_cancel
    /usr/bin/open -a "$OMC_APP_BUNDLE_PATH" "$project_path"
else
    set_status "$GEN_STATUS_ID" "Changes applied"
fi
