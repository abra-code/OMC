#!/bin/sh
# Tests/40-build-hygiene.test.sh - what the build refuses to ship.
#
# clean_build_junk is the last thing between a developer's working tree and a
# signed, notarized artifact. Everything it sweeps is something that would
# otherwise be sealed into the code signature: __pycache__ from running a bundled
# verifier, .DS_Store from opening the bundle in Finder, an editor's config
# directory. The rule this file pins down is that it is LOUD - the sweep says
# what it removed and what it could not, and it never quietly deletes anything a
# developer would miss.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

BUILD=lib.build.sh

# clean_build_junk is a build phase, so it reports through ab_log / ab_report
# rather than to the window. ab_call_log runs it with the stderr defaults in
# place and hands back the transcript.
sweep() { ab_call_log $BUILD clean_build_junk "$1"; }

section "1. a bundle with nothing wrong in it is swept in silence"
# The positive control for every section below: if the sweep printed a header
# unconditionally, "it reported __pycache__" would prove nothing.

pristine="$(ab_make_project Pristine)"
check "no sweep was announced"    "0"  "$(sweep "$pristine" | /usr/bin/grep -c 'Removing development junk')"
check "and it succeeded"          "0"  "$(ab_call_rc $BUILD clean_build_junk "$pristine")"

section "2. __pycache__ is removed, and said so by name"
# Running the bundled command_verifier or actionui_verifier leaves these behind
# inside the bundle. They are regenerable, so they are swept - but reported, so
# that a developer sees the bundle is being written into rather than silently
# cleaned up after on every build.

dirty="$(ab_make_project Dirty)"
/bin/mkdir -p "$dirty/Contents/Resources/Scripts/__pycache__"
printf 'x' > "$dirty/Contents/Resources/Scripts/__pycache__/mod.cpython-314.pyc"
check "the fixture really has one" "yes" \
    "$([ -d "$dirty/Contents/Resources/Scripts/__pycache__" ] && echo yes || echo no)"

log="$(sweep "$dirty")"
check "the sweep announced itself"     "1"  "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Removing development junk')"
check "and named __pycache__"          "1"  "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Removed 1 __pycache__ director')"
check_absent "the directory is gone"   "$dirty/Contents/Resources/Scripts/__pycache__"

section "3. loose .pyc and .DS_Store go the same way"

/bin/mkdir -p "$dirty/Contents/Resources/Scripts"
printf 'x' > "$dirty/Contents/Resources/Scripts/stale.pyc"
printf 'x' > "$dirty/Contents/Resources/.DS_Store"
log="$(sweep "$dirty")"
check "the .pyc was reported"    "1"  "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Removed 1 \*\.pyc file')"
check "the .DS_Store was reported" "1" "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Removed 1 \.DS_Store file')"
check_absent "the .pyc is gone"       "$dirty/Contents/Resources/Scripts/stale.pyc"
check_absent "the .DS_Store is gone"  "$dirty/Contents/Resources/.DS_Store"

section "3b. the file sweep is case-insensitive, as a shared volume needs"
# clean_build_junk matches files with -iname on purpose: a Thumbs.db arriving
# over SMB from a case-insensitive volume is as often lowercase. Changing those
# three -iname to -name is invisible to a test that only ever uses the canonical
# spelling.

printf 'x' > "$dirty/Contents/Resources/thumbs.db"
printf 'x' > "$dirty/Contents/Resources/Scripts/STALE.PYC"
log="$(sweep "$dirty")"
check "a lowercase thumbs.db was swept" "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Removed 1 Thumbs.db file')"
check_absent "and is gone"        "$dirty/Contents/Resources/thumbs.db"
check_absent "as is an uppercase .PYC" "$dirty/Contents/Resources/Scripts/STALE.PYC"

section "4. a config directory is named individually, not folded into a count"
# Deleting one of these costs a developer their own settings, and rm does not use
# the Trash. A bare "removed 1 directory" would not tell them what they lost.

/bin/mkdir -p "$dirty/Contents/Resources/.claude"
printf 'x' > "$dirty/Contents/Resources/.claude/settings.json"
log="$(sweep "$dirty")"
check "the exact path was printed" "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Contents/Resources/.claude')"
check_absent "and it was removed"  "$dirty/Contents/Resources/.claude"

section "5. a repository inside the bundle is reported and left alone"
# The one thing the sweep must not delete. Losing an applet's history to a
# routine build is not a call this function gets to make.

