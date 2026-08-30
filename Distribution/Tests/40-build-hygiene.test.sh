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

section "9. running a bundled verifier does not scribble __pycache__ into the app"
# clean_build_junk above is the last line of defense; this is the first. Python
# writes bytecode next to every module it imports, so a single `appletbuilder
# validate` from a terminal used to leave 14 __pycache__ directories inside
# AppletBuilder.app: two in the bundled verifiers and twelve in the embedded
# interpreter's own stdlib. Opening Help adds four more, in mistune. Each one
# breaks a signed bundle's seal, and only the two verifier directories are even
# visible to git - everything under Contents/Library/Python is ignored wholesale
# as a vendored tree, as is Contents/Library/mistune. The GUI was never exposed:
# the engine sets a prefix for any applet that bundles its own Python. The agent
# CLI, which runs with no engine under it, was.
#
# Two premises hold this section up, and both are asserted rather than assumed.
# The harness exports its own PYTHONPYCACHEPREFIX - into the scratch,
# deliberately, so no test can dirty the bundle under test - so every check
# strips it from the child, or the applet is never the thing being asked. And
# the interpreter has to be willing to write bytecode at all: under
# PYTHONDONTWRITEBYTECODE every "nothing landed in the bundle" below is true
# for the wrong reason, and the section reports a clean 12 for a fix that has
# been deleted.

ab_pyc_dirs() {
    /usr/bin/find "$OMC_APP_BUNDLE_PATH/Contents/Library" -type d -name __pycache__ 2>/dev/null \
        | /usr/bin/wc -l | /usr/bin/tr -d ' '
}

# First, before anything in this section has run an interpreter, and
# deliberately loud. Python skips writing a .pyc that is already there and
# current, so pre-existing junk would make every check below pass without
# anything being redirected. Red here means the bundle you are testing is
# already dirty - sweep it, and find out what put it there.
check "the bundle holds no cached bytecode before we start" "0" "$(ab_pyc_dirs)"

# ...and the bundle has to be somewhere bytecode COULD land. "Nothing appeared"
# is free against a root-owned copy in /Applications or a read-only volume.
pyc_probe_file="$OMC_APP_BUNDLE_PATH/Contents/Library/.omctest_write_probe"
: > "$pyc_probe_file" 2>/dev/null
check "and Contents/Library is writable, so an absence means something" "yes" \
    "$([ -f "$pyc_probe_file" ] && echo yes || echo no)"
/bin/rm -f "$pyc_probe_file"

# Inherited from the harness, so it is the environment every check below runs
# in. Asserted rather than stripped: if bytecode writing were disabled globally
# the right answer is to say so, not to paper over it in one subshell and leave
# the rest of the section reporting green.
check "bytecode writing is not disabled in this environment" "" \
    "$PYTHONDONTWRITEBYTECODE"

# The positive control, in two halves, because both are premises: this
# interpreter does write bytecode, and PYTHONPYCACHEPREFIX is what moves it.
# Note the control SETS a prefix rather than clearing one - running the bundled
# interpreter unredirected is the very thing this section exists to prevent, and
# it caches its own stdlib on startup, so a control that cleared the prefix
# would dirty the bundle it is about to measure.
ab_python="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
probe_pkg="$OMCTEST_WORK/pycprobe"
probe_cache="$OMCTEST_WORK/pycprobe_cache"
/bin/mkdir -p "$probe_pkg"
: > "$probe_pkg/__init__.py"
printf 'VALUE = 1\n' > "$probe_pkg/probe.py"
( PYTHONPYCACHEPREFIX="$probe_cache"
  export PYTHONPYCACHEPREFIX
  "$ab_python" -c 'import sys; sys.path.insert(0, sys.argv[1]); import pycprobe.probe' \
      "$OMCTEST_WORK" ) >/dev/null 2>&1
# probe.*.pyc, not *.pyc: `python -c` caches ~38 stdlib modules into the same
# prefix on startup, so a bare *.pyc would report success for an import that
# never happened.
check "this interpreter does cache bytecode" "1" \
    "$([ -n "$(/usr/bin/find "$probe_cache" -name 'probe.*.pyc' 2>/dev/null | /usr/bin/head -1)" ] && echo 1 || echo 0)"
