#!/bin/bash
# defaults/test_defaults.sh - tests of the applets' defaults tool (defaults/defaults), on macOS and
# Linux. The tool runs from a scratch folder with a plister beside it, as in an applet's Support
# folder, and keeps its JSON files in a scratch settings folder: nothing touches the user's
# settings. The macOS pass-through to /usr/bin/defaults is checked with a file-path domain in the
# scratch folder, and only when the preferences daemon can be reached (not from a sandboxed run).
#
# Usage: test_defaults.sh <plister>
#   <plister> is a built plister: on macOS e.g. .../Command.framework/Versions/A/Support/plister,
#   on Linux the build's products folder's plister.
# Exit status: 0 all passed, 1 a check failed, 2 bad arguments.

plister_built="$1"
if [ -z "$plister_built" ] || [ ! -x "$plister_built" ]; then
    printf 'Usage: %s <a built plister>\n' "$0" >&2
    exit 2
fi
here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/defaults-test.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'cannot make a scratch folder\n' >&2
    exit 1
fi
work="$(CDPATH= cd -P -- "$work" && pwd)" # physical: macOS's preferences daemon refuses /var links
/bin/mkdir -p "$work/Support" "$work/settings"
/bin/cp "$here/defaults" "$plister_built" "$work/Support/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot copy the tool and plister\n' >&2
    exit 1
fi
tool="$work/Support/defaults"

passed=0
failed=0
check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        passed=$((passed + 1))
        printf 'ok   %s\n' "$1"
    else
        failed=$((failed + 1))
        printf 'FAIL %s\n     expected: [%s]\n     actual:   [%s]\n' "$1" "$2" "$3"
    fi
}
# Runs the tool; prints its output, then "|" and its exit status
run() {
    local output
    output="$("$tool" "$@" 2>/dev/null)"
    local run_status=$?
    printf '%s|%s' "$output" "$run_status"
}

printf '== JSON settings in OMC_DEFAULTS_PATH ==\n'
export OMC_DEFAULTS_PATH="$work/settings"
domain="com.example.defaults-test"
check "a missing domain reads as missing" "|1" "$(run read "$domain" Name)"
check "a string is written" "|0" "$(run write "$domain" Name "a b {c} \"quoted\" -x")"
check "into <folder>/<domain>.json" "yes" "$([ -f "$work/settings/$domain.json" ] && printf yes || printf no)"
check "and reads back as it was" "a b {c} \"quoted\" -x|0" "$(run read "$domain" Name)"
check "an untyped value is a string, not parsed" "|0" "$(run write "$domain" Parsed "(1, 2)")"
check "and reads back as written" "(1, 2)|0" "$(run read "$domain" Parsed)"
check "a bool is written" "|0" "$(run write "$domain" Flag -bool YES)"
check "and reads back as 1" "1|0" "$(run read "$domain" Flag)"
check "false reads back as 0" "0|0" "$(run write "$domain" Off -bool false >/dev/null; run read "$domain" Off)"
check "an integer" "-42|0" "$(run write "$domain" Count -int -42 >/dev/null; run read "$domain" Count)"
check "a real, printed as macOS's defaults prints it" "1.5|0" "$(run write "$domain" Ratio -float 1.5 >/dev/null; run read "$domain" Ratio)"
check "a whole real" "2|0" "$(run write "$domain" Whole -float 2.0 >/dev/null; run read "$domain" Whole)"
check "a leading + is dropped" "5|0" "$(run write "$domain" Plus -int +5 >/dev/null; run read "$domain" Plus)"
check "a key written again is replaced, with its new type" "text|0" "$(run write "$domain" Count text >/dev/null; run read "$domain" Count)"
check "a missing key reads as missing" "|1" "$(run read "$domain" Nothing)"
check "a key is deleted" "|0" "$(run delete "$domain" Name)"
check "and then reads as missing" "|1" "$(run read "$domain" Name)"
check "deleting it again says so" "|1" "$(run delete "$domain" Name)"
check "the other keys stay" "1|0" "$(run read "$domain" Flag)"
check "a domain is deleted" "|0" "$(run delete "$domain")"
check "its file with it" "no" "$([ -f "$work/settings/$domain.json" ] && printf yes || printf no)"
check "a missing domain cannot be deleted" "|1" "$(run delete "$domain")"

