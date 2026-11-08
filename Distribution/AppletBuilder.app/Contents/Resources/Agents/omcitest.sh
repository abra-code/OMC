#!/bin/bash
# omcitest.sh - the library behind `appletbuilder itest`: integration tests that drive a real
# applet through the real OMC engine (see Documentation/omcitest_guide.md).
#
# Each *.itest.sh file gets a fresh applet process. The runner launches the applet's own
# executable for a test (OMC's OMCTestHost.h): a private folder under /tmp holds the bridge socket
# and the token, the token reaches the applet on descriptor 3, and the applet starts its ActionUI
# bridge at launch with the omc.test.* methods. The test file is then sourced and uses the
# functions below; afterwards the applet is asked to quit, so app.will.terminate runs, and is
# killed if it does not.
#
# The engine only offers this to an applet signed for local use (ad hoc, self-signed, or a debug
# build with get-task-allow); a Developer ID, App Store or TestFlight build, or one signed with
# any other Apple certificate that is not a development one, refuses the launch (exit 78).
#
# Test-file vocabulary (omctest's words where they mean the same):
#   section <header>                       a heading in the output
#   check <description> <expected> <actual>
#   check_contains <description> <needle> <haystack>
#   itest_run <command-id> [--text T] [--file PATH]... [--key-window] [--open-panel] [--window W]
#                                          runs a command as its menu item would; prints the run number
#                                          (--open-panel: a command that needs files asks for them;
#                                          --window: as window W's subcommand, as a menu bar command
#                                          runs for the key window, which a test launch does not have)
#   itest_wait_idle [seconds]              waits until nothing runs and the applet has settled
#   itest_windows                          the open ActionUI windows, one uuid per line
#   itest_new_window <before>              the window in itest_windows that was not in <before>
#   itest_close <window>                   closes the window as its close button does (its end command
#                                          runs); then itest_wait_idle
#   itest_value <window> <view-id> [part]  a control's value as text
#   itest_set_value <window> <view-id> <text> [part]
#   itest_click <window> <view-id> [part]  fires the control's actionID as a click would; prints it
#   itest_output <run>                     the text the run's tasks wrote
#   itest_run_finished <run>               "yes" when all of the run's tasks ended, else "no"
#   itest_answer_save <path>               the next panel is a save panel; answer it with <path>
#   itest_answer_open <path>...            the next panel is an open panel; answer it with these
#   itest_answer_cancel                    cancel the next panel
#                                          (a panel with no answer queued is canceled too; every
#                                          panel is recorded, answered or not)
#   itest_answer_alert <default|alternate|other>
#                                          answers the next of the engine's own alerts (a command's
#                                          WARNING confirmation, a version warning, an error alert)
#                                          with that button; it shares the panels' queue, in order.
#                                          An alert with no usable answer takes its alternate
#                                          (Cancel) button, or its only one. Not the alert tool a
#                                          handler runs: answer that with alert_answer
#   itest_panel_count                      how many panels, engine alerts and END_NOTIFICATION
#                                          notices the applet showed
#   itest_panel <index|last> <field>       a field of that record: kind (save, open, alert, notice),
#                                          title, message, prompt, defaultName, defaultDirectory,
#                                          identifier, allowedContentTypes, canChooseFiles,
#                                          canChooseDirectories, allowsMultiple, paths, canceled,
#                                          problem; for an alert or notice also level, buttons and
#                                          button (the one that answered)
#   itest_panels_clear                     forget the panel records and any answers not yet taken
#   itest_pasteboard [name]                the text on the run's own pasteboard <name> (default
#                                          general): what a handler's pasteboard tool, or the
#                                          engine as the clipboard, put there
#   itest_set_pasteboard <text> [name]     puts <text> there, e.g. the clipboard a command reads
#   alert_answer <rc> [rc ...]             answers for the next alerts, in order (0 OK, 1 Cancel,
#                                          2 Other); with none queued an alert answers 0
#   alerts_count, alerts_mention <text>    the alerts shown so far, and how many mention <text>
#   notify_count, notify_mention <text>    the same for notifications
#   alerts_reset, alert_answers_reset      forget the alerts shown, or the answers not yet taken
#                                          (alert and notify are omctest's recording stand-ins:
#                                          nothing is shown, the words are omctest's)
#   itest_call <method> [params-json]      any bridge method; prints the result as JSON
#   itest_quit                             quits now (normally the runner does this after the file)
#   ITEST_WORK                             a private folder for the test's own files
#   ITEST_HOME                             the applet's $HOME for this file: a private folder with
#                                          Library/Application Support, Preferences and Caches, so
#                                          what shell and Python handlers keep under $HOME or ~
#                                          is the test's, not the user's. Whatever asks the system
#                                          for the home folder instead (NSHomeDirectory,
#                                          CFPreferences, NSUserDefaults, a framework's own
#                                          Application Support lookup) still gets the user's.
#   ITEST_TMPDIR                           the applet's $TMPDIR for this file, private as omctest's:
#                                          applets keep per-window state there and sweep it at quit
#                                          (PackageBuilder deletes every packagebuilder-state-*), so
#                                          a shared one would let a test delete the user's own work
#   ITEST_APP                              the applet under test
#   ITEST_PASTEBOARD_PREFIX                the run's pasteboards are "<prefix>.<name>": the applet
#                                          and its handlers never touch the user's pasteboards
#
# bash 3.2, no set -e; every external tool by absolute path.

