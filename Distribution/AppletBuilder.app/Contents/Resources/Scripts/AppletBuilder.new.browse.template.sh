#!/bin/bash
# AppletBuilder.new.browse.template - Set clone source path from the folder chooser's result
# (a folder chooser: an applet is a folder on Linux, and macOS's panel opens packages as folders)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

source_app="${OMC_DLG_CHOOSE_FOLDER_PATH%/}"
# A folder chooser takes any folder (or one inside a package): only an applet is a clone source,
# else the clone would copy that whole folder
case "$source_app" in
    *.app) ;;
    *) source_app="" ;;
esac
if [ -n "$OMC_DLG_CHOOSE_FOLDER_PATH" ] && { [ -z "$source_app" ] || [ ! -f "$source_app/Contents/Info.plist" ]; }; then
    set_status "$NEW_STATUS_ID" "Not an applet: ${OMC_DLG_CHOOSE_FOLDER_PATH}. Choose a folder whose name ends in .app."
    exit 0
fi

if [ -n "$source_app" ]; then
    set_status "$NEW_STATUS_ID" ""
    set_value "$NEW_TEMPLATE_PATH_ID" "$source_app"
    "$dialog_tool" "$window_uuid" "$NEW_CLONE_SOURCE_ROW_ID" omc_set_property "hidden" "false"
fi
