#!/bin/sh
# Tests/50-thin-python.test.sh - the Python thinning phase, from the arguments up.
#
# applet_thin_python is the code behind the Build & Run pane's Execute button
# and `appletbuilder thin-python`. What it actually does is decide: whether this
# applet can be thinned at all, which plan an apply should use, whether to ask
# first, and what the front end is called with. The analysis underneath is
# Python-Embedding's and is tested there; running it here would cost minutes and
# a whole applet with a working interpreter per case.
#
# So the front end is named through AB_THIN_PYTHON_TOOL and pointed at
# helpers/thin_recorder.py, which appends its argv and honors the one part of
# the real contract this phase leans on - a successful `plan` leaves a plan file.
# Every check below is about a decision the applet makes, which is the half that
# can regress here.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

BUILD=lib.build.sh

# ── The seam ──────────────────────────────────────────────────────────────────
#
# Exported, because ab_call runs the library in a child shell: an unexported
# variable would leave the phase pointed at the real front end, and a "plan" case
# would then quietly start cloning an 80 MB bundle.

AB_THIN_PYTHON_TOOL="$OMCTEST_TESTS/helpers/thin_recorder.py"
THIN_RECORD="$OMCTEST_WORK/thin-args.txt"
export AB_THIN_PYTHON_TOOL THIN_RECORD

[ -f "$AB_THIN_PYTHON_TOOL" ] || { printf '50-thin-python: no recorder at %s\n' "$AB_THIN_PYTHON_TOOL" >&2; exit 1; }

# Each case reads the argv of ITS run, so the record starts empty every time.
record_reset() {
    /bin/rm -f "$THIN_RECORD"
    THIN_RECORD_RC=0
    export THIN_RECORD_RC
}

record_count() {
    if [ ! -f "$THIN_RECORD" ]; then
        printf '0'
        return
    fi
    /usr/bin/grep -c '' < "$THIN_RECORD" | /usr/bin/tr -d ' '
}

# One recorded invocation, tab-separated, 1-based.
record_line() { # <n>
    if [ ! -f "$THIN_RECORD" ]; then
        return
    fi
    /usr/bin/sed -n "${1}p" "$THIN_RECORD"
}