OMCITEST_PYTHON="${OMCITEST_PYTHON:-}"
OMCITEST_RPC="${OMCITEST_RPC:-}"
OMCITEST_LAUNCH_TIMEOUT="${OMCITEST_LAUNCH_TIMEOUT:-20}"
OMCITEST_IDLE_TIMEOUT="${OMCITEST_IDLE_TIMEOUT:-20}"
OMCITEST_QUIT_TIMEOUT="${OMCITEST_QUIT_TIMEOUT:-10}"
OMCITEST_PID=""
ITEST_WORK=""
ITEST_HOME=""
ITEST_TMPDIR=""
ITEST_APP=""
ITEST_PASTEBOARD_PREFIX=""
OMCITEST_PASTEBOARD_TOOL=""
OMCTEST_UI=""
_OMCITEST_MADE_WORK=""

_omcitest_rpc() {
    "$OMCITEST_PYTHON" "$OMCITEST_RPC" "$@"
}

# -- Checks ------------------------------------------------------------------------------------

section() { # <header>
    printf '\n== %s ==\n' "$1" >&2
}

check() { # <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf 'p' >> "$ITEST_WORK/counts.pass"
        printf 'ok   %s\n' "$1" >&2
    else
        printf 'f' >> "$ITEST_WORK/counts.fail"
        printf 'FAIL %s\n       expected [%s]\n       actual   [%s]\n' "$1" "$2" "$3" >&2
    fi
}

check_contains() { # <description> <needle> <haystack>
    case "$3" in
        *"$2"*)
            printf 'p' >> "$ITEST_WORK/counts.pass"
            printf 'ok   %s\n' "$1" >&2
            ;;
        *)
            printf 'f' >> "$ITEST_WORK/counts.fail"
            printf 'FAIL %s\n       expected to contain [%s]\n       actual              [%s]\n' "$1" "$2" "$3" >&2
            ;;
    esac
}

# A failure that is not a comparison: the applet did not launch, a call failed.
_omcitest_fail() { # <description>
    printf 'f' >> "$ITEST_WORK/counts.fail"
    printf 'FAIL %s\n' "$1" >&2
}

_omcitest_count() { # <pass|fail>
    local _file="$ITEST_WORK/counts.$1"
    if [ ! -f "$_file" ]; then
        printf '0'
        return 0
    fi
    /usr/bin/wc -c < "$_file" | /usr/bin/tr -d ' '
}

# -- Driving the applet ------------------------------------------------------------------------

itest_call() { # <method> [params-json]
    _omcitest_rpc call "$1" "${2:-}"
}

itest_run() { # <command-id> [--text T] [--file PATH]... [--key-window] [--open-panel] [--window W]
    _omcitest_rpc run "$@"
}

itest_answer_save() { # <path>
    _omcitest_rpc answer save "$1" > /dev/null
}

itest_answer_open() { # <path>...
    _omcitest_rpc answer open "$@" > /dev/null
}

itest_answer_cancel() {
    _omcitest_rpc answer cancel > /dev/null
}

itest_answer_alert() { # <default|alternate|other>
    _omcitest_rpc answer alert "$1" > /dev/null
}

