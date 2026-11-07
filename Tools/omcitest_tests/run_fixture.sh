#!/bin/bash
# Tools/omcitest_tests/run_fixture.sh - builds the ITestFixture applet from AppletBuilder's
# "ActionUI Window" template and the sources beside this script, then runs Tests/*.itest.sh against
# it with `appletbuilder itest`: the end-to-end check of the integration-test surface (OMCTestHost)
# and its harness (omcitest.sh).
#
# Usage: run_fixture.sh [--framework <Abracode.framework>] [--keep] [--verbose]
#   --framework  put this engine into the applet instead of AppletBuilder's (an engine you just
#                built, e.g. DerivedData/.../Build/Products/Release/Abracode.framework; build it with
#                the "OMC Distribution" scheme, the others link the undefined-behavior sanitizer)
#   --keep       keep the built applet and each test's private folder, and print where they are
#   --verbose    print the applet's output after each test file
#
# Runs real windows on the screen. In an agent session it needs the sandbox off (Unix sockets).
# Exit status: 0 all passed, 1 a test failed or the fixture could not be built, 2 bad arguments.

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(CDPATH= cd -P -- "$here/../.." && pwd)"
appletbuilder="$repo/Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder"
codesign_applet="$repo/Distribution/Scripts/codesign_applet.sh"

framework=""
keep=0
itest_options=""
while [ $# -gt 0 ]; do
    case "$1" in
        --framework)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'run_fixture: --framework needs a path\n' >&2
                exit 2
            fi
            framework="$2"
            shift 2
            ;;
        --keep) keep=1; itest_options="$itest_options --keep"; shift ;;
        --verbose) itest_options="$itest_options --verbose"; shift ;;
        *) printf 'run_fixture: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
if [ -n "$framework" ] && [ ! -f "$framework/Versions/A/Abracode" ]; then
    printf 'run_fixture: not an Abracode.framework: %s\n' "$framework" >&2
    exit 2
fi

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcitest-fixture.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'run_fixture: cannot create a work folder\n' >&2
    exit 1
fi

"$appletbuilder" create --template "ActionUI Window" --name ITestFixture --dest "$work" > /dev/null
status=$?
app="$work/ITestFixture.app"
if [ "$status" -ne 0 ] || [ ! -d "$app" ]; then
    printf 'run_fixture: appletbuilder create failed (%s)\n' "$status" >&2
    exit 1
fi

resources="$app/Contents/Resources"
/bin/rm -f "$resources/Scripts/"*.sh
/bin/cp "$here/ITestFixture/Command.json" "$resources/Command.json"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run_fixture: cannot copy Command.json\n' >&2
    exit 1
fi
/bin/cp "$here/ITestFixture/Base.lproj/Window.json" "$resources/Base.lproj/Window.json"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run_fixture: cannot copy Window.json\n' >&2
    exit 1
fi
/bin/cp "$here/ITestFixture/Scripts/"*.sh "$resources/Scripts/"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run_fixture: cannot copy the scripts\n' >&2
    exit 1
fi
/bin/chmod +x "$resources/Scripts/"*.sh

if [ -n "$framework" ]; then
    /bin/mv "$app/Contents/Frameworks/Abracode.framework" "$work/Abracode.framework.from-template"
    /usr/bin/ditto "$framework" "$app/Contents/Frameworks/Abracode.framework"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'run_fixture: cannot copy %s\n' "$framework" >&2
        exit 1
    fi
fi

# Ad hoc, without the hardened runtime: the signature the test surface is allowed for.
/bin/bash "$codesign_applet" --brief "$app" "-" > "$work/codesign.log" 2>&1
/usr/bin/codesign --verify --deep --strict "$app"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'run_fixture: the fixture does not verify after signing; see %s\n' "$work/codesign.log" >&2
    exit 1
fi

# shellcheck disable=SC2086
"$appletbuilder" itest "$app" --tests "$here/Tests" $itest_options
status=$?

if [ "$keep" -eq 1 ]; then
    printf 'kept the fixture: %s\n' "$app" >&2
else
    /bin/rm -rf "$work"
fi
exit "$status"
