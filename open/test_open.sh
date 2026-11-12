#!/bin/bash
# test_open.sh <open> <plister> - checks the open tool (open/open). The argument checks run on both
# systems; on Linux also -a (an executable, an applet bundle, a command on PATH), opening an applet
# bundle, and -R (needs a desktop session: the file manager's D-Bus service). Programs started
# here are recorders that write the arguments they got, so no real application is opened.

open_tool="$1"
plister_tool="$2"
if [ -z "$open_tool" ] || [ ! -f "$open_tool" ] || [ -z "$plister_tool" ] || [ ! -x "$plister_tool" ]; then
    printf 'usage: test_open.sh <open> <plister>\n' >&2
    exit 2
fi

PASS=0
FAIL=0
pass() { printf 'ok   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; FAIL=$((FAIL + 1)); }
check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

scratch=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/opentest.XXXXXX")
if [ -z "$scratch" ] || [ ! -d "$scratch" ]; then
    printf 'cannot make a scratch folder\n' >&2
    exit 2
fi
# The tool beside a plister, as in the framework's Support folder
support="$scratch/Support"
/bin/mkdir -p "$support"
/bin/cp "$open_tool" "$support/open"
/bin/cp "$plister_tool" "$support/plister"
/bin/chmod 755 "$support/open" "$support/plister"
tool="$support/open"

run() { # <args...>; sets rc and err
    "$tool" "$@" > /dev/null 2> "$scratch/err"
    rc=$?
    err=$(/bin/cat "$scratch/err")
}

echo "== arguments (both systems) =="
run
check "no arguments: status 2" "2" "$rc"
run -R
check "-R with nothing to show: status 2" "2" "$rc"
run -a
check "-a with no application: status 2" "2" "$rc"
run -e "$scratch"
check "an option this open does not take: status 2" "2" "$rc"
run "$scratch/missing file"
check "a file that is not there: status 1" "1" "$rc"
case "$err" in
    *"does not exist"*) pass "with macOS's message" ;;
    *) fail "with macOS's message" "$err" ;;
esac
run -R "$scratch/missing file"
check "-R of a file that is not there: status 1" "1" "$rc"
run -a "no-such-application-$$"
check "-a with an application that is not there: status 1" "1" "$rc"

case "${OSTYPE:-}" in
    linux*) ;;
    *)
        /bin/rm -rf "$scratch"
        printf '%d passed, %d failed (the rest runs on Linux)\n' "$PASS" "$FAIL"
        [ "$FAIL" -eq 0 ]
        exit $?
        ;;
esac

# A recorder: writes its arguments, one per line, to $OPEN_TEST_RECORD
recorder="$scratch/recorder"
printf '#!/bin/sh\nprintf "%%s\\n" "started" "$@" > "$OPEN_TEST_RECORD.tmp" && /bin/mv "$OPEN_TEST_RECORD.tmp" "$OPEN_TEST_RECORD"\n' > "$recorder"
/bin/chmod 755 "$recorder"
export OPEN_TEST_RECORD="$scratch/record"

# Waits up to 5 seconds for the recorder (it runs detached) and prints what it wrote
recorded() {
    local tries=0
    while [ ! -f "$OPEN_TEST_RECORD" ] && [ "$tries" -lt 50 ]; do
        /bin/sleep 0.1
        tries=$((tries + 1))
    done
    if [ -f "$OPEN_TEST_RECORD" ]; then
        /bin/cat "$OPEN_TEST_RECORD"
        /bin/rm -f "$OPEN_TEST_RECORD"
    fi
}

echo "== -a (Linux) =="
: > "$scratch/one.txt"
: > "$scratch/two words.txt"
run -a "$recorder" "$scratch/one.txt" "$scratch/two words.txt"
check "-a with an executable: status 0" "0" "$rc"
check "it gets the files' paths" "started
$scratch/one.txt
$scratch/two words.txt" "$(recorded)"
(cd "$scratch" && "$tool" -a "$recorder" one.txt)
check "a relative path is made absolute" "started
$scratch/one.txt" "$(recorded)"
run -a "$recorder"
check "-a with no file just starts it" "started" "$(recorded)"

bundle="$scratch/Recorder Test.app"
/bin/mkdir -p "$bundle/Contents/Linux"
/bin/cp "$recorder" "$bundle/Contents/Linux/RecorderTest"
"$plister_tool" set dict "$bundle/Contents/Info.plist" / > /dev/null
"$plister_tool" insert CFBundleExecutable string RecorderTest "$bundle/Contents/Info.plist" / > /dev/null
run -a "$bundle" "$scratch/one.txt"
check "-a with an applet bundle: status 0" "0" "$rc"
check "its Contents/Linux executable gets the file" "started
$scratch/one.txt" "$(recorded)"
run "$bundle"
check "opening an applet bundle runs it" "started" "$(recorded)"
/bin/mkdir -p "$scratch/Empty.app/Contents"
run -a "$scratch/Empty.app"
check "a bundle with no Linux executable: status 1" "1" "$rc"

/bin/mkdir -p "$scratch/bin"
/bin/cp "$recorder" "$scratch/bin/recorder-on-path"
PATH="$scratch/bin:$PATH" run -a recorder-on-path "$scratch/one.txt"
check "-a with a command on PATH" "started
$scratch/one.txt" "$(recorded)"
run -a fail
check "-a with a shell function's name (no file on PATH): status 1" "1" "$rc"
env_recorder="$scratch/env-recorder"
printf '#!/bin/sh\nprintf "%%s\\n" "started" "mark=${OMC_TEST_MARK:-none}" "other=${OPEN_TEST_OTHER:-none}" > "$OPEN_TEST_RECORD.tmp" && /bin/mv "$OPEN_TEST_RECORD.tmp" "$OPEN_TEST_RECORD"\n' > "$env_recorder"
/bin/chmod 755 "$env_recorder"
OMC_TEST_MARK="from the caller" OPEN_TEST_OTHER="kept" run -a "$env_recorder"
check "what it starts gets no OMC_ variable, and the rest of the environment" "started
mark=none
other=kept" "$(recorded)"

echo "== -R (Linux, desktop session) =="
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    run -R "$scratch/two words.txt"
    check "-R shows a file: status 0" "0" "$rc"
else
    printf '     (no D-Bus session: -R not checked)\n'
fi

/bin/rm -rf "$scratch"
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
