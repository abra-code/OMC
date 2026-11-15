#!/bin/bash
# Linux/Tests/OMCPythonAppletTest/run.sh - a Linux applet with an embedded Python: the fixture
# PythonTest.app made into a bundle with Linux/make-applet-bundle.sh --python (the Linux Python in
# Contents/Library/Python, omc.py and actionui_remote.py from AppletBuilder's Library/Packages in
# Contents/Library/Packages), launched in the desktop session, its commands logging what they ran
# on to a file.
#
# Checks: a .py command runs on the embedded interpreter, with Library/Packages on sys.path, a
# bytecode cache outside the bundle, the bundled OpenSSL and the system's CA certificates; a .sh
# command's python3 is the embedded one; omc.py works an open window over the ActionUI remote
# bridge from the embedded python3, and a .py END_OK handler reads the value; --python refuses a
# missing or non-ELF Python.
#
# Usage: run.sh <the build's products folder, holding CommandApplet> <a Linux Python folder>
#   The Python folder is a relocatable Linux build (Python-Embedding's build-embedded-python.sh),
#   for the architecture of CommandApplet. Needs a desktop session (on the agent-vm box: GNOME's
#   Wayland socket, set up below when WAYLAND_DISPLAY is unset).
# Exit status: 0 all passed, 1 a check failed, 2 bad arguments.

products="$1"
python_folder="$2"
applet_executable="$products/CommandApplet"
if [ -z "$products" ] || [ ! -x "$applet_executable" ] || [ -z "$python_folder" ] || [ ! -x "$python_folder/bin/python3" ]; then
    printf 'Usage: %s <the build'"'"'s products folder, holding CommandApplet> <a Linux Python folder, holding bin/python3>\n' "$0" >&2
    exit 2
fi

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
repo="$(CDPATH= cd -P -- "$here/../../.." && pwd)"
make_bundle="$repo/Linux/make-applet-bundle.sh"
packages="$repo/Distribution/AppletBuilder.app/Contents/Library/Packages"
for needed in "$packages/omc.py" "$packages/actionui_remote.py" "$make_bundle"; do
    if [ ! -f "$needed" ]; then
        printf 'run.sh: missing %s\n' "$needed" >&2
        exit 1
    fi
done

uid="$(/usr/bin/id -u)"
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export WAYLAND_DISPLAY=wayland-0
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
fi
export SWIFT_BACKTRACE=enable=no
# The applet under test is not on the desktop's app list: no first-launch question, which would keep
# it from quitting once idle (Platform/Linux/OMCDesktopRegistration.h)
export COMMAND_ENGINE_NO_DESKTOP_PROMPT=1

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
work="$HOME/.omc-python-test-$$"
/bin/mkdir -p "$work"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make %s\n' "$work" >&2
    exit 1
fi
export PYTHONTEST_LOG="$work/log"
# The desktop's recent files (recently-used.xbel) in the work folder, not the session's own list
export XDG_DATA_HOME="$work/data"

# Waits up to <seconds> for the process to end; sets result to its exit status, or "running" (then
# it is killed). Not in a $(...) subshell, which cannot wait for this shell's children.
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
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    result=running
}

# Waits up to <seconds> for a log line starting with <key>:, then prints the rest of the first
# such line; prints nothing when none came
wait_for_key() { # <key> <seconds>
    local tenths=$(( $2 * 10 ))
    local waited=0
    local line
    while [ "$waited" -lt "$tenths" ]; do
        if [ -f "$PYTHONTEST_LOG" ]; then
            while IFS= read -r line; do
                case "$line" in
                    "$1:"*)
                        printf '%s' "${line#"$1:"}"
                        return
                        ;;
                esac
            done < "$PYTHONTEST_LOG"
        fi
        /bin/sleep 0.1
        waited=$((waited + 1))
    done
}

log_text() { /bin/cat "$PYTHONTEST_LOG" 2>/dev/null | /usr/bin/tr '\n' ' '; }

printf '== make-applet-bundle.sh --python refuses what is not a Linux Python ==\n'
# The real interpreter of the given Python, for the virtual-environment case below
embedded_source_python="$(/usr/bin/readlink -f -- "$python_folder/bin/python3")"
/bin/bash "$make_bundle" --python "$work/no-such-python" "$products" "$here/PythonTest.app" "$work/Refused.app" 2> /dev/null
status=$?
check "a missing Python folder: bad arguments (2)" "$([ "$status" = "2" ] && echo 1 || echo 0)" "status $status"
/bin/mkdir -p "$work/script-python/bin"
printf '#!/bin/sh\necho not python\n' > "$work/script-python/bin/python3"
/bin/chmod 755 "$work/script-python/bin/python3"
/bin/bash "$make_bundle" --python "$work/script-python" "$products" "$here/PythonTest.app" "$work/Refused.app" 2> /dev/null
status=$?
check "a bin/python3 that is not ELF: refused (1), no bundle made" "$([ "$status" = "1" ] && [ ! -e "$work/Refused.app" ] && echo 1 || echo 0)" "status $status"
# A virtual environment: bin/python3 links to the system's interpreter, outside the folder
/bin/mkdir -p "$work/venv-python/bin"
/bin/ln -s "$embedded_source_python" "$work/venv-python/bin/python3"
/bin/bash "$make_bundle" --python "$work/venv-python" "$products" "$here/PythonTest.app" "$work/Refused.app" 2> /dev/null
status=$?
check "a bin/python3 leading outside the folder (a virtual environment): refused (1)" "$([ "$status" = "1" ] && [ ! -e "$work/Refused.app" ] && echo 1 || echo 0)" "status $status"

