#!/bin/bash
# lib.validate.sh - Script syntax validation for AppletBuilder
#
# Sources lib.common.sh for: python3

[ -n "$__LIB_VALIDATE_SH" ] && return 0
__LIB_VALIDATE_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

# Heuristic scan for bash 4+ features that do not exist in macOS bash 3.2
# (/bin/bash AND /bin/sh are both bash 3.2 — there is no bash 4/5 on a stock
# Mac). Most of these parse fine under `bash -n` / `sh -n` and only fail at
# runtime, so a syntax check alone cannot catch them. Comment-only lines are
# skipped, as is any line carrying a "bash4-ok" marker (the escape hatch for
# false positives, e.g. construct names inside string literals).
# Output: one "line N: …" warning per finding; empty when clean.
scan_bash4_isms() {
    /usr/bin/awk '
    function warn(msg) { printf "line %d: %s\n", NR, msg }
    /^[[:space:]]*#/ { next }
    /bash4-ok/ { next }
    /(^|[;&| \t])(mapfile|readarray)([ \t]|$)/ {                       # bash4-ok
        warn("mapfile/readarray is bash 4+ - use a while IFS= read -r loop") }    # bash4-ok
    /(declare|local|typeset)[ \t]+-[a-zA-Z]*A/ {                       # bash4-ok
        warn("associative arrays (declare -A) are bash 4+ - use state files or case statements") }  # bash4-ok
    /\$\{[^}]*(\^\^|,,)\}/ {                                           # bash4-ok
        warn("${var^^} / ${var,,} case conversion is bash 4+ - use tr") }  # bash4-ok
    /\$\{[A-Za-z_][A-Za-z0-9_]*(\^|,)\}/ {                             # bash4-ok
        warn("${var^} / ${var,} case conversion is bash 4+ - use tr") }    # bash4-ok
    /\|\&/ { warn("pipe-ampersand is bash 4+ - use 2>&1 |") }          # bash4-ok
    /&>>/  { warn("ampersand-append redirect is bash 4+ - use >> file 2>&1") }  # bash4-ok
    /(^|[;& \t])coproc([ \t]|$)/ { warn("coproc is bash 4+") }         # bash4-ok
    /;;&/  { warn("case fallthrough operator is bash 4+") }            # bash4-ok
    /\$\{[^}]*@[QEPAaULuK]\}/ { warn("${var@Q}-style transformations are bash 4.4+") }  # bash4-ok
    /\$\{[^}]*:[0-9]+:-/ { warn("negative substring length is bash 4.2+") }  # bash4-ok
    /\$EPOCHSECONDS|\$EPOCHREALTIME/ { warn("EPOCH variables are bash 5+ - use $(date +%s)") }  # bash4-ok
    ' "$1"
}

# Syntax-check a single script file based on its extension, using the same
# interpreter the OMC engine uses to run it (OmcExecutor.cp: .sh → /bin/sh,
# .bash → /bin/bash, .zsh → /bin/zsh). Checking .sh with bash would miss
# fatal POSIX-mode parse errors such as process substitution `< <(cmd)`.
# Sets SCRIPT_VALIDATE_OUTPUT to any validator output (errors).
# Sets SCRIPT_VALIDATE_WARNINGS to bash-4+ heuristic findings (sh/bash only).
# Returns: 0 = valid, 99 = no validator for this type, any other nonzero =
# the validator's own error exit code (e.g. sh -n yields 2, jsc yields 3).
SCRIPT_VALIDATE_OUTPUT=""
SCRIPT_VALIDATE_WARNINGS=""
validate_script_file() {
    local path="$1"
    SCRIPT_VALIDATE_OUTPUT=""
    SCRIPT_VALIDATE_WARNINGS=""
    local filename ext rc
    filename=$(/usr/bin/basename "$path")
    ext=$(echo "${filename##*.}" | /usr/bin/tr '[:upper:]' '[:lower:]')

    case "$ext" in
        sh)
            SCRIPT_VALIDATE_OUTPUT=$(/bin/sh -n "$path" 2>&1)
            rc=$?
            if [ $rc -ne 0 ] && /bin/bash -n "$path" >/dev/null 2>&1; then
                SCRIPT_VALIDATE_OUTPUT="${SCRIPT_VALIDATE_OUTPUT}

note: this script parses under bash but OMC runs .sh files with /bin/sh
(bash 3.2 in POSIX mode), where bash-only syntax such as process
substitution \`< <(cmd)\` is a fatal error. Rewrite the offending line
POSIX-compatible, or rename the script to .zsh to get a modern shell."
            fi
            [ $rc -eq 0 ] && SCRIPT_VALIDATE_WARNINGS=$(scan_bash4_isms "$path")
            ;;
        bash)
            SCRIPT_VALIDATE_OUTPUT=$(/bin/bash -n "$path" 2>&1)
            rc=$?
            [ $rc -eq 0 ] && SCRIPT_VALIDATE_WARNINGS=$(scan_bash4_isms "$path")
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
