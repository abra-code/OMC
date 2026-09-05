# actionui_remote_walk.awk - the top-level JSON walker of actionui_remote.sh.
#
#     printf '%s\n' "$json" | /usr/bin/awk -v mode=MODE [-v key=KEY] -f actionui_remote_walk.awk
#
# One line of JSON text on stdin. What the shell client feeds it is replies, which carry no
# token, plus in actionui_call the caller's own params before the token is added. It is read on
# stdin rather than passed in argv for the reason README.md gives: a process's arguments are
# readable by every process on the system.
#
# Modes:
#   reply  print four lines: kind (R result / E error / B batch array / N a well-formed line that
#          is not a reply, to be ignored as PROTOCOL.md section 3 requires / X unparseable), the
#          raw id, the raw value (the result, the error object, or the whole batch), and a "."
#          terminator so that an empty value still splits correctly.
#   key    print the raw value of top-level key KEY, or nothing (status 1) when absent.
#   items  print each top-level array element raw, one per line.
#
# A walker rather than a parser: it finds where each top-level value ends and hands it back raw,
# so nothing here has to understand numbers or nesting beyond that, and a string keeps its
# escapes. plutil unescapes one in the shell, and only when a caller asks for the text.

function ws(p) { while (p <= n && index(" \t\r", substr(s, p, 1))) p++; return p }
# Index just past the value that starts at p; 0 for an unterminated string or container,
# and p itself when there is no value there at all. Every caller demands progress, so
# malformed input ends the walk instead of looping on it.
function vend(p,    c, instr, st, o) {
    c = substr(s, p, 1)
    if (c == "\"") {
        p++
        while (p <= n) {
            c = substr(s, p, 1)
            if (c == "\\") { p += 2; continue }
            if (c == "\"") return p + 1
            p++
        }
        return 0
    }
    if (c == "{" || c == "[") {
        st = ""; instr = 0; o = ""
        while (p <= n) {
            c = substr(s, p, 1)
            if (instr) {
                if (c == "\\") { p += 2; continue }
                if (c == "\"") instr = 0
                p++; continue
            }
            if (c == "\"") instr = 1
            else if (c == "{" || c == "[") st = st c
            else if (c == "}" || c == "]") {
                # The closer must match the innermost opener; [} is not a container.
                if (st == "") return 0
                o = substr(st, length(st), 1)
                if ((c == "}" && o != "{") || (c == "]" && o != "[")) return 0
                st = substr(st, 1, length(st) - 1)
                if (st == "") return p + 1
            }
            p++
        }
        return 0
    }
    while (p <= n && !index(",}] \t\r", substr(s, p, 1))) p++
    return p
}
function bad() { if (mode == "reply") { print "X"; print ""; print ""; print "." } exit 1 }
NR == 1 { s = $0; n = length(s) }
NR > 1 { exit 0 }
END {
    i = ws(1)
    c = substr(s, i, 1)
    if (mode == "items") {
        if (c != "[") bad()
        i = ws(i + 1)
        while (i <= n && substr(s, i, 1) != "]") {
            e = vend(i); if (e <= i) exit 1
            print substr(s, i, e - i)
            i = ws(e)
            if (substr(s, i, 1) == ",") i = ws(i + 1)
        }
        exit 0
    }
    if (mode == "reply" && c == "[") {
        if (vend(i) <= 0) bad()
        print "B"; print ""; print s; print "."; exit 0
    }
    if (mode == "reply" && c != "{") {
        # Not an object: a JSON scalar is a line to ignore; anything else is not JSON.
        rest = substr(s, i); sub(/[ \t\r]+$/, "", rest)
        if (rest ~ /^"([^"\\]|\\.)*"$/ || rest ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/ ||
            rest == "true" || rest == "false" || rest == "null") {
            print "N"; print ""; print ""; print "."; exit 0
        }
        bad()
    }
    i = ws(i + 1)
    kind = ""; id = ""; raw = ""; hasmethod = 0
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "}") break
        if (c == ",") { i = ws(i + 1); continue }
        if (c != "\"") bad()
        ke = vend(i); if (ke <= i) bad()
        k = substr(s, i + 1, ke - i - 2)
        i = ws(ke)
        if (substr(s, i, 1) != ":") bad()
        i = ws(i + 1)
        ve = vend(i); if (ve <= i) bad()
        v = substr(s, i, ve - i); i = ws(ve)
        if (mode == "key") {
            if (k == key) { print v; exit 0 }
            continue
        }
        if (k == "result") { kind = "R"; raw = v }
        else if (k == "error" && kind != "R") { kind = "E"; raw = v }
        else if (k == "id") { id = v }
        else if (k == "method") { hasmethod = 1 }
    }
    if (mode == "key") exit 1
    # A method makes it a request from the host, not a reply, whatever id it carries.
    if (kind == "") { kind = "N"; if (hasmethod) id = "" }
    print kind; print id; print raw; print "."
}
