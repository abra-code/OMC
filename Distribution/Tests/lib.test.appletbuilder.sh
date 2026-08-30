#!/bin/sh
# Tests/lib.test.appletbuilder.sh - AppletBuilder's own vocabulary for omctest.
#
# Sourced by every test file after omctest.sh. It holds what the harness has no
# business knowing: where AppletBuilder keeps its state, how it names its
# pasteboard keys, and how to reach into its shell libraries and Python helpers
# directly.
#
# AppletBuilder is unusual as an applet under test in three ways, and each one is
# handled here rather than in the individual files:
#
#   1. The applet under test IS the applet shipping the harness. Nothing special
#      follows from that - omctest runs Scripts/ handlers, and these are its own -
#      but it does mean the interposition tools come from this bundle's framework,
#      so a test failure can be the framework rather than the handler.
#
#   2. Its documents are other applets. So the fixture is a whole .app, built
#      here from the templates the bundle already ships (ab_make_project) rather
#      than committed - no binaries in the repository, and the fixture tracks the
#      templates automatically.
#
#   3. It keeps two settings in a `defaults` DOMAIN, which no test run can
#      isolate. See ab_prefs_isolate below.

AB_SCRIPTS="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts"
AB_TEMPLATES="$OMC_APP_BUNDLE_PATH/Contents/Resources/Templates"
AB_AGENTS="$OMC_APP_BUNDLE_PATH/Contents/Resources/Agents"
AB_PLISTER="$OMC_OMC_SUPPORT_PATH/plister"
AB_PASTEBOARD="$OMC_OMC_SUPPORT_PATH/pasteboard"

ab_fatal() {
    printf 'lib.test.appletbuilder.sh: %s\n' "$1" >&2
    exit 1
}

[ -d "$AB_SCRIPTS" ] || ab_fatal "no Scripts directory at $AB_SCRIPTS"

# -----------------------------------------------------------------------------
# View ids - imported from the applet, never restated
# -----------------------------------------------------------------------------
#
# lib.common.sh declares them one per line as NAME_ID=<digits>. Importing beats
# a second list that can silently disagree with the first; the guard below turns
# a naming change into one loud failure instead of every check failing on an
# empty id.

eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$AB_SCRIPTS/lib.common.sh")"

for _ab_id in GEN_NAME_ID GEN_BUNDLE_ID_ID GEN_VERSION_ID GEN_STATUS_ID \
              CMD_TABLE_ID CMD_DETAIL_ID CMD_SAVE_BTN_ID CMD_EDITED_LABEL_ID \
              SCRIPTS_TABLE_ID SCRIPTS_DETAIL_ID \
              UI_TABLE_ID UI_DETAIL_ID UI_SAVE_BTN_ID UI_EDITED_LABEL_ID \
              UI_VALIDATE_BTN_ID UI_PRETTIFY_BTN_ID UI_PREVIEW_BTN_ID \
              SVC_TABLE_ID SVC_COMMAND_PICKER_ID BUILD_LOG_ID BUILD_STATUS_ID
do
    eval "_ab_val=\$$_ab_id"
    [ -n "$_ab_val" ] || ab_fatal "no view id imported for $_ab_id - has lib.common.sh changed its ID naming?"
done
unset _ab_id _ab_val

# -----------------------------------------------------------------------------
# Per-window state keys
# -----------------------------------------------------------------------------
#
# lib.common.sh builds every key as "<base>_${window_uuid}". The bases are
# imported the same way the ids are, and the uuid is interpolated at call time
# rather than at source time, so ab_pb_* stays correct across omc_window_switch.

eval "$(/usr/bin/sed -n \
    's/^\(PB_[A-Z_]*\)="\([A-Za-z0-9_]*\)_\${window_uuid}"$/\1_BASE="\2"/p' \
    "$AB_SCRIPTS/lib.common.sh")"

[ -n "$PB_PROJECT_PATH_BASE" ] || ab_fatal "no pasteboard key bases imported - has lib.common.sh changed how it builds them?"

# <PB_ variable name> -> the key the applet would use for the CURRENT window.
ab_pb_key() {
    eval "_ab_base=\$${1}_BASE"
    [ -n "$_ab_base" ] || ab_fatal "unknown state key $1"
    printf '%s_%s' "$_ab_base" "${OMC_ACTIONUI_WINDOW_UUID:-$OMC_NIB_DLG_GUID}"
}

