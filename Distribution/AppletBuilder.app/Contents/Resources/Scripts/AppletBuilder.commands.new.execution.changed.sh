#!/bin/bash
# AppletBuilder.commands.new.execution.changed - Update Create Script picker when Execution changes

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

execution="${OMC_ACTIONUI_VIEW_803_VALUE}"

case "$execution" in
    exe_script_file|exe_script_file_with_output_window)
        # Script file modes: default to Shell
        set_value "$NEWCMD_SCRIPT_ID" "sh"
        ;;
    *)
        # Non-script-file modes: no script creation
        set_value "$NEWCMD_SCRIPT_ID" "none"
        ;;
esac
