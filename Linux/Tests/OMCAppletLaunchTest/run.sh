#!/bin/bash
# Linux/Tests/OMCAppletLaunchTest/run.sh - the Linux applet's app shell end to end
# (AbracodeFramework/EntryPoints/Linux/OMCAppletMain.cpp): a flat bundle made of the fixture
# LaunchTest.app, the built applet executable and a resource-only Frameworks/Abracode.framework
# with the built support tools (the layout of Platform/Linux/OMCEngineBundle.cpp), launched in the
# desktop session, with its commands logging what ran to a file.
#
# Usage: run.sh <the build's products folder, holding OMCApplet and the tools>
# Needs a desktop session (on the agent-vm box: GNOME's Wayland socket, set up below when
# WAYLAND_DISPLAY is unset). Exit status: 0 all passed, 1 a check failed, 2 bad arguments.

products="$1"
applet_executable="$products/OMCApplet"
if [ -z "$products" ] || [ ! -x "$applet_executable" ]; then
    printf 'Usage: %s <the build'"'"'s products folder, holding OMCApplet>\n' "$0" >&2
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
/bin/cp -R "$here/LaunchTest.app" "$bundle"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot copy the fixture\n' >&2
    exit 1
fi
/bin/cp "$applet_executable" "$bundle/LaunchTest"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot copy the applet executable\n' >&2
    exit 1
fi
/bin/chmod +x "$bundle/LaunchTest" "$bundle/Scripts/"*.sh
framework="$bundle/Frameworks/Abracode.framework"
/bin/mkdir -p "$framework/Support"
/bin/cp "$here/Abracode.framework/Info.plist" "$framework/Info.plist"
for tool in omc_dialog_control omc_next_command plister b64 filt loco; do
    if [ -x "$products/$tool" ]; then
        /bin/cp "$products/$tool" "$framework/Support/$tool"
    fi
done
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
