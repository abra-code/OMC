#!/bin/bash
# Validate Command.plist: plutil syntax gate, then the advanced command_verifier
# (Layer 1 key/type/enum/required/conditional checks + Layer 2 bundle cross-references).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "No Command.plist found"
    exit 0
fi

# 1) Fast syntax gate — gives a precise location for malformed plists.
lint_output=$(/usr/bin/plutil -lint "$cmd_plist" 2>&1)
if [ "$?" -ne 0 ]; then
    set_value "$CMD_EDITED_LABEL_ID" "🛑 Invalid plist"
    show_errors "Plist syntax error in Command.plist:

$lint_output"
    exit 0
fi

# 2) Advanced verification. Pass the bundle so Layer 2 cross-references run
#    (scripts, JSON/NIB resources, subcommand IDs, duplicate COMMAND_IDs).
verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/command_verifier/validate_command_plist.py"
if [ ! -f "$verifier" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Valid plist"
    exit 0
fi

verifier_output=$("$python3" "$verifier" "$project_path" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    set_value "$CMD_EDITED_LABEL_ID" "✅ Valid"
elif [ "$rc" -eq 2 ]; then
    set_value "$CMD_EDITED_LABEL_ID" "⚠️ Warnings"
    show_errors "Command.plist validation warnings:

$verifier_output"
else
    set_value "$CMD_EDITED_LABEL_ID" "🛑 Validation errors"
    show_errors "Command.plist validation errors:

$verifier_output"
fi
