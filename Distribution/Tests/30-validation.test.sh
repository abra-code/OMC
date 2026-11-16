#!/bin/sh
# Tests/30-validation.test.sh - the validators, and the pure logic under them.
#
# lib.validate.sh is the gate every build, every Test run and every agent
# `appletbuilder validate` passes through, and it is the one part of AppletBuilder
# whose job is to be right about other people's code. A validator that wrongly
# passes is worse than none: it certifies a broken applet.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

VALIDATE=lib.validate.sh
COMMON=lib.common.sh
BUILD=lib.build.sh

section "1. shell scripts are checked with the shell OMC would actually run"

good="$OMCTEST_WORK/good.sh"
printf '#!/bin/sh\nfoo=1\necho "$foo"\n' > "$good"
check "a clean script passes"          "0"  "$(ab_call_rc $VALIDATE validate_script_file "$good")"
check "and reports nothing"            ""   "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_OUTPUT validate_script_file "$good")"

bad="$OMCTEST_WORK/bad.sh"
printf '#!/bin/sh\nif [ 1 = 1 ]; then\n  echo yes\n' > "$bad"        # never closed
check "an unterminated if is rejected"  "2" "$(ab_call_rc $VALIDATE validate_script_file "$bad")"
check "and the error names the problem" "1" \
    "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_OUTPUT validate_script_file "$bad" | /usr/bin/grep -ci 'unexpected end of file')"

section "2. bash-only syntax in a .sh file is an error, with an explanation"
# OMC runs .sh under /bin/sh - bash 3.2 in POSIX mode. Process substitution
# parses under bash and is fatal there, which is exactly the trap the note is for.

bashism="$OMCTEST_WORK/bashism.sh"
printf '#!/bin/sh\nwhile read -r l; do echo "$l"; done < <(echo hi)\n' > "$bashism"
check "it is rejected"                 "2"  "$(ab_call_rc $VALIDATE validate_script_file "$bashism")"
check "and the report explains why it looked fine" "1" \
    "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_OUTPUT validate_script_file "$bashism" | /usr/bin/grep -c 'the Command Engine runs .sh files with /bin/sh')"

section "3. bash 4 constructs parse but never run, so they are warned about"
# These are the ones a syntax check cannot catch: valid to the parser, absent
# from the only bash a stock Mac has.

b4() { # <line of shell> -> the warning text, or empty
    _f="$OMCTEST_WORK/b4.sh"
    printf '#!/bin/sh\n%s\n' "$1" > "$_f"
    ab_call_out $VALIDATE SCRIPT_VALIDATE_WARNINGS validate_script_file "$_f"
}

check "mapfile is caught"        "1" "$(b4 'mapfile -t arr < f'   | /usr/bin/grep -c 'bash 4+')"
check "declare -A is caught"     "1" "$(b4 'declare -A m'         | /usr/bin/grep -c 'bash 4+')"
check "uppercase expansion is caught" "1" "$(b4 'echo "${v^^}"'   | /usr/bin/grep -c 'bash 4+')"
check "coproc is caught"         "1" "$(b4 'coproc cat'           | /usr/bin/grep -c 'bash 4+')"
check "@Q transformation is caught" "1" "$(b4 'echo "${v@Q}"'     | /usr/bin/grep -c 'bash 4.4+')"  # bash4-ok
check "EPOCHSECONDS is caught"   "1" "$(b4 'echo $EPOCHSECONDS'   | /usr/bin/grep -c 'bash 5+')"
check "and the warning carries the line number" "1" "$(b4 'mapfile -t arr < f' | /usr/bin/grep -c '^line 2: ')"

# The scanner is a text heuristic, so its two escape hatches are the difference
# between a useful warning and one everybody learns to ignore.
check "a commented-out construct is not flagged"  "" "$(b4 '# mapfile -t arr < f')"
check "a bash4-ok marker silences a false positive" "" "$(b4 'echo "the mapfile builtin" # bash4-ok')"

# The positive control for both: the same lines without their exemption DO fire.
# Without this, a scanner that had stopped working entirely would pass above.
check "the same line unexempted does fire" "1" "$(b4 'echo "the mapfile builtin"' | /usr/bin/grep -c 'bash 4+')"

# Three of the scanner's rules can never fire for a .sh or .bash file, and it is
# worth pinning why rather than assuming they work. `|&`, `&>>` and `;;&` are
# syntax errors to bash 3.2, so /bin/sh -n rejects the file and the scan - which
# only runs on a file that parsed - is never reached. They are caught, just by
# the parser and with a less helpful message. The rules stay as belt and braces.
b4rc() { # <line of shell> -> validate_script_file's exit code
    _f="$OMCTEST_WORK/b4rc.sh"
    printf '#!/bin/sh\n%s\n' "$1" > "$_f"
    ab_call_rc $VALIDATE validate_script_file "$_f"
}
check "|& never reaches the scanner: it is a parse error"  "2" "$(b4rc 'cmd |& other')"  # bash4-ok
check "and so is &>>"                                      "2" "$(b4rc 'ls &>> out.log')"  # bash4-ok
check "and so is the case fallthrough operator"            "2" "$(b4rc 'case x in a) echo a ;;& esac')"  # bash4-ok
check "while @Q does parse, which is why it needs the scanner" "0" "$(b4rc 'echo "${v@Q}"')"

