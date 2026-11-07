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
#   itest_run <command-id> [--text T] [--file PATH]... [--key-window]
#                                          runs a command as its menu item would; prints the run number
#   itest_wait_idle [seconds]              waits until nothing runs and the applet has settled
#   itest_windows                          the open ActionUI windows, one uuid per line
#   itest_new_window <before>              the window in itest_windows that was not in <before>
#   itest_value <window> <view-id> [part]  a control's value as text
#   itest_set_value <window> <view-id> <text> [part]
#   itest_click <window> <view-id> [part]  fires the control's actionID as a click would; prints it
#   itest_output <run>                     the text the run's tasks wrote
#   itest_run_finished <run>               "yes" when all of the run's tasks ended, else "no"
#   itest_call <method> [params-json]      any bridge method; prints the result as JSON
#   itest_quit                             quits now (normally the runner does this after the file)
#   ITEST_WORK                             a private folder for the test's own files
#
# bash 3.2, no set -e; every external tool by absolute path.

OMCITEST_PYTHON="${OMCITEST_PYTHON:-}"
OMCITEST_RPC="${OMCITEST_RPC:-}"
OMCITEST_LAUNCH_TIMEOUT="${OMCITEST_LAUNCH_TIMEOUT:-20}"
OMCITEST_IDLE_TIMEOUT="${OMCITEST_IDLE_TIMEOUT:-20}"
OMCITEST_QUIT_TIMEOUT="${OMCITEST_QUIT_TIMEOUT:-10}"
OMCITEST_PID=""
ITEST_WORK=""
_OMCITEST_MADE_WORK=""

_omcitest_rpc() {
    "$OMCITEST_PYTHON" "$OMCITEST_RPC" "$@"
}

# ── Checks ──────────────────────────────────────────────────────────────────

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

# ── Driving the applet ──────────────────────────────────────────────────────

itest_call() { # <method> [params-json]
    _omcitest_rpc call "$1" "${2:-}"
}

itest_run() { # <command-id> [--text T] [--file PATH]... [--key-window]
    _omcitest_rpc run "$@"
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

itest_quit() {
    if [ -z "$OMCITEST_PID" ]; then
        return 0
    fi
    _omcitest_rpc call omc.test.quit > /dev/null 2>&1
    _omcitest_wait_exit "$OMCITEST_QUIT_TIMEOUT"
}

# ── Launch and teardown ─────────────────────────────────────────────────────

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

    # The token goes to the applet on descriptor 3, never in its environment.
    # The harness's own variables stay out of the applet and its handlers; ITEST_WORK goes in, so a
    # handler can leave files there for the test to check.
    /usr/bin/env -u OMCITEST_TOKEN_FILE -u OMCITEST_SOCKET -u OMCITEST_RESULTS -u OMCITEST_RPC -u OMCITEST_PYTHON \
        OMC_TEST_BRIDGE_PATH="$OMCITEST_SOCKET" OMC_TEST_TOKEN_FD=3 \
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
    return 0
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
