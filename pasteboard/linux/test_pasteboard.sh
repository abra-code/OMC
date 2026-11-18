#!/bin/bash
# test_pasteboard.sh <pasteboard> - checks the Linux pasteboard tool (pasteboard/linux/pasteboard).
# Run on Linux: every check uses its own XDG_RUNTIME_DIR in a scratch folder, so the user's
# pasteboards are never touched.

tool="$1"
if [ -z "$tool" ] || [ ! -x "$tool" ]; then
    printf 'usage: test_pasteboard.sh <pasteboard tool>\n' >&2
    exit 2
fi

PASS=0
FAIL=0
pass() { printf 'ok   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; FAIL=$((FAIL + 1)); }
check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

scratch=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/pbtest.XXXXXX")
if [ -z "$scratch" ] || [ ! -d "$scratch" ]; then
    printf 'cannot make a scratch folder\n' >&2
    exit 2
fi
export XDG_RUNTIME_DIR="$scratch/run"
/bin/mkdir -m 700 "$XDG_RUNTIME_DIR"
unset OMC_TEST_PASTEBOARD_PREFIX
boards="$XDG_RUNTIME_DIR/omc-pasteboards"

# Run the tool, keeping stdout exactly (a trailing newline included) and the status
run() { # <args...>; sets out (with an "x" sentinel removed), err, rc
    local result=$("$tool" "$@" 2>"$scratch/err"; printf 'x%s' "$?")
    rc="${result##*x}"
    out="${result%x*}"
    err=$(/bin/cat "$scratch/err")
}

echo "== put and get =="
run Board1 set "hello world"
check "set exits 0" "0" "$rc"
run Board1 get
check "get prints the value, no newline added" "hello world" "$out"
check "get exits 0" "0" "$rc"
run Board1 put "via put"
run Board1 get
check "put is set" "via put" "$out"
printf 'line one\nline two\n' | "$tool" Board2 set
run Board2 get
check "set with no value stores stdin verbatim, newline and all" "line one
line two
" "$out"
run Never get
check "a board never written prints nothing" "" "$out"
check "and exits 0" "0" "$rc"
run Board1 set ""
run Board1 get
check "an empty string empties the board" "" "$out"
run Board3 set "a" "extra" "args"
run Board3 get
check "arguments past the value are ignored" "a" "$out"
check "the folder is made with mode 700" "700" "$(/usr/bin/stat -c '%a' "$boards")"

echo "== names =="
run "a/b" set "slash"
run "a_b" set "underscore"
run "a/b" get
check "a name with / is a board of its own" "slash" "$out"
run "a_b" get
check "and one that maps alike stays apart" "underscore" "$out"
run "../escape" set "x"
check "a name with .. stays in the folder" "" "$(/bin/ls "$XDG_RUNTIME_DIR" | /usr/bin/grep -v '^omc-pasteboards$')"
run "with space" set "s"
run "with space" get
check "a name with a space" "s" "$out"
run "$(printf 'new\nline')" set "nl"
run "$(printf 'new\nline')" get
check "a name with a newline" "nl" "$out"
run "caf$(printf '\303\251')" set "accent"
run "caf$(printf '\303\251')" get
check "a non-ASCII name" "accent" "$out"
run "Case" set "upper"
run "case" set "lower"
run "Case" get
check "names differing in case are two boards" "upper" "$out"
long=$(printf '%0100d' 0)
run "$long" set "long"
run "$long" get
check "a 100-character name" "long" "$out"
run "findSelection" set "named"
run "findSelection" get
check "a name starting with find is a named board" "named" "$out"
value=$(printf '%s' "$(/usr/bin/head -c 200000 /dev/zero | /usr/bin/tr '\0' 'v')")
printf '%s' "$value" | "$tool" Big set
run Big get
check "a 200 KB value from stdin" "200000" "${#out}"

echo "== errors =="
run
check "no arguments: status 255" "255" "$rc"
run OnlyName
check "a name with no operation: status 255" "255" "$rc"
run Board1 copy "x"
check "an unknown operation: status 255" "255" "$rc"
case "$err" in
    *"Unknown pasteboard operation"*) pass "with the macOS tool's message" ;;
    *) fail "with the macOS tool's message" "$err" ;;
esac
run general set "clip"
check "general without a test prefix is refused" "1" "$rc"
run find get
check "and so is find" "1" "$rc"

echo "== the test prefix =="
export OMC_TEST_PASTEBOARD_PREFIX="omcitest.1.abc"
run Board1 set "under test"
run general set "test clipboard"
run general get
check "with a prefix, general is the run's own board" "test clipboard" "$out"
unset OMC_TEST_PASTEBOARD_PREFIX
run Board1 get
check "a prefixed board does not reach the user's" "" "$out"
OMC_TEST_PASTEBOARD_PREFIX="omcitest.1.abc" run Board1 get
check "and reads back under the prefix" "under test" "$out"
OMC_TEST_PASTEBOARD_PREFIX="bad prefix" run Board9 set "x"
check "an unusable prefix: status 255" "255" "$rc"
OMC_TEST_PASTEBOARD_PREFIX="" run Board9 set "x"
check "an empty prefix: status 255" "255" "$rc"
run Board9 get
check "and nothing was written" "" "$out"

echo "== the folder =="
other="$scratch/other"
/bin/mkdir -m 700 "$other"
/bin/mkdir -m 700 "$scratch/target"
/bin/ln -s "$scratch/target" "$other/omc-pasteboards"
XDG_RUNTIME_DIR="$other" run Board1 set "x"
check "a link in place of the folder is refused" "1" "$rc"
check "and nothing is written through it" "" "$(/bin/ls "$scratch/target")"
nodir_tmp="$scratch/tmp"
/bin/mkdir -m 700 "$nodir_tmp"
XDG_RUNTIME_DIR="" TMPDIR="$nodir_tmp/" run Board1 set "fallback"
check "with no XDG_RUNTIME_DIR, a per-user folder in TMPDIR" "0" "$rc"
check "named with the user id" "yes" "$([ -d "$nodir_tmp/omc-pasteboards-$(/usr/bin/id -u)" ] && echo yes)"

override="$scratch/override/boards"
/bin/mkdir -p "$scratch/override"
OMC_PASTEBOARD_PATH="$override" run Board1 set "in the override"
OMC_PASTEBOARD_PATH="$override" run Board1 get
check "OMC_PASTEBOARD_PATH names the folder" "in the override" "$out"
check "made with mode 700" "700" "$(/usr/bin/stat -c '%a' "$override")"
check "and the board is a file there" "yes" "$([ -f "$override/Board1.plain" ] && echo yes)"

echo "== concurrent writers =="
i=0
while [ "$i" -lt 20 ]; do
    "$tool" Race set "value-$i-$(printf '%0500d' "$i")" &
    i=$((i + 1))
done
wait
run Race get
whole=no
i=0
while [ "$i" -lt 20 ]; do
    if [ "$out" = "value-$i-$(printf '%0500d' "$i")" ]; then
        whole=yes
    fi
    i=$((i + 1))
done
check "20 writers leave one whole value" "yes" "$whole"
check "and no temporary file" "" "$(/bin/ls "$boards" | /usr/bin/grep '\.tmp$')"

/bin/rm -rf "$scratch"
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