/bin/mkdir -p "$dirty/Contents/Resources/.git/objects"
printf 'ref: refs/heads/master\n' > "$dirty/Contents/Resources/.git/HEAD"
log="$(sweep "$dirty")"
check "the developer was warned"   "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'WARNING: .git left in place')"
check "the warning says it will be signed in" "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'sealed into the signed copy')"
check_exists "and the repository survived"  "$dirty/Contents/Resources/.git"
check_exists "with its contents intact"     "$dirty/Contents/Resources/.git/HEAD"
check "reporting it is not a failure" "0" "$(ab_call_rc $BUILD clean_build_junk "$dirty")"

section "6. junk that cannot be swept is escalated, not glossed over"
# A read-only parent directory is the reachable stand-in for the real case, a
# root-owned dropping. The point is that the sweep notices it failed.

stuck_app="$(ab_make_project Stuck)"
holder="$stuck_app/Contents/Resources/locked"
/bin/mkdir -p "$holder/__pycache__"
/bin/chmod 555 "$holder"

log="$(sweep "$stuck_app")"
check "the survivor was counted"  "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'junk item(s) survived and will be signed into the applet')"
check "it says how many of how many" "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'WARNING: __pycache__: 1 of 1 could not be removed')"
# Without --warnings-as-errors the build continues; with it, this stops the build
# rather than signing the junk in.
check "on its own the build continues" "0" \
    "$(AB_WARNINGS_AS_ERRORS=0 ab_call_rc $BUILD clean_build_junk "$stuck_app")"
check "with warnings-as-errors it halts" "1" \
    "$(AB_WARNINGS_AS_ERRORS=1 ab_call_rc $BUILD clean_build_junk "$stuck_app")"
/bin/chmod 755 "$holder"
check "and once it can be removed, it is" "0" \
    "$(AB_WARNINGS_AS_ERRORS=1 ab_call_rc $BUILD clean_build_junk "$stuck_app")"
check_absent "with the junk actually gone" "$holder/__pycache__"

section "7. a symlink wearing a junk name is swept, and its target is not"
# find -type d walks straight past a symlink, but the code signature seals it
# just the same. rm -rf on a link removes the link only, which is what makes
# sweeping it safe.

link_app="$(ab_make_project Linked)"
real_dir="$OMCTEST_WORK/precious"
/bin/mkdir -p "$real_dir"
printf 'do not delete me\n' > "$real_dir/keep.txt"
/bin/ln -s "$real_dir" "$link_app/Contents/Resources/__pycache__"
check "the fixture link is in place" "yes" \
    "$([ -L "$link_app/Contents/Resources/__pycache__" ] && echo yes || echo no)"

sweep "$link_app" >/dev/null
check "the link was removed" "no" \
    "$([ -L "$link_app/Contents/Resources/__pycache__" ] && echo yes || echo no)"
check_exists "but what it pointed at survived" "$real_dir/keep.txt"
check "with its contents untouched" "do not delete me" "$(/bin/cat "$real_dir/keep.txt")"

section "8. profiling droppings are a validation warning, not a silent sweep"
# A .profraw is evidence that an instrumented binary ran with its CWD inside the
# bundle. Deleting it would hide the cause, so validation names it instead.

prof="$(ab_make_project Profiled)"
ab_add_executable "$prof"
printf 'x' > "$prof/Contents/Resources/default.profraw"
log="$(ab_call_log $BUILD validate_project "$prof")"
# Two lines, deliberately: a one-line verdict in the running log, and a detailed
# block naming the files. Asserting a total of 2 would break the day either is
# reworded; asserting each says what each is for.
check "the log carries the verdict"  "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'Profiling droppings: warning')"
check "and the report explains the cause" "1" \
    "$(printf '%s\n' "$log" | /usr/bin/grep -c 'an instrumented binary is being run with CWD inside the bundle')"
check "and names the file"     "1"  "$(printf '%s\n' "$log" | /usr/bin/grep -c 'default.profraw')"
check "as a warning, so validation still passes" "0" \
    "$(ab_call_rc $BUILD validate_project "$prof")"
check_exists "and the file was NOT deleted behind the developer's back" \
    "$prof/Contents/Resources/default.profraw"
check "but warnings-as-errors makes it stop the build" "1" \
    "$(AB_WARNINGS_AS_ERRORS=1 ab_call_rc $BUILD validate_project "$prof")"

omctest_end
