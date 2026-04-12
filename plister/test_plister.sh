#!/bin/bash
#
# test_plister.sh — exercises plister commands including JSON support
# Usage: ./test_plister.sh /path/to/plister

PLISTER="${1:?Usage: $0 /path/to/plister}"

if [ ! -x "$PLISTER" ]; then
    echo "Error: '$PLISTER' is not executable" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Warning: python3 not found — JSON validation tests will be skipped" >&2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Run plister and compare stdout to expected string
check() {
    local desc="$1" expected="$2"
    shift 2
    local actual
    actual=$("$PLISTER" "$@" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        printf '      expected: %s\n' "$expected"
        printf '      actual:   %s\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

# Run plister command that must exit 0
ok() {
    local desc="$1"
    shift
    if "$PLISTER" "$@" >/dev/null 2>&1; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (plister exited non-zero for: $*)"
        FAIL=$((FAIL + 1))
    fi
}

# Run plister command that must exit non-zero
nok() {
    local desc="$1"
    shift
    if "$PLISTER" "$@" >/dev/null 2>&1; then
        echo "FAIL: $desc (expected non-zero exit, got success)"
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

# Check that a file is valid JSON
check_json() {
    local desc="$1" file="$2"
    if ! command -v python3 >/dev/null 2>&1; then
        # python3 not available — skip JSON validation but don't fail
        echo "SKIP: $desc (python3 not available)"
        return
    fi
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$file" 2>/dev/null; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (not valid JSON: $file)"
        FAIL=$((FAIL + 1))
    fi
}

# ─── Plist: basic scalar types ────────────────────────────────────────────────

PLIST="$TMP/test.plist"

echo
echo "=== Plist: basic scalar types ==="

ok    "set dict creates root"              set dict    "$PLIST" /
ok    "insert string"                      insert Name   string  "Alice"   "$PLIST" /
ok    "insert integer"                     insert Age    integer 30         "$PLIST" /
ok    "insert real"                        insert Score  real    9.5        "$PLIST" /
ok    "insert bool true"                   insert Active bool    true       "$PLIST" /
ok    "insert bool false"                  insert Hidden bool    false      "$PLIST" /

check "get string via get string"          "Alice"     get string  "$PLIST" /Name
check "get string via get value"           "Alice"     get value   "$PLIST" /Name
check "get integer"                        "30"        get value   "$PLIST" /Age
check "get real"                           "9.500000"  get value   "$PLIST" /Score
check "get bool true"                      "true"      get value   "$PLIST" /Active
check "get bool false"                     "false"     get value   "$PLIST" /Hidden

check "get type string"                    "string"    get type    "$PLIST" /Name
check "get type integer"                   "integer"   get type    "$PLIST" /Age
check "get type real"                      "real"      get type    "$PLIST" /Score
check "get type bool"                      "bool"      get type    "$PLIST" /Active

check "get count of root dict"             "5"         get count   "$PLIST" /

# ─── Plist: set (replace existing) ───────────────────────────────────────────

echo
echo "=== Plist: set (replace existing) ==="

ok    "set string"                         set string  "Bob"        "$PLIST" /Name
check "get after set string"               "Bob"       get string   "$PLIST" /Name
ok    "set integer"                        set integer 99           "$PLIST" /Age
check "get after set integer"              "99"        get value    "$PLIST" /Age
check "count unchanged after set"          "5"         get count    "$PLIST" /

# ─── Plist: remove / delete alias ────────────────────────────────────────────

echo
echo "=== Plist: remove / delete alias ==="

ok    "remove key"                         remove "$PLIST" /Hidden
check "count decremented after remove"     "4"    get count "$PLIST" /
ok    "delete alias"                       delete "$PLIST" /Score
check "count decremented after delete"     "3"    get count "$PLIST" /

# ─── Plist: data (base64) ────────────────────────────────────────────────────

echo
echo "=== Plist: data (base64) ==="

# base64("hello") = "aGVsbG8="
ok    "insert data"                        insert Blob data "aGVsbG8=" "$PLIST" /
check "get type data"                      "data"       get type   "$PLIST" /Blob
check "get data value is base64"           "aGVsbG8="   get string "$PLIST" /Blob

# ─── Plist: arrays ───────────────────────────────────────────────────────────

echo
echo "=== Plist: arrays ==="

ok    "insert empty array"                 insert Items array          "$PLIST" /
ok    "append first string"                append string "alpha"       "$PLIST" /Items
ok    "append second string"               append string "beta"        "$PLIST" /Items
ok    "add alias appends third"            add    string "gamma"       "$PLIST" /Items

check "array count after appends"          "3"      get count  "$PLIST" /Items
check "array item 0"                       "alpha"  get string "$PLIST" /Items/0
check "array item 1"                       "beta"   get string "$PLIST" /Items/1
check "array item 2"                       "gamma"  get string "$PLIST" /Items/2
check "get type of array"                  "array"  get type   "$PLIST" /Items

ok    "insert at index 0 shifts items"     insert 0 string "zero" "$PLIST" /Items
check "array count after index insert"     "4"      get count  "$PLIST" /Items
check "item 0 is newly inserted"           "zero"   get string "$PLIST" /Items/0
check "item 1 shifted to former item 0"    "alpha"  get string "$PLIST" /Items/1

ok    "remove array item by index"         remove "$PLIST" /Items/0
check "count decremented after remove"     "3"     get count  "$PLIST" /Items
check "former item 1 is now item 0"        "alpha" get string "$PLIST" /Items/0

# ─── Plist: nested structures ─────────────────────────────────────────────────

echo
echo "=== Plist: nested structures ==="

ok    "insert nested dict"                 insert Info dict            "$PLIST" /
ok    "insert integer into nested dict"    insert Version integer 2    "$PLIST" /Info
ok    "insert string into nested dict"     insert Label   string  "v2" "$PLIST" /Info

check "get nested integer"                 "2"        get value  "$PLIST" /Info/Version
check "get nested string"                  "v2"       get string "$PLIST" /Info/Label
check "get type of nested dict"            "dict"     get type   "$PLIST" /Info
check "get count of nested dict"           "2"        get count  "$PLIST" /Info

ok    "set value in nested dict"           set integer 7   "$PLIST" /Info/Version
check "get updated nested value"           "7"         get value "$PLIST" /Info/Version

# ─── Plist: get key / get keys ───────────────────────────────────────────────

echo
echo "=== Plist: get key / get keys ==="

ok    "get key at index 0 of nested dict"  get key  "$PLIST" /Info/0
ok    "get keys of root dict succeeds"     get keys "$PLIST" /

# ─── Plist: find and findall ─────────────────────────────────────────────────

echo
echo "=== Plist: find and findall ==="

FIND="$TMP/find.plist"
ok    "create find test plist"             set dict   "$FIND" /
ok    "insert tags array"                  insert Tags array      "$FIND" /
ok    "append apple"                       append string "apple"  "$FIND" /Tags
ok    "append banana"                      append string "banana" "$FIND" /Tags
ok    "append apple again"                 append string "apple"  "$FIND" /Tags

check "find returns index of first match"  "0"  find    string "apple"  "$FIND" /Tags
check "find returns empty when no match"   ""   find    string "cherry" "$FIND" /Tags

actual_findall=$("$PLISTER" findall string "apple" "$FIND" /Tags 2>/dev/null)
expected_findall="$(printf '0\n2')"
if [ "$actual_findall" = "$expected_findall" ]; then
    echo "PASS: findall returns all matching indices"
    PASS=$((PASS + 1))
else
    echo "FAIL: findall returns all matching indices (got: '$actual_findall')"
    FAIL=$((FAIL + 1))
fi

# ─── Plist: find in dict with subpath ────────────────────────────────────────

echo
echo "=== Plist: find in dict with subpath ==="

PEOPLE="$TMP/people.plist"
ok    "create people plist"                set dict    "$PEOPLE" /
ok    "insert alice dict"                  insert alice dict       "$PEOPLE" /
ok    "insert alice age"                   insert age  integer 30  "$PEOPLE" /alice
ok    "insert bob dict"                    insert bob  dict        "$PEOPLE" /
ok    "insert bob age"                     insert age  integer 25  "$PEOPLE" /bob

check "find in dict by subpath returns key"  "alice"  find integer 30 "$PEOPLE" / /age
check "findall in dict by subpath"           "alice"  findall integer 30 "$PEOPLE" / /age

# ─── Plist: iterate ──────────────────────────────────────────────────────────

echo
echo "=== Plist: iterate ==="

ITER="$TMP/iter.plist"
ok    "create iter plist"                  set dict    "$ITER" /
ok    "insert nums array"                  insert nums array      "$ITER" /
ok    "append 10"                          append integer 10      "$ITER" /nums
ok    "append 20"                          append integer 20      "$ITER" /nums
ok    "append 30"                          append integer 30      "$ITER" /nums

line_count=$("$PLISTER" iterate "$ITER" /nums get value / 2>/dev/null | wc -l | tr -d ' ')
if [ "$line_count" = "3" ]; then
    echo "PASS: iterate+get prints one line per element"
    PASS=$((PASS + 1))
else
    echo "FAIL: iterate+get prints one line per element (got $line_count lines)"
    FAIL=$((FAIL + 1))
fi

ok    "iterate+set mutates all elements"   iterate "$ITER" /nums set integer 99 /
check "element 0 after iterate+set"        "99"  get value "$ITER" /nums/0
check "element 1 after iterate+set"        "99"  get value "$ITER" /nums/1
check "element 2 after iterate+set"        "99"  get value "$ITER" /nums/2

# iterate+remove: iterate and delete all items in the array
ok    "iterate+remove clears array"        iterate "$ITER" /nums remove /
check "array empty after iterate+remove"   "0"   get count "$ITER" /nums

# ─── Plist: copy ─────────────────────────────────────────────────────────────

echo
echo "=== Plist: copy ==="

SRC="$TMP/src.plist"
DST="$TMP/dst.plist"
ok    "create source plist"                set dict   "$SRC" /
ok    "insert value to copy"               insert CopiedKey string "copied_value" "$SRC" /
ok    "create dest plist"                  set dict   "$DST" /
ok    "insert copy from source"            insert Destination copy "$SRC" /CopiedKey "$DST" /
check "copied value appears in dest"       "copied_value" get string "$DST" /Destination

ok    "create dest array for append copy"   insert result array "$DST" /
ok    "append copy from source into array" append copy "$SRC" /CopiedKey "$DST" /result
check "appended copy in dest array"        "copied_value" get string "$DST" /result/0

# ─── JSON: basic types ───────────────────────────────────────────────────────

echo
echo "=== JSON: basic types ==="

JSON="$TMP/test.json"

ok    "set dict creates JSON root"         set dict    "$JSON" /
check_json "file is valid JSON after set dict" "$JSON"

ok    "json insert string"                 insert name   string  "Alice"  "$JSON" /
ok    "json insert integer"                insert age    integer 30        "$JSON" /
ok    "json insert bool true"              insert active bool    true      "$JSON" /
ok    "json insert bool false"             insert hidden bool    false     "$JSON" /

check "json get string"                    "Alice"   get string  "$JSON" /name
check "json get integer"                   "30"      get value   "$JSON" /age
check "json get bool true"                 "true"    get value   "$JSON" /active
check "json get bool false"                "false"   get value   "$JSON" /hidden

check "json get type string"               "string"  get type    "$JSON" /name
check "json get type integer"              "integer" get type    "$JSON" /age
check "json get type bool"                 "bool"    get type    "$JSON" /active

check "json get count of root"             "4"       get count   "$JSON" /
check_json "file is valid JSON after inserts" "$JSON"

# ─── JSON: set and remove ─────────────────────────────────────────────────────

echo
echo "=== JSON: set and remove ==="

ok    "json set string"                    set string  "Bob"  "$JSON" /name
check "json get after set string"          "Bob"       get string "$JSON" /name
ok    "json set integer"                   set integer 55     "$JSON" /age
check "json get after set integer"         "55"        get value  "$JSON" /age
check_json "file remains valid JSON after set" "$JSON"

ok    "json remove key"                    remove "$JSON" /hidden
check "json count after remove"            "3"    get count "$JSON" /
check_json "file remains valid JSON after remove" "$JSON"

# ─── JSON: arrays ────────────────────────────────────────────────────────────

echo
echo "=== JSON: arrays ==="

ok    "json insert empty array"            insert scores array     "$JSON" /
ok    "json append integer 10"             append integer 10       "$JSON" /scores
ok    "json append integer 20"             append integer 20       "$JSON" /scores
ok    "json append integer 30"             append integer 30       "$JSON" /scores

check "json array count"                   "3"   get count  "$JSON" /scores
check "json array item 0"                  "10"  get value  "$JSON" /scores/0
check "json array item 1"                  "20"  get value  "$JSON" /scores/1
check "json array item 2"                  "30"  get value  "$JSON" /scores/2

ok    "json insert at index 0"             insert 0 integer 5 "$JSON" /scores
check "json count after index insert"      "4"   get count  "$JSON" /scores
check "json item 0 is newly inserted"      "5"   get value  "$JSON" /scores/0
check "json former item 0 shifted to 1"    "10"  get value  "$JSON" /scores/1

check_json "file is valid JSON after array ops" "$JSON"

# ─── JSON: nested objects ────────────────────────────────────────────────────

echo
echo "=== JSON: nested objects ==="

NJSON="$TMP/nested.json"
ok    "json create root"                   set dict "$NJSON" /
ok    "json insert nested dict"            insert address dict              "$NJSON" /
ok    "json insert string into nested"     insert street  string  "Main St" "$NJSON" /address
ok    "json insert integer into nested"    insert number  integer 42         "$NJSON" /address

check "json get nested string"             "Main St" get string "$NJSON" /address/street
check "json get nested integer"            "42"       get value  "$NJSON" /address/number
check "json get type of nested dict"       "dict"     get type   "$NJSON" /address
check_json "nested json is valid"          "$NJSON"

ok    "json set value in nested dict"      set string "Oak Ave" "$NJSON" /address/street
check "json get after nested set"          "Oak Ave"  get string "$NJSON" /address/street
check_json "nested json valid after set"   "$NJSON"

# ─── JSON: round-trip from pre-existing file ──────────────────────────────────

echo
echo "=== JSON: round-trip from pre-existing file ==="

PRE="$TMP/preexisting.json"
printf '{"city":"Springfield","population":30720,"capital":false}' > "$PRE"

check "read existing json string"          "Springfield" get string "$PRE" /city
check "read existing json integer"         "30720"        get value  "$PRE" /population
check "read existing json bool"            "false"        get value  "$PRE" /capital

ok    "mutate existing json"               set string "Shelbyville" "$PRE" /city
check "get mutated value"                  "Shelbyville" get string "$PRE" /city
check_json "mutated file is still valid JSON" "$PRE"

# Verify it did NOT get rewritten as XML plist
first_char=$(head -c 1 "$PRE")
if [ "$first_char" = "{" ]; then
    echo "PASS: mutated JSON file retained JSON format (not rewritten as plist XML)"
    PASS=$((PASS + 1))
else
    echo "FAIL: mutated JSON file lost JSON format (first char: '$first_char')"
    FAIL=$((FAIL + 1))
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAIL" -eq 0 ]