section "4. warnings are only raised for a script that parses at all"
# A file with both a syntax error and a bash4-ism reports the error; scanning a
# file the shell could not parse would guess at line numbers.

both="$OMCTEST_WORK/both.sh"
printf '#!/bin/sh\nmapfile -t a < f\nif [ 1 = 1 ]; then\n' > "$both"
check "the syntax error is what is reported" "2" "$(ab_call_rc $VALIDATE validate_script_file "$both")"
check "and no warnings are guessed at"       ""  "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_WARNINGS validate_script_file "$both")"

section "5. Python is checked with the applet's own embedded interpreter"

pygood="$OMCTEST_WORK/good.py"
printf 'def f(x):\n    return x + 1\n' > "$pygood"
check "a clean module passes"          "0"  "$(ab_call_rc $VALIDATE validate_script_file "$pygood")"

pybad="$OMCTEST_WORK/bad.py"
printf 'def f(x)\n    return x\n' > "$pybad"                          # missing colon
check "a syntax error is rejected"     "1"  "$(ab_call_rc $VALIDATE validate_script_file "$pybad")"
check "and the report locates it"      "1" \
    "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_OUTPUT validate_script_file "$pybad" | /usr/bin/grep -c 'line 1')"

section "6. a file type with no validator is not a failure"
# 99 means "nothing to say", and the build pipeline must not read it as an error -
# a .txt or a .png in Scripts/ is legal.

other="$OMCTEST_WORK/notes.txt"
printf 'just text\n' > "$other"
check "an unknown extension yields 99" "99" "$(ab_call_rc $VALIDATE validate_script_file "$other")"

section "7. the command manifest is validated, and a broken one is located"

project="$(ab_make_project Widget)"
check "the shipped template validates clean" "0" \
    "$(ab_call_rc $VALIDATE validate_command_file "$project")"

torn="$project/Contents/Resources/Command.json"
/bin/cp "$torn" "$OMCTEST_WORK/Command.json.orig"
printf '{"COMMAND_LIST": [' > "$torn"
check "malformed JSON is caught by the syntax gate" "3" \
    "$(ab_call_rc $VALIDATE validate_command_file "$project")"
check "and the report says where"      "1" \
    "$(ab_call_out $VALIDATE COMMAND_VALIDATE_OUTPUT validate_command_file "$project" | /usr/bin/grep -ci 'line')"
/bin/cp "$OMCTEST_WORK/Command.json.orig" "$torn"
check "restored, it validates again"   "0"  "$(ab_call_rc $VALIDATE validate_command_file "$project")"

empty="$OMCTEST_WORK/NoManifest.app"
/bin/mkdir -p "$empty/Contents/Resources"
check "an applet with no manifest yields 99" "99" \
    "$(ab_call_rc $VALIDATE validate_command_file "$empty")"

section "8. ActionUI documents are validated against the shipped schemas"

check "the template's window validates clean" "0" \
    "$(ab_call_rc $VALIDATE validate_actionui_file "$project/Contents/Resources/Base.lproj/Window.json")"

nonsense="$OMCTEST_WORK/Nonsense.json"
printf '{"elements":[{"type":"NoSuchElementType","id":9}]}' > "$nonsense"
check "an unknown element type is not called valid" "0" \
    "$(_rc=$(ab_call_rc $VALIDATE validate_actionui_file "$nonsense"); [ "$_rc" = "0" ] && echo 1 || echo 0)"

section "8b. the Swift verifier is preferred, the Python one is the fallback"
# Two verifiers ship: actionui-verify (Swift, Contents/Helpers) and the Python one
# (Contents/Library/actionui_verifier). Section 8 above ran whichever is preferred.
# This section pins which one that is, what it is given, and that the fallback
# still gives the same answers. AB_ACTIONUI_VERIFY_TOOL is the seam; every use is
# inside $(...), so the override cannot outlive its check.

check "the Swift verifier is bundled" "yes" \
    "$([ -x "$OMC_APP_BUNDLE_PATH/Contents/Helpers/actionui-verify" ] && echo yes || echo no)"

# A stand-in that records its arguments, to see what validate_actionui_file runs.
verify_stub="$OMCTEST_WORK/actionui-verify-stub"
verify_args="$OMCTEST_WORK/actionui-verify-args"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\necho "[OK] stub"\n' "$verify_args" > "$verify_stub"
/bin/chmod 755 "$verify_stub"
window_json="$project/Contents/Resources/Base.lproj/Window.json"
check "the tool is what runs when it is there" "[OK] stub" \
    "$(AB_ACTIONUI_VERIFY_TOOL="$verify_stub" ab_call_out $VALIDATE ACTIONUI_VALIDATE_OUTPUT validate_actionui_file "$window_json")"
check "it reads the schemas the Python verifier ships" \
    "--schemas
$OMC_APP_BUNDLE_PATH/Contents/Library/actionui_verifier/schemas
$window_json" \
    "$(/bin/cat "$verify_args" 2>/dev/null)"

# The fallback, forced by pointing the seam at nothing.
no_tool="$OMCTEST_WORK/no-such-actionui-verify"
check "without the tool, the Python verifier passes the template's window" "0" \
    "$(AB_ACTIONUI_VERIFY_TOOL="$no_tool" ab_call_rc $VALIDATE validate_actionui_file "$window_json")"
check "and still rejects an unknown element type" "0" \
    "$(_rc=$(AB_ACTIONUI_VERIFY_TOOL="$no_tool" ab_call_rc $VALIDATE validate_actionui_file "$nonsense"); [ "$_rc" = "0" ] && echo 1 || echo 0)"