printf '== the bundle ==\n'
# The fixture with the Python modules an applet carries (AppletBuilder copies them in on macOS)
source_app="$work/source/PythonTest.app"
/bin/mkdir -p "$work/source"
/bin/cp -R -- "$here/PythonTest.app" "$work/source/"
status=$?
/bin/mkdir -p "$source_app/Contents/Library/Packages"
/bin/cp -- "$packages/omc.py" "$packages/actionui_remote.py" "$source_app/Contents/Library/Packages/"
copy_status=$?
if [ "$status" -ne 0 ] || [ "$copy_status" -ne 0 ]; then
    printf 'cannot copy the fixture applet\n' >&2
    exit 1
fi
bundle="$work/PythonTest.app"
/bin/bash "$make_bundle" --python "$python_folder" "$products" "$source_app" "$bundle"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'cannot make the applet bundle (make-applet-bundle.sh status %s)\n' "$status" >&2
    exit 1
fi
applet="$bundle/Contents/Linux/PythonTest"
embedded="$bundle/Contents/Library/Python"
check "the Python is in Contents/Library/Python" "$([ -x "$embedded/bin/python3" ] && echo 1 || echo 0)"
check "bin/python3 stays a symbolic link" "$([ -L "$embedded/bin/python3" ] && echo 1 || echo 0)"
# Every path the scripts log is resolved (os.path.realpath)
embedded_python="$(/usr/bin/readlink -f -- "$embedded/bin/python3")"
embedded_prefix="$(/usr/bin/readlink -f -- "$embedded")"
bundle_real="$(/usr/bin/readlink -f -- "$bundle")"

printf '== a .py command runs on the embedded Python ==\n'
: > "$PYTHONTEST_LOG"
"$applet" 'pythontest://exe?commandID=pt.python' 2> "$work/python.err" &
pid=$!
value="$(wait_for_key py.omc 15)"
check "the .py command ran" "$([ -n "$value" ] && echo 1 || echo 0)" "$(log_text) $(/usr/bin/tr '\n' ' ' < "$work/python.err" | /usr/bin/cut -c1-300)"
value="$(wait_for_key py.executable 1)"
check "sys.executable is the bundle's python3" "$([ "$value" = "$embedded_python" ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.prefix 1)"
check "sys.prefix is the bundle's Python" "$([ "$value" = "$embedded_prefix" ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.packages-on-path 1)"
check "Contents/Library/Packages is on sys.path" "$([ "$value" = "yes" ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.pycache-prefix 1)"
check "a bytecode cache prefix outside the bundle" "$([ -n "$value" ] && [ "${value#"$bundle_real"}" = "$value" ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.openssl 1)"
check "the ssl module loads (bundled OpenSSL)" "$([ "${value#OpenSSL }" != "$value" ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.ca-certificates 1)"
case "$value" in
    ''|*[!0-9]*) ca_count=0 ;; # not a count: fails the check
    *) ca_count="$value" ;;
esac
check "the default SSL context has the system's CA certificates" "$([ "$ca_count" -gt 0 ] && echo 1 || echo 0)" "$value"
value="$(wait_for_key py.omc 1)"
check "import omc finds the bundle's omc.py" "$([ "$value" = "$bundle_real/Contents/Library/Packages/omc.py" ] && echo 1 || echo 0)" "$value"
wait_for_exit "$pid" 20
check "and the applet quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== a .sh command'"'"'s python3 is the embedded one ==\n'
: > "$PYTHONTEST_LOG"
"$applet" 'pythontest://exe?commandID=pt.shell' &
pid=$!
value="$(wait_for_key sh.python3 15)"
check "python3 in a .sh script is the bundle's" "$([ "$value" = "$embedded_python" ] && echo 1 || echo 0)" "$value"
wait_for_exit "$pid" 20
check "and the applet quits once idle" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

printf '== omc.py on the embedded Python works an open window over the remote bridge ==\n'
: > "$PYTHONTEST_LOG"
"$applet" 'pythontest://exe?commandID=pt.window' 2> "$work/window.err" &
pid=$!
value="$(wait_for_key window.worker.python3 15)"
check "the window's worker runs on the bundle's python3" "$([ "$value" = "$embedded_python" ] && echo 1 || echo 0)" "$value $(log_text)"
value="$(wait_for_key window.worker.read 5)"
check "omc.window().get_string reads the field" "$([ "$value" = "initial" ] && echo 1 || echo 0)" "$(log_text) $(/usr/bin/tr '\n' ' ' < "$work/window.err" | /usr/bin/cut -c1-300)"
value="$(wait_for_key window.ok.env 10)"
check "set_string and terminate_ok: the .py END_OK handler gets the new value" "$([ "$value" = "initial via omc.py" ] && echo 1 || echo 0)" "$(log_text)"
value="$(wait_for_key window.ok.omc 1)"
check "and omc.context().view_value gives it too" "$([ "$value" = "initial via omc.py" ] && echo 1 || echo 0)" "$value"
wait_for_exit "$pid" 20
check "then, with no window left, the applet quits by itself" "$([ "$result" = "0" ] && echo 1 || echo 0)" "exit: $result"

/bin/rm -rf "$work"
printf '%d passed, %d failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
    exit 1
fi
exit 0