itest_panel_count() {
    _omcitest_rpc panel-count
}

itest_panel() { # <index|last> <field>
    _omcitest_rpc panel "$1" "$2"
}

itest_panels_clear() {
    _omcitest_rpc panels --clear > /dev/null
}

itest_wait_idle() { # [seconds]
    local _timeout="${1:-$OMCITEST_IDLE_TIMEOUT}"
    _omcitest_rpc wait-idle --timeout "$_timeout"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _omcitest_fail "the applet did not become idle within ${_timeout}s"
    fi
    return "$_status"
}

itest_windows() {
    _omcitest_rpc windows
}

itest_close() { # <window>
    _omcitest_rpc call omc.test.closeWindow "{\"window\": \"$1\"}"
}

itest_new_window() { # <before: output of itest_windows>
    local _before="$1"
    local _now
    _now="$(itest_windows)"
    local _window
    for _window in $_now; do
        case "$_before" in
            *"$_window"*) ;;
            *) printf '%s\n' "$_window"; return 0 ;;
        esac
    done
    return 1
}

itest_value() { # <window> <view-id> [part]
    if [ -n "${3:-}" ]; then
        _omcitest_rpc value "$1" "$2" --part "$3"
    else
        _omcitest_rpc value "$1" "$2"
    fi
}

itest_set_value() { # <window> <view-id> <text> [part]
    if [ -n "${4:-}" ]; then
        _omcitest_rpc set-value "$1" "$2" "$3" --part "$4"
    else
        _omcitest_rpc set-value "$1" "$2" "$3"
    fi
}

itest_click() { # <window> <view-id> [part]
    if [ -n "${3:-}" ]; then
        _omcitest_rpc click "$1" "$2" --part "$3"
    else
        _omcitest_rpc click "$1" "$2"
    fi
}

itest_output() { # <run>
    _omcitest_rpc output "$1"
}

itest_run_finished() { # <run>
    local _record
    _record="$(_omcitest_rpc run-record "$1")"
    case "$_record" in
        *'"finished": true'*) printf 'yes\n' ;;
        *) printf 'no\n' ;;
    esac
}

# The applet's own pasteboard tool, with the run's prefix, so it reads and writes the run's boards.
_omcitest_pasteboard() { # <name> <get|put> [text]
    if [ -z "$OMCITEST_PASTEBOARD_TOOL" ] || [ -z "$ITEST_PASTEBOARD_PREFIX" ]; then
        printf 'omcitest: no pasteboard tool in the applet\n' >&2
        return 1
    fi
    OMC_TEST_PASTEBOARD_PREFIX="$ITEST_PASTEBOARD_PREFIX" "$OMCITEST_PASTEBOARD_TOOL" "$@"
}

itest_pasteboard() { # [name]
    _omcitest_pasteboard "${1:-general}" get
}

itest_set_pasteboard() { # <text> [name]
    _omcitest_pasteboard "${2:-general}" put "$1"
}

# -- Alerts and notifications ------------------------------------------------------------------
#
# The applet's handlers run omctest's alert and notify stand-ins from the run's support folder
# (_omcitest_build_support), which log to and answer from $OMCTEST_UI. These are omctest's words over
# the same files, so a ported omctest scenario keeps its alert answers and counts.

alert_answer() { # <rc> [rc ...]
    local _rc
    for _rc; do
        printf '%s\n' "$_rc" >> "$OMCTEST_UI/alert_answers"
    done
}

alerts_reset() { : > "$OMCTEST_UI/alerts.log"; }
alert_answers_reset() { : > "$OMCTEST_UI/alert_answers"; }
alerts_count() { /usr/bin/awk 'END { print NR }' "$OMCTEST_UI/alerts.log" 2>/dev/null; }
alerts_mention() { /usr/bin/grep -c -- "$1" "$OMCTEST_UI/alerts.log" 2>/dev/null | /usr/bin/tr -d ' '; }
notify_count() { /usr/bin/awk 'END { print NR }' "$OMCTEST_UI/notifications.log" 2>/dev/null; }
notify_mention() { /usr/bin/grep -c -- "$1" "$OMCTEST_UI/notifications.log" 2>/dev/null | /usr/bin/tr -d ' '; }