# Same lines from both, on a document with errors and warnings in it - the
# property that makes the swap invisible to everything that reads the report.
mixed="$OMCTEST_WORK/Mixed.json"
printf '{"type":"VStack","children":[{"type":"Text","id":1,"properties":{"txt":"typo"}},{"type":"Text","id":1},{"type":"Nope"}]}' > "$mixed"
swift_report="$(ab_call_out $VALIDATE ACTIONUI_VALIDATE_OUTPUT validate_actionui_file "$mixed" | /usr/bin/sort)"
python_report="$(AB_ACTIONUI_VERIFY_TOOL="$no_tool" ab_call_out $VALIDATE ACTIONUI_VALIDATE_OUTPUT validate_actionui_file "$mixed" | /usr/bin/sort)"
check "the mixed document has something to compare" "yes" \
    "$(printf '%s\n' "$swift_report" | /usr/bin/grep -q 'duplicate' && printf '%s\n' "$swift_report" | /usr/bin/grep -q 'possible typo' && echo yes || echo no)"
check "and both verifiers report it line for line" "$python_report" "$swift_report"
check "with the same exit code" \
    "$(AB_ACTIONUI_VERIFY_TOOL="$no_tool" ab_call_rc $VALIDATE validate_actionui_file "$mixed")" \
    "$(ab_call_rc $VALIDATE validate_actionui_file "$mixed")"

section "9. which manifest a project uses, decided the way OMC decides it"
# OMC reads Command.json when both exist. A resolver that disagreed would let the
# editor save into the file the engine ignores.

both_app="$OMCTEST_WORK/Both.app"
/bin/mkdir -p "$both_app/Contents/Resources"
printf '{}' > "$both_app/Contents/Resources/Command.json"
printf '<plist/>' > "$both_app/Contents/Resources/Command.plist"
check "JSON wins when both are present" "$both_app/Contents/Resources/Command.json" \
    "$(ab_call $COMMON command_file_path "$both_app")"

/bin/rm "$both_app/Contents/Resources/Command.json"
check "the plist is used when it is the only one" "$both_app/Contents/Resources/Command.plist" \
    "$(ab_call $COMMON command_file_path "$both_app")"

/bin/rm "$both_app/Contents/Resources/Command.plist"
check "with neither, the modern default is proposed" "$both_app/Contents/Resources/Command.json" \
    "$(ab_call $COMMON command_file_path "$both_app")"

check "Command.json is recognized as the manifest"  "0" "$(ab_call_rc $COMMON is_command_file_name Command.json)"
check "Command.plist is too"                        "0" "$(ab_call_rc $COMMON is_command_file_name Command.plist)"
check "but a window document is not"                "1" "$(ab_call_rc $COMMON is_command_file_name Window.json)"
check "nor one that merely contains the word"       "1" "$(ab_call_rc $COMMON is_command_file_name MyCommand.json)"

section "10. framework version comparison, which decides whether to overwrite"
# Getting this backwards downgrades a working applet's framework on every build.

check "a higher major is newer"  "newer"  "$(ab_call $BUILD compare_versions 6.0.0 5.9.9)"
check "a lower major is older"   "older"  "$(ab_call $BUILD compare_versions 5.9.9 6.0.0)"
check "equal is same"            "same"   "$(ab_call $BUILD compare_versions 5.2.1 5.2.1)"
check "minor version decides"    "newer"  "$(ab_call $BUILD compare_versions 5.3 5.2)"
check "patch version decides"    "newer"  "$(ab_call $BUILD compare_versions 5.2.1 5.2)"
# The one people get wrong: string comparison would call 5.10 older than 5.9.
check "ten sorts above nine"     "newer"  "$(ab_call $BUILD compare_versions 5.10 5.9)"
check "a missing component reads as zero" "same" "$(ab_call $BUILD compare_versions 5.2 5.2.0)"

section "11. where a suite is expected to live"

# Compared against a normalized parent, not against "$OMCTEST_WORK/Tests":
# macOS hands an app a TMPDIR with a trailing slash, so the harness scratch path
# carries an interior "//" that applet_tests_dir's own cd/pwd removes. Comparing
# the raw strings would fail over a doubled slash rather than over the answer.
check "Tests sits beside the applet, not inside it" \
    "$(cd "$OMCTEST_WORK" && pwd)/Tests" \
    "$(ab_call $BUILD applet_tests_dir "$project")"
check "and it is named for the applet's parent, not the applet" "0" \
    "$(ab_call $BUILD applet_tests_dir "$project" | /usr/bin/grep -c 'Widget.app')"

section "12. a new command gets an id nothing else in the manifest is using"

cmd_file="$(ab_command_file "$project")"
check "the first one is unsuffixed" "Widget.new.command" \
    "$(ab_call lib.plist.sh unique_command_id "$cmd_file" "Widget")"

/usr/bin/plutil -replace COMMAND_LIST.0.COMMAND_ID -string "Widget.new.command" "$cmd_file"
check "a taken id is stepped over"  "Widget.new.command.2" \
    "$(ab_call lib.plist.sh unique_command_id "$cmd_file" "Widget")"

