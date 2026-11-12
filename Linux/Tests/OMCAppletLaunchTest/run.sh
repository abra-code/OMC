#!/bin/bash
# Linux/Tests/OMCAppletLaunchTest/run.sh - the Linux applet's app shell end to end
# (AbracodeFramework/EntryPoints/Linux/OMCAppletMain.cpp): the fixture LaunchTest.app made into a
# bundle as every Linux applet is (Linux/make-applet-bundle.sh: the built CommandApplet executable,
# the engine's framework with its built-in windows, texts and support tools), launched in the
# desktop session, with its commands logging what ran to a file.
#
# Usage: run.sh <the build's products folder, holding CommandApplet and the tools>
# Needs a desktop session (on the agent-vm box: GNOME's Wayland socket, set up below when
# WAYLAND_DISPLAY is unset). Exit status: 0 all passed, 1 a check failed, 2 bad arguments.

products="$1"
applet_executable="$products/CommandApplet"
if [ -z "$products" ] || [ ! -x "$applet_executable" ]; then
    printf 'Usage: %s <the build'"'"'s products folder, holding CommandApplet>\n' "$0" >&2
    exit 2
fi

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
uid="$(/usr/bin/id -u)"
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export WAYLAND_DISPLAY=wayland-0
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
fi
export SWIFT_BACKTRACE=enable=no

passed=0
failed=0
check() { # <name> <0 or 1> [detail]
    if [ "$2" -eq 1 ]; then
        passed=$((passed + 1))
        printf 'ok   %s\n' "$1"
    else
        failed=$((failed + 1))
        printf 'FAIL %s%s\n' "$1" "${3:+: $3}"
    fi
}

# In the home folder: the engine refuses private folders on paths others can write to, like /tmp
work="$HOME/.omc-applet-test-$$"
/bin/mkdir -p "$work"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$work" >&2
    exit 1
fi
bundle="$work/LaunchTest.app"
/bin/bash "$here/../../make-applet-bundle.sh" "$products" "$here/LaunchTest.app" "$bundle"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make the applet bundle (make-applet-bundle.sh status %s)\n' "$status" >&2
    exit 1
fi
export LAUNCHTEST_LOG="$work/log"
# The desktop's recent files (recently-used.xbel) in the work folder, not the session's own list
export XDG_DATA_HOME="$work/data"

# Waits up to <seconds> for the process to end; sets result to its exit status, or "running" (then
# it is killed). Not
# in a $(...) subshell, which cannot wait for this shell's children.
wait_for_exit() { # <pid> <seconds>
    local pid="$1"
    local tenths=$(( $2 * 10 ))
    local waited=0
    while [ "$waited" -lt "$tenths" ]; do
        kill -0 "$pid" 2>/dev/null
        status=$?
        if [ "$status" -ne 0 ]; then
            wait "$pid"
            result=$?
            return
        fi
        /bin/sleep 0.1
        waited=$((waited + 1))
    done
    # Still running: killed, so it cannot hold the bus name and take the next checks' launches
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    result=running
}

# Waits up to <seconds> for a line in the log; prints yes or no
wait_for_line() { # <line> <seconds>
    local tenths=$(( $2 * 10 ))
    local waited=0
    local found
    while [ "$waited" -lt "$tenths" ]; do
        found="$(/usr/bin/grep -c -x -F -- "$1" "$LAUNCHTEST_LOG" 2>/dev/null)"
        if [ -n "$found" ] && [ "$found" -gt 0 ]; then
            printf 'yes'
            return
        fi
        /bin/sleep 0.1
        waited=$((waited + 1))
    done
    printf 'no'
}

log_text() { /bin/cat "$LAUNCHTEST_LOG" 2>/dev/null | /usr/bin/tr '\n' ' '; }

printf '== launched with nothing: the main command, then launched, then it quits by itself ==\n'
: > "$LAUNCHTEST_LOG"
export LAUNCHTEST_MAIN_SECONDS=1
"$bundle/LaunchTest" &
pid=$!
wait_for_exit "$pid" 20
check "the applet quits by itself once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
lines="$(log_text)"
check "the main command ran with no file, then app.did.launch, then app.will.terminate" \
    "$([ "$lines" = "main: did.launch will.terminate " ] && echo 1 || echo 0)" "$lines"

printf '== a second launch with a file hands it to the running applet ==\n'
: > "$LAUNCHTEST_LOG"
export LAUNCHTEST_MAIN_SECONDS=4
"$bundle/LaunchTest" &
first=$!
started="$(wait_for_line "did.launch" 10)"
check "the first applet is running" "$([ "$started" = "yes" ] && echo 1 || echo 0)"
: > "$work/dropped file.txt"
"$bundle/LaunchTest" "$work/dropped file.txt" &
second=$!
wait_for_exit "$second" 10
check "the second launch exits at once" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
opened="$(wait_for_line "main:$work/dropped file.txt" 10)"
check "the running applet runs its main command with the file" "$([ "$opened" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
wait_for_exit "$first" 20
check "and quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
mains="$(/usr/bin/grep -c '^main:' "$LAUNCHTEST_LOG")"
check "the main command ran twice in all, in one applet" "$([ "$mains" = "2" ] && echo 1 || echo 0)" "$(log_text)"
recent="$(/usr/bin/grep -c -F 'dropped%20file.txt' "$XDG_DATA_HOME/recently-used.xbel" 2>/dev/null)"
check "the file is in the recent files" "$([ "$recent" = "1" ] && echo 1 || echo 0)" "count: $recent"

