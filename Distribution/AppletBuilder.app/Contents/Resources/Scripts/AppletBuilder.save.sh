#!/bin/bash
# Cmd+S handler: dispatch save to the active tab's save command

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

active_tab="${OMC_ACTIONUI_VIEW_10_VALUE}"

case "$active_tab" in
    1) # Commands tab
        "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.save.detail"
        ;;
    2) # Scripts tab
        "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.scripts.save.detail"
        ;;
    3) # UI Files tab
        "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.uifiles.save.detail"
        ;;
esac