/usr/bin/plutil -insert COMMAND_LIST -json '{"NAME":"Widget","COMMAND_ID":"Widget.new.command.2"}' -append "$cmd_file"
check "and it keeps stepping"       "Widget.new.command.3" \
    "$(ab_call lib.plist.sh unique_command_id "$cmd_file" "Widget")"

check "a different prefix is unaffected" "Other.new.command" \
    "$(ab_call lib.plist.sh unique_command_id "$cmd_file" "Other")"

section "13. the agent CLI validates the same way the Test button does"
# Same lib.build.sh entry points, so this is a smoke test of the wiring, not a
# second copy of the rules.

clean="$(ab_make_project Pristine)"
ab_add_executable "$clean"
ab_cli validate "$clean" >/dev/null 2>&1
check "a well-formed applet passes"    "0"  "$?"

ab_cli validate "$OMCTEST_WORK/NoSuchApplet.app" >/dev/null 2>&1
check "a missing applet is a usage error" "0" \
    "$(_rc=$?; [ "$_rc" = "0" ] && echo 1 || echo 0)"

printf 'if [ 1 = 1 ]; then\n' > "$clean/Contents/Resources/Scripts/Broken.helper.sh"
ab_cli validate "$clean" >/dev/null 2>&1
check "a broken handler script fails the applet" "1" "$?"

section "13b. an option with no value is refused, on every command that takes one"
# The failure this pins is a HANG, not a wrong answer: `shift 2` with one argument
# left shifts nothing and returns non-zero, so an option arriving as the final argv
# token spins the loop forever at 100% CPU. A truncated argv is an ordinary thing
# for an agent to produce, and every command that takes an option value is one
# missing guard away from it.
#
# Run under a hard time cap, or a regression would hang this suite instead of
# failing it. perl, because macOS ships no timeout(1).
cli_capped() { # <seconds> <args...> -> the CLI's exit status, or 142 if it hung
    _cap="$1"
    shift
    /usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' \
        "$_cap" "$AB_AGENTS/appletbuilder" "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

check "create --name with nothing after it"    "2" "$(cli_capped 10 create --name)"
check "create --template"                      "2" "$(cli_capped 10 create --template)"
check "create --dest"                          "2" "$(cli_capped 10 create --dest)"
check "create --identity"                      "2" "$(cli_capped 10 create --identity)"
check "preview --screenshot"                   "2" "$(cli_capped 10 preview --screenshot)"
check "build --identity"                       "2" "$(cli_capped 10 build --identity)"
check "test --filter"                          "2" "$(cli_capped 10 test --filter)"
# The value-shaped guard too: an option swallowing the NEXT option as its value is
# the same argv typo one token longer.
check "and an option is not a value"           "2" "$(cli_capped 10 create --name --python)"

section "13c. create: a bare name is a template's, and only an applet is copied"
# A bare --template name that was also a folder in the current directory took the folder,
# so "ActionUI" run from ~/git copied the ActionUI repository and then failed on its missing
# Info.plist with a message about the URL scheme. Now the template comes first, and anything
# that is not an applet stops the command before a copy.
tpl_work="$OMCTEST_WORK/template-lookup"
/bin/mkdir -p "$tpl_work/cwd/Empty/inside" "$tpl_work/cwd/NotATemplate" "$tpl_work/dest"
tpl_status="$(cd "$tpl_work/cwd" && "$AB_AGENTS/appletbuilder" create --template Empty --name FromTemplate --dest "$tpl_work/dest" >/dev/null 2>&1; printf '%s' "$?")"
check "a bare name beside a folder of that name takes the template" "0|yes" \
    "$tpl_status|$([ -f "$tpl_work/dest/FromTemplate.app/Contents/Info.plist" ] && echo yes || echo no)"
tpl_status="$(cd "$tpl_work/cwd" && "$AB_AGENTS/appletbuilder" create --template NotATemplate --name FromFolder --dest "$tpl_work/dest" >/dev/null 2>&1; printf '%s' "$?")"
check "a folder that is not an applet is a usage error, nothing copied" "2|no" \
    "$tpl_status|$([ -e "$tpl_work/dest/FromFolder.app" ] && echo yes || echo no)"
tpl_message="$(cd "$tpl_work/cwd" && "$AB_AGENTS/appletbuilder" create --template NoSuchTemplate --name Missing --dest "$tpl_work/dest" 2>&1 >/dev/null)"
tpl_found="no: $tpl_message"
case "$tpl_message" in
    *"no template named 'NoSuchTemplate'"*) tpl_found="yes" ;;
esac
check "an unknown name says there is no such template" "yes" "$tpl_found"
"$AB_AGENTS/appletbuilder" create --clone "$tpl_work/cwd/NotATemplate" --name Cloned --dest "$tpl_work/dest" >/dev/null 2>&1
check "a clone of a folder that is not an applet is a usage error" "2" "$?"
/bin/mkdir -p "$tpl_work/cwd/Mine.app/Contents"
/bin/cp "$tpl_work/dest/FromTemplate.app/Contents/Info.plist" "$tpl_work/cwd/Mine.app/Contents/Info.plist"
tpl_status="$(cd "$tpl_work/cwd" && "$AB_AGENTS/appletbuilder" create --template Mine.app --name FromCwd --dest "$tpl_work/dest" >/dev/null 2>&1; printf '%s' "$?")"
check "an applet folder in the current directory is still taken by bare name" "0" "$tpl_status"

