# actionui_remote_escape.awk - the control-character pass of actionui_remote.sh's JSON escaping.
#
#     printf '%s\n' "$text" | /usr/bin/awk -f actionui_remote_escape.awk
#
# Stdin is a text whose backslashes and double quotes the shell has already escaped. Stdout is
# that text with every character JSON forbids inside a string literal replaced by its escape, on
# one line: the line separators of a multi-line text become \n, so the result can be wrapped in
# quotes exactly as it comes back.
#
# The text arrives on stdin and never in argv, which is what makes this pass safe for the token.
# A process's arguments are readable by every process on the system whatever its code-signing
# flags; a pipe into a restricted Apple binary is not. See "Never in argv" in README.md.
#
# The shell does the backslash and quote passes itself, so ordinary text - the overwhelming
# majority of it - never reaches this file at all. Control characters are rare enough in UI text
# to be worth one process on the occasions they turn up.

BEGIN {
    for (k = 1; k < 32; k++) ctl[sprintf("%c", k)] = sprintf("\\u%04x", k)
    ctl["\b"] = "\\b"; ctl["\f"] = "\\f"; ctl["\r"] = "\\r"; ctl["\t"] = "\\t"
    ctl[sprintf("%c", 127)] = "\\u007f"
}
NR > 1 { printf "\\n" }
{
    n = length($0)
    for (j = 1; j <= n; j++) {
        c = substr($0, j, 1)
        if (c in ctl) printf "%s", ctl[c]; else printf "%s", c
    }
}