printf '== a URL on the applet goes to omc.app.handle-url ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://hello?x=1&y=two%20words' 'launchtest://hello?q=100%' &
pid=$!
handled="$(wait_for_line 'url:launchtest://hello?x=1&y=two%20words' 10)"
check "the URL reaches omc.app.handle-url" "$([ "$handled" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
# NSURLComponents takes a query with a stray "%" as text (OMCURLParse.h); a stricter parser refuses the URL
handled="$(wait_for_line 'url:launchtest://hello?q=100%' 10)"
check "a URL whose query has a stray % too, as on macOS" "$([ "$handled" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
wait_for_exit "$pid" 20
check "and the applet quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
mains="$(/usr/bin/grep -c '^main:' "$LAUNCHTEST_LOG")"
check "without running the main command" "$([ "$mains" = "0" ] && echo 1 || echo 0)" "$(log_text)"

printf '== a command'"'"'s ActionUI window: init, a value set with omc_dialog_control, OK ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://exe?commandID=lt.window' &
pid=$!
command_ran="$(wait_for_line 'window.command' 10)"
check "the window command runs" "$([ "$command_ran" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
inits="$(/usr/bin/grep -c '^window.init:[0-9A-F-]\{36\}$' "$LAUNCHTEST_LOG")"
check "its window opens and runs INIT_SUBCOMMAND_ID with the window's UUID" "$([ "$inits" = "1" ] && echo 1 || echo 0)" "$(log_text)"
set_status="$(wait_for_line 'window.set:0' 10)"
check "omc_dialog_control sets a value in the window" "$([ "$set_status" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
ok_value="$(wait_for_line 'window.ok:set by omc_dialog_control' 10)"
check "omc_terminate_ok closes it and END_OK_SUBCOMMAND_ID reads that value" "$([ "$ok_value" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
wait_for_exit "$pid" 20
check "then, with no window left, the applet quits by itself" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== a quit ends a blocking window'"'"'s modal run ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://exe?commandID=lt.modal' &
pid=$!
modal_open="$(wait_for_line 'modal.init' 10)"
check "a blocking window opens (its init ran)" "$([ "$modal_open" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
kill -TERM "$pid"
wait_for_exit "$pid" 10
check "SIGTERM ends the applet while the window's modal run goes on" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== macOS version requirements are ignored on Linux ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://exe?commandID=lt.macos' &
pid=$!
macos_ran="$(wait_for_line 'macos.ran' 10)"
check "a command that requires macOS 99 and at most 10.1 runs" "$([ "$macos_ran" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
wait_for_exit "$pid" 20
check "and the applet quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== shell commands and .sh scripts run with bash, as on macOS ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://exe?commandID=lt.shell' &
pid=$!
command_bash="$(wait_for_line 'shell.command.bash' 10)"
check "a command line runs with bash" "$([ "$command_bash" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
script_bash="$(wait_for_line 'shell.script.bash' 10)"
check "a .sh script runs with bash" "$([ "$script_bash" = "yes" ] && echo 1 || echo 0)" "$(log_text)"
wait_for_exit "$pid" 20
check "and the applet quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== the engine'"'"'s framework in the bundle: a built-in window opens ==\n'
: > "$LAUNCHTEST_LOG"
"$bundle/LaunchTest" 'launchtest://exe?commandID=lt.input' 2> "$work/input.err" &
pid=$!
/bin/sleep 4
alive="no"
if kill -0 "$pid" 2>/dev/null; then
    alive="yes"
fi
missing="$(/usr/bin/grep -c 'missing from the engine' "$work/input.err")"
check "the input dialog (omc_input_text, from the framework) is open and waits" \
    "$([ "$alive" = "yes" ] && [ "$missing" = "0" ] && echo 1 || echo 0)" "running: $alive, $(/usr/bin/tr '\n' ' ' < "$work/input.err" | /usr/bin/cut -c1-300)"
kill -TERM "$pid" 2>/dev/null
wait_for_exit "$pid" 10
check "and SIGTERM ends the applet while the dialog waits" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== the master applet, CommandApplet.app (made by build-linux.sh) ==\n'
master="$products/CommandApplet.app"
if [ -x "$master/CommandApplet" ]; then
    "$master/CommandApplet" 2> "$work/master.err" &
    pid=$!
    /bin/sleep 4
    alive="no"
    if kill -0 "$pid" 2>/dev/null; then
        alive="yes"
    fi
    problems="$(/usr/bin/grep -c -i 'missing from the engine\|not found\|Unable to create' "$work/master.err")"
    check "CommandApplet starts and keeps running (its window open), with no document or tool missing" \
        "$([ "$alive" = "yes" ] && [ "$problems" = "0" ] && echo 1 || echo 0)" "running: $alive, $(/usr/bin/tr '\n' ' ' < "$work/master.err" | /usr/bin/cut -c1-300)"
    kill -TERM "$pid" 2>/dev/null
    wait_for_exit "$pid" 10
    check "and quits on SIGTERM" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
else
    check "CommandApplet.app is in the products folder" 0 "not found: $master (build-linux.sh makes it)"
fi

printf '== SIGTERM quits as Quit does ==\n'
: > "$LAUNCHTEST_LOG"
export LAUNCHTEST_MAIN_SECONDS=30
"$bundle/LaunchTest" &
pid=$!
started="$(wait_for_line "did.launch" 10)"
kill -TERM "$pid"
wait_for_exit "$pid" 10
check "the applet ends on SIGTERM" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"
check "after app.will.terminate" "$(/usr/bin/grep -c -x 'will.terminate' "$LAUNCHTEST_LOG" | /usr/bin/grep -c -x 1)" "$(log_text)"
/usr/bin/pkill -f "$bundle/Scripts/LaunchTest.main.sh" 2>/dev/null

/bin/rm -rf "$work"
printf '%d passed, %d failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
exit 0
