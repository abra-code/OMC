#!/bin/bash
# Validate the project's command file (Command.json or Command.plist) and present
# the result. The validation itself (fast syntax gate + advanced command_verifier,
# Layer 1 + 2) lives in validate_command_file (lib.validate.sh), shared with the
# build pipeline and the agent CLI.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")
cmd_file_label=$(/usr/bin/basename "$cmd_plist")

validate_command_file "$project_path"
rc=$?

case "$rc" in
    0)
        set_value "$CMD_EDITED_LABEL_ID" "✅ Valid"
        ;;
    2)
        set_value "$CMD_EDITED_LABEL_ID" "⚠️ Warnings"
        show_errors "$cmd_file_label validation warnings:

$COMMAND_VALIDATE_OUTPUT"
        ;;
    3)
        set_value "$CMD_EDITED_LABEL_ID" "🛑 Invalid $cmd_file_label"
        show_errors "Syntax error in $cmd_file_label:

$COMMAND_VALIDATE_OUTPUT"
        ;;
    99)
        set_value "$CMD_EDITED_LABEL_ID" "No command file found"
        ;;
    *)
        set_value "$CMD_EDITED_LABEL_ID" "🛑 Validation errors"
        show_errors "$cmd_file_label validation errors:

$COMMAND_VALIDATE_OUTPUT"
        ;;
esac