check "and a prefix is what moves it off the module" "0" \
    "$(/usr/bin/find "$probe_pkg" -type d -name __pycache__ | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

pyc_proj="$(ab_make_project Pyc)"
cmd_out="$( unset PYTHONPYCACHEPREFIX
            ab_call_out lib.validate.sh COMMAND_VALIDATE_OUTPUT validate_command_file "$pyc_proj" )"
check "the command verifier really ran" "1" \
    "$(printf '%s\n' "$cmd_out" | /usr/bin/grep -c 'All files valid')"
check "and importing it left nothing in the bundle" "0" "$(ab_pyc_dirs)"

ui_out="$( unset PYTHONPYCACHEPREFIX
           ab_call_out lib.validate.sh ACTIONUI_VALIDATE_OUTPUT validate_actionui_file \
               "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/Settings.json" )"
check "the ActionUI verifier really ran" "1" \
    "$(printf '%s\n' "$ui_out" | /usr/bin/grep -c '\[OK\].*Settings\.json')"
check "and it left nothing either" "0" "$(ab_pyc_dirs)"

# The third importer, and the only one reaching a package with subpackages:
# mistune contributes four directories of its own, none of them tracked.
#
# TMPDIR is redirected into the scratch for this one, which moves HELP_HTML_DIR
# with it. ensure_help_docs_converted is a staleness gate over that directory,
# and the real one at $TMPDIR/appletbuilder_help outlives a suite run - against
# it the function would find the HTML current, start no interpreter at all, and
# the check below would still see the file and report a conversion that never
# happened. A fresh directory forces the conversion every run.
pyc_help_tmp="$OMCTEST_WORK/help_tmp"
/bin/mkdir -p "$pyc_help_tmp"
( unset PYTHONPYCACHEPREFIX
  TMPDIR="$pyc_help_tmp"
  export TMPDIR
  ab_call lib.help.sh ensure_help_docs_converted ) >/dev/null 2>&1
check "the help converter really ran" "1" \
    "$([ -f "$pyc_help_tmp/appletbuilder_help/appletbuilder_user_guide.html" ] && echo 1 || echo 0)"
check "and mistune cached itself elsewhere" "0" "$(ab_pyc_dirs)"

# The seam itself, so a future edit cannot quietly move the cache back inside
# the bundle or stomp the prefix its caller chose.
#
# The expected value is spelled out rather than tested for a property. The
# harness prefix is non-empty and outside the bundle too, so "is set" and
# "points outside the bundle" would both stay green the day the unset below
# stops reaching the child - which is the one failure that would silently
# hollow out every check above.
pyc_default="$( unset PYTHONPYCACHEPREFIX; ab_call_out lib.common.sh PYTHONPYCACHEPREFIX : )"
check "lib.common.sh sets its own prefix when none is inherited" \
    "${TMPDIR:-/tmp}/appletbuilder_pyc" "$pyc_default"

# With no $TMPDIR either - cron, `env -i`, `sudo` without -E. What lands in this
# directory is executable bytecode that CPython will load back after validating
# nothing but the source's mtime and size, so the fallback must not be a
# predictable path under a world-writable parent.
pyc_no_tmp="$( unset PYTHONPYCACHEPREFIX TMPDIR; ab_call_out lib.common.sh PYTHONPYCACHEPREFIX : )"
check "and falls back into the user's own home, never /tmp" \
    "$OMCTEST_HOME/Library/Caches/com.abracode.applet-builder/appletbuilder_pyc" \
    "$pyc_no_tmp"

# omctest's own isolation rests on this: the harness sets the prefix before it
# runs a handler, and lib.common.sh must not overrule it.
check "an inherited prefix is left exactly alone" "/harness/scratch/pyc" \
    "$( PYTHONPYCACHEPREFIX=/harness/scratch/pyc; export PYTHONPYCACHEPREFIX
        ab_call_out lib.common.sh PYTHONPYCACHEPREFIX : )"

# If a check above went red the bundle now holds real junk. Removing it is not
# suppression - the red check is the loud part - but leaving it would poison
# the precondition of every later run, and a stale cache Python then declines
# to rewrite would turn this whole section permanently, silently green.
/usr/bin/find "$OMC_APP_BUNDLE_PATH/Contents/Library" -type d -name __pycache__ -prune \
    -exec /bin/rm -rf {} + 2>/dev/null

omctest_end