section "14. the manifest editor's operations, called directly"
# The Info.plist edits (the General pane's fields, the Services) are made with
# plister alone (lib.plist.sh's info_plist_*), on macOS and Linux, through
# plist_edit's temp copy. The command file's are plist_edit.py's: its op_*
# functions take a dict and mutate it with no I/O, so they can be called
# straight rather than only through a whole handler.

info_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ab_info_plist_XXXXXX")"
info_plist="$info_dir/Info.plist"
/bin/cat > "$info_plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Widget</string>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Show Path</string></dict>
			<key>NSSendFileTypes</key>
			<array><string>public.item</string></array>
			<key>NSUserData</key>
			<string>demo.show</string>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Folders Only</string></dict>
			<key>NSSendFileTypes</key>
			<array><string>public.folder</string></array>
			<key>NSSendTypes</key>
			<array><string>NSFilenamesPboardType</string></array>
			<key>NSUserData</key>
			<string>demo.show</string>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Modern Text</string></dict>
			<key>NSSendTypes</key>
			<array><string>public.utf8-plain-text</string></array>
			<key>NSUserData</key>
			<string>text.modern</string>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Upper Case</string></dict>
			<key>NSSendTypes</key>
			<array><string>NSStringPboardType</string></array>
			<key>NSUserData</key>
			<string>text.upper</string>
		</dict>
		<dict>
			<key>NSMenuItem</key>
			<dict><key>default</key><string>Images</string></dict>
			<key>NSSendFileTypes</key>
			<array><string>public.image</string></array>
			<key>NSUserData</key>
			<string>demo.images</string>
		</dict>
	</array>
</dict>
</plist>
EOF
/bin/chmod 644 "$info_plist"
info_value() { ab_call lib.plist.sh plist_read "$info_plist" "$1"; }

check "set_keys writes the pair it is given" "0" \
    "$(ab_call_rc lib.plist.sh plist_edit "$info_plist" set_keys CFBundleName Renamed)"
check "and the value is there" "Renamed" "$(info_value CFBundleName)"
ab_call lib.plist.sh plist_edit "$info_plist" set_keys CFBundleName "A & <B>" CFBundleVersion 1.0 >/dev/null 2>&1
check "it takes several pairs at once" "A & <B>|1.0" "$(info_value CFBundleName)|$(info_value CFBundleVersion)"
check "a key with no value is refused" "1" \
    "$(ab_call_rc lib.plist.sh plist_edit "$info_plist" set_keys CFBundleVersion)"
check "and leaves the file as it was" "1.0" "$(info_value CFBundleVersion)"
check "the Info.plist keeps its mode" "644" "$(/usr/bin/stat -f '%Lp' "$info_plist")"

# The pane's Input kind of each service (the picker shows it; a save is compared with it)
check "the Input kinds: public.item, public.folder, a modern text type, NSStringPboardType" "files folders text text" \
    "$(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 0) $(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 1) $(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 2) $(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 3)"
# File types make a file service whatever NSSendTypes says (the engine and command-services.py),
# so file types with a text type are other; an entry that is not a string does not end the scan
kinds_plist="$info_dir/Kinds.plist"
/bin/cat > "$kinds_plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSSendFileTypes</key>
			<array><string>public.folder</string></array>
			<key>NSSendTypes</key>
			<array><string>NSStringPboardType</string></array>
		</dict>
		<dict>
			<key>NSSendTypes</key>
			<array><dict/><string>NSStringPboardType</string></array>
		</dict>
		<dict>
			<key>NSSendFileTypes</key>
			<array/>
			<key>NSSendTypes</key>
			<array><string>NSStringPboardType</string></array>
		</dict>
	</array>
</dict>
</plist>
EOF
check "the Input kinds: folder and text types, text after a dict, empty file types and text" "other text text" \
    "$(ab_call lib.plist.sh info_plist_service_kind "$kinds_plist" 0) $(ab_call lib.plist.sh info_plist_service_kind "$kinds_plist" 1) $(ab_call lib.plist.sh info_plist_service_kind "$kinds_plist" 2)"

# The pane saves a service at every field change, the title at each keystroke:
# with the Input picker as shown, the service's own types must stay as they are
ab_call lib.plist.sh plist_edit "$info_plist" update_service 1 "Folders Only, Renamed" demo.other folders >/dev/null 2>&1
check "a title save sets the title" "Folders Only, Renamed" "$(info_value NSServices/1/NSMenuItem/default)"
check "and the command" "demo.other" "$(info_value NSServices/1/NSUserData)"
check "and a folders-only service stays one" "public.folder" "$(info_value NSServices/1/NSSendFileTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 0 "Show Path" demo.show files >/dev/null 2>&1
check "a service with file types only is not given send types" "" "$(info_value NSServices/0/NSSendTypes/0)"
check "and keeps its file types" "public.item" "$(info_value NSServices/0/NSSendFileTypes/0)"
# A modern text type shows as text, and a text save keeps it
ab_call lib.plist.sh plist_edit "$info_plist" update_service 2 "Modern Text" text.modern text >/dev/null 2>&1
check "types the picker cannot write are kept" "public.utf8-plain-text" "$(info_value NSServices/2/NSSendTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 3 "Upper Case" text.upper text >/dev/null 2>&1
check "a text service saved as text stays text" "NSStringPboardType" "$(info_value NSServices/3/NSSendTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 0 "Show Path" demo.show text >/dev/null 2>&1
check "changing the Input to text sets the text type" "NSStringPboardType" "$(info_value NSServices/0/NSSendTypes/0)"
check "and drops the file types" "" "$(info_value NSServices/0/NSSendFileTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 0 "Show Path" demo.show files >/dev/null 2>&1
check "and back to files" "NSFilenamesPboardType" "$(info_value NSServices/0/NSSendTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 1 "Folders Only, Renamed" demo.other "" >/dev/null 2>&1
check "a save with no Input value keeps the types" "public.folder|" \
    "$(info_value NSServices/1/NSSendFileTypes/0)|$(info_value NSServices/1/NSSendTypes/1)"