itest_quit() {
    if [ -z "$OMCITEST_PID" ]; then
        return 0
    fi
    _omcitest_rpc call omc.test.quit > /dev/null 2>&1
    _omcitest_wait_exit "$OMCITEST_QUIT_TIMEOUT"
}

# -- Launch and teardown -----------------------------------------------------------------------

# Waits up to <seconds> for the applet to exit; then OMCITEST_EXIT_STATUS is its status and the
# pid is cleared. Returns 1 when it is still running.
_omcitest_wait_exit() { # <seconds>
    local _deadline=$(( $(/bin/date +%s) + $1 ))
    local _alive
    while :; do
        /bin/kill -0 "$OMCITEST_PID" 2>/dev/null
        _alive=$?
        if [ "$_alive" -ne 0 ]; then
            break
        fi
        if [ "$(/bin/date +%s)" -ge "$_deadline" ]; then
            return 1
        fi
        /bin/sleep 0.1
    done
    wait "$OMCITEST_PID" 2>/dev/null
    OMCITEST_EXIT_STATUS=$?
    OMCITEST_PID=""
    return 0
}

# The run's support folder: a link to each of the applet's own Support tools, except alert and notify,
# which are omctest's recording stand-ins (written by omctest.sh's own emitters, so both harnesses
# answer and log alike). The applet hands this folder to its handlers as OMC_OMC_SUPPORT_PATH.
_omcitest_build_support() { # <App.app> <dest>
    local _real="$1/Contents/Frameworks/Abracode.framework/Versions/A/Support"
    if [ ! -d "$_real" ]; then
        _real="$1/Contents/Frameworks/Abracode.framework/Support"
    fi
    if [ ! -d "$_real" ]; then
        printf 'omcitest: no Abracode.framework Support folder in %s\n' "$1" >&2
        return 1
    fi
    local _lib="${OMCITEST_RPC%/*}/omctest.sh"
    if [ ! -f "$_lib" ]; then
        printf 'omcitest: omctest.sh is not beside omcitest_rpc.py: %s\n' "$_lib" >&2
        return 1
    fi
    /bin/mkdir -p "$2" || return 1
    local _tool
    for _tool in "$_real"/*; do
        [ -e "$_tool" ] || continue
        case "${_tool##*/}" in
            alert|notify) ;;
            *) /bin/ln -s "$_tool" "$2/${_tool##*/}" || return 1 ;;
        esac
    done
    local _name
    for _name in alert notify; do
        # shellcheck disable=SC1090
        ( unset OMCTEST_PREPARED; OMCTEST_RUNNER=1; . "$_lib"; "omctest_emit_stub_$_name" ) > "$2/$_name" || return 1
        /bin/chmod 755 "$2/$_name" || return 1
    done
}

_omcitest_executable() { # <App.app>
    local _name
    _name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$1/Contents/Info.plist" 2>/dev/null)"
    if [ -z "$_name" ]; then
        return 1
    fi
    printf '%s\n' "$1/Contents/MacOS/$_name"
}

