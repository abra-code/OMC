#!/bin/bash
# Tools/omcitest_tests/run_fixture.sh - runs integration tests (`appletbuilder itest`) against a
# signed copy of an applet, optionally with an engine you just built:
# - by default the ITestFixture applet, built from AppletBuilder's "ActionUI Window" template and the
#   sources beside this script, with Tests/*.itest.sh here: the end-to-end check of the
#   integration-test surface (OMCTestHost) and its harness (omcitest.sh);
# - with --app, any applet: a copy of it, so the applet in its repository is never re-signed or
#   changed, with the *.itest.sh files of the Tests folder beside it (or --tests).
#
# Usage: run_fixture.sh [--app <App.app> [--tests <dir>]] [--framework <Abracode.framework>]
#                       [--filter <glob>] [--keep] [--verbose]
#   --app        test a copy of this applet instead of the fixture
#   --tests      the folder of *.itest.sh files (default: the Tests folder beside --app)
#   --framework  put this engine into the applet instead of the one it carries (an engine you just
#                built, e.g. DerivedData/.../Build/Products/Release/Abracode.framework; build it with
#                the "OMC Distribution" scheme, the others link the undefined-behavior sanitizer)
#   --filter     run only the test files whose name matches the glob
#   --keep       keep the applet copy and each test's private folder, and print where they are
#   --verbose    print the applet's output after each test file
#
# Runs real windows on the screen. In an agent session it needs the sandbox off (Unix sockets).
# Exit status: 0 all passed, 1 a test failed or the applet could not be built, copied or signed,
# 2 bad arguments.

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname "$0")" && pwd)"
repo="$(CDPATH= cd -P -- "$here/../.." && pwd)"
appletbuilder="$repo/Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder"
codesign_applet="$repo/Distribution/Scripts/codesign_applet.sh"

framework=""
source_app=""
tests=""
filter=""
keep=0
itest_options=""
while [ $# -gt 0 ]; do
    case "$1" in
        --framework|--app|--tests|--filter)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'run_fixture: %s needs a value\n' "$1" >&2
                exit 2
            fi
            case "$1" in
                --framework) framework="$2" ;;
                --app) source_app="${2%/}" ;;
                --tests) tests="${2%/}" ;;
                --filter) filter="$2" ;;
            esac
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
if [ -n "$source_app" ] && [ ! -d "$source_app/Contents" ]; then
    printf 'run_fixture: not an applet bundle: %s\n' "$source_app" >&2
    exit 2
fi
if [ -z "$source_app" ] && [ -n "$tests" ]; then
    printf 'run_fixture: --tests goes with --app\n' >&2
    exit 2
fi
if [ -n "$source_app" ] && [ -z "$tests" ]; then
    tests="$(/usr/bin/dirname "$source_app")/Tests"
fi
if [ -z "$source_app" ]; then
    tests="$here/Tests"
fi
if [ ! -d "$tests" ]; then
    printf 'run_fixture: no tests folder: %s\n' "$tests" >&2
    exit 2
fi

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omcitest-fixture.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'run_fixture: cannot create a work folder\n' >&2
    exit 1
fi

if [ -n "$source_app" ]; then
    app="$work/$(/usr/bin/basename "$source_app")"
    /usr/bin/ditto "$source_app" "$app"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'run_fixture: cannot copy %s\n' "$source_app" >&2
        exit 1
    fi
else
    "$appletbuilder" create --template "ActionUI Window" --name ITestFixture --dest "$work" > /dev/null
    status=$?
    app="$work/ITestFixture.app"
    if [ "$status" -ne 0 ] || [ ! -d "$app" ]; then
        printf 'run_fixture: appletbuilder create failed (%s)\n' "$status" >&2
        exit 1
    fi

    # Handler scripts need no executable bit: the engine runs each through the interpreter its
    # extension names.
    resources="$app/Contents/Resources"
    /bin/rm -f "$resources/Scripts/"*.sh
    /bin/cp "$here/ITestFixture/Command.json" "$resources/Command.json"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'run_fixture: cannot copy Command.json\n' >&2
        exit 1
    fi
    /bin/cp "$here/ITestFixture/Base.lproj/"*.json "$resources/Base.lproj/"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'run_fixture: cannot copy the window descriptions (Base.lproj)\n' >&2
        exit 1
    fi
    /bin/cp "$here/ITestFixture/Scripts/"*.sh "$resources/Scripts/"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'run_fixture: cannot copy the scripts\n' >&2
        exit 1
    fi
fi

if [ -n "$framework" ]; then
    # Moved aside, not merged into: the engine has to be exactly the one given.
    if [ -d "$app/Contents/Frameworks/Abracode.framework" ]; then
        /bin/mv "$app/Contents/Frameworks/Abracode.framework" "$work/Abracode.framework.from-applet"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'run_fixture: cannot move the applet'"'"'s own engine aside\n' >&2
            exit 1
        fi
    fi
    /bin/mkdir -p "$app/Contents/Frameworks"
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
    printf 'run_fixture: the applet does not verify after signing; see %s\n' "$work/codesign.log" >&2
    exit 1
fi

# A framework from `xcodebuild test` is built with code coverage (the test plan gathers it), and
# so are its helper tools. With no LLVM_PROFILE_FILE, an instrumented tool a test script runs
# writes default.profraw into its working folder, which is the caller's: the repository root, say.
# Their counters go to the work folder instead, removed with it.
export LLVM_PROFILE_FILE="$work/profraw/%p.profraw"

# shellcheck disable=SC2086
if [ -n "$filter" ]; then
    "$appletbuilder" itest "$app" --tests "$tests" --filter "$filter" $itest_options
    status=$?
else
    "$appletbuilder" itest "$app" --tests "$tests" $itest_options
    status=$?
fi

if [ "$keep" -eq 1 ]; then
    printf 'kept the applet: %s\n' "$app" >&2
else
    /bin/rm -rf "$work"
fi
exit "$status"