# Through Text and back to Folders (the owner's ServiceDemo lost its folders-only type going through
# Text and back to Files / Folders, when the picker had no Folders choice)
ab_call lib.plist.sh plist_edit "$info_plist" update_service 1 "Folders Only, Renamed" demo.other text >/dev/null 2>&1
check "a folders service changed to text" "NSStringPboardType|" \
    "$(info_value NSServices/1/NSSendTypes/0)|$(info_value NSServices/1/NSSendFileTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 1 "Folders Only, Renamed" demo.other folders >/dev/null 2>&1
check "and back to folders" "public.folder||folders" \
    "$(info_value NSServices/1/NSSendFileTypes/0)|$(info_value NSServices/1/NSSendTypes/0)|$(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 1)"
# File types the pane cannot write show as other, and a save, other or not, keeps them unless a
# writable kind is chosen
ab_call lib.plist.sh plist_edit "$info_plist" update_service 0 "Show Path" demo.show other >/dev/null 2>&1
check "other on a files service changes nothing" "NSFilenamesPboardType" "$(info_value NSServices/0/NSSendTypes/0)"
check "a service for images is other" "other" "$(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 4)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 4 "Images" demo.images other >/dev/null 2>&1
check "and keeps its types at a save" "public.image" "$(info_value NSServices/4/NSSendFileTypes/0)"
ab_call lib.plist.sh plist_edit "$info_plist" update_service 4 "Images" demo.images folders >/dev/null 2>&1
check "until Folders is chosen" "public.folder||folders" \
    "$(info_value NSServices/4/NSSendFileTypes/0)|$(info_value NSServices/4/NSSendFileTypes/1)|$(ab_call lib.plist.sh info_plist_service_kind "$info_plist" 4)"
check "an update of a service that is not there fails" "1" \
    "$(ab_call_rc lib.plist.sh plist_edit "$info_plist" update_service 9 "Nothing" demo.show files)"
check "as does one with no index" "1" \
    "$(ab_call_rc lib.plist.sh plist_edit "$info_plist" update_service "" "Nothing" demo.show files)"

ab_call lib.plist.sh plist_edit "$info_plist" append_service "New Service" demo.new >/dev/null 2>&1
check "a new service goes at the end" "New Service" "$(info_value NSServices/5/NSMenuItem/default)"
check "for files and folders" "NSFilenamesPboardType" "$(info_value NSServices/5/NSSendTypes/0)"
check "with the engine's service entry point" "runOMCService|OMCService|demo.new" \
    "$(info_value NSServices/5/NSMessage)|$(info_value NSServices/5/NSPortName)|$(info_value NSServices/5/NSUserData)"
ab_call lib.plist.sh plist_edit "$info_plist" remove_service 0 >/dev/null 2>&1
check "removing a service removes exactly that one" "Folders Only, Renamed|New Service" \
    "$(info_value NSServices/0/NSMenuItem/default)|$(info_value NSServices/4/NSMenuItem/default)"
check "removing one that is not there is a no-op" "0" \
    "$(ab_call_rc lib.plist.sh plist_edit "$info_plist" remove_service 7)"

# NSServices made when there is none, and a binary plist edited as binary
/bin/rm -f "$info_plist"
/usr/bin/printf '{"CFBundleName": "Bare"}' > "$info_dir/bare.json"
/usr/bin/plutil -convert binary1 -o "$info_plist" "$info_dir/bare.json"
ab_call lib.plist.sh plist_edit "$info_plist" append_service "First" demo.first >/dev/null 2>&1
check "the first service of an applet that has none" "First" "$(info_value NSServices/0/NSMenuItem/default)"
check "and a binary Info.plist stays binary" "bplist00" "$(/usr/bin/head -c 8 "$info_plist")"
/bin/rm -rf "$info_dir"

check "a new command carries the id it was given" "widget.do.thing" \
    "$(ab_py plist_edit 'op_append_command_full(d, args) or d["COMMAND_LIST"][0]["COMMAND_ID"]' \
        Widget widget.do.thing exe_script_file act_always)"
check "and a script-file command gets no inline body" "no" \
    "$(ab_py plist_edit '"yes" if "COMMAND" in (op_append_command_full(d, args) or d["COMMAND_LIST"][0]) else "no"' \
        Widget widget.do.thing exe_script_file act_always)"
# The branch that matters: a mode that runs inline code must ship a stub, or the
# new command does nothing at all when the user runs it.
check "but an inline mode does get one" "yes" \
    "$(ab_py plist_edit '"yes" if "COMMAND" in (op_append_command_full(d, args) or d["COMMAND_LIST"][0]) else "no"' \
        Widget widget.do.thing exe_shell_script act_always)"
check "and an output-window mode gets its settings" "yes" \
    "$(ab_py plist_edit '"yes" if "OUTPUT_WINDOW_SETTINGS" in (op_append_command_full(d, args) or d["COMMAND_LIST"][0]) else "no"' \
        Widget widget.do.thing exe_display_in_output_window act_always)"