ab_pb_get() { "$AB_PASTEBOARD" "$(ab_pb_key "$1")" get; }
ab_pb_set() { "$AB_PASTEBOARD" "$(ab_pb_key "$1")" set "$2"; }

# The one key that is NOT window-scoped: main.sh stashes the dropped applet here
# for project.init / general.loaded to pick up.
AB_PENDING_PB="appletbuilder_pending_project"
ab_pending_get() { "$AB_PASTEBOARD" "$AB_PENDING_PB" get; }
ab_pending_set() { "$AB_PASTEBOARD" "$AB_PENDING_PB" set "$1"; }

# Everything AppletBuilder remembers about a window. Clearing the directory is
# not enough - all of this applet's state lives in pasteboard keys.
# Derived from the applet, like the bases themselves, so a key added to
# lib.common.sh is reset and asserted on without anyone remembering to add it
# here. A hand-written list would drift silently.
AB_STATE_KEYS=$(/usr/bin/sed -n \
    's/^\(PB_[A-Z_]*\)="[A-Za-z0-9_]*_\${window_uuid}"$/\1/p' \
    "$AB_SCRIPTS/lib.common.sh")
[ -n "$AB_STATE_KEYS" ] || ab_fatal "no per-window state keys imported"

ab_reset_state() {
    for _ab_k in $AB_STATE_KEYS; do
        ab_pb_set "$_ab_k" ""
    done
    ab_pending_set ""
    unset _ab_k
}

# -----------------------------------------------------------------------------
# Calling into the applet's own code
# -----------------------------------------------------------------------------

# Run one of the applet's shell-library functions directly.
#   ab_call lib.common.sh command_file_path "$project"
#
# Under /bin/bash because that is what the libs declare and what the engine runs
# them with; the test file itself is POSIX sh. The subprocess also keeps the
# library's globals out of the test file and stops a function that exits from
# taking the whole file with it.
ab_call() {
    _ab_lib="$1"
    shift
    /bin/bash -c '. "$1" >/dev/null 2>&1; shift; "$@"' _ "$AB_SCRIPTS/$_ab_lib" "$@"
}

# Same, but print the value a library function left in one of its GLOBALS - the
# way lib.validate.sh reports, setting SCRIPT_VALIDATE_OUTPUT and friends rather
# than writing to stdout. The function's own output is discarded.
#   ab_call_out lib.validate.sh SCRIPT_VALIDATE_OUTPUT validate_script_file "$f"
ab_call_out() {
    _ab_lib="$1"
    _ab_global="$2"
    shift 2
    /bin/bash -c '. "$1" >/dev/null 2>&1; _g="$2"; shift 2; "$@" >/dev/null 2>&1; printf "%s" "${!_g}"' \
        _ "$AB_SCRIPTS/$_ab_lib" "$_ab_global" "$@"
}

# What a library function REPORTED. lib.common.sh's ab_log / ab_report default to
# stderr, and the pipeline code talks to the user only through them, so this is
# how a test reads a build phase's transcript without a window.
ab_call_log() {
    _ab_lib="$1"
    shift
    /bin/bash -c '. "$1" >/dev/null 2>&1; shift; "$@" 2>&1 >/dev/null' \
        _ "$AB_SCRIPTS/$_ab_lib" "$@"
}

