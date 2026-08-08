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

# Run a plister command that must FAIL IN WORDS: non-zero, but not a signal
# death. Plain "nok" cannot tell the two apart, and every defect in this area
# was a crash, so "nok" passed against the broken binary for the wrong reason.
# 133/134/139 are SIGTRAP, SIGABRT and SIGSEGV as a shell reports them.
nok_clean() {
    local desc="$1"
    shift
    "$PLISTER" "$@" >/dev/null 2>&1
    local rc=$?
    if [ "$rc" = "0" ]; then
        echo "FAIL: $desc (expected non-zero exit, got success)"
        FAIL=$((FAIL + 1))
    elif [ "$rc" = "133" ] || [ "$rc" = "134" ] || [ "$rc" = "139" ]; then
        echo "FAIL: $desc (died on a signal, rc $rc)"
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

# === Containers as appended/inserted values ==================================
#
# "dict" and "array" create an empty container and take no value argument, so they
# need one fewer argument than every other type. Requiring the value-carrying count
# made "append dict" and "append array" impossible to call at all.

echo
echo "=== Containers as appended/inserted values ==="

CONT="$TMP/containers.json"
ok    "container root"                       set dict "$CONT" /
ok    "container list"                       insert LIST array "$CONT" /

ok    "append dict onto array"               append dict  "$CONT" /LIST
ok    "append array onto array"              append array "$CONT" /LIST
ok    "add alias appends a dict"             add    dict  "$CONT" /LIST

check "array holds the three containers"     "3"     get count "$CONT" /LIST
check "appended item 0 is a dict"            "dict"  get type  "$CONT" /LIST/0
check "appended item 1 is an array"          "array" get type  "$CONT" /LIST/1
check "appended item 2 is a dict"            "dict"  get type  "$CONT" /LIST/2

ok    "insert into the appended dict"        insert Key string "Value" "$CONT" /LIST/0
check "read it back"                         "Value" get string "$CONT" /LIST/0/Key
ok    "append into the appended array"       append integer 7 "$CONT" /LIST/1
check "read that back"                       "7"     get value  "$CONT" /LIST/1/0
check_json "file is valid JSON after container appends" "$CONT"

# The per-type counts must still reject what they always rejected.
nok   "append rejects a missing value"       append string "$CONT" /LIST
nok   "append dict rejects a stray value"    append dict "extra" "$CONT" /LIST
nok   "insert rejects a missing value"       insert Key string "$CONT" /
nok   "insert dict rejects a stray value"    insert Key dict "extra" "$CONT" /
# The type argument itself missing. "plister insert Key" is argc 3, which is the
# smallest argv that reaches the command parser at all - one argument shorter and
# main's own argc check prints the help instead, so the guard would never be
# reached and the case would pass for the wrong reason.
nok   "insert rejects a missing type"        insert Key
# check compares stdout; this message goes to stderr, so it is compared here.
missing_type_msg=$("$PLISTER" insert Key 2>&1 >/dev/null | head -n 1)
if [ "$missing_type_msg" = "Plister error: key or index and value type must both be specified" ]; then
    echo "PASS: and says which two are needed"
    PASS=$((PASS + 1))
else
    echo "FAIL: and says which two are needed"
    printf '      actual: %s\n' "$missing_type_msg"
    FAIL=$((FAIL + 1))
fi

# === Format detection by content =============================================
#
# The extension decides the format when it is one we know; for any other extension
# the content decides, so a JSON document does not have to be named ".json".

echo
echo "=== Format detection by content ==="

# Assert a file's leading bytes, which is how we tell the written format apart.
check_head() {
    local desc="$1" expected="$2" file="$3"
    local actual
    actual=$(head -c ${#expected} "$file")
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"
        printf '      expected leading bytes: %s\n' "$expected"
        printf '      actual:                 %s\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

SNIFF="$TMP/project.pkgbuilderproj"
printf '{\n  "NAME" : "widget",\n  "LIST" : [ 1, 2 ]\n}\n' > "$SNIFF"

check "json content read through an unknown extension" "widget" get string "$SNIFF" /NAME
check "and its container types"                        "array"  get type   "$SNIFF" /LIST
ok    "written through an unknown extension"           set string "gadget" "$SNIFF" /NAME
check "the write landed"                               "gadget" get string "$SNIFF" /NAME
check_json "and the file is still JSON, not plist XML" "$SNIFF"

# A JSON array at the root - unambiguous, no old-style plist opens with '['.
ARRDOC="$TMP/menu.uidoc"
printf '[ "a", "b" ]\n' > "$ARRDOC"
check "json array root through an unknown extension"   "2"  get count "$ARRDOC" /
ok    "append to it"                                   append string "c" "$ARRDOC" /
check "the append landed"                              "3"  get count "$ARRDOC" /
check_head "and it stayed JSON"                        "[" "$ARRDOC"

# Leading BOM and whitespace must not defeat the sniff.
BOMDOC="$TMP/bom.uidoc"
printf '\xef\xbb\xbf\n\n   {"A":"B"}\n' > "$BOMDOC"
check "json behind a BOM and blank lines"              "B" get string "$BOMDOC" /A

# XML plist through an unknown extension: worked before by CF autodetection, and
# must keep working and keep writing XML.
XMLDOC="$TMP/settings.pbproj"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>A</key><string>B</string></dict></plist>\n' > "$XMLDOC"
check "xml plist through an unknown extension"         "B" get string "$XMLDOC" /A
ok    "write to it"                                    set string "C" "$XMLDOC" /A
check "the write landed"                               "C" get string "$XMLDOC" /A
check_head "and it stayed XML"                         "<?xml" "$XMLDOC"

# An old-style OpenStep plist opens with '{' just as a JSON object does, so the
# reader has to fall back to the plist parser when the JSON parse fails.
OLDDOC="$TMP/legacy.conf"
printf '{\n  A = B;\n  C = ( 1, 2 );\n}\n' > "$OLDDOC"
check "old-style plist behind a JSON-looking brace"    "B" get string "$OLDDOC" /A
ok    "write to it"                                    set string "Z" "$OLDDOC" /A
check_head "written back as XML, the only plist form CF emits" "<?xml" "$OLDDOC"

# A binary plist stays binary: "output format matches input format".
BINDOC="$TMP/binary.plist"
ok    "create a plist"                                 set dict "$BINDOC" /
ok    "put a key in it"                                insert K string "V" "$BINDOC" /
if plutil -convert binary1 "$BINDOC" >/dev/null 2>&1; then
    ok    "modify the binary plist"                    insert K2 string "V2" "$BINDOC" /
    check "the modification landed"                    "V2" get string "$BINDOC" /K2
    check_head "and the file is still binary"          "bplist00" "$BINDOC"
else
    echo "SKIP: binary plist round trip (plutil -convert binary1 failed)"
fi

# Nothing to sniff: a file that does not exist yet falls back to the extension,
# and an extension we do not know still means XML.
NEWDOC="$TMP/fresh.weird"
ok    "create through an unknown extension"            set dict "$NEWDOC" /
ok    "put a key in it"                                insert A string "B" "$NEWDOC" /
check_head "a new file with an unknown extension is XML" "<?xml" "$NEWDOC"

nok   "a file that is not there is an error"           get value "$TMP/nonexistent.weird" /A
: > "$TMP/zero.weird"
nok   "and so is a zero-byte one"                      get value "$TMP/zero.weird" /A

# A bare scalar at the root is deliberately left to the plist reader: "true" is
# equally a JSON boolean and an unquoted old-style plist string, and reading it
# as JSON would silently change the type a one-word file reports.
printf 'true' > "$TMP/word.weird"
check "a bare word keeps its old reading"        "string" get type "$TMP/word.weird" /
printf '42' > "$TMP/number.weird"
check "and so does a bare number"                "string" get type "$TMP/number.weird" /

# A value with no JSON spelling must be refused, not thrown: dataWithJSONObject
# raises on CFData rather than returning nil, which took the process down.
ok    "a plist holding data"                           set dict "$TMP/withdata.plist" /
ok    "with a data value in it"                        insert Blob data "aGVsbG8=" "$TMP/withdata.plist" /
ok    "and a JSON file to copy it into"                set dict "$TMP/target.json" /
nok_clean "data into a JSON file is refused, not thrown" insert Blob copy "$TMP/withdata.plist" /Blob "$TMP/target.json" /
check "the JSON file was left alone"             "0"   get count "$TMP/target.json" /

# A write that could not happen is not a success. This is the one fix with no
# check of its own until now: it was covered only transitively, through the case
# above needing it once the crash was stopped.
/bin/mkdir -p "$TMP/ro" && printf '{"k":1}' > "$TMP/ro/f.json" && chmod 555 "$TMP/ro"
nok   "a save that cannot be written is not a success" set string x "$TMP/ro/f.json" /k
chmod 755 "$TMP/ro"

# A value that cannot be read as the type asked for is a diagnostic, not a
# signal. An unset shell variable is the ordinary way to arrive here:
# "plister set integer "$count" f.json /N" with $count unset used to SIGABRT out
# of CFDictionarySetValue, and the "find" forms died in CFEqual printing nothing.
ok       "a document to try it on"                     set dict "$TMP/badvalue.json" /
nok_clean "an empty integer is refused"                set integer "" "$TMP/badvalue.json" /N
nok_clean "a non-numeric integer is refused"           insert N integer "abc" "$TMP/badvalue.json" /
nok_clean "an empty real is refused"                   insert R real "" "$TMP/badvalue.json" /
nok_clean "a bool that is not one is refused"          insert B bool "maybe" "$TMP/badvalue.json" /
nok_clean "non-base64 data is refused"                 insert D data "not!base64" "$TMP/badvalue.json" /
ok       "an array to append into"                     insert L array "$TMP/badvalue.json" /
nok_clean "append refuses one too"                     append integer "" "$TMP/badvalue.json" /L
nok_clean "and so does find, which died silently"      find integer "abc" "$TMP/badvalue.json" /
nok_clean "and findall"                                findall bool "maybe" "$TMP/badvalue.json" /
# Only the array added above is there: none of N, R, B or D landed.
check "and none of the bad values landed"        "1"   get count "$TMP/badvalue.json" /
check "the array is still empty too"             "0"   get count "$TMP/badvalue.json" /L

# An iterate whose modifying subcommand fails must not report success: the
# partial modification would be saved and the caller told it worked.
ok    "a list to iterate"                              set dict "$TMP/iter.json" /
ok    "with an array in it"                            insert L array "$TMP/iter.json" /
ok    "holding a string"                               append string "one" "$TMP/iter.json" /L
nok_clean "a bad get parameter is caught at parse time" iterate "$TMP/iter.json" /L get vlaue /
nok_clean "and a modifying subcommand's failure is kept" iterate "$TMP/iter.json" /L set integer "" /
# A read-only iteration over items that lack the subpath is an ordinary miss.
ok    "but a plain iteration still succeeds"           iterate "$TMP/iter.json" /L get value /

# A missing pseudopath is a typo, not a crash. "set dict <file>" dereferenced a
# NULL spec chain; "get <bogus-type>" hit an assert. Both aborted the process.
nok_clean "set with no pseudopath is refused"          set dict "$TMP/nopath.plist"
nok_clean "an unknown get parameter is refused"        get vlaue "$TMP/target.json" /
nok_clean "and a misspelled one under iterate"         iterate "$TMP/target.json" / get vlaue /

# ─── Summary ─────────────────────────────────────────────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAIL" -eq 0 ]