# Does any recorded invocation carry this argument? Printed as yes/no so a check
# reads as a value rather than as an exit status. grep runs on its own line and
# its status is tested afterwards - the applet's own rule, and this file is not
# exempt from it.
record_has() { # <argument>
    if [ ! -f "$THIN_RECORD" ]; then
        printf 'no'
        return
    fi
    _rh_hits=$(/usr/bin/grep -cF "	$1" "$THIN_RECORD")
    if [ "${_rh_hits:-0}" -gt 0 ]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# An option AND the value next to it. "the last field" passes only for as long
# as nobody appends another option after this one, which is a property of the
# assembly order rather than of what is being asserted.
record_has_pair() { # <option> <value>
    if [ ! -f "$THIN_RECORD" ]; then
        printf 'no'
        return
    fi
    _rp_hits=$(/usr/bin/grep -cF "	$1	$2" "$THIN_RECORD")
    if [ "${_rp_hits:-0}" -gt 0 ]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# Is this an absolute path? A helper rather than an inline `case`, because a
# case pattern's ")" inside a $( ) substitution ends the substitution instead of
# the pattern - the check read as a literal fragment of its own source and
# failed with it in the actual column.
is_absolute() { # <path>
    case "$1" in
        /*) printf 'yes' ;;
        *)  printf 'no' ;;
    esac
}

# $OMCTEST_WORK as the applet resolves it. $TMPDIR lives under /var, which is a
# symlink to /private/var, so an expectation built from the logical path fails
# against code that (correctly) resolves the physical one.
work_real=$(CDPATH= cd -P -- "$OMCTEST_WORK" && pwd -P)

# An applet the guard will accept. The phase only asks whether the bundle has an
# executable Contents/Library/Python/bin/python3 - installing a real 60 MB
# interpreter per fixture would make this file take minutes to prove nothing more.
add_fake_python() { # <app>
    /bin/mkdir -p "$1/Contents/Library/Python/bin"
    /bin/cp /bin/echo "$1/Contents/Library/Python/bin/python3"
}

plan_beside() { # <app> -> the default plan path, built the way the applet builds it
    ab_call $BUILD applet_plan_path "$1"
}

# Does this path exist? Printed as yes/no: `check` compares values, and a bare
# test would report an exit status nobody can read in the transcript.
test_file_exists() { # <path>
    if [ -e "$1" ]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# The phase, with the transcript on stdout and the status kept separately - both
# matter in most sections and running it twice would double the recorded argv.
thin() { # <app>
    THIN_LOG=$(ab_call_log $BUILD applet_thin_python "$1")
    THIN_RC=$?
}

# ──────────────────────────────────────────────────────────────────────────────

section "1. an applet with no embedded Python is refused, by reason"
# The one guard that has to name what is wrong: "no such file" naming a path
# three directories deep inside the bundle tells a developer nothing about the
# fact that this applet was simply never given an interpreter.

record_reset
bare="$(ab_make_project NoPython)"
AB_THIN_PYTHON_ACTION=plan; export AB_THIN_PYTHON_ACTION
thin "$bare"

check "it failed"                    "1"   "$THIN_RC"
check "and said the applet has none" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'does not bundle its own Python')"
check "the front end was never run"  "0"   "$(record_count)"

section "2. plan names the verb, the applet and the plan beside the bundle"
# The positive control for section 1, and the shape every later case varies.

record_reset
planner="$(ab_make_project Planner)"
add_fake_python "$planner"
AB_THIN_ARCH=none; export AB_THIN_ARCH
thin "$planner"

expected_plan="$(plan_beside "$planner")"
check "it succeeded"        "0" "$THIN_RC"
check "one invocation"      "1" "$(record_count)"
check "with the plan verb, the applet and the default plan path" \
    "$(printf 'plan\t%s\t--plan\t%s' "$planner" "$expected_plan")" \
    "$(record_line 1)"
check "the plan is named after the applet" "Planner.thinning-plan.json" \
    "$(/usr/bin/basename "$expected_plan")"
check "and sits beside it" "$work_real" "$(/usr/bin/dirname "$expected_plan")"
# Absolute, and it matters beyond tidiness: this path is recorded for the
# fallback in section 11, and a relative one would later be resolved against
# whatever directory the applying run happened to start in - which is a plan for
# a different applet as easily as this one.
check "as an absolute path" "yes" "$(is_absolute "$expected_plan")"
check_exists "and the plan really landed there" "$expected_plan"
check "the front end's own output reached the log" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'thin_recorder: plan')"

section "2b. a relative applet path still yields an absolute plan path"
# `cd MyDir && appletbuilder thin-python plan MyApp.app` is the natural CLI
# invocation, and dirname of that is ".". Recorded that way, the path is correct
# for that run and wrong forever after: a later apply resolves it against ITS
# working directory, where a plan for an entirely different applet of the same
# name may well be sitting. That was reproduced, not theorized.

rel_plan=$(CDPATH= cd -P -- "$OMCTEST_WORK" && ab_call $BUILD applet_plan_path "Planner.app")
check "the plan path is absolute"  "yes" "$(is_absolute "$rel_plan")"
check "and names the applet's real directory" \
    "$work_real/Planner.thinning-plan.json" "$rel_plan"

rel_keep=$(CDPATH= cd -P -- "$OMCTEST_WORK" && ab_call $BUILD applet_keep_file "Planner.app")
check "the keep file is absolute too" "yes" "$(is_absolute "$rel_keep")"

section "2c. an exported CDPATH cannot redirect any of that"
# `cd` searches $CDPATH for any operand that does not begin with /, ./ or ../,
# so a bare `cd -P "$dir"` resolves "sub/MyApp.app" against the trap instead of
# against the working directory - and that path is then written to, remembered,
# and later applied from. The self-guard resolves paths the same way, and an
# exported CDPATH made it compare two different bundles and wave the applet
# through. Both were reproduced against the first version of these fixes.

/bin/mkdir -p "$OMCTEST_WORK/cdtrap/sub" "$OMCTEST_WORK/sub"
cd_plan=$( export CDPATH="$OMCTEST_WORK/cdtrap"
           # The trap is for the code under test. This cd is the harness's own, and
           # it takes the same precaution the rule asks for - a CDPATH-resolved cd
           # also PRINTS the directory it landed in, which here would land inside
           # the capture and corrupt the value being checked.
           CDPATH= cd -P -- "$OMCTEST_WORK" || exit
           ab_call $BUILD applet_plan_path "sub/Planner.app" )
check "the plan path ignores CDPATH" "$work_real/sub/Planner.thinning-plan.json" "$cd_plan"

# The same trap aimed at the self-guard: a directory on CDPATH holding something
# called AppletBuilder.app, and a relative operand for cd to resolve.
/bin/mkdir -p "$OMCTEST_WORK/cdtrap/AppletBuilder.app"
record_reset
AB_THIN_PYTHON_ACTION=apply
self_log=$( export CDPATH="$OMCTEST_WORK/cdtrap"
            CDPATH= cd -P -- "$(/usr/bin/dirname "$OMC_APP_BUNDLE_PATH")" || exit
            ab_call_log $BUILD applet_thin_python "$(/usr/bin/basename "$OMC_APP_BUNDLE_PATH")" )
check "the self-guard still recognizes AppletBuilder under CDPATH" "1" \
    "$(printf '%s\n' "$self_log" | /usr/bin/grep -c 'This is AppletBuilder itself')"
check "and nothing ran"  "0" "$(record_count)"
AB_THIN_PYTHON_ACTION=plan

section "3. the pane's architecture choice is carried into the plan"
# An applet sliced to one architecture with a universal interpreter inside it is
# half a job, and the arch has to be recorded IN the plan or a re-apply after a
# Python reinstall would silently stop slicing.

record_reset
AB_THIN_ARCH=arm64
thin "$planner"
check "--arch is passed with the pane's value" "yes" "$(record_has_pair "--arch" "arm64")"

record_reset
AB_THIN_ARCH=none
thin "$planner"
check "and \"None\" passes no --arch at all" "no" "$(record_has "--arch")"

record_reset
AB_THIN_ARCH=""
thin "$planner"
check "nor does an empty picker value" "no" "$(record_has "--arch")"
AB_THIN_ARCH=none

section "4. a keep file beside the bundle is picked up, and only when it exists"
# The escape hatch for a module no analysis can discover. Passing --keep-file for
# a file that is not there would fail the run outright, so the existence test is
# the whole feature.

record_reset
thin "$planner"
check "no keep file, no --keep-file" "no" "$(record_has "--keep-file")"

keep_file="$OMCTEST_WORK/Planner.thinning-keep.txt"
printf 'ssl\nsqlite3\n' > "$keep_file"
record_reset
thin "$planner"
check "the keep file is passed, by its path" "yes" \
    "$(record_has_pair "--keep-file" "$work_real/Planner.thinning-keep.txt")"
check "and the log says it is in use" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Planner.thinning-keep.txt')"
/bin/rm -f "$keep_file"

section "5. an apply with no plan anywhere is refused, and says where it looked"
# Its own applet: the remembered fallback is keyed by applet identity, and
# Planner has one
# recorded from section 2, which is exactly what this case must not find.

record_reset
orphan="$(ab_make_project Orphan)"
add_fake_python "$orphan"
AB_THIN_PYTHON_ACTION=apply
AB_ASSUME_YES=1; export AB_ASSUME_YES
thin "$orphan"

check "it failed"                     "1" "$THIN_RC"
check "naming the applet"             "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'No thinning plan for Orphan')"
check "and the path it looked at"     "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Orphan.thinning-plan.json')"
check "nothing was run"               "0" "$(record_count)"

section "6. an apply uses the plan beside the bundle"

record_reset
orphan_plan="$(plan_beside "$orphan")"
printf '{"remove":{"modules":[]}}\n' > "$orphan_plan"
thin "$orphan"

check "it succeeded"   "0" "$THIN_RC"
check "with the apply verb and that plan" \
    "$(printf 'apply\t%s\t--plan\t%s' "$orphan" "$orphan_plan")" \
    "$(record_line 1)"
check "and no --dry-run"     "no" "$(record_has "--dry-run")"
check "and no --skip-verify" "no" "$(record_has "--skip-verify")"

section "6b. an explicit plan is used, and a missing one is named as such"
# The --plan route. Its error has to be distinguishable from "no plan anywhere":
# a caller who named a file wants to know that file was not found, not to be told
# where the default would have been.

record_reset
elsewhere="$OMCTEST_WORK/elsewhere"
/bin/mkdir -p "$elsewhere"
explicit_plan="$elsewhere/hand-written.json"
printf '{"remove":{"modules":[]}}\n' > "$explicit_plan"
AB_THIN_PLAN="$explicit_plan"; export AB_THIN_PLAN
thin "$orphan"

check "the named plan is used, not the one beside the bundle" "yes" \
    "$(record_has_pair "--plan" "$explicit_plan")"
check "and it succeeded" "0" "$THIN_RC"

record_reset
AB_THIN_PLAN="$elsewhere/not-there.json"
thin "$orphan"
check "a missing named plan fails"        "1" "$THIN_RC"
check "naming the file that was not found" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Thinning plan not found: .*not-there.json')"
check "and nothing ran"                   "0" "$(record_count)"
AB_THIN_PLAN=""

section "6c. a plan whose Packages section names another bundle is refused"
# The one way an apply can delete outside the applet it was given. A plan records
# packages.dir as an absolute path into the bundle it was planned against, and
# the applier resolves packages.remove against THAT path - so a plan carried to a
# copy, which is exactly what the remembered fallback encourages, would back up
# and delete out of the original.

record_reset
foreign="$(ab_make_project Foreign)"
foreign_pkgs="$foreign/Contents/Library/Packages"
/bin/mkdir -p "$foreign_pkgs"
/bin/cat > "$(plan_beside "$orphan")" <<PLAN
{"remove": {"modules": []},
 "packages": {"dir": "$foreign_pkgs", "remove": ["victim"]}}
PLAN
thin "$orphan"

check "it is refused"                    "1" "$THIN_RC"
check "naming the other bundle's directory" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Foreign.app/Contents/Library/Packages')"
check "and nothing ran"                  "0" "$(record_count)"

# The positive control, and the common case: packages is an AUDIT with an empty
# remove list, so a directory elsewhere deletes nothing and must not block a run.
record_reset
/bin/cat > "$(plan_beside "$orphan")" <<PLAN
{"remove": {"modules": []},
 "packages": {"dir": "$foreign_pkgs", "remove": []}}
PLAN
thin "$orphan"

check "an empty packages.remove is not blocked" "1" "$(record_count)"
check "though the log says where the audit points" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Packages audit refers to')"

# The control that keeps the classifier honest. Without it, a check that only
# ever asserts the refusal is equally satisfied by a guard that refuses
# everything - which would break every legitimate packages removal there is.
record_reset
own_pkgs="$orphan/Contents/Library/Packages"
/bin/mkdir -p "$own_pkgs"
/bin/cat > "$(plan_beside "$orphan")" <<PLAN
{"remove": {"modules": []},
 "packages": {"dir": "$own_pkgs", "remove": ["victim"]}}
PLAN
thin "$orphan"

check "the applet's OWN Packages are removable" "1" "$(record_count)"
check "and the run succeeded"                   "0" "$THIN_RC"

section "6d. a Packages check that cannot answer refuses, it does not wave through"
# The guard used to test for the literal string "outside" and let everything
# else past - so an answer it could not parse read as permission. A newline
# inside packages.dir is the reachable way to produce one.

record_reset
"$OMCTEST_PYTHON" - "$(plan_beside "$orphan")" "$foreign_pkgs" <<'MAKEPLAN'
import json, sys
json.dump({"remove": {"modules": []},
           "packages": {"dir": sys.argv[2] + "\nsecond line", "remove": ["victim"]}},
          open(sys.argv[1], "w"))
MAKEPLAN
thin "$orphan"

check "it is refused"      "1" "$THIN_RC"
check "saying it could not check" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Packages section could not be checked')"
check "and nothing ran"    "0" "$(record_count)"

printf '{"remove":{"modules":[]}}\n' > "$(plan_beside "$orphan")"

section "7. dry run and skip-verify reach the front end, and the log"

record_reset
AB_THIN_PYTHON_ACTION=apply-dry
thin "$orphan"
check "--dry-run is passed"          "yes" "$(record_has "--dry-run")"
check "and the log says nothing will be removed" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Dry run - nothing will be removed')"

record_reset
AB_THIN_PYTHON_ACTION=apply
AB_THIN_SKIP_VERIFY=1; export AB_THIN_SKIP_VERIFY
thin "$orphan"
check "--skip-verify is passed" "yes" "$(record_has "--skip-verify")"
# Disabling the verify removes the only thing that restores an over-thinned
# interpreter, so it may not pass silently.
check "and it is warned about"  "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'verification disabled')"
AB_THIN_SKIP_VERIFY=0

section "8. removing modules is confirmed first, and declining runs nothing"
# The confirmation is the only thing between a click on Execute and a rewritten
# interpreter, so both answers are pinned - the decline
# AND the positive control, or "nothing ran" would pass for a phase that had
# stopped for some entirely different reason.

record_reset
AB_ASSUME_YES=0
thin "$orphan"
check "declining is reported as declined, not as a failure" "2" "$THIN_RC"
check "the log says so"    "1" "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Thinning canceled')"
check "and nothing ran"    "0" "$(record_count)"

record_reset
AB_ASSUME_YES=1
thin "$orphan"
check "accepting runs the apply" "1" "$(record_count)"
check "and it succeeds"          "0" "$THIN_RC"

section "8b. a plan needs no confirmation - it modifies nothing"
# Confirming a preview trains people to confirm without reading, and planning
# cannot damage the applet: the front end analyzes a clone.

record_reset
AB_THIN_PYTHON_ACTION=plan
AB_ASSUME_YES=0
thin "$orphan"
check "the plan ran without asking" "1" "$(record_count)"
check "and succeeded"               "0" "$THIN_RC"
AB_ASSUME_YES=1

section "9. plan-and-apply runs both, in order, against the plan just written"

record_reset
AB_THIN_PYTHON_ACTION=plan-apply
combo="$(ab_make_project Combo)"
add_fake_python "$combo"
thin "$combo"

combo_plan="$(plan_beside "$combo")"
check "it succeeded"        "0" "$THIN_RC"
check "two invocations"     "2" "$(record_count)"
check "the plan came first" \
    "$(printf 'plan\t%s\t--plan\t%s' "$combo" "$combo_plan")" "$(record_line 1)"
check "then the apply, on that same plan" \
    "$(printf 'apply\t%s\t--plan\t%s' "$combo" "$combo_plan")" "$(record_line 2)"

section "9b. a failed plan stops before the apply"
# The case the ordering exists for. An apply after a failed plan would resolve
# some older file - or the remembered one from another applet copy - and remove
# whatever THAT named, which is the worst thing this phase could do.

record_reset
THIN_RECORD_RC=1
export THIN_RECORD_RC
stopper="$(ab_make_project Stopper)"
add_fake_python "$stopper"
thin "$stopper"

check "the run failed"           "1" "$THIN_RC"
check "only the plan was tried"  "1" "$(record_count)"
check "and it was the plan"      "plan" "$(record_line 1 | /usr/bin/awk -F'\t' '{print $1}')"
THIN_RECORD_RC=0

section "10. an unknown action is refused rather than guessed at"

record_reset
AB_THIN_PYTHON_ACTION=demolish
thin "$orphan"
check "it failed"         "1" "$THIN_RC"
check "naming the action" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'Unknown thinning action: demolish')"
check "and ran nothing"   "0" "$(record_count)"
AB_THIN_PYTHON_ACTION=plan

section "10b. AppletBuilder refuses to remove modules from itself"
# The thinning runs under AppletBuilder's own interpreter ($python3), so applying
# to this bundle would have the applier deleting modules out from under the
# process doing the deleting - and the verification hook then relaunches that
# same, now-thinned interpreter to import json, shlex and argparse.
#
# Only the refusal is exercised. Planning against this bundle is allowed, and
# running it here would write a plan file into the repository next to the app.

record_reset
AB_THIN_PYTHON_ACTION=apply
thin "$OMC_APP_BUNDLE_PATH"

check "it is refused"        "1" "$THIN_RC"
check "saying why"           "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'This is AppletBuilder itself')"
check "and nothing ran"      "0" "$(record_count)"
check "the standalone script is offered instead" "1" \
    "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'thin_applet_python.py apply')"

# A dry run removes nothing - thin_with_plan.sh returns before it copies the
# backup - so the guard does not refuse one: what AppletBuilder could shed is a
# fair question to ask of AppletBuilder. Both dry actions, because the guard is a
# case list and it used to name plan-apply-dry while letting apply-dry through -
# the same preview, refused or allowed depending on which box wrote the plan.
#
# The plan is named into the scratch directory. Left to the default, a plan run
# against this bundle would write one into the repository beside the app.
record_reset
self_plan="$OMCTEST_WORK/self-dry.json"
printf '{"remove":{"modules":[]}}\n' > "$self_plan"
AB_THIN_PLAN="$self_plan"; export AB_THIN_PLAN
AB_THIN_PYTHON_ACTION=apply-dry
thin "$OMC_APP_BUNDLE_PATH"

check "a dry run against itself is allowed" "0" "$THIN_RC"
check "and reaches the front end"           "1" "$(record_count)"
check "as a preview"                        "yes" "$(record_has "--dry-run")"

record_reset
AB_THIN_PYTHON_ACTION=plan-apply-dry
thin "$OMC_APP_BUNDLE_PATH"

check "so is planning and previewing in one go" "0" "$THIN_RC"
check "the plan runs first"                     "plan" \
    "$(record_line 1 | /usr/bin/awk -F'\t' '{print $1}')"
check "and the preview second"                  "apply" \
    "$(record_line 2 | /usr/bin/awk -F'\t' '{print $1}')"
check "removing nothing"                        "yes" "$(record_has "--dry-run")"
# The redirect above is load-bearing and silent when it breaks: without it the plan
# lands beside this bundle, which is inside the repository, and every check here
# still passes.
check "and no plan was left beside the applet" "no" \
    "$(test_file_exists "$(plan_beside "$OMC_APP_BUNDLE_PATH")")"
AB_THIN_PLAN=""; export AB_THIN_PLAN

section "11. the plan written for an applet is found again after it is copied"
# The release flow this fallback exists for: the plan is written and reviewed
# against the development copy, a distribution copy is made elsewhere, and that
# copy is what gets thinned. It has no plan beside it, and hand-carrying one is
# the step that gets forgotten.
#
# Guarded, because the record lives in a `defaults` domain and cfprefsd is
# unreachable from a sandboxed run - where `defaults write` exits 0 having
# written nothing, which would make every check below describe a phase that
# simply found no plan.

if ab_prefs_usable; then
    record_reset
    AB_THIN_PYTHON_ACTION=plan
    origin="$(ab_make_project Shipped)"
    add_fake_python "$origin"
    thin "$origin"
    origin_plan="$(plan_beside "$origin")"
    check_exists "the development copy has its plan" "$origin_plan"

    # The distribution copy: same applet, different directory, no plan beside it.
    /bin/mkdir -p "$OMCTEST_WORK/dist"
    /bin/cp -R "$origin" "$OMCTEST_WORK/dist/Shipped.app"
    release="$OMCTEST_WORK/dist/Shipped.app"
    check_absent "the release copy has none" "$(plan_beside "$release")"

    record_reset
    AB_THIN_PYTHON_ACTION=apply
    thin "$release"

    check "the apply ran"                  "1" "$(record_count)"
    check "against the plan from the development copy" \
        "$(printf 'apply\t%s\t--plan\t%s' "$release" "$origin_plan")" "$(record_line 1)"
    check "and the log says where that plan came from" "1" \
        "$(printf '%s\n' "$THIN_LOG" | /usr/bin/grep -c 'using the one last written for Shipped')"

    # Identity, not name. Somebody else's applet that happens to be called
    # Shipped has its own bundle identifier, and inheriting this plan would mean
    # removing modules chosen by an analysis of a different program.
    impostor="$(ab_make_project Impostor)"
    /bin/mkdir -p "$OMCTEST_WORK/impostor"
    /bin/mv "$impostor" "$OMCTEST_WORK/impostor/Shipped.app"
    impostor="$OMCTEST_WORK/impostor/Shipped.app"
    /usr/bin/plutil -replace CFBundleIdentifier -string "com.example.not-ours" \
        "$impostor/Contents/Info.plist" >/dev/null
    add_fake_python "$impostor"

    record_reset
    thin "$impostor"
    check "an unrelated applet of the same name inherits nothing" "0" "$(record_count)"
    check "and is refused for want of a plan"                     "1" "$THIN_RC"

    # The fallback is a convenience, not a license: a plan file that has since
    # been deleted must not be handed to the applier as a path that no longer
    # resolves.
    /bin/rm -f "$origin_plan"
    record_reset
    thin "$release"
    check "a remembered plan that has been deleted is not used" "0" "$(record_count)"
    check "the run is refused instead"                          "1" "$THIN_RC"
else
    ab_skip_section "11. remembered plan fallback (defaults is not writable here)"
fi

section "12. the button's handler reads the checkboxes and reports to the pane"
# Everything above tests the phase. This is the wiring the pane depends on: the
# checkboxes become the action, the transcript reaches the log control, the
# verdict row ends up green rather than spinning, and the buttons come back.

record_reset
unset AB_THIN_PYTHON_ACTION
ui_reset
buttoned="$(ab_make_project Buttoned)"
add_fake_python "$buttoned"
ab_open_project "$buttoned"
omc_control_defaults BuildRun
omc_run AppletBuilder.thin.python

check_status "the handler exited cleanly" 0
# The pane's own defaults - Write Thinning Plan ticked, Apply and Dry Run clear -
# are the safe action, and this is where that is pinned rather than in the JSON.
check "the pane's defaults mean a plan" "plan" \
    "$(record_line 1 | /usr/bin/awk -F'\t' '{print $1}')"
check "the verdict row is the plan's"   "Thinning plan written" "$(ui_value "$BUILD_STATUS_ID")"
check "the transcript reached the log"  "1" \
    "$(ui_value "$BUILD_LOG_ID" | /usr/bin/grep -c 'Thinning the embedded Python of Buttoned.app')"
# The row is the PANE's, and it is one row: a run holds the buttons until it has
# a verdict to show. Asserting the state the user meets - enabled - covers both
# the release and the cleanup trap.
check "the Execute button came back"     "1" "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"
check "and so did Build"                 "1" "$(ui_enabled "$BUILD_BUILD_BTN_ID")"

section "12b. the handler's alert is the confirmation, and Cancel is respected"
# The GUI's ab_confirm is an alert; the phase's contract is that a "no" runs
# nothing. Both answers, because "nothing ran" alone would pass for a handler
# that never got as far as asking.

record_reset
alerts_reset
omc_control "$BUILD_THIN_PLAN_ID" 0
omc_control "$BUILD_THIN_APPLY_ID" 1
printf '{"remove":{"modules":[]}}\n' > "$(plan_beside "$buttoned")"
alert_answer 1                      # Cancel
omc_run AppletBuilder.thin.python

# The app-modal alert, not an ActionUI one: it goes through the `alert` tool, so
# it is alerts.log that holds it, not the window's pending_alert.
check "exactly one alert was raised"      "1" "$(alerts_count)"
check "naming the applet it would strip"  "1" "$(alerts_mention 'Buttoned.app')"
# Which plan is what decides whether saying yes is safe, so it has to be in the
# alert rather than in the log the user reads afterwards.
check "and the plan it would apply"       "1" "$(alerts_mention 'Buttoned.thinning-plan.json')"
check "and where thinning normally happens" "1" "$(alerts_mention 'distribution copy')"
check "nothing was removed"               "0" "$(record_count)"
check "and the row says canceled"         "Thinning canceled" "$(ui_value "$BUILD_STATUS_ID")"

record_reset
alert_answer 0                      # Thin
omc_run AppletBuilder.thin.python
check "answering Thin runs the apply" "1" "$(record_count)"
check "and the row says so"           "Embedded Python thinned" "$(ui_value "$BUILD_STATUS_ID")"

section "12d. the three checkboxes are a product, and this is the table"
# Write Thinning Plan and Apply Plan are independent things the button can do, and
# Dry Run qualifies the second. Every combination has to land on the action it
# reads as, because the pane offers no other way to say it.

thin_boxes() { # <plan> <apply> <dry> -> the verb the handler chose
    record_reset
    omc_control "$BUILD_THIN_PLAN_ID"    "$1"
    omc_control "$BUILD_THIN_APPLY_ID"   "$2"
    omc_control "$BUILD_THIN_DRY_RUN_ID" "$3"
    alert_answer 0                        # any confirmation: yes
    omc_run AppletBuilder.thin.python
    record_line 1 | /usr/bin/awk -F'\t' '{print $1 (index($0, "--dry-run") ? " --dry-run" : "")}'
}

check "Write Thinning Plan alone"     "plan"                "$(thin_boxes 1 0 0)"
check "Apply alone"                   "apply"               "$(thin_boxes 0 1 0)"
check "Apply with Dry Run"            "apply --dry-run"     "$(thin_boxes 0 1 1)"
check "both boxes"                    "plan"                "$(thin_boxes 1 1 0 | /usr/bin/awk '{print $1}')"
check "and both means two runs"       "2"                   "$(record_count)"
check "the second of them applies"    "apply"               "$(record_line 2 | /usr/bin/awk -F'\t' '{print $1}')"
thin_boxes 1 1 1 >/dev/null
check "both boxes with Dry Run still plan first" "plan" \
    "$(record_line 1 | /usr/bin/awk -F'\t' '{print $1}')"
check "and preview instead of removing"          "yes" "$(record_has "--dry-run")"
alert_answers_reset

# Dry Run alone is not a state the pane can reach - the changed handler disables
# the box while Apply is clear - but the handler is what runs if it is somehow
# reached, and it must not quietly do something.
record_reset
omc_control "$BUILD_THIN_PLAN_ID"    0
omc_control "$BUILD_THIN_APPLY_ID"   0
omc_control "$BUILD_THIN_DRY_RUN_ID" 1
omc_run AppletBuilder.thin.python
check "neither box ticked runs nothing" "0" "$(record_count)"
check "and says what to tick"           "Choose Write Thinning Plan or Apply Plan" \
    "$(ui_value "$BUILD_STATUS_ID")"

section "12e. the checkboxes keep each other honest"
# The rules the pane enforces as you click, rather than after you have clicked
# the button: Dry Run has no meaning without a removal to preview, and the button
# has nothing to do with both boxes clear.

omc_control "$BUILD_THIN_PLAN_ID"  1
omc_control "$BUILD_THIN_APPLY_ID" 1
omc_run AppletBuilder.thin.python.changed
check "Apply ticked enables Dry Run" "1" "$(ui_enabled "$BUILD_THIN_DRY_RUN_ID")"
check "and the button is live"       "1" "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

omc_control "$BUILD_THIN_APPLY_ID" 0
omc_run AppletBuilder.thin.python.changed
check "clearing Apply disables Dry Run" "0" "$(ui_enabled "$BUILD_THIN_DRY_RUN_ID")"
# Cleared as well as disabled: a Dry Run left ticked underneath would come back
# the moment Apply was ticked again, turning a real run into a preview. The value
# is "false", not 0 - setElementValueFromString takes only "true"/"false" for a
# Bool view and warns past anything else, so a 0 here would clear nothing at all.
check "and clears it"                   "false" "$(ui_value "$BUILD_THIN_DRY_RUN_ID")"
check "Write Thinning Plan alone still arms the button" "1" \
    "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

omc_control "$BUILD_THIN_PLAN_ID" 0
omc_run AppletBuilder.thin.python.changed
check "with neither box, the button goes dead" "0" "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

section "12h. a run takes the checkboxes with it, and gives back only what they allow"
# Two holes from disabling the buttons alone. The checkboxes stayed live through
# a run, so ticking one mid-apply ran the changed handler, which re-armed Execute:
# a second thinning over the first, both writing the same .thinbak while the first
# applier is already deleting. And the release enabled Execute flat, so a build
# ended with a live button on a pane where the user had cleared both boxes.
#
# ab_actions_enabled is called directly. What it reads is the engine's
# dispatch-time export of the two boxes, which is exactly what a run cannot
# change - they are disabled for its duration - and which a handler run from here
# cannot vary either.

ui_reset
OMC_ACTIONUI_VIEW_412_VALUE=1                       # BUILD_THIN_PLAN_ID
OMC_ACTIONUI_VIEW_414_VALUE=1                       # BUILD_THIN_APPLY_ID
export OMC_ACTIONUI_VIEW_412_VALUE OMC_ACTIONUI_VIEW_414_VALUE
ab_call lib.common.sh ab_actions_enabled false

check "a run disables Write Thinning Plan" "0" "$(ui_enabled "$BUILD_THIN_PLAN_ID")"
check "and Apply Plan"                     "0" "$(ui_enabled "$BUILD_THIN_APPLY_ID")"
check "and Dry Run"                        "0" "$(ui_enabled "$BUILD_THIN_DRY_RUN_ID")"
check "and Execute"                        "0" "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

ui_reset
ab_call lib.common.sh ab_actions_enabled true
check "the end of a run gives the boxes back" "1" "$(ui_enabled "$BUILD_THIN_PLAN_ID")"
check "Dry Run comes back with Apply ticked"  "1" "$(ui_enabled "$BUILD_THIN_DRY_RUN_ID")"
check "and so does Execute"                   "1" "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

ui_reset
OMC_ACTIONUI_VIEW_414_VALUE=0
ab_call lib.common.sh ab_actions_enabled true
check "Apply clear leaves Dry Run off"        "0" "$(ui_enabled "$BUILD_THIN_DRY_RUN_ID")"
check "Write Thinning Plan alone keeps Execute live" "1" \
    "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"

ui_reset
OMC_ACTIONUI_VIEW_412_VALUE=0
ab_call lib.common.sh ab_actions_enabled true
check "with neither box, a build does not revive Execute" "0" \
    "$(ui_enabled "$BUILD_THIN_PYTHON_BTN_ID")"
# Only the thinning group's controls are conditional; the build's own buttons come
# back whatever the checkboxes say, or a run would end with a dead pane.
check "Build comes back regardless" "1" "$(ui_enabled "$BUILD_BUILD_BTN_ID")"

unset OMC_ACTIONUI_VIEW_412_VALUE OMC_ACTIONUI_VIEW_414_VALUE

section "12f. the group is disabled for an applet with no embedded Python"
# The user's first question about a grayed-out group is "why", so the answer is
# in the pane rather than in a log line after a click.

ui_reset
unequipped="$(ab_make_project Plain)"          # no interpreter
ab_open_project "$unequipped"
omc_run AppletBuilder.buildrun.loaded

check "the group is disabled"   "0"  "$(ui_enabled "$BUILD_THIN_GROUP_ID")"
check "and says why"            "This applet has no embedded Python." \
    "$(ui_value "$BUILD_THIN_NOTE_ID")"
check "the note is shown"       "1" "$(ui_visible "$BUILD_THIN_NOTE_ID")"

ui_reset
equipped="$(ab_make_project Equipped)"
add_fake_python "$equipped"
ab_open_project "$equipped"
omc_run AppletBuilder.buildrun.loaded

check "an applet with one has the group enabled" "1" "$(ui_enabled "$BUILD_THIN_GROUP_ID")"
check "and the note is hidden again"             "0" "$(ui_visible "$BUILD_THIN_NOTE_ID")"

# With no project open the pane cannot answer, and must not assert the negative:
# the group would otherwise stay grayed out with a note about an applet nobody
# has chosen until the pane was reloaded.
ui_reset
ab_open_project ""
omc_run AppletBuilder.buildrun.loaded
check "no project leaves the group alone" "" "$(ui_enabled "$BUILD_THIN_GROUP_ID")"
check "and writes no note"                "" "$(ui_value "$BUILD_THIN_NOTE_ID")"

section "12c. a refused run replaces the log, it does not leave the last one up"
# The pane keeps one log control and one verdict row. A guard that reported to
# the error window and returned without logging used to leave the previous run's
# successful transcript sitting under a red "Thinning failed" - which is exactly
# the state ab_log_to_control exists to prevent.

record_reset
nopython="$(ab_make_project Unequipped)"        # deliberately no interpreter
ab_open_project "$nopython"
# Stated rather than inherited: the section before this one leaves both boxes
# clear, and a handler that stops at "choose an action" would never reach the
# guard this section is about.
omc_control "$BUILD_THIN_PLAN_ID"    1
omc_control "$BUILD_THIN_APPLY_ID"   0
omc_control "$BUILD_THIN_DRY_RUN_ID" 0
omc_run AppletBuilder.thin.python

check "the log names this run"          "1" \
    "$(ui_value "$BUILD_LOG_ID" | /usr/bin/grep -c 'Thinning the embedded Python of Unequipped.app')"
check "and not the previous applet's"   "0" \
    "$(ui_value "$BUILD_LOG_ID" | /usr/bin/grep -c 'Buttoned')"
check "the verdict is a failure"        "Thinning failed" "$(ui_value "$BUILD_STATUS_ID")"

section "12g. the checkboxes are wired the way a Toggle actually listens"
# A Toggle fires actionID when its value changes, and reads valueChangeActionID
# not at all - Slider, TextField, DatePicker and a handful of others do, which is
# what makes the mistake easy. ActionUI accepts the property on any view, so a
# checkbox wired that way parses, validates, resolves to a real COMMAND_ID, and
# then never calls it. That is what left Dry Run stuck disabled
# with Apply Plan ticked. Nothing else in the suite crosses from the pane's JSON
# to the handler that has to run, so this is where that hop is pinned.

# Every *ActionID a pane element carries, so a check fails on the wrong property
# as loudly as on a missing one.
pane_actions() { # <element id>
    "$OMCTEST_PYTHON" - \
        "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/BuildRun.json" "$1" <<'PYEOF'
import json, sys

def find(node, wanted):
    if isinstance(node, dict):
        if node.get("id") == wanted:
            props = node.get("properties") or {}
            return ",".join("%s=%s" % (k, props[k]) for k in sorted(props)
                            if k == "actionID" or k.endswith("ActionID"))
        children = node.values()
    elif isinstance(node, list):
        children = node
    else:
        return None
    for child in children:
        found = find(child, wanted)
        if found is not None:
            return found
    return None

doc = json.load(open(sys.argv[1]))
found = find(doc, int(sys.argv[2]))
# "" is an element that carries no action; only None means it is not there.
sys.stdout.write("<no such element>" if found is None else found)
PYEOF
}

check "Write Thinning Plan calls the changed handler" \
    "actionID=AppletBuilder.thin.python.changed" "$(pane_actions "$BUILD_THIN_PLAN_ID")"
check "and so does Apply Plan" \
    "actionID=AppletBuilder.thin.python.changed" "$(pane_actions "$BUILD_THIN_APPLY_ID")"
check "Execute runs the phase" \
    "actionID=AppletBuilder.thin.python" "$(pane_actions "$BUILD_THIN_PYTHON_BTN_ID")"
# Dry Run is read at click time, not watched: a change action on it would run the
# coherence handler for a box that constrains nothing.
check "Dry Run needs no action of its own" "" "$(pane_actions "$BUILD_THIN_DRY_RUN_ID")"

section "13. the CLI maps its verbs onto the same phase"
# The other front door. It shares every decision above; what is its own is the
# argument surface - and one safety property: --dry-run is a property of a
# removal, so on a verb that performs none it is refused rather than ignored,
# which would report a real run as a preview.

record_reset
cli_app="$(ab_make_project Clied)"
add_fake_python "$cli_app"

ab_cli thin-python plan "$cli_app" >/dev/null 2>&1
check "plan runs"                 "0"      "$?"
check "as the plan verb"          "plan"   "$(record_line 1 | /usr/bin/awk -F'\t' '{print $1}')"

record_reset
ab_cli thin-python apply --dry-run "$cli_app" >/dev/null 2>&1
check "apply --dry-run runs"      "0"   "$?"
check "and passes --dry-run"      "yes" "$(record_has "--dry-run")"

record_reset
ab_cli thin-python plan --dry-run "$cli_app" >/dev/null 2>&1
check "--dry-run on plan is a usage error, not a silent no-op" "2" "$?"
check "and nothing ran"           "0"   "$(record_count)"

# The same argument for the other flag that belongs to a removal: honoring it
# silently on a verb that removes nothing suggests a step was skipped.
ab_cli thin-python plan --skip-verify "$cli_app" >/dev/null 2>&1
check "--skip-verify on plan is refused too" "2" "$?"
check "and nothing ran"           "0"   "$(record_count)"
ab_cli thin-python apply --skip-verify "$cli_app" >/dev/null 2>&1
check "but it is fine on apply"   "0"   "$?"
check "and is passed through"     "yes" "$(record_has "--skip-verify")"

# An architecture the phase does not recognize is dropped from the front end's
# arguments, so a typo would otherwise write a universal plan without a word
# about the slice it was asked for.
record_reset
ab_cli thin-python plan --thin armv8 "$cli_app" >/dev/null 2>&1
check "an unknown --thin value is refused" "2" "$?"
check "and nothing ran"                    "0" "$(record_count)"
ab_cli thin-python plan --thin x86_64 "$cli_app" >/dev/null 2>&1
check "a real one still runs"              "0" "$?"
check "and reaches the front end"          "yes" "$(record_has_pair "--arch" "x86_64")"

# `build --thin` shares the flag and shared the hazard: thin_distribution.sh exits
# 1 on an arch it does not know, and the build used to log that one line, sign a
# universal applet and report success. Checked here because this is where the
# flag's contract is written down, not because it belongs to thin-python.
ab_cli build --thin armv8 "$cli_app" >/dev/null 2>&1
check "build refuses an unknown arch as well" "2" "$?"

record_reset
ab_cli thin-python demolish "$cli_app" >/dev/null 2>&1
check "an unknown verb is refused"        "2" "$?"
ab_cli thin-python >/dev/null 2>&1
check "so is a missing verb"              "2" "$?"
ab_cli thin-python apply >/dev/null 2>&1
check "so is a missing bundle"            "2" "$?"
ab_cli thin-python apply "$OMCTEST_WORK/NoSuch.app" >/dev/null 2>&1
check "so is a path that is not a bundle" "2" "$?"
check "and none of them ran anything"     "0" "$(record_count)"

section "14. the phase writes nothing to the window"
# It is a build phase: everything it says goes through ab_log / ab_report, which
# the GUI handler routes to the pane. A stray omc_dialog_control call from the
# library would be a view id this file never declared.

check "no undeclared view ids" "" "$(ui_unknown_writes)"

omctest_end
