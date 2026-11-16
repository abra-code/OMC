#!/bin/bash
# Linux/Packaging/check-swift-runtime-tests.sh - the second check before a new Swift patch release
# goes into the folder of its minor release (Linux/Packaging/swift-runtime-versions, "rolling"): runs
# the tests of earlier engine releases, from their tests archives (make-tests-archive.sh,
# published beside each release), on the candidate runtime.
#
# The first gate, check-swift-runtime-abi.sh, finds removed symbols; this one finds what keeps every
# symbol and still breaks (a changed type layout, changed behavior). Failing either means the minor
# release's folder stays at its current release for good ("<minor> frozen <current release>" in
# swift-runtime-versions).
#
# Usage: check-swift-runtime-tests.sh [--python <Linux Python folder>] <candidate runtime folder>
#                                      <tests archive>...
#   The candidate folder holds the runtime libraries (a toolchain's /usr/lib/swift/linux, or a
#   candidate runtime package unpacked with dpkg-deb -x). Each archive is unpacked into a new folder in
#   the home folder (the engine refuses private folders on paths others can write to, like /tmp) and
#   its run-tests.sh runs with --runtime <candidate>; a passing archive's folder is removed, a failing
#   one's is kept and named. --python passes a Linux Python to the archives' embedded Python test.
#   Needs a desktop session (see run-tests.sh).
# Exit status: 0 every archive passed, 1 an archive failed or could not be unpacked, 2 bad arguments.

python_args=()
if [ $# -ge 2 ] && [ "$1" = "--python" ]; then
    # Checked here: run-tests.sh would refuse it for every archive, which reads as a failed gate
    if [ ! -x "$2/bin/python3" ]; then
        printf 'No bin/python3 in %s\n' "$2" >&2
        exit 2
    fi
    python_args=(--python "$2")
    shift 2
fi
if [ $# -lt 2 ]; then
    printf 'Usage: %s [--python <Linux Python folder>] <candidate runtime folder> <tests archive>...\n' "$0" >&2
    exit 2
fi
candidate_given="$1"
shift
candidate="$(CDPATH= cd -P -- "$candidate_given" 2>/dev/null && pwd)"
if [ -z "$candidate" ] || [ ! -f "$candidate/libswiftCore.so" ]; then
    printf 'No libswiftCore.so in %s\n' "$candidate_given" >&2
    exit 2
fi
for archive in "$@"; do
    if [ ! -f "$archive" ]; then
        printf 'No tests archive %s\n' "$archive" >&2
        exit 2
    fi
done

summary=""
failed=0
for archive in "$@"; do
    work="$(/usr/bin/mktemp -d "$HOME/runtime-gate.XXXXXX")"
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$work" ]; then
        printf 'Cannot make a work folder in %s\n' "$HOME" >&2
        exit 1
    fi
    /usr/bin/tar -C "$work" -xzf "$archive"
    status=$?
    if [ "$status" -ne 0 ]; then
        summary="${summary}FAIL $archive: cannot unpack (tar status $status), in $work
"
        failed=$((failed + 1))
        continue
    fi
    kit=""
    for folder in "$work"/command-engine-tests-*; do
        if [ -x "$folder/run-tests.sh" ]; then
            kit="$folder"
        fi
    done
    if [ -z "$kit" ]; then
        summary="${summary}FAIL $archive: no command-engine-tests-*/run-tests.sh in it, in $work
"
        failed=$((failed + 1))
        continue
    fi
    printf '\n######## %s on %s ########\n' "${kit##*/}" "$candidate"
    /bin/bash "$kit/run-tests.sh" --runtime "$candidate" "${python_args[@]}"
    status=$?
    if [ "$status" -eq 0 ]; then
        summary="${summary}ok   ${kit##*/}
"
        /bin/rm -rf -- "$work"
    else
        summary="${summary}FAIL ${kit##*/} (status $status), kept in $work
"
        failed=$((failed + 1))
    fi
done

printf '\n======== The candidate runtime %s ========\n%s' "$candidate" "$summary"
if [ "$failed" -ne 0 ]; then
    printf 'Do not put this release into the minor release'"'"'s folder: freeze it (swift-runtime-versions) or find the cause.\n'
    exit 1
fi
exit 0
