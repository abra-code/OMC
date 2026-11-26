#!/bin/bash
# Linux/Tests/OMCITest/run.sh - the integration tests of OMC's test surface (OMCTestHost.h) on
# Linux: the fixture applet of Tools/omcitest_tests (ITestFixture: its Command.json, windows and
# scripts) made into a Linux applet bundle (Linux/make-applet-bundle.sh), and its *.itest.sh files
# run with AppletBuilder's harness (omcitest.sh, omcitest_rpc.py), each against a fresh applet
# process, as `appletbuilder itest` runs them on macOS.
#
# Usage: run.sh <the build's products folder> [--filter <glob>] [--keep] [--verbose]
#   The products folder is a debug build's (./build-linux.sh debug; release is its default): only
#   a debug build has the test surface (OMC_TEST_SURFACE). Needs python3 (the harness's bridge client) and a desktop session
#   (on the agent-vm box: GNOME's Wayland socket, set up below when WAYLAND_DISPLAY is unset).
#   The pasteboard tests drive the Linux pasteboard tool (pasteboard/linux/pasteboard, in the
#   bundle's Support folder), with the run's pasteboard prefix.
#   The fixture's end command reads its closed window with ActionUI's Linux shell client
#   (actionui_remote_linux.bash, from the ActionUI checkout beside this repo, as Package.swift
#   finds it), which needs OpenBSD netcat and coreutils timeout.
# Exit status: 0 all passed, 1 a test failed or the fixture could not be made, 2 bad arguments.

products=""
filter=""
while [ $# -gt 0 ]; do
    case "$1" in
        --filter)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'run.sh: --filter needs a glob\n' >&2
                exit 2
            fi
            filter="$2"
            shift 2
            ;;
        --keep) export OMCITEST_KEEP=1; shift ;;
        --verbose) export OMCITEST_VERBOSE=1; shift ;;
        -*) printf 'run.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
        *)
            if [ -n "$products" ]; then
                printf 'run.sh: one products folder only\n' >&2
                exit 2
            fi
            products="$1"
            shift
            ;;
    esac
done
if [ -z "$products" ] || [ ! -x "$products/CommandApplet" ]; then
    printf 'Usage: %s <the build'"'"'s products folder, holding CommandApplet> [--filter <glob>] [--keep] [--verbose]\n' "$0" >&2
    exit 2
fi

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
repo="$(CDPATH= cd -P -- "$here/../../.." && pwd)"
fixture="$repo/Tools/omcitest_tests/ITestFixture"
tests="$repo/Tools/omcitest_tests/Tests"
agents="$repo/Distribution/AppletBuilder.app/Contents/Resources/Agents"
python3="/usr/bin/python3"
if [ ! -x "$python3" ]; then
    printf 'run.sh: the harness needs %s\n' "$python3" >&2
    exit 1
fi
shell_client="$repo/../ActionUI/ActionUIRemote/Shell/actionui_remote_linux.bash"
for needed in "$fixture/Command.json" "$agents/omcitest.sh" "$agents/omcitest_rpc.py" "$agents/omctest.sh" "$shell_client"; do
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

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcitest-linux.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'run.sh: cannot create a work folder\n' >&2
    exit 1
fi

# The fixture's sources, with the Info.plist a Linux bundle needs (on macOS AppletBuilder's
# "ActionUI Window" template gives it)
source_folder="$work/ITestFixture-source"
/bin/mkdir -p "$source_folder"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run.sh: cannot make %s\n' "$source_folder" >&2
    exit 1
fi
/bin/cp -R "$fixture/Command.json" "$fixture/Base.lproj" "$fixture/Scripts" "$source_folder/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run.sh: cannot copy the fixture\n' >&2
    exit 1
fi
/bin/cat > "$source_folder/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>ITestFixture</string>
	<key>CFBundleIdentifier</key>
	<string>com.abracode.omc.itestfixture</string>
	<key>CFBundleName</key>
	<string>ITestFixture</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
</dict>
</plist>
PLIST
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run.sh: cannot write the fixture Info.plist\n' >&2
    exit 1
fi
app="$work/ITestFixture.app"
/bin/bash "$repo/Linux/make-applet-bundle.sh" "$products" "$source_folder" "$app"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run.sh: cannot make the fixture applet (make-applet-bundle.sh status %s)\n' "$status" >&2
    exit 1
fi

results="$work/results"
: > "$results"
matched=0
for test_file in "$tests"/*.itest.sh; do
    if [ ! -f "$test_file" ]; then
        continue
    fi
    base="$(/usr/bin/basename "$test_file")"
    if [ -n "$filter" ]; then
        case "$base" in
            $filter) ;;
            *) continue ;;
        esac
    fi
    matched=$((matched + 1))
    # Its own bash process per file, as `appletbuilder itest` runs them
    OMCITEST_PYTHON="$python3" OMCITEST_RPC="$agents/omcitest_rpc.py" OMCITEST_RESULTS="$results" \
        ITEST_SHELL_CLIENT="$shell_client" \
        /bin/bash -c 'source "$1"; omcitest_run_file "$2" "$3"' omcitest "$agents/omcitest.sh" "$app" "$test_file"
done

passed=0
failed=0
count=0
while read -r p f name; do
    if [ -z "$name" ]; then
        continue
    fi
    count=$((count + 1))
    passed=$((passed + p))
    failed=$((failed + f))
done < "$results"
if [ "$count" -lt "$matched" ]; then
    failed=$((failed + matched - count))
    printf 'run.sh: %s file(s) reported no result\n' "$((matched - count))" >&2
fi
printf '%d passed, %d failed, %d files\n' "$passed" "$failed" "$matched"
if [ "${OMCITEST_KEEP:-0}" != "1" ] && [ "$failed" -eq 0 ]; then
    /bin/rm -rf -- "$work"
else
    printf 'kept: %s\n' "$work" >&2
fi
if [ "$failed" -ne 0 ] || [ "$matched" -eq 0 ]; then
    exit 1
fi
exit 0