# Launches <App.app> for a test. Sets ITEST_WORK, OMCITEST_PID, OMCITEST_SOCKET and
# OMCITEST_TOKEN_FILE. Returns 1, with the reason on stderr, when the applet does not come up.
omcitest_launch() { # <App.app>
    local _app="$1"
    local _exe
    _exe="$(_omcitest_executable "$_app")"
    if [ -z "$_exe" ] || [ ! -x "$_exe" ]; then
        printf 'omcitest: no executable in %s\n' "$_app" >&2
        return 1
    fi

    # Under /tmp, not $TMPDIR: a Unix socket path must fit in 104 bytes.
    local _work
    _work="$(/usr/bin/mktemp -d /tmp/omcit.XXXXXX)"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_work" ]; then
        printf 'omcitest: cannot create a private folder under /tmp\n' >&2
        return 1
    fi
    /bin/chmod 700 "$_work"
    ITEST_WORK="$_work"
    _OMCITEST_MADE_WORK="$_work"
    export ITEST_WORK

    local _token
    _token="$(/usr/bin/openssl rand -hex 32)"
    if [ -z "$_token" ]; then
        printf 'omcitest: cannot make a token\n' >&2
        return 1
    fi
    OMCITEST_TOKEN_FILE="$_work/token"
    ( umask 077; printf '%s\n' "$_token" > "$OMCITEST_TOKEN_FILE" )
    OMCITEST_SOCKET="$_work/bridge.sock"
    export OMCITEST_TOKEN_FILE OMCITEST_SOCKET

    # The run's own pasteboards, unique to this launch: the folder's random name and this process.
    ITEST_PASTEBOARD_PREFIX="omcitest.$$.${_work##*/omcit.}"
    export ITEST_PASTEBOARD_PREFIX

    # A private $HOME, as omctest gives every file: an applet's own state under $HOME (recents,
    # saved configurations, caches) is the test's, and the user's is never read or rewritten.
    ITEST_HOME="$_work/home"
    /bin/mkdir -p "$ITEST_HOME/Library/Application Support" "$ITEST_HOME/Library/Preferences" "$ITEST_HOME/Library/Caches" || return 1
    export ITEST_HOME

    # A private $TMPDIR too, with omctest's trailing slash. Applets keep per-window state in TMPDIR
    # and clean it up at quit by pattern: PackageBuilder's app.will.terminate deletes every
    # packagebuilder-state-* there and stops the builds they record, which in the user's own TMPDIR
    # would be the user's open, unsaved projects.
    ITEST_TMPDIR="$_work/tmp/"
    /bin/mkdir -p "$ITEST_TMPDIR" || return 1
    export ITEST_TMPDIR

    # alert and notify record and answer instead of showing anything.
    OMCTEST_UI="$_work/ui"
    /bin/mkdir -p "$OMCTEST_UI" || return 1
    : > "$OMCTEST_UI/alerts.log"
    : > "$OMCTEST_UI/notifications.log"
    : > "$OMCTEST_UI/alert_answers"
    _omcitest_build_support "$_app" "$_work/support"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'omcitest: cannot build the run'"'"'s support folder\n' >&2
        return 1
    fi

    # The token goes to the applet on descriptor 3, never in its environment.
    # The harness's own variables stay out of the applet and its handlers; ITEST_WORK goes in, so a
    # handler can leave files there for the test to check.
    /usr/bin/env -u OMCITEST_TOKEN_FILE -u OMCITEST_SOCKET -u OMCITEST_RESULTS -u OMCITEST_RPC -u OMCITEST_PYTHON \
        OMC_TEST_BRIDGE_PATH="$OMCITEST_SOCKET" OMC_TEST_TOKEN_FD=3 OMC_TEST_PASTEBOARD_PREFIX="$ITEST_PASTEBOARD_PREFIX" \
        OMC_TEST_SUPPORT_PATH="$_work/support" OMCTEST_UI="$OMCTEST_UI" HOME="$ITEST_HOME" TMPDIR="$ITEST_TMPDIR" \
        "$_exe" 3< "$OMCITEST_TOKEN_FILE" > "$_work/applet.log" 2>&1 &
    OMCITEST_PID=$!

    _omcitest_rpc wait-ready --pid "$OMCITEST_PID" --timeout "$OMCITEST_LAUNCH_TIMEOUT"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        printf 'omcitest: the applet did not come up for the test; its output:\n' >&2
        /usr/bin/sed 's/^/    /' "$_work/applet.log" >&2
        _omcitest_wait_exit 0
        _status=$?
        if [ "$_status" -ne 0 ]; then
            /bin/kill -KILL "$OMCITEST_PID" 2>/dev/null
            _omcitest_wait_exit 5
        fi
        return 1
    fi
    # The launch itself ran app.will.launch and app.did.launch; let them finish.
    _omcitest_rpc wait-idle --timeout "$OMCITEST_IDLE_TIMEOUT" > /dev/null

    # The applet's pasteboard tool, only once its engine reports the run's prefix: an older tool
    # ignores OMC_TEST_PASTEBOARD_PREFIX and would read, write and clear the user's pasteboards.
    local _status_reply
    _status_reply="$(itest_call omc.test.status)"
    case "$_status_reply" in
        *"\"pasteboardPrefix\": \"$ITEST_PASTEBOARD_PREFIX\""*)
            OMCITEST_PASTEBOARD_TOOL="$_app/Contents/Frameworks/Abracode.framework/Versions/A/Support/pasteboard"
            if [ ! -x "$OMCITEST_PASTEBOARD_TOOL" ]; then
                OMCITEST_PASTEBOARD_TOOL="$_app/Contents/Frameworks/Abracode.framework/Support/pasteboard"
            fi
            if [ ! -x "$OMCITEST_PASTEBOARD_TOOL" ]; then
                OMCITEST_PASTEBOARD_TOOL=""
            fi
            ;;
        *)
            printf 'omcitest: the applet did not report the run'"'"'s pasteboards; itest_pasteboard is off\n' >&2
            ;;
    esac

    # An engine that ignores OMC_TEST_SUPPORT_PATH hands its handlers the real alert, which waits
    # for a click no one will make: refuse the launch rather than stall each test on it.
    case "$_status_reply" in
        *"\"supportPath\": \"$_work/support\""*) ;;
        *)
            printf 'omcitest: the applet did not take the run'"'"'s support folder (an engine without it): its alert and notify would be the real ones\n' >&2
            itest_quit
            return 1
            ;;
    esac
    return 0
}

