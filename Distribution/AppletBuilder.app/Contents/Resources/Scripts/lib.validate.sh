#!/bin/bash
# lib.validate.sh - Script syntax validation for AppletBuilder
#
# Sources lib.common.sh for: python3

[ -n "$__LIB_VALIDATE_SH" ] && return 0
__LIB_VALIDATE_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

# Syntax-check a single script file based on its extension.
# Sets SCRIPT_VALIDATE_OUTPUT to any validator output (errors / warnings).
# Returns: 0 = valid, 99 = no validator for this type, any other nonzero =
# the validator's own error exit code (e.g. bash -n yields 2, jsc yields 3).
SCRIPT_VALIDATE_OUTPUT=""
validate_script_file() {
    local path="$1"
    SCRIPT_VALIDATE_OUTPUT=""
    local filename ext rc
    filename=$(/usr/bin/basename "$path")
    ext=$(echo "${filename##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')

    case "$ext" in
        sh|bash)
            SCRIPT_VALIDATE_OUTPUT=$(/bin/bash -n "$path" 2>&1)
            rc=$?
            ;;
        zsh)
            SCRIPT_VALIDATE_OUTPUT=$(/bin/zsh -n "$path" 2>&1)
            rc=$?
            ;;
        py)
            local py="$python3"
            [ -x "$py" ] || py="/usr/bin/python3"
            SCRIPT_VALIDATE_OUTPUT=$("$py" -c '
import ast, sys
try:
    ast.parse(open(sys.argv[1]).read(), filename=sys.argv[1])
except SyntaxError as e:
    print("%s (line %s, column %s)" % (e.msg, e.lineno, e.offset), file=sys.stderr)
    sys.exit(1)
' "$path" 2>&1)
            rc=$?
            ;;
        applescript|scpt)
            local tmp
            tmp=$(/usr/bin/mktemp -d /tmp/ab_validate_XXXXXX)
            SCRIPT_VALIDATE_OUTPUT=$(/usr/bin/osacompile -o "$tmp/out.scpt" "$path" 2>&1)
            rc=$?
            /bin/rm -rf "$tmp"
            ;;
        js)
            # OMC runs .js via JavaScriptCore; use its jsc shell's checkSyntax()
            # (parses without executing). The path is passed as a positional
            # argument, never embedded in the -e source.
            local jsc="/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc"
            if [ -x "$jsc" ]; then
                local raw
                raw=$("$jsc" -e "checkSyntax(arguments[0])" -- "$path" 2>&1)
                rc=$?
                # Drop jsc's own backtrace frames, keep the SyntaxError + location
                SCRIPT_VALIDATE_OUTPUT=$(printf '%s\n' "$raw" | /usr/bin/grep -v -e '@\[native code\]' -e '@\[Command Line\]')
            else
                return 99
            fi
            ;;
        *)
            return 99
            ;;
    esac

    return $rc
}
