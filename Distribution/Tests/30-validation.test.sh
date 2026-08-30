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
    "$(ab_call_out $VALIDATE SCRIPT_VALIDATE_OUTPUT validate_script_file "$bashism" | /usr/bin/grep -c 'OMC runs .sh files with /bin/sh')"

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

section "14. the manifest editor's operations, called directly"
# plist_edit.py holds the rules for what a new command looks like. Its op_*
# functions take a dict and mutate it with no I/O, so they can be called
# straight rather than only through a whole handler.

check "set_keys writes the pair it is given" "Renamed" \
    "$(ab_py plist_edit 'op_set_keys(d, args) or d["CFBundleName"]' CFBundleName Renamed)"
check "and takes several pairs at once" "1.0" \
    "$(ab_py plist_edit 'op_set_keys(d, args) or d["CFBundleVersion"]' \
        CFBundleName Renamed CFBundleVersion 1.0)"

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

omctest_end