# Empties the run's general and find pasteboards once the applet is gone. Pasteboards under names a
# handler chose stay in the pasteboard server until the user logs out; nothing reads them, since
# their names carry this run's prefix.
_omcitest_clear_pasteboards() {
    if [ -z "$OMCITEST_PASTEBOARD_TOOL" ] || [ -z "$ITEST_PASTEBOARD_PREFIX" ]; then
        return 0
    fi
    _omcitest_pasteboard general put "" > /dev/null 2>&1
    _omcitest_pasteboard find put "" > /dev/null 2>&1
}

omcitest_finish() {
    if [ -n "$OMCITEST_PID" ]; then
        itest_quit
        local _status=$?
        if [ "$_status" -ne 0 ]; then
            _omcitest_fail "the applet did not quit within ${OMCITEST_QUIT_TIMEOUT}s; terminating it"
            /bin/kill -TERM "$OMCITEST_PID" 2>/dev/null
            _omcitest_wait_exit 5
            _status=$?
            if [ "$_status" -ne 0 ]; then
                /bin/kill -KILL "$OMCITEST_PID" 2>/dev/null
                _omcitest_wait_exit 5
            fi
        fi
    fi
}

# Runs one test file against a fresh applet and appends "<passed> <failed> <file>" to
# $OMCITEST_RESULTS. Meant to run in its own bash process (cmd_itest does that).
omcitest_run_file() { # <App.app> <test-file>
    local _app="$1"
    local _file="$2"
    ITEST_APP="$_app"
    export ITEST_APP
    local _name
    _name="$(/usr/bin/basename "$_file")"
    printf '\n## %s\n' "$_name" >&2

    omcitest_launch "$_app"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        if [ -z "$ITEST_WORK" ]; then
            printf '0 1 %s\n' "$_name" >> "$OMCITEST_RESULTS"
            return 1
        fi
        _omcitest_fail "launch for $_name"
    else
        # shellcheck disable=SC1090
        source "$_file"
        omcitest_finish
        if [ -n "${OMCITEST_EXIT_STATUS:-}" ] && [ "$OMCITEST_EXIT_STATUS" != "0" ]; then
            _omcitest_fail "the applet exited with status $OMCITEST_EXIT_STATUS"
        fi
        if [ "${OMCITEST_VERBOSE:-0}" = "1" ]; then
            printf -- '-- applet output --\n' >&2
            /usr/bin/sed 's/^/    /' "$ITEST_WORK/applet.log" >&2
        fi
    fi

    _omcitest_clear_pasteboards

    local _passed _failed
    _passed="$(_omcitest_count pass)"
    _failed="$(_omcitest_count fail)"
    printf '%s %s %s\n' "$_passed" "$_failed" "$_name" >> "$OMCITEST_RESULTS"
    if [ "${OMCITEST_KEEP:-0}" = "1" ]; then
        printf 'kept: %s\n' "$ITEST_WORK" >&2
    else
        # The whole folder: the test's own files (ITEST_WORK) are in it too. The one mktemp made,
        # not ITEST_WORK, which a test file could have reassigned.
        if [ -n "$_OMCITEST_MADE_WORK" ]; then
            /bin/rm -rf "$_OMCITEST_MADE_WORK"
        fi
    fi
    if [ "$_failed" != "0" ]; then
        return 1
    fi
    return 0
}
