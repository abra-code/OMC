#!/bin/bash
# AppletBuilder.scripts.validate - Syntax-check the selected script by type

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

selected_path=$(pb_get "$PB_SCRIPTS_SELECTED")

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

filename=$(/usr/bin/basename "$selected_path")
ext=$(echo "${filename##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')

validator_output=""
rc=0
checked=1

case "$ext" in
    sh|bash)
        validator_output=$(/bin/bash -n "$selected_path" 2>&1)
        rc=$?
        ;;
    zsh)
        validator_output=$(/bin/zsh -n "$selected_path" 2>&1)
        rc=$?
        ;;
    py)
        py="$python3"
        [ -x "$py" ] || py="/usr/bin/python3"
        validator_output=$("$py" -c '
import ast, sys
try:
    ast.parse(open(sys.argv[1]).read(), filename=sys.argv[1])
except SyntaxError as e:
    print("%s (line %s, column %s)" % (e.msg, e.lineno, e.offset), file=sys.stderr)
    sys.exit(1)
' "$selected_path" 2>&1)
        rc=$?
        ;;
    applescript|scpt)
        tmp=$(/usr/bin/mktemp -d /tmp/ab_validate_XXXXXX)
        validator_output=$(/usr/bin/osacompile -o "$tmp/out.scpt" "$selected_path" 2>&1)
        rc=$?
        /bin/rm -rf "$tmp"
        ;;
    js)
        # OMC runs .js via JavaScriptCore; use its jsc shell's checkSyntax()
        # (parses without executing). The path is passed as a positional
        # argument, never embedded in the -e source.
        jsc="/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc"
        if [ -x "$jsc" ]; then
            raw=$("$jsc" -e "checkSyntax(arguments[0])" -- "$selected_path" 2>&1)
            rc=$?
            # Drop jsc's own backtrace frames, keep the SyntaxError + location
            validator_output=$(printf '%s\n' "$raw" | /usr/bin/grep -v -e '@\[native code\]' -e '@\[Command Line\]')
        else
            checked=0
        fi
        ;;
    *)
        checked=0
        ;;
esac

if [ "$checked" -eq 0 ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "No validator for .${ext} files"
    exit 0
fi

if [ "$rc" -eq 0 ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "✅ Valid"
else
    set_value "$SCRIPTS_EDITED_LABEL_ID" "🛑 Syntax errors"
    show_errors "Syntax errors in ${filename}:

$validator_output"
fi