check "removing an out-of-range index is a no-op, not a crash" "1" \
    "$(ab_py plist_edit 'len((op_append_command(d, ["A"]), op_remove_command(d, ["7"]), d["COMMAND_LIST"])[2])')"
check "removing a valid index removes exactly one" "0" \
    "$(ab_py plist_edit 'len((op_append_command(d, ["A"]), op_remove_command(d, ["0"]), d["COMMAND_LIST"])[2])')"

section "14b. a legacy Command.plist on Linux: plist_convert.py does what plutil does"
# A legacy Command.plist is edited as JSON: plutil converts it on macOS, and on
# Linux (no plutil) plist_convert.py with plistlib. lib.plist.sh picks by OSTYPE,
# so setting it to linux-gnu runs the Linux branch here, and every result is
# compared with plutil's, byte for byte.

legacy_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ab_legacy_plist_XXXXXX")"
/bin/cat > "$legacy_dir/Command.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>VERSION</key>
	<integer>2</integer>
	<key>COMMAND_LIST</key>
	<array>
		<dict>
			<key>NAME</key>
			<string>Show "Path" &amp; More</string>
			<key>COMMAND_ID</key>
			<string>widget.show</string>
			<key>EXECUTION_MODE</key>
			<string>exe_shell_script</string>
			<key>COMMAND</key>
			<array>
				<string>echo "caf&#233; &lt;ok&gt;"</string>
			</array>
			<key>OUTPUT_WINDOW_SETTINGS</key>
			<dict>
				<key>TEXT_SIZE</key>
				<integer>11</integer>
				<key>WINDOW_ALPHA</key>
				<real>0.95</real>
				<key>WINDOW_LARGE</key>
				<real>1e+20</real>
			</dict>
			<key>REFRESH_PATHS</key>
			<true/>
		</dict>
		<dict>
			<key>NAME</key>
			<string>Second</string>
			<key>EXECUTION_MODE</key>
			<string>exe_script_file</string>
		</dict>
	</array>
</dict>
</plist>
EOF
# lib.plist.sh run as on Linux: OSTYPE set before it is sourced (bash sets it at start-up)
as_linux() {
    /bin/bash -c 'OSTYPE=linux-gnu; . "$1" >/dev/null 2>&1; shift; "$@"' _ "$AB_SCRIPTS/lib.plist.sh" "$@"
}
legacy="$legacy_dir/Command.plist"

check "the editor's text of a command is plutil's" \
    "$(ab_call lib.plist.sh command_text "$legacy" 0)" "$(as_linux command_text "$legacy" 0)"
check "and it is the command's dict" "<dict>" "$(as_linux command_text "$legacy" 0 | /usr/bin/head -1)"
check "a command that is not there shows nothing" "" "$(as_linux command_text "$legacy" 5)"

/usr/bin/plutil -convert json -o "$legacy_dir/plutil.json" "$legacy"
as_linux command_plist_to_json "$legacy" "$legacy_dir/linux.json"
check "converted to JSON" "0" "$?"
/usr/bin/plutil -convert xml1 -o "$legacy_dir/from-plutil-json.plist" "$legacy_dir/plutil.json"
/usr/bin/plutil -convert xml1 -o "$legacy_dir/from-linux-json.plist" "$legacy_dir/linux.json"
check "with the values plutil's JSON has" "same" \
    "$(/usr/bin/cmp -s "$legacy_dir/from-plutil-json.plist" "$legacy_dir/from-linux-json.plist" && echo same || echo different)"
as_linux command_plist_from_json "$legacy_dir/plutil.json" "$legacy_dir/linux-xml1.plist"
check "and back to XML as plutil writes it" "same" \
    "$(/usr/bin/cmp -s "$legacy_dir/from-plutil-json.plist" "$legacy_dir/linux-xml1.plist" && echo same || echo different)"

check "a valid plist passes the lint" "0" "$(as_linux command_plist_lint "$legacy" >/dev/null 2>&1; echo $?)"
printf '<plist><dict><key>A</key></dict>' > "$legacy_dir/broken.plist"
check "a broken one does not" "1" "$(as_linux command_plist_lint "$legacy_dir/broken.plist" >/dev/null 2>&1; echo $?)"
check "and says why" "yes" \
    "$([ -n "$(as_linux command_plist_lint "$legacy_dir/broken.plist" 2>&1)" ] && echo yes || echo no)"

# A whole edit through plist_edit, once by each branch, from the same file
/bin/cp "$legacy" "$legacy_dir/mac.plist"
/bin/cp "$legacy" "$legacy_dir/linux.plist"
ab_call lib.plist.sh plist_edit "$legacy_dir/mac.plist" append_command_full New new.cmd exe_shell_script act_always >/dev/null 2>&1
as_linux plist_edit "$legacy_dir/linux.plist" append_command_full New new.cmd exe_shell_script act_always >/dev/null 2>&1
check "an edit on Linux succeeds" "0" "$?"
check "and writes what the plutil branch writes" "same" \
    "$(/usr/bin/cmp -s "$legacy_dir/mac.plist" "$legacy_dir/linux.plist" && echo same || echo different)"
check "the new command is there" "New" "$(ab_call lib.plist.sh plist_read "$legacy_dir/linux.plist" COMMAND_LIST/2/NAME)"