# The exit code of a library function, as a string to compare against. Written
# out rather than left to $? so a check reads as one expression.
ab_call_rc() {
    ab_call "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

# Evaluate a Python expression against one of the applet's helper modules, under
# the interpreter the harness resolved. Arguments arrive as a list named "args"
# and are passed through argv - never interpolated into the expression, because
# the values worth testing are the ones with quotes and backslashes in them.
#   ab_py json_rename_value 'walk(json.loads(args[0]), args[1], args[2])' "$j" old new
#
# Note there is no argv[0] placeholder here. `python -c` already puts "-c" in
# sys.argv[0], so the "_" that `sh -c` needs would shift every index by one.
ab_py() {
    _ab_mod="$1"
    _ab_expr="$2"
    shift 2
    "$OMCTEST_PYTHON" -c '
import sys, os, json, importlib
sys.path.insert(0, os.path.join(os.environ["OMC_APP_BUNDLE_PATH"],
                                "Contents", "Resources", "Scripts"))
mod = importlib.import_module(sys.argv[1])
args = sys.argv[3:]
# "d" is a fresh dict in every call, for the op_* functions that take a document
# and mutate it in place. They return None, so the idiom is
#   op_whatever(d, args) or d["KEY"]
# Module first, bridge names last: a helper that ever defined its own "args" or
# "d" would otherwise shadow them and quietly change what a check is asserting.
sys.stdout.write(str(eval(sys.argv[2],
                          {**vars(mod), "json": json, "args": args, "d": {}})))
' "$_ab_mod" "$_ab_expr" "$@"
}

# The agent CLI, which shares lib.build.sh with the GUI handlers.
ab_cli() { "$AB_AGENTS/appletbuilder" "$@"; }

# -----------------------------------------------------------------------------
# Fixtures: a project applet to point AppletBuilder at
# -----------------------------------------------------------------------------
#
# Built from a template the bundle already ships rather than committed, so there
# are no binaries in the repository and the fixture cannot drift from what "New
# Applet" actually produces. Templates carry no Mach-O of their own; a test that
# needs Contents/MacOS/<exe> to exist creates it itself.

# <Name> [template, default "ActionUI Window"] -> prints the new .app path
ab_make_project() {
    _ab_name="$1"
    _ab_tmpl="${2:-ActionUI Window}"
    _ab_src="$AB_TEMPLATES/${_ab_tmpl}.applet"
    [ -d "$_ab_src" ] || ab_fatal "no template at $_ab_src"

    _ab_dst="$OMCTEST_WORK/${_ab_name}.app"
    /bin/rm -rf "$_ab_dst"
    /bin/cp -Rp "$_ab_src" "$_ab_dst" || ab_fatal "could not copy template to $_ab_dst"
    /bin/chmod -R u+w "$_ab_dst"

    # A template sitting in a working tree collects junk - an editor's config
    # directory, a __pycache__ from running a bundled verifier, a .DS_Store from
    # opening it in Finder. Copying that through would make every fixture depend
    # on the state of the machine, so it is swept here with a plain find rather
    # than with clean_build_junk, which is itself under test in
    # 40-build-hygiene.test.sh and must not be its own fixture builder.
    # The same set clean_build_junk sweeps, deliberately kept in step: a stray
    # .pytest_cache or Thumbs.db in a shipped template would otherwise break
    # 40-build-hygiene's "swept in silence" control and read as an applet bug
    # two hundred lines from its cause.
    /usr/bin/find "$_ab_dst" \( -type d -o -type l \) \
        \( -name '.claude' -o -name '.idea' -o -name '.vscode' \
           -o -name '.pytest_cache' -o -name '.mypy_cache' -o -name '.ruff_cache' \
           -o -name '__pycache__' \) \
        -prune -exec /bin/rm -rf {} + 2>/dev/null
    /usr/bin/find "$_ab_dst" \( -type f -o -type l \) \
        \( -name '.DS_Store' -o -name '._*' -o -name '*.pyc' -o -name '*.pyo' \
           -o -name '*.thin.tmp' -o -name 'Thumbs.db' \) -delete 2>/dev/null

    _ab_plist="$_ab_dst/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "$_ab_name" "$_ab_plist" || ab_fatal "could not name the fixture"
    /usr/bin/plutil -replace CFBundleExecutable -string "$_ab_name" "$_ab_plist"
    /usr/bin/plutil -replace CFBundleIdentifier -string "com.omc.applet.$_ab_name" "$_ab_plist"
    /usr/bin/plutil -replace CFBundleVersion -string "1.0" "$_ab_plist"

    # Rename the command and its handler the way the create pipeline would, so a
    # test asserting on the commands table reads the fixture's own name back
    # rather than the template's. Only the two places the applet keys off - the
    # command NAME and the script stem - not the full rename pass, which needs
    # ibtool and Launch Services.
    _ab_cmd="$_ab_dst/Contents/Resources/Command.json"
    if [ -f "$_ab_cmd" ]; then
        /usr/bin/plutil -replace COMMAND_LIST.0.NAME -string "$_ab_name" "$_ab_cmd"
    fi
    _ab_main="$_ab_dst/Contents/Resources/Scripts/${_ab_tmpl}.main.sh"
    if [ -f "$_ab_main" ]; then
        /bin/mv "$_ab_main" "$_ab_dst/Contents/Resources/Scripts/${_ab_name}.main.sh"
    fi

    printf '%s' "$_ab_dst"
}

# Give a fixture a Contents/MacOS/<exe>, for the paths that check one exists.
ab_add_executable() {
    _ab_app="$1"
    _ab_exe=$(/usr/bin/plutil -extract CFBundleExecutable raw "$_ab_app/Contents/Info.plist" 2>/dev/null)
    [ -n "$_ab_exe" ] || ab_fatal "fixture has no CFBundleExecutable"
    /bin/mkdir -p "$_ab_app/Contents/MacOS"
    /bin/cp /bin/echo "$_ab_app/Contents/MacOS/$_ab_exe" || ab_fatal "could not install a stand-in executable"
}

# The project the window is working on, as project.init would have recorded it.
ab_open_project() { ab_pb_set PB_PROJECT_PATH "$1"; }

# Read a key out of a fixture's Info.plist the way the applet does.
ab_plist_read() { /usr/bin/plutil -extract "$2" raw "$1/Contents/Info.plist" 2>/dev/null; }

# The command file the applet would resolve for a project - asked of the applet
# itself rather than recomputed here.
ab_command_file() { ab_call lib.common.sh command_file_path "$1"; }

# -----------------------------------------------------------------------------
# Preferences
# -----------------------------------------------------------------------------
#
# AppletBuilder keeps BundleIDPrefix and ExternalEditor in a `defaults` domain,
# and a domain is keyed by uid rather than by $HOME - so a handler that saves one
# under test rewrites the real preferences of whoever ran the suite. omctest
# reports the construct at the start of every run for exactly this reason.
#
# The applet therefore reads its domain from AB_PREFS_DOMAIN (lib.prefs.sh),
# and this points it at a plist inside the per-file fake home. `defaults`
# accepts a path in place of a domain, so the same code path runs against a file
# that dies with the scratch: nothing to clean up, and nothing global to clobber.
ab_prefs_isolate() {
    /bin/mkdir -p "$OMCTEST_HOME/Library/Preferences"
    # The PHYSICAL path, not the logical one. $TMPDIR on macOS is under /var,
    # which is a symlink to /private/var, and cfprefsd silently refuses to write
    # through it: `defaults write` exits 0 having created nothing. It also
    # dislikes the interior "//" that $TMPDIR's trailing slash produces. pwd -P
    # settles both. This cost an afternoon; the positive control in
    # 10-project.test.sh section 14 is what surfaced it, because without a
    # check_exists on this file every preferences assertion would have gone on
    # quietly describing the built-in fallback.
    _ab_prefs_dir=$(cd "$OMCTEST_HOME/Library/Preferences" && pwd -P) || return 1
    AB_PREFS_DOMAIN="$_ab_prefs_dir/com.abracode.applet-builder.test.plist"
    export AB_PREFS_DOMAIN
}

# Is `defaults` actually able to write? It reaches cfprefsd over a Mach service,
# which a sandboxed run cannot get to - and it fails SILENTLY there, exiting 0
# having written nothing. Without this probe every preferences assertion would
# quietly describe the built-in fallback value instead of a stored one.
ab_prefs_usable() {
    # Probed beside the isolated domain, so the probe answers for the exact
    # directory the applet will write to - symlinks, doubled slashes and all.
    _ab_probe="$(/usr/bin/dirname "$AB_PREFS_DOMAIN")/prefs-probe.plist"
    /bin/rm -f "$_ab_probe"
    /usr/bin/defaults write "$_ab_probe" ProbeKey ProbeValue 2>/dev/null
    _ab_back=$(/usr/bin/defaults read "$_ab_probe" ProbeKey 2>/dev/null)
    /bin/rm -f "$_ab_probe"
    [ "$_ab_back" = "ProbeValue" ]
}

ab_skip_section() {
    printf 'SKIP %s\n' "$1" >&2
}

# Fatal rather than best-effort: if this fails, AB_PREFS_DOMAIN stays unset and
# lib.prefs.sh falls straight back to the REAL com.abracode.applet-builder.
ab_prefs_isolate || ab_fatal "could not isolate the preferences domain"
