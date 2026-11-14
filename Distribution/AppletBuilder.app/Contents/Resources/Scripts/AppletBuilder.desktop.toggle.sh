#!/bin/bash
# AppletBuilder.desktop.toggle - Linux: Build & Run's Add To Desktop / Remove From Desktop button
# (after Show; "type:linux" in BuildRun.json, so macOS has none). Adds the loaded applet to the
# desktop's app list (a desktop entry with its name and icon, by CFBundleIdentifier), or takes it
# off when it is there, then relabels the button. Builds and saves only update an entry that is
# there (applet_finalize); they never add one.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

project_path=$(load_project_path)
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    ab_status_set "exclamationmark.triangle.fill" "orange" "No project loaded"
    exit 1
fi

existing_entry="$(applet_desktop_entry_file "$project_path")"
action="install"
if [ -n "$existing_entry" ]; then
    action="uninstall"
fi

entry_output="$(applet_desktop_entry "$action" "$project_path")"
entry_status=$?
ab_desktop_button "$project_path"
if [ "$entry_status" -ne 0 ]; then
    # The status row is one line: the tool's last line is its error (a traceback ends with it)
    entry_error="$(printf '%s\n' "$entry_output" | /usr/bin/tail -n 1)"
    if [ "$action" = "install" ]; then
        ab_status_set "exclamationmark.triangle.fill" "orange" "Not added to the desktop: ${entry_error}"
    else
        ab_status_set "exclamationmark.triangle.fill" "orange" "Not removed from the desktop: ${entry_error}"
    fi
    exit 1
fi
if [ "$action" = "install" ]; then
    ab_status_set "checkmark.circle.fill" "green" "Added to the desktop's app list"
else
    ab_status_set "checkmark.circle.fill" "green" "Removed from the desktop's app list"
fi
exit 0