# One difference, on purpose: plutil's JSON writes a whole-number real as 1, which
# comes back an integer; plistlib's JSON keeps it a real (1.0)
printf '<plist version="1.0"><dict><key>COMMAND_LIST</key><array><dict><key>NAME</key><string>A</string><key>SCALE</key><real>1</real></dict></array></dict></plist>' > "$legacy_dir/real.plist"
as_linux plist_edit "$legacy_dir/real.plist" remove_command 5 >/dev/null 2>&1
check "a whole-number real stays a real on Linux" "1" "$(/usr/bin/grep -c '<real>1</real>' "$legacy_dir/real.plist")"

# A carriage return would come back a line feed through plistlib: refused, file untouched
printf '<plist version="1.0"><dict><key>COMMAND_LIST</key><array><dict><key>NAME</key><string>A</string><key>COMMAND</key><array><string>echo a\r\necho b</string></array></dict></array></dict></plist>' > "$legacy_dir/crlf.plist"
/bin/cp "$legacy_dir/crlf.plist" "$legacy_dir/crlf-before.plist"
as_linux plist_edit "$legacy_dir/crlf.plist" remove_command 5 >/dev/null 2>&1
check "a Command.plist with a carriage return is refused on Linux" "1" "$?"
check "and left as it was" "same" \
    "$(/usr/bin/cmp -s "$legacy_dir/crlf.plist" "$legacy_dir/crlf-before.plist" && echo same || echo different)"
printf '<plist version="1.0"><dict><key>COMMAND_LIST</key><array><dict><key>NAME</key><string>A&#13;</string></dict></array></dict></plist>' > "$legacy_dir/cr-ref.plist"
check "so is one written as a character reference" "1" \
    "$(as_linux command_plist_lint "$legacy_dir/cr-ref.plist" >/dev/null 2>&1; echo $?)"
/bin/rm -rf "$legacy_dir"

section "15. renaming values inside a JSON manifest"
# json_rename_value.walk is what carries an applet's new name through its command
# file. It must replace whole scalar VALUES only - never keys, never substrings,
# or a rename corrupts every command whose text merely mentions the old name.

check "a matching value is replaced" "New" \
    "$(ab_py json_rename_value 'walk("Old", "Old", "New")')"
check "a non-matching value is left alone" "Older" \
    "$(ab_py json_rename_value 'walk("Older", "Old", "New")')"
check "a substring is NOT replaced" "MyOldThing" \
    "$(ab_py json_rename_value 'walk("MyOldThing", "Old", "New")')"
check "a matching KEY is left alone" "{'Old': 'New'}" \
    "$(ab_py json_rename_value 'walk({"Old": "Old"}, "Old", "New")')"
check "it recurses into lists" "['New', 'keep']" \
    "$(ab_py json_rename_value 'walk(["Old", "keep"], "Old", "New")')"

section "16. Credits.md is required: the About window shows it"
# The engine's About window shows Contents/Resources/Credits.md, on macOS and on
# Linux; Credits.rtf, which macOS's standard panel read, is not shown any more.
# A project without Credits.md does not build, and one that still has only
# Credits.rtf is told how to convert it. A leftover Credits.rtf beside a
# Credits.md is a warning.

credits_ok="$(ab_make_project CreditsOK)"
check "a template has Credits.md" "yes" \
    "$([ -f "$credits_ok/Contents/Resources/Credits.md" ] && echo yes || echo no)"
check "and validates" "0" "$(ab_call_rc lib.build.sh validate_project "$credits_ok")"
check "saying so" "1" \
    "$(ab_call_log lib.build.sh validate_project "$credits_ok" | /usr/bin/grep -c 'Credits.md: OK')"

credits_none="$(ab_make_project CreditsNone)"
/bin/rm -f "$credits_none/Contents/Resources/Credits.md"
check "no Credits.md is an error" "1" "$(ab_call_rc lib.build.sh validate_project "$credits_none")"
check "named as missing" "1" \
    "$(ab_call_log lib.build.sh validate_project "$credits_none" | /usr/bin/grep -c 'Credits.md: MISSING$')"

credits_rtf="$(ab_make_project CreditsRTF)"
/bin/mv "$credits_rtf/Contents/Resources/Credits.md" "$credits_rtf/Contents/Resources/Credits.rtf"
check "Credits.rtf alone is an error" "1" "$(ab_call_rc lib.build.sh validate_project "$credits_rtf")"
rtf_log="$(ab_call_log lib.build.sh validate_project "$credits_rtf")"
check "that says the RTF is no longer shown" "1" \
    "$(printf '%s\n' "$rtf_log" | /usr/bin/grep -c 'Credits.md: MISSING (Credits.rtf is no longer shown)')"
check "and how to convert it" "1" \
    "$(printf '%s\n' "$rtf_log" | /usr/bin/grep -c 'Convert Credits.rtf to Markdown')"

credits_both="$(ab_make_project CreditsBoth)"
printf '{\\rtf1 old}' > "$credits_both/Contents/Resources/Credits.rtf"
check "a leftover Credits.rtf beside Credits.md still builds" "0" \
    "$(ab_call_rc lib.build.sh validate_project "$credits_both")"
check "with a warning to delete it" "1" \
    "$(ab_call_log lib.build.sh validate_project "$credits_both" | /usr/bin/grep -c 'Credits.rtf: warning (not shown)')"

omctest_end