printf '== A file path as the domain ==\n'
check "a path domain gets .json" "|0" "$(run write "$work/paths/prefs" Key value)"
check "the file is <path>.json" "yes" "$([ -f "$work/paths/prefs.json" ] && printf yes || printf no)"
check "and reads back" "value|0" "$(run read "$work/paths/prefs" Key)"
check "a path ending in .json is used as given" "|0" "$(run write "$work/paths/given.json" Key v)"
check "as given" "yes" "$([ -f "$work/paths/given.json" ] && printf yes || printf no)"

printf '== Refused, on every system ==\n'
check "a key with a slash" "|2" "$(run write "$domain" "a/b" v)"
check "an unknown type" "|2" "$(run write "$domain" Key -dict v)"
check "a bool that is not one" "|2" "$(run write "$domain" Key -bool maybe)"
check "an integer that is not one" "|2" "$(run write "$domain" Key -int 1.5)"
check "an integer beyond 64 bits" "|2" "$(run write "$domain" Key -int 9223372036854775808)"
check "a real that is not one" "|2" "$(run write "$domain" Key -float abc)"
check "a read with no key" "|2" "$(run read "$domain")"
check "an unknown verb" "|2" "$(run export "$domain" x)"
check "an empty domain" "|2" "$(run read "" Key)"
check "a domain that looks like an option" "|2" "$(run read -g Key)"
check "nothing was written by the refused calls" "no" "$([ -f "$work/settings/$domain.json" ] && printf yes || printf no)"

printf '== Without OMC_DEFAULTS_PATH ==\n'
unset OMC_DEFAULTS_PATH
case "${OSTYPE:-}" in
    darwin*)
        # The pass-through, with a file path as the domain so nothing reaches the user's settings
        probe="$work/probe-prefs"
        /usr/bin/defaults write "$probe" ProbeKey ProbeValue 2>/dev/null
        back="$(/usr/bin/defaults read "$probe" ProbeKey 2>/dev/null)"
        if [ "$back" != "ProbeValue" ]; then
            printf '  (left out: /usr/bin/defaults cannot reach the preferences daemon here)\n'
        else
            check "macOS: a write goes to /usr/bin/defaults" "|0" "$(run write "$work/mac-prefs" Name "passed through")"
            check "as a plist, not JSON" "yes no" "$([ -f "$work/mac-prefs.plist" ] && printf yes || printf no) $([ -f "$work/mac-prefs.json" ] && printf yes || printf no)"
            check "and reads back through it" "passed through|0" "$(run read "$work/mac-prefs" Name)"
            check "a bool reads back as 1, as from JSON" "1|0" "$(run write "$work/mac-prefs" Flag -bool true >/dev/null; run read "$work/mac-prefs" Flag)"
            check "an untyped value stays a string there too" "(1, 2)|0" "$(run write "$work/mac-prefs" Parsed "(1, 2)" >/dev/null; run read "$work/mac-prefs" Parsed)"
            check "a missing key reads as missing" "|1" "$(run read "$work/mac-prefs" Nothing)"
        fi
        ;;
    *)
        export XDG_CONFIG_HOME="$work/config"
        check "Linux: a write goes to XDG_CONFIG_HOME" "|0" "$(run write "$domain" Name linux)"
        check "as <domain>.json there" "yes" "$([ -f "$work/config/$domain.json" ] && printf yes || printf no)"
        unset XDG_CONFIG_HOME
        check "else to HOME/.config" "|0" "$(HOME="$work/home" run write "$domain" Name home)"
        check "as <domain>.json there" "yes" "$([ -f "$work/home/.config/$domain.json" ] && printf yes || printf no)"
        check "and reads back from there" "home|0" "$(HOME="$work/home" run read "$domain" Name)"
        ;;
esac

/bin/rm -rf -- "$work"
printf '%d passed, %d failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
exit 0
