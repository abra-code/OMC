#!/bin/sh
# actionui_remote.sh - out-of-process client for ActionUI windows, for shell scripts.
#
# Speaks ActionUI Remote Protocol version 1 (see ../PROTOCOL.md): newline-delimited JSON-RPC 2.0
# over a Unix domain socket to a host that embeds ActionUI and runs ActionUIRemoteServer. The
# shell counterpart of ../Python/actionui_remote.py, with the same commands and exit codes.
#
# Why a shell client exists at all, when the Python one already has a command line:
#
#   Every Apple-provided shell (/bin/sh, bash, zsh, ksh, dash, csh, tcsh) and every Apple tool this
#   file spawns (nc, awk, plutil, mktemp, mkfifo, rm) carries the CS_RESTRICT code-signing flag,
#   so macOS withholds their environment from other processes: `ps eww` shows their argv and
#   nothing else. A python3 or node process has no such flag, and while one runs, any process of
#   the same user can read ACTIONUI_REMOTE_TOKEN out of it with one ps invocation. A handler
#   written against this file keeps the token inside processes that hide it.
#
#   That holds only as long as the token never reaches argv (visible for every process, restricted
#   or not) and never reaches the environment of a process that does not hide it. This file keeps
#   both rules: the token travels to nc on a pipe, never as an argument, and printf and echo are
#   shell builtins here, so nothing that touches the token is ever an external command with the
#   token in its argv. `actionui_hold_token` and `actionui_handoff` are how a script keeps the
#   rules when it spawns something else. See the README next to this file.
#
# Requirements: /bin/sh as shipped on macOS (bash 3.2 in POSIX mode) or zsh. Nothing else. Sourced
# under zsh with actionui_remote.zsh in front of it, the nc transport is replaced by zsh's own
# socket module: no helper process at all, and one connection kept open across calls.
#
# The two awk programs this file runs are files of their own beside it, actionui_remote_escape.awk
# and actionui_remote_walk.awk, found there when this file is loaded, sourced or run. The three
# go together:
# copying only this one leaves a client that cannot escape a control character or read a reply,
# so it says so and stops rather than letting the first call discover it.
#
# This file sets no traps, so a script interrupted in the middle of a call under the nc transport
# leaves a small directory with two FIFOs under TMPDIR and an nc that exits when its timeout
# expires. A script that cares can `trap` on INT and TERM itself. And under /bin/sh (POSIX mode)
# a failed redirection on `exec` ends the script, as POSIX requires of a special builtin, so a
# process that has run out of descriptors, or whose TMPDIR vanished mid-call, ends there.
#
# Use as a library:
#
#     . /path/to/actionui_remote.sh
#     actionui_set_string 4 "Working..."          # window from $ACTIONUI_WINDOW_UUID
#     rows=$(actionui_get_rows 5) || exit $?      # JSON, one line
#     name=$(actionui_get_string 2)               # the text itself
#
# Use as a command:
#
#     actionui_remote.sh hello
#     actionui_remote.sh --window UUID get-value 5
#     actionui_remote.sh get-rows 5                # window from $ACTIONUI_WINDOW_UUID
#     actionui_remote.sh call actionui.getRows '{"window":"UUID","viewID":5}'
#
# Configuration, all read when a call is made rather than when this file is sourced:
#
#     ACTIONUI_REMOTE_ENDPOINT   socket path (required)
#     ACTIONUI_WINDOW_UUID       default window for the element functions
#     ACTIONUI_REMOTE_TOKEN      token, when the host requires one (PROTOCOL.md section 10)
#     ACTIONUI_REMOTE_TOKEN_FD   read the token from this inherited descriptor instead; it is read
#                                once, then closed, and the variable is removed
#     ACTIONUI_REMOTE_TIMEOUT    seconds to wait for a reply (default 15)
#
# Argument conventions, deliberately shell-shaped rather than a copy of the Python signatures:
# getters take VIEWID then an optional PART; setters take VIEWID, the value, then an optional
# PART. Values that the protocol types as JSON (set_value, set_property, set_state, rows) are
# passed as JSON text; values typed as strings (set_string, set_state_string) are passed as
# plain text and escaped here.
#
# Output and exit status, the same as `python3 -m actionui_remote`: a getter prints its result
# as one line of JSON exactly as the host sent it (get_string prints the text itself, windows
# prints one UUID per line), a setter prints nothing. 0 on success; 1 when the host answered an
# error, with "[code] message" on stderr; 2 for a usage error; 3 when there is no host to talk
# to. After every call ACTIONUI_RESULT holds the raw result, and on an error ACTIONUI_ERROR_CODE
# and ACTIONUI_ERROR_MESSAGE are set, for callers that do not capture output.

# Two things are settled before anything is defined, so that a shell that cannot run this file,
# or a copy that arrived without its awk programs, is left holding nothing at all.

# The shell. The element functions use ${var//x/y}, the nc transport needs `read -t`, and finding
# this file's own directory below needs one or the other; nothing here is portable to a third
# shell, and a silent no-op would be worse than a message.
if [ -z "${ZSH_VERSION:-}" ] && [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' "actionui_remote.sh needs bash (macOS /bin/sh) or zsh; this shell is neither" >&2
    return 2 2>/dev/null || exit 2
fi

# Where the two awk programs are: beside this file. Resolved once here, and made absolute, so a
# handler that cd's afterwards still finds them - this is a library, and "afterwards" can be much
# later. zsh's %x names the file being sourced whatever $0 has been set to, and :A resolves a
# symlink to it as well; bash sets BASH_SOURCE when sourced and $0 when executed, and there a
# symlink is followed by hand, so that a client reached through /usr/local/bin still finds them.
if [ -n "${ZSH_VERSION:-}" ]; then
    # Behind eval so that no other shell's parser ever sees zsh-only syntax: a dot-script is read
    # ahead of what it runs, so the guard above does not protect a third shell from a parse error.
    eval '_AUI_SELF=${${(%):-%x}:A}'
else
    _AUI_SELF=${BASH_SOURCE:-$0}
    case $_AUI_SELF in
        */*) ;;
        *) _AUI_SELF=./$_AUI_SELF ;;
    esac
    # Bounded at what the kernel itself will follow, so that a chain it can resolve is not
    # refused here and a cycle ends the loop instead of spinning in it. readlink is an Apple
    # binary and takes a path, never anything secret.
    _aui_hops=0
    while [ -L "$_AUI_SELF" ] && [ "$_aui_hops" -lt 32 ]; do
        _aui_link=$(/usr/bin/readlink "$_AUI_SELF")
        if [ -z "$_aui_link" ]; then
            break
        fi
        case $_aui_link in
            /*) _AUI_SELF=$_aui_link ;;
            *)
                # Against the physical directory the link lives in, not by pasting the two paths
                # together: a target with .. in it, reached through a symlinked directory, is a
                # different place once the shell resolves that .. textually.
                _aui_base=${_AUI_SELF%/*}
                if [ -z "$_aui_base" ]; then
                    _aui_base=/
                fi
                _aui_base=$(CDPATH= cd "$_aui_base" 2>/dev/null && pwd -P)
                if [ -z "$_aui_base" ]; then
                    break
                fi
                _AUI_SELF=$_aui_base/$_aui_link ;;
        esac
        _aui_hops=$((_aui_hops + 1))
    done
    unset _aui_hops _aui_link _aui_base
fi
# Both branches leave a path with a slash in it, so the directory is what precedes the last one,
# and the empty result means this file is installed at the filesystem root.
_AUI_LIB_DIR=${_AUI_SELF%/*}
if [ -z "$_AUI_LIB_DIR" ]; then
    _AUI_LIB_DIR=/
fi
# cd and pwd are builtins in both shells, so an absolute path costs no exec, and the subshell
# keeps the directory change to itself. CDPATH is cleared for it: a relative path that CDPATH
# happens to resolve lands somewhere else, and cd prints where it went, which would end up in
# this capture and make a correct install look like a broken one.
_AUI_LIB_DIR=$(CDPATH= cd "$_AUI_LIB_DIR" 2>/dev/null && pwd -P)
_AUI_AWK_ESCAPE="$_AUI_LIB_DIR/actionui_remote_escape.awk"
_AUI_AWK_WALK="$_AUI_LIB_DIR/actionui_remote_walk.awk"
if [ -z "$_AUI_LIB_DIR" ] || [ ! -r "$_AUI_AWK_ESCAPE" ] || [ ! -r "$_AUI_AWK_WALK" ]; then
    # The resolved directory, not the path as typed, so that the two shells say the same thing:
    # zsh's :A resolves /var to /private/var and bash's symlink walk does not.
    printf '%s\n' "actionui_remote.sh: cannot read actionui_remote_escape.awk and actionui_remote_walk.awk in '${_AUI_LIB_DIR:-${_AUI_SELF%/*}}'; the three files go together, copy them as a set" >&2
    unset _AUI_SELF _AUI_LIB_DIR _AUI_AWK_ESCAPE _AUI_AWK_WALK
    return 2 2>/dev/null || exit 2
fi
unset _AUI_SELF _AUI_LIB_DIR

ACTIONUI_PROTOCOL_VERSION=1
ACTIONUI_EXIT_OK=0
ACTIONUI_EXIT_REMOTE_ERROR=1
ACTIONUI_EXIT_USAGE=2
ACTIONUI_EXIT_NO_HOST=3

# Private state. Not exported: a child must never inherit any of it.
_AUI_NEXT_ID=1
_AUI_TOKEN=""
_AUI_TOKEN_HELD=0           # 1 once the token has been captured and removed from the environment
_AUI_BATCH_ACTIVE=0
_AUI_BATCH=""
_AUI_SUN_PATH_LIMIT=103     # macOS sun_path, PROTOCOL.md section 1

# A literal newline, for pattern work. Built without $'...' so it reads the same everywhere.
_AUI_NL=$(printf '\nx')
_AUI_NL=${_AUI_NL%x}
_AUI_TAB=$(printf '\tx')
_AUI_TAB=${_AUI_TAB%x}
_AUI_CR=$(printf '\rx')
_AUI_CR=${_AUI_CR%x}

# --- Configuration ------------------------------------------------------------------------------

_aui_endpoint() {
    _aui_ep=${ACTIONUI_REMOTE_ENDPOINT:-}
    if [ -z "$_aui_ep" ]; then
        _aui_error="ACTIONUI_REMOTE_ENDPOINT is not set; this host did not start the ActionUI remote server"
        return "$ACTIONUI_EXIT_NO_HOST"
    fi
    if [ "${#_aui_ep}" -gt "$_AUI_SUN_PATH_LIMIT" ]; then
        _aui_error="socket path is too long for sun_path (limit $_AUI_SUN_PATH_LIMIT bytes): $_aui_ep"
        return "$ACTIONUI_EXIT_NO_HOST"
    fi
    return 0
}

# Is $1 a positive number of seconds? Digits and at most one dot, with a nonzero digit somewhere,
# so that 0, 00, 0.0 and .000 are all rejected the same way.
_aui_positive_seconds() {
    case $1 in
        ''|*[!0-9.]*|.|*.*.*|0[0-9]*) return 1 ;;
    esac
    case $1 in
        *[1-9]*) return 0 ;;
    esac
    return 1
}

# The timeout in seconds, into _aui_to. Anything that is not a positive number means the default.
# zsh honors a fraction; the nc transport truncates to whole seconds (bash 3.2's read -t and
# nc -w accept nothing else), never below one.
_aui_timeout() {
    if _aui_positive_seconds "${ACTIONUI_REMOTE_TIMEOUT:-}"; then
        _aui_to=$ACTIONUI_REMOTE_TIMEOUT
        # zsh's read -t takes a number that starts with a digit; .5 would be read as no number
        # at all, that is, a poll that never waits.
        case $_aui_to in
            .*) _aui_to=0$_aui_to ;;
        esac
    else
        _aui_to=15
    fi
    return 0
}

# The token this client sends, into _aui_tok. Precedence: a token already held, then a descriptor,
# then the environment. Never printed: a $(...) would put it on a pipe for nothing, and a subshell
# would lose the held copy.
#
# The descriptor is read once, and then this side of its lifecycle is closed out: the descriptor
# is closed and the variable removed, so nothing this script spawns inherits an open descriptor
# to a drained pipe, or a variable naming one. The other side belongs to whoever created the
# pipe: write the token, close the write end. A child that needs the token is given its own with
# actionui_handoff, which does exactly that. A descriptor that cannot be read is a failure, not a
# fallback to the environment, and stays configured so that every call reports the same thing.
_aui_token() {
    if [ "$_AUI_TOKEN_HELD" -eq 1 ]; then
        _aui_tok=$_AUI_TOKEN
        return 0
    fi
    if [ -n "${ACTIONUI_REMOTE_TOKEN_FD:-}" ]; then
        case $ACTIONUI_REMOTE_TOKEN_FD in
            ''|*[!0-9]*)
                _aui_clear_outcome
                _aui_error="ACTIONUI_REMOTE_TOKEN_FD must be a descriptor number, not '$ACTIONUI_REMOTE_TOKEN_FD'"
                return "$ACTIONUI_EXIT_USAGE" ;;
        esac
        _AUI_TOKEN=""
        IFS= read -r -u "$ACTIONUI_REMOTE_TOKEN_FD" _AUI_TOKEN 2>/dev/null
        # A token with no trailing newline still reads, with status 1; only an empty read is a failure.
        if [ -z "$_AUI_TOKEN" ]; then
            _aui_clear_outcome
            _aui_error="nothing could be read from descriptor $ACTIONUI_REMOTE_TOKEN_FD (ACTIONUI_REMOTE_TOKEN_FD)"
            return "$ACTIONUI_EXIT_NO_HOST"
        fi
        # The number was validated as digits above, so these evals are a fixed shape. zsh does not
        # take a descriptor above 9 in redirection syntax (`exec 12<&-` is "exec the command 12",
        # and the shell exits); its own form, {var}<&-, must stay behind eval so bash never
        # parses it.
        if [ -n "${ZSH_VERSION:-}" ]; then
            eval 'exec {ACTIONUI_REMOTE_TOKEN_FD}<&-'
        else
            eval "exec $ACTIONUI_REMOTE_TOKEN_FD<&-"
        fi
        unset ACTIONUI_REMOTE_TOKEN_FD
        _AUI_TOKEN_HELD=1
        _aui_tok=$_AUI_TOKEN
        return 0
    fi
    _aui_tok=${ACTIONUI_REMOTE_TOKEN:-}
    return 0
}

# Move the token out of the environment and into this shell. After this, nothing the script
# spawns inherits ACTIONUI_REMOTE_TOKEN, so a python3 or node child cannot expose it through ps;
# this file keeps working, because it sends the held copy. Call it first thing in a handler that
# has anything sensitive on screen. Safe to call when there is no token at all.
#
# The variables are removed whether or not the token could be read: a descriptor that turns
# out to be unreadable must not leave the token exported for every later child. The
# library then holds no token, so a host that requires one refuses it with 1006 - a loud
# failure, which is the right one. The status reports the problem to a caller that checks.
actionui_hold_token() {
    _aui_token
    _aui_rc=$?
    unset ACTIONUI_REMOTE_TOKEN ACTIONUI_REMOTE_TOKEN_FD
    _AUI_TOKEN_HELD=1
    if [ "$_aui_rc" -ne 0 ]; then
        _AUI_TOKEN=""
        printf '%s\n' "$_aui_error" >&2
        return "$_aui_rc"
    fi
    _AUI_TOKEN=$_aui_tok
    return 0
}

# Run a command with the token delivered on descriptor 3 and removed from its environment. This
# is how a shell handler hands work to a python3 or node script without putting the token where
# ps can see it: not in the child's argv, not in its environment, only on a pipe the child reads.
# The child is told which descriptor with ACTIONUI_REMOTE_TOKEN_FD=3 (the number is no secret).
# The pipe's write end closes as soon as the token is written and the read end lives only in the
# child's process; nothing of it remains in this shell afterwards.
# A python3 child that uses actionui_remote.py needs no code for it at all: that module reads the
# descriptor when it is imported, then closes it and removes the variable.
# The command's own stdin is preserved. Returns the command's exit status.
actionui_handoff() {
    if [ "$#" -eq 0 ]; then
        _aui_clear_outcome
        printf '%s\n' "actionui_handoff: a command is required" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    _aui_token
    _aui_rc=$?
    if [ "$_aui_rc" -ne 0 ]; then
        printf '%s\n' "$_aui_error" >&2
        return "$_aui_rc"
    fi
    if [ -z "$_aui_tok" ]; then
        # Nothing to hand over; still scrub, so the child cannot pick up a stale variable.
        (
            unset ACTIONUI_REMOTE_TOKEN ACTIONUI_REMOTE_TOKEN_FD
            "$@"
        )
        return $?
    fi
    # Descriptor 5 carries the original stdin across the pipeline, scoped to this group only;
    # the token pipe becomes descriptor 3 in the child.
    {
        printf '%s\n' "$_aui_tok" | (
            exec 3<&0 0<&5 5<&-
            unset ACTIONUI_REMOTE_TOKEN
            ACTIONUI_REMOTE_TOKEN_FD=3
            export ACTIONUI_REMOTE_TOKEN_FD
            "$@"
        )
    } 5<&0
    return $?
}

# --- JSON out ----------------------------------------------------------------------------------

# Escape TEXT for use inside a JSON string, into _aui_escaped. The backslash and quote passes are
# pure shell, so ordinary text - and the token - never leaves this process. Control characters
# are rare in UI text and need one awk pass, actionui_remote_escape.awk beside this file; awk is
# a restricted Apple binary and reads the text on stdin, so the token is still never an argument.
_aui_escape() {
    _aui_escaped=$1
    _aui_escaped=${_aui_escaped//\\/\\\\}
    _aui_escaped=${_aui_escaped//\"/\\\"}
    case $_aui_escaped in
        *[[:cntrl:]]*)
            _aui_escaped=$(printf '%s\n' "$_aui_escaped" | /usr/bin/awk -f "$_AUI_AWK_ESCAPE") ;;
    esac
    return 0
}

# A JSON string literal for TEXT, into _aui_json.
_aui_json_string() {
    _aui_escape "$1"
    _aui_json="\"$_aui_escaped\""
    return 0
}

# The public outcome of the previous call, cleared at the start of the next one on every path.
_aui_clear_outcome() {
    ACTIONUI_RESULT=""
    ACTIONUI_ERROR_CODE=""
    ACTIONUI_ERROR_MESSAGE=""
    return 0
}

# Validate an integer argument. $1 value, $2 its name for the message.
_aui_int() {
    case $1 in
        ''|*[!0-9-]*|-|?*-*)
            _aui_clear_outcome
            _aui_error="$2 must be an integer, not '$1'"
            return "$ACTIONUI_EXIT_USAGE" ;;
    esac
    return 0
}

# Validate a boolean argument, normalizing into _aui_bool.
_aui_boolean() {
    case $1 in
        true|1|yes|on|TRUE|YES|ON)    _aui_bool=true ;;
        false|0|no|off|FALSE|NO|OFF)  _aui_bool=false ;;
        *)
            _aui_clear_outcome
            _aui_error="$2 must be true or false, not '$1'"
            return "$ACTIONUI_EXIT_USAGE" ;;
    esac
    return 0
}

# The window for element calls: an explicit override wins, then the environment.
_aui_window() {
    _aui_win=${ACTIONUI_REMOTE_WINDOW:-${ACTIONUI_WINDOW_UUID:-}}
    if [ -z "$_aui_win" ]; then
        _aui_clear_outcome
        _aui_error="no window: set ACTIONUI_WINDOW_UUID or call actionui_use_window"
        return "$ACTIONUI_EXIT_USAGE"
    fi
    return 0
}

# Address a window other than the one in the environment, for the rest of the script.
actionui_use_window() {
    ACTIONUI_REMOTE_WINDOW=$1
    return 0
}

# Build the members of a params object for an element call, into _aui_members:
#   $1 viewID (may be empty for window-only methods), $2 viewPartID (may be empty or 0),
#   $3 extra members already in JSON, without braces (may be empty).
_aui_element_params() {
    _aui_window || return $?
    _aui_json_string "$_aui_win"
    _aui_members="\"window\":$_aui_json"
    if [ -n "$1" ]; then
        _aui_int "$1" "VIEWID" || return $?
        _aui_members="$_aui_members,\"viewID\":$1"
    fi
    if [ -n "$2" ] && [ "$2" != "0" ]; then
        _aui_int "$2" "PART" || return $?
        _aui_members="$_aui_members,\"viewPartID\":$2"
    fi
    if [ -n "$3" ]; then
        _aui_members="$_aui_members,$3"
    fi
    return 0
}

# --- JSON in -----------------------------------------------------------------------------------

# One awk program walks the top level of a JSON text: actionui_remote_walk.awk beside this file,
# where the modes and what each prints are documented. It reads the text on stdin, and what it
# reads is replies - which carry no token - plus, in actionui_call, the caller's own params before
# the token is added. In mode reply it prints four lines: kind (R result / E error / B batch array
# / N a well-formed line that is not a reply / X unparseable), the raw id, the raw value, and a
# "." terminator so that an empty value still splits correctly.
_aui_walk() {
    /usr/bin/awk -v mode="$1" -v key="${2:-}" -f "$_AUI_AWK_WALK"
}

# Turn a raw JSON string literal into its text, into _aui_text. plutil does the unescaping
# (including \uXXXX and surrogate pairs); a literal without escapes needs no process at all. The
# sentinel keeps $(...) from eating the text's own trailing newlines; plutil's one is stripped.
_aui_unquote() {
    _aui_text=$1
    _aui_text=${_aui_text#\"}
    _aui_text=${_aui_text%\"}
    case $_aui_text in
        *\\*)
            _aui_text=$(printf '{"s":%s}' "$1" | /usr/bin/plutil -extract s raw -o - - 2>/dev/null; printf 'x')
            _aui_text=${_aui_text%x}
            _aui_text=${_aui_text%"$_AUI_NL"} ;;
    esac
    return 0
}

# --- Wire --------------------------------------------------------------------------------------

# The transport: send one request line and receive the reply, into _aui_reply. $1 is the line,
# $2 the id to wait for ("" for a batch, whose reply is an array or a whole-batch error with a
# null id). Returns 0, or ACTIONUI_EXIT_NO_HOST with _aui_error set.
#
# This is the nc implementation, one connection per request (PROTOCOL.md section 1 allows it).
# actionui_remote.zsh defines its own before sourcing this file, and that one wins.
#
# nc's stdin is a FIFO this shell holds open until the reply has been read. That is not fussiness:
# macOS nc half-closes the socket when its stdin hits EOF, and the host closes a connection on
# EOF even with a reply still pending on its main thread, so a request piped straight into nc
# can lose its own answer. The request FIFO is opened read-write before nc starts, so nc's open
# of it cannot block and a write into it can never raise SIGPIPE. The reply FIFO is opened
# read-only after nc starts, in a rendezvous with nc's own open of it for writing, so that EOF
# on it means nc is gone; that open is the one place this shell waits on nc, and only until nc
# has started.
if ! command -v _aui_send_receive >/dev/null 2>&1; then
_aui_send_receive() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        # zsh renices background jobs by default, and complains where it may not; not for the
        # two helpers here. Scoped to this function, so the caller's options are untouched.
        eval 'setopt localoptions no_bg_nice'
    fi
    _aui_endpoint || return $?
    _aui_timeout
    _aui_to_nc=${_aui_to%%.*}
    _aui_to_nc=${_aui_to_nc#"${_aui_to_nc%%[!0]*}"}
    case $_aui_to_nc in
        ''|0) _aui_to_nc=1 ;;
    esac
    _aui_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/actionui_remote.XXXXXX")
    if [ $? -ne 0 ] || [ -z "$_aui_dir" ]; then
        _aui_error="cannot create a temporary directory under ${TMPDIR:-/tmp}"
        return "$ACTIONUI_EXIT_NO_HOST"
    fi
    /usr/bin/mkfifo "$_aui_dir/in" "$_aui_dir/out"
    if [ $? -ne 0 ]; then
        /bin/rm -rf "$_aui_dir"
        _aui_error="cannot create FIFOs in $_aui_dir"
        return "$ACTIONUI_EXIT_NO_HOST"
    fi
    exec 8<>"$_aui_dir/in"
    # 8<&- matters: without it nc inherits descriptor 8, a write end of its own stdin, and never
    # sees EOF when this shell closes its copy - it then lingers until -w expires.
    # nc's own idle timeout gets two seconds of slack, so that on a host that never answers it is
    # this shell's read -t that expires, and the failure is classified as the timeout it is.
    /usr/bin/nc -w "$((_aui_to_nc + 2))" -U "$_aui_ep" <"$_aui_dir/in" >"$_aui_dir/out" 2>"$_aui_dir/err" 8<&- &
    _aui_nc=$!
    exec 9<"$_aui_dir/out"
    # The request is written by a forked helper (no exec, so nothing new is visible to ps): a
    # request larger than the pipe can hold would otherwise block this shell forever if nc has
    # already gone, since this shell holds the read end too and can never see SIGPIPE.
    printf '%s\n' "$1" >&8 &
    _aui_writer=$!
    _aui_reply=""
    _aui_rc=0
    _aui_reason=""
    while :; do
        # Cleared every time: on a timeout, read leaves the variable as it was, and a stale line
        # from the previous call would otherwise be taken for this call's reply.
        _aui_line=""
        IFS= read -r -t "$_aui_to_nc" -u 9 _aui_line 2>/dev/null
        _aui_read=$?
        if [ "$_aui_read" -ne 0 ] && [ -z "$_aui_line" ]; then
            _aui_rc="$ACTIONUI_EXIT_NO_HOST"
            break
        fi
        _aui_reply_matches "$_aui_line" "$2"
        _aui_match=$?
        if [ "$_aui_match" -eq 0 ]; then
            _aui_reply=$_aui_line
            break
        fi
        if [ "$_aui_match" -eq 2 ]; then
            _aui_rc="$ACTIONUI_EXIT_NO_HOST"
            _aui_reason="malformed reply from host: $_aui_line"
            break
        fi
        # Not ours: a reply to nothing we sent, or a line from a later protocol version. Skip it.
    done
    # Done with the FIFOs; the helper and nc are stopped and reaped. On success the reply is in
    # hand and nc is simply killed. On failure nc's wait status says what happened: killed (above
    # 128) means it was alive and the host never answered; 0 means the host closed; anything
    # else means the connection failed. nc prints nothing on stderr for a socket nobody listens
    # on, so its fate is the only way to tell the cases apart. On failure nc is signaled before
    # its stdin is closed: closing first would let it half-close, a one-shot listener would then
    # hang up, and nc would exit 0 on its own in the gap - a timeout misread as a hang-up.
    if [ "$_aui_rc" -ne 0 ]; then
        kill "$_aui_nc" 2>/dev/null
    fi
    exec 8>&-
    exec 9<&-
    kill "$_aui_writer" 2>/dev/null
    wait "$_aui_writer" 2>/dev/null
    kill "$_aui_nc" 2>/dev/null
    wait "$_aui_nc" 2>/dev/null
    _aui_ncrc=$?
    _aui_ncerr=""
    if [ -s "$_aui_dir/err" ]; then
        IFS= read -r _aui_ncerr < "$_aui_dir/err" 2>/dev/null
    fi
    /bin/rm -rf "$_aui_dir"
    if [ "$_aui_rc" -ne 0 ]; then
        if [ -n "$_aui_reason" ]; then
            _aui_error=$_aui_reason
        elif [ "$_aui_ncrc" -gt 128 ]; then
            _aui_error="no reply from $_aui_ep within $_aui_to_nc s"
        elif [ "$_aui_ncrc" -eq 0 ]; then
            _aui_error="the host at $_aui_ep closed the connection before replying"
        elif [ ! -S "$_aui_ep" ]; then
            _aui_error="no ActionUI host is listening at $_aui_ep (No such file or directory)"
        elif [ -n "$_aui_ncerr" ]; then
            _aui_error="cannot connect to $_aui_ep: ${_aui_ncerr#nc: }"
        else
            _aui_error="no ActionUI host is listening at $_aui_ep (Connection refused)"
        fi
        return "$_aui_rc"
    fi
    return 0
}
fi

# Is LINE the reply to request id EXPECTED? 0 when it is; 1 when it is some other line, to be
# skipped - a reply to nothing we sent, or a server-initiated line from a later protocol version,
# which section 3 says a client must ignore; 2 when it is not JSON at all. For a batch (EXPECTED empty) an array, or a
# whole-batch rejection carrying a null id. For a single request, the matching id, or an error
# with a null id: the host could not read the request at all, and this client only ever has one
# outstanding, so the answer is for us. The Python client waits for a matching id instead and
# reports a timeout; here the parse error is reported as what it is. Leaves the parsed pieces
# in _aui_kind, _aui_id and _aui_raw for the caller.
_aui_reply_matches() {
    _aui_parsed=$(printf '%s\n' "$1" | _aui_walk reply)
    _aui_parsed=${_aui_parsed%"$_AUI_NL".}
    _aui_kind=${_aui_parsed%%"$_AUI_NL"*}
    _aui_rest=${_aui_parsed#*"$_AUI_NL"}
    _aui_id=${_aui_rest%%"$_AUI_NL"*}
    _aui_raw=${_aui_rest#*"$_AUI_NL"}
    case $_aui_kind in
        B) [ -z "$2" ] && return 0 ;;
        R|E)
            if [ -z "$2" ]; then
                [ "$_aui_kind" = "E" ] && [ "$_aui_id" = "null" ] && return 0
            else
                [ "$_aui_id" = "$2" ] && return 0
                [ "$_aui_kind" = "E" ] && [ "$_aui_id" = "null" ] && return 0
            fi ;;
        N)
            # A well-formed line that is not a reply. Except when it carries our id: a reply
            # must hold a result or an error, so that one is malformed, not something to wait past.
            if [ -n "$2" ] && [ "$_aui_id" = "$2" ]; then
                return 2
            fi
            return 1 ;;
        *) return 2 ;;
    esac
    return 1
}

# Send METHOD with params members (JSON without braces, may be empty), or record it when a batch
# is open. On return: ACTIONUI_RESULT is the raw result and the status is 0; or ACTIONUI_ERROR_CODE
# and ACTIONUI_ERROR_MESSAGE are set and the status is 1; or 3 when the host could not be reached.
# The token rides in params on every request, as the Python client does, so that one connection
# per request (this file's nc mode) needs no extra round trip and a reconnect is transparent.
_aui_request() {
    ACTIONUI_RESULT=""
    ACTIONUI_ERROR_CODE=""
    ACTIONUI_ERROR_MESSAGE=""
    _aui_token || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_members=$2
    if [ -n "$_aui_tok" ]; then
        _aui_json_string "$_aui_tok"
        if [ -n "$_aui_members" ]; then
            _aui_members="$_aui_members,\"token\":$_aui_json"
        else
            _aui_members="\"token\":$_aui_json"
        fi
    fi
    _aui_json_string "$1"
    _aui_reqid=$_AUI_NEXT_ID
    _AUI_NEXT_ID=$((_AUI_NEXT_ID + 1))
    _aui_envelope="{\"jsonrpc\":\"2.0\",\"id\":$_aui_reqid,\"method\":$_aui_json"
    if [ -n "$_aui_members" ]; then
        _aui_envelope="$_aui_envelope,\"params\":{$_aui_members}"
    fi
    _aui_envelope="$_aui_envelope}"
    if [ "$_AUI_BATCH_ACTIVE" -eq 1 ]; then
        if [ -n "$_AUI_BATCH" ]; then
            _AUI_BATCH="$_AUI_BATCH,$_aui_envelope"
        else
            _AUI_BATCH=$_aui_envelope
        fi
        ACTIONUI_RESULT=""
        return 0
    fi
    _aui_send_receive "$_aui_envelope" "$_aui_reqid"
    _aui_rc=$?
    if [ "$_aui_rc" -ne 0 ]; then
        printf '%s\n' "$_aui_error" >&2
        return "$_aui_rc"
    fi
    # _aui_reply_matches has already parsed the accepted line into _aui_kind and _aui_raw.
    _aui_finish_reply
}

# Turn the parsed reply into the public outcome.
_aui_finish_reply() {
    ACTIONUI_ERROR_CODE=""
    ACTIONUI_ERROR_MESSAGE=""
    case $_aui_kind in
        R)
            ACTIONUI_RESULT=$_aui_raw
            return 0 ;;
        E)
            ACTIONUI_RESULT=""
            ACTIONUI_ERROR_CODE=$(printf '%s\n' "$_aui_raw" | _aui_walk key code)
            _aui_msg=$(printf '%s\n' "$_aui_raw" | _aui_walk key message)
            _aui_unquote "$_aui_msg"
            ACTIONUI_ERROR_MESSAGE=$_aui_text
            printf '[%s] %s\n' "${ACTIONUI_ERROR_CODE:--32603}" "$ACTIONUI_ERROR_MESSAGE" >&2
            return "$ACTIONUI_EXIT_REMOTE_ERROR" ;;
        *)
            ACTIONUI_RESULT=""
            _aui_error="malformed reply from host: $_aui_reply"
            printf '%s\n' "$_aui_error" >&2
            return "$ACTIONUI_EXIT_NO_HOST" ;;
    esac
}

# --- Batch -------------------------------------------------------------------------------------

# Between actionui_batch_begin and actionui_batch_send every call is recorded instead of sent,
# and the batch runs on the host inside one main-thread turn, in order (PROTOCOL.md section 3).
# actionui_batch_send prints the reply array exactly as the host sent it - one envelope per call,
# in order - and returns 1 when any member is an error (the first one on stderr), else 0.
actionui_batch_begin() {
    _AUI_BATCH_ACTIVE=1
    _AUI_BATCH=""
    return 0
}

actionui_batch_send() {
    if [ "$_AUI_BATCH_ACTIVE" -ne 1 ]; then
        _aui_clear_outcome
        printf '%s\n' "actionui_batch_send: no batch is open" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    _AUI_BATCH_ACTIVE=0
    ACTIONUI_RESULT=""
    ACTIONUI_ERROR_CODE=""
    ACTIONUI_ERROR_MESSAGE=""
    if [ -z "$_AUI_BATCH" ]; then
        printf '[]\n'
        ACTIONUI_RESULT="[]"
        return 0
    fi
    _aui_send_receive "[$_AUI_BATCH]" ""
    _aui_rc=$?
    _AUI_BATCH=""
    if [ "$_aui_rc" -ne 0 ]; then
        printf '%s\n' "$_aui_error" >&2
        return "$_aui_rc"
    fi
    if [ "$_aui_kind" = "E" ]; then
        # The whole batch was rejected (parse error, oversized batch): one object, null id.
        _aui_finish_reply
        return $?
    fi
    ACTIONUI_RESULT=$_aui_raw
    printf '%s\n' "$_aui_raw"
    _aui_first=""
    _aui_first=$(printf '%s\n' "$_aui_raw" | _aui_walk items | while IFS= read -r _aui_item; do
        _aui_code=$(printf '%s\n' "$_aui_item" | _aui_walk key error)
        if [ -n "$_aui_code" ]; then
            printf '%s\n' "$_aui_code"
            break
        fi
    done)
    if [ -n "$_aui_first" ]; then
        ACTIONUI_ERROR_CODE=$(printf '%s\n' "$_aui_first" | _aui_walk key code)
        _aui_msg=$(printf '%s\n' "$_aui_first" | _aui_walk key message)
        _aui_unquote "$_aui_msg"
        ACTIONUI_ERROR_MESSAGE=$_aui_text
        printf '[%s] %s\n' "${ACTIONUI_ERROR_CODE:--32603}" "$ACTIONUI_ERROR_MESSAGE" >&2
        return "$ACTIONUI_EXIT_REMOTE_ERROR"
    fi
    return 0
}

# --- Printing results --------------------------------------------------------------------------

# Print ACTIONUI_RESULT as the getters do. Inside a batch nothing is printed.
_aui_print_result() {
    if [ "$_AUI_BATCH_ACTIVE" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "$ACTIONUI_RESULT"
    return 0
}

# Print a string result as text: the text itself, and an empty line for null and for "".
_aui_print_text() {
    if [ "$_AUI_BATCH_ACTIVE" -eq 1 ]; then
        return 0
    fi
    case $ACTIONUI_RESULT in
        null|'') printf '\n' ;;
        *)
            _aui_unquote "$ACTIONUI_RESULT"
            printf '%s\n' "$_aui_text" ;;
    esac
    return 0
}

# --- Host-level methods ------------------------------------------------------------------------

actionui_hello() {
    _aui_request "actionui.hello" "" || return $?
    _aui_print_result
}

actionui_windows() {
    _aui_request "actionui.listWindows" "" || return $?
    if [ "$_AUI_BATCH_ACTIVE" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "$ACTIONUI_RESULT" | _aui_walk items | while IFS= read -r _aui_item; do
        _aui_unquote "$_aui_item"
        printf '%s\n' "$_aui_text"
    done
    return 0
}

# Any method, with `window` filled in when one is configured and PARAMS names none. Host methods
# (omc.*) go here. $1 method, $2 params as a JSON object (optional).
actionui_call() {
    if [ -z "${1:-}" ]; then
        _aui_clear_outcome
        printf '%s\n' "actionui_call: a method name is required" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    _aui_params=${2:-}
    # Surrounding whitespace is not part of the object.
    while :; do
        case $_aui_params in
            ' '*|"$_AUI_TAB"*|"$_AUI_NL"*|"$_AUI_CR"*) _aui_params=${_aui_params#?} ;;
            *' '|*"$_AUI_TAB"|*"$_AUI_NL"|*"$_AUI_CR") _aui_params=${_aui_params%?} ;;
            *) break ;;
        esac
    done
    case $_aui_params in
        ''|'{}'|'{ }') _aui_params="" ;;
        \{*\}) _aui_params=${_aui_params#\{}; _aui_params=${_aui_params%\}} ;;
        *)
            _aui_clear_outcome
            printf '%s\n' "actionui_call: params must be a JSON object, not '$_aui_params'" >&2
            return "$ACTIONUI_EXIT_USAGE" ;;
    esac
    _aui_win=${ACTIONUI_REMOTE_WINDOW:-${ACTIONUI_WINDOW_UUID:-}}
    if [ -n "$_aui_win" ]; then
        _aui_has_window=""
        if [ -n "$_aui_params" ]; then
            _aui_has_window=$(printf '{%s}\n' "$_aui_params" | _aui_walk key window)
        fi
        if [ -z "$_aui_has_window" ]; then
            _aui_json_string "$_aui_win"
            if [ -n "$_aui_params" ]; then
                _aui_params="\"window\":$_aui_json,$_aui_params"
            else
                _aui_params="\"window\":$_aui_json"
            fi
        fi
    fi
    _aui_request "$1" "$_aui_params" || return $?
    _aui_print_result
}

# --- Window methods ----------------------------------------------------------------------------
# Every function here addresses the window from ACTIONUI_WINDOW_UUID (or actionui_use_window).

# A window-only call: $1 method, $2 extra members (optional). Prints the result.
_aui_window_call() {
    _aui_element_params "" "" "${2:-}" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "$1" "$_aui_members" || return $?
    _aui_print_result
}

# The same, for a setter: the host answers true and nothing is printed, as the Python CLI does.
_aui_window_set() {
    _aui_element_params "" "" "${2:-}" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "$1" "$_aui_members"
}

# An element call: $1 method, $2 VIEWID, $3 PART, $4 extra members (optional). Prints the result.
_aui_element_call() {
    _aui_int "$2" "VIEWID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_element_params "$2" "$3" "${4:-}" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "$1" "$_aui_members" || return $?
    _aui_print_result
}

# The same, for a setter: nothing is printed.
_aui_element_set() {
    _aui_int "$2" "VIEWID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_element_params "$2" "$3" "${4:-}" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "$1" "$_aui_members"
}

_aui_need() {   # $1 count of required args present, $2 usage
    if [ "$1" -eq 0 ]; then
        _aui_clear_outcome
        printf '%s\n' "usage: $2" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    return 0
}

# -- discovery

actionui_elements() { _aui_window_call "actionui.getElementInfo"; }
actionui_get_element_info() { _aui_window_call "actionui.getElementInfo"; }
actionui_content_size_limits() { _aui_window_call "actionui.contentSizeLimits"; }

# -- values

# actionui_get_value VIEWID [PART]
actionui_get_value() {
    _aui_need "$#" "actionui_get_value VIEWID [PART]" || return $?
    _aui_element_call "actionui.getValue" "$1" "${2:-0}"
}

# actionui_set_value VIEWID JSON [PART]
actionui_set_value() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_value VIEWID JSON [PART]"; return $?; fi
    _aui_element_set "actionui.setValue" "$1" "${3:-0}" "\"value\":$2"
}

# actionui_get_string VIEWID [PART] [CONTENT_TYPE]   - prints the text itself
actionui_get_string() {
    _aui_need "$#" "actionui_get_string VIEWID [PART] [CONTENT_TYPE]" || return $?
    _aui_int "$1" "VIEWID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_more=""
    if [ -n "${3:-}" ]; then
        _aui_json_string "$3"
        _aui_more="\"contentType\":$_aui_json"
    fi
    _aui_element_params "$1" "${2:-0}" "$_aui_more" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "actionui.getValueString" "$_aui_members" || return $?
    _aui_print_text
}

# actionui_set_string VIEWID TEXT [PART] [CONTENT_TYPE]
actionui_set_string() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_string VIEWID TEXT [PART] [CONTENT_TYPE]"; return $?; fi
    _aui_json_string "$2"
    _aui_more="\"value\":$_aui_json"
    if [ -n "${4:-}" ]; then
        _aui_json_string "$4"
        _aui_more="$_aui_more,\"contentType\":$_aui_json"
    fi
    _aui_element_set "actionui.setValueString" "$1" "${3:-0}" "$_aui_more"
}

actionui_get_int() { actionui_get_value "$@"; }
actionui_get_double() { actionui_get_value "$@"; }
actionui_get_bool() { actionui_get_value "$@"; }

# actionui_set_int VIEWID N [PART]
actionui_set_int() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_int VIEWID N [PART]"; return $?; fi
    _aui_int "$2" "N" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    actionui_set_value "$1" "$2" "${3:-0}"
}

# Is $1 a JSON number? An optional minus, digits with at most one dot and no leading zero,
# then optionally e or E, an optional sign, and digits.
_aui_json_number() {
    _aui_num=$1
    case $_aui_num in -*) _aui_num=${_aui_num#-} ;; esac
    _aui_mant=${_aui_num%%[eE]*}
    case $_aui_mant in
        ''|*[!0-9.]*|*.*.*|.*|*.|0[0-9]*) return 1 ;;
    esac
    if [ "$_aui_mant" != "$_aui_num" ]; then
        _aui_exp=${_aui_num#*[eE]}
        case $_aui_exp in -*|+*) _aui_exp=${_aui_exp#?} ;; esac
        case $_aui_exp in ''|*[!0-9]*) return 1 ;; esac
    fi
    return 0
}

# actionui_set_double VIEWID NUMBER [PART]   - a JSON number: digits, optional sign, fraction, exponent
actionui_set_double() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_double VIEWID NUMBER [PART]"; return $?; fi
    if ! _aui_json_number "$2"; then
        _aui_clear_outcome
        printf '%s\n' "NUMBER must be a number, not '$2'" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    actionui_set_value "$1" "$2" "${3:-0}"
}

# actionui_set_bool VIEWID true|false [PART]
actionui_set_bool() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_bool VIEWID true|false [PART]"; return $?; fi
    _aui_boolean "$2" "VALUE" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    actionui_set_value "$1" "$_aui_bool" "${3:-0}"
}

# -- properties and state

# actionui_get_property VIEWID NAME
actionui_get_property() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_get_property VIEWID NAME"; return $?; fi
    _aui_json_string "$2"
    _aui_element_call "actionui.getProperty" "$1" "" "\"name\":$_aui_json"
}

# actionui_set_property VIEWID NAME JSON
actionui_set_property() {
    if [ "$#" -lt 3 ]; then _aui_need 0 "actionui_set_property VIEWID NAME JSON"; return $?; fi
    _aui_json_string "$2"
    _aui_element_set "actionui.setProperty" "$1" "" "\"name\":$_aui_json,\"value\":$3"
}

# actionui_set_enabled VIEWID true|false   - sugar for the `disabled` property
actionui_set_enabled() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_enabled VIEWID true|false"; return $?; fi
    _aui_boolean "$2" "ENABLED" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    if [ "$_aui_bool" = "true" ]; then _aui_bool=false; else _aui_bool=true; fi
    actionui_set_property "$1" "disabled" "$_aui_bool"
}

# actionui_set_hidden VIEWID true|false   - sugar for the `hidden` property
actionui_set_hidden() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_hidden VIEWID true|false"; return $?; fi
    _aui_boolean "$2" "HIDDEN" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    actionui_set_property "$1" "hidden" "$_aui_bool"
}

# actionui_get_state VIEWID KEY
actionui_get_state() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_get_state VIEWID KEY"; return $?; fi
    _aui_json_string "$2"
    _aui_element_call "actionui.getState" "$1" "" "\"key\":$_aui_json"
}

# actionui_get_state_string VIEWID KEY   - prints the text itself
actionui_get_state_string() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_get_state_string VIEWID KEY"; return $?; fi
    _aui_int "$1" "VIEWID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_json_string "$2"
    _aui_element_params "$1" "" "\"key\":$_aui_json" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_request "actionui.getStateString" "$_aui_members" || return $?
    _aui_print_text
}

# actionui_set_state VIEWID KEY JSON
actionui_set_state() {
    if [ "$#" -lt 3 ]; then _aui_need 0 "actionui_set_state VIEWID KEY JSON"; return $?; fi
    _aui_json_string "$2"
    _aui_element_set "actionui.setState" "$1" "" "\"key\":$_aui_json,\"value\":$3"
}

# actionui_set_state_string VIEWID KEY TEXT
actionui_set_state_string() {
    if [ "$#" -lt 3 ]; then _aui_need 0 "actionui_set_state_string VIEWID KEY TEXT"; return $?; fi
    _aui_json_string "$2"
    _aui_more="\"key\":$_aui_json"
    _aui_json_string "$3"
    _aui_element_set "actionui.setStateString" "$1" "" "$_aui_more,\"value\":$_aui_json"
}

# -- rows and selection

actionui_get_column_count() {
    _aui_need "$#" "actionui_get_column_count VIEWID" || return $?
    _aui_element_call "actionui.getColumnCount" "$1" ""
}

# actionui_get_rows VIEWID   - JSON array of arrays, or null
actionui_get_rows() {
    _aui_need "$#" "actionui_get_rows VIEWID" || return $?
    _aui_element_call "actionui.getRows" "$1" ""
}

# actionui_set_rows VIEWID JSON   - JSON array of arrays of strings
actionui_set_rows() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_set_rows VIEWID JSON"; return $?; fi
    _aui_element_set "actionui.setRows" "$1" "" "\"rows\":$2"
}

actionui_append_rows() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_append_rows VIEWID JSON"; return $?; fi
    _aui_element_set "actionui.appendRows" "$1" "" "\"rows\":$2"
}

actionui_clear_rows() {
    _aui_need "$#" "actionui_clear_rows VIEWID" || return $?
    _aui_element_set "actionui.clearRows" "$1" ""
}

# actionui_select_row VIEWID INDEX   - prints the selected row, or null when out of range
actionui_select_row() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_select_row VIEWID INDEX"; return $?; fi
    _aui_int "$2" "INDEX" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_element_call "actionui.selectRow" "$1" "" "\"index\":$2"
}

# actionui_select_row_with_content VIEWID TEXT [COLUMN]   - prints the row index, or -1
actionui_select_row_with_content() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_select_row_with_content VIEWID TEXT [COLUMN]"; return $?; fi
    _aui_json_string "$2"
    _aui_more="\"text\":$_aui_json"
    if [ -n "${3:-}" ]; then
        _aui_int "$3" "COLUMN" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
        _aui_more="$_aui_more,\"column\":$3"
    fi
    _aui_element_call "actionui.selectRowWithContent" "$1" "" "$_aui_more"
}

actionui_clear_selection() {
    _aui_need "$#" "actionui_clear_selection VIEWID" || return $?
    _aui_element_set "actionui.clearSelection" "$1" ""
}

# -- structural mutation

# Optional container and position members for the insert methods, into _aui_more.
_aui_insert_extras() {
    _aui_more=""
    if [ -n "${1:-}" ]; then
        _aui_json_string "$1"
        _aui_more=",\"container\":$_aui_json"
    fi
    if [ -n "${2:-}" ]; then
        case $2 in
            append|prepend) _aui_more="$_aui_more,\"position\":\"$2\"" ;;
            *)              _aui_more="$_aui_more,\"position\":$2" ;;
        esac
    fi
    return 0
}

# actionui_insert_element PARENTID ELEMENT_JSON [CONTAINER] [POSITION]   - prints the new id
# POSITION is append, prepend, or a JSON object such as {"kind":"at","index":2}.
actionui_insert_element() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_insert_element PARENTID ELEMENT_JSON [CONTAINER] [POSITION]"; return $?; fi
    _aui_int "$1" "PARENTID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_insert_extras "${3:-}" "${4:-}"
    _aui_window_call "actionui.insertElement" "\"parentID\":$1,\"element\":$2$_aui_more"
}

# actionui_insert_row PARENTID CELLS_JSON [CONTAINER] [POSITION]   - prints the new ids
actionui_insert_row() {
    if [ "$#" -lt 2 ]; then _aui_need 0 "actionui_insert_row PARENTID CELLS_JSON [CONTAINER] [POSITION]"; return $?; fi
    _aui_int "$1" "PARENTID" || { _aui_rc=$?; printf '%s\n' "$_aui_error" >&2; return "$_aui_rc"; }
    _aui_insert_extras "${3:-}" "${4:-}"
    _aui_window_call "actionui.insertRow" "\"parentID\":$1,\"cells\":$2$_aui_more"
}

actionui_remove_element() {
    _aui_need "$#" "actionui_remove_element VIEWID" || return $?
    _aui_element_set "actionui.removeElement" "$1" ""
}

# -- presentation

# Shared tail of the present_modal forms: $1 the source member, then FORMAT STYLE ON_DISMISS.
_aui_present_modal() {
    _aui_more=$1
    if [ -n "${2:-}" ]; then _aui_json_string "$2"; _aui_more="$_aui_more,\"format\":$_aui_json"; fi
    if [ -n "${3:-}" ]; then _aui_json_string "$3"; _aui_more="$_aui_more,\"style\":$_aui_json"; fi
    if [ -n "${4:-}" ]; then _aui_json_string "$4"; _aui_more="$_aui_more,\"onDismissActionID\":$_aui_json"; fi
    _aui_window_set "actionui.presentModal" "$_aui_more"
}

# actionui_present_modal_element ELEMENT_JSON [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]
actionui_present_modal_element() {
    _aui_need "$#" "actionui_present_modal_element ELEMENT_JSON [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]" || return $?
    _aui_present_modal "\"element\":$1" "${2:-}" "${3:-}" "${4:-}"
}

# actionui_present_modal_json TEXT [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]   - JSON or plist text
actionui_present_modal_json() {
    _aui_need "$#" "actionui_present_modal_json TEXT [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]" || return $?
    _aui_json_string "$1"
    _aui_present_modal "\"json\":$_aui_json" "${2:-}" "${3:-}" "${4:-}"
}

# actionui_present_modal_path PATH [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]   - a resource the host resolves
actionui_present_modal_path() {
    _aui_need "$#" "actionui_present_modal_path PATH [FORMAT] [STYLE] [ON_DISMISS_ACTION_ID]" || return $?
    _aui_json_string "$1"
    _aui_present_modal "\"path\":$_aui_json" "${2:-}" "${3:-}" "${4:-}"
}

actionui_dismiss_modal() { _aui_window_set "actionui.dismissModal"; }

# actionui_present_alert TITLE [MESSAGE] [BUTTONS_JSON]
actionui_present_alert() {
    _aui_need "$#" "actionui_present_alert TITLE [MESSAGE] [BUTTONS_JSON]" || return $?
    _aui_json_string "$1"
    _aui_more="\"title\":$_aui_json"
    if [ -n "${2:-}" ]; then _aui_json_string "$2"; _aui_more="$_aui_more,\"message\":$_aui_json"; fi
    if [ -n "${3:-}" ]; then _aui_more="$_aui_more,\"buttons\":$3"; fi
    _aui_window_set "actionui.presentAlert" "$_aui_more"
}

# actionui_present_confirmation_dialog TITLE MESSAGE BUTTONS_JSON   - MESSAGE may be ""
actionui_present_confirmation_dialog() {
    if [ "$#" -lt 3 ]; then _aui_need 0 "actionui_present_confirmation_dialog TITLE MESSAGE BUTTONS_JSON"; return $?; fi
    _aui_json_string "$1"
    _aui_more="\"title\":$_aui_json"
    if [ -n "$2" ]; then _aui_json_string "$2"; _aui_more="$_aui_more,\"message\":$_aui_json"; fi
    _aui_window_set "actionui.presentConfirmationDialog" "$_aui_more,\"buttons\":$3"
}

actionui_dismiss_dialog() { _aui_window_set "actionui.dismissDialog"; }

# actionui_present_toast MESSAGE [DURATION] [ACTION_TITLE] [ACTION_ID]
actionui_present_toast() {
    _aui_need "$#" "actionui_present_toast MESSAGE [DURATION] [ACTION_TITLE] [ACTION_ID]" || return $?
    _aui_json_string "$1"
    _aui_more="\"message\":$_aui_json"
    if [ -n "${2:-}" ]; then
        case $2 in
            *[!0-9.]*|.|*.*.*)
                _aui_clear_outcome
                printf '%s\n' "DURATION must be a number of seconds, not '$2'" >&2
                return "$ACTIONUI_EXIT_USAGE" ;;
        esac
        _aui_more="$_aui_more,\"duration\":$2"
    fi
    if [ -n "${3:-}" ]; then _aui_json_string "$3"; _aui_more="$_aui_more,\"actionTitle\":$_aui_json"; fi
    if [ -n "${4:-}" ]; then _aui_json_string "$4"; _aui_more="$_aui_more,\"actionID\":$_aui_json"; fi
    _aui_window_set "actionui.presentToast" "$_aui_more"
}

actionui_dismiss_toast() { _aui_window_set "actionui.dismissToast"; }

# --- Command line ------------------------------------------------------------------------------
#
# The same commands as `python3 -m actionui_remote`, minus --token: a token on the command line
# is in argv, which every process can read, and keeping it out of there is what this file is for.
# Use the environment or ACTIONUI_REMOTE_TOKEN_FD instead.

_aui_usage() {
    /bin/cat <<'EOF'
usage: actionui_remote.sh [--endpoint PATH] [--window UUID] [--timeout SECONDS] COMMAND ...

commands:
  hello                                  print the host's actionui.hello
  windows                                print every window UUID, one per line
  elements                               print the window's element ids and types as JSON
  get-value VIEWID [--part N]            print an element's value as JSON
  set-value VIEWID JSON [--part N]       set an element's value from JSON
  get-string VIEWID [--part N] [--content-type TYPE]    print an element's value as text
  set-string VIEWID TEXT [--part N] [--content-type TYPE]  set an element's value from text
  get-rows VIEWID                        print a Table's rows as JSON
  set-rows VIEWID JSON                   set a Table's rows from a JSON array of arrays
  get-property VIEWID NAME               print a property as JSON
  set-property VIEWID NAME JSON          set a property from JSON
  get-state VIEWID KEY                   print a state key as JSON
  set-state VIEWID KEY JSON              set a state key from JSON
  call METHOD [JSON]                     call any method, host methods included

--endpoint, --window and --timeout default to ACTIONUI_REMOTE_ENDPOINT, ACTIONUI_WINDOW_UUID and
15 seconds. A token comes from ACTIONUI_REMOTE_TOKEN or ACTIONUI_REMOTE_TOKEN_FD, never from the
command line. Exit codes: 0 ok, 1 the host answered
an error, 2 bad usage, 3 no host to talk to. An argument starting with a dash that is not a
number needs -- before it, as in `set-string 2 -- -hello`.
EOF
}

actionui_main() {
    _aui_part=0
    _aui_ctype=""
    while [ "$#" -gt 0 ]; do
        case $1 in
            --endpoint)
                [ "$#" -ge 2 ] || { printf '%s\n' "--endpoint needs a path" >&2; return "$ACTIONUI_EXIT_USAGE"; }
                ACTIONUI_REMOTE_ENDPOINT=$2; shift 2 ;;
            --endpoint=*) ACTIONUI_REMOTE_ENDPOINT=${1#--endpoint=}; shift ;;
            --window)
                [ "$#" -ge 2 ] || { printf '%s\n' "--window needs a UUID" >&2; return "$ACTIONUI_EXIT_USAGE"; }
                ACTIONUI_REMOTE_WINDOW=$2; shift 2 ;;
            --window=*) ACTIONUI_REMOTE_WINDOW=${1#--window=}; shift ;;
            --timeout)
                [ "$#" -ge 2 ] || { printf '%s\n' "--timeout needs a number of seconds" >&2; return "$ACTIONUI_EXIT_USAGE"; }
                ACTIONUI_REMOTE_TIMEOUT=$2; shift 2 ;;
            --timeout=*) ACTIONUI_REMOTE_TIMEOUT=${1#--timeout=}; shift ;;
            --token|--token=*)
                printf '%s\n' "--token is not accepted: a token in argv is readable by every process. Use ACTIONUI_REMOTE_TOKEN or ACTIONUI_REMOTE_TOKEN_FD." >&2
                return "$ACTIONUI_EXIT_USAGE" ;;
            -h|--help) _aui_usage; return "$ACTIONUI_EXIT_OK" ;;
            --) shift; break ;;
            -*) printf '%s\n' "unknown option $1" >&2; _aui_usage >&2; return "$ACTIONUI_EXIT_USAGE" ;;
            *) break ;;
        esac
    done
    if [ "$#" -eq 0 ]; then
        _aui_usage >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    _aui_cmd=$1
    shift
    if ! _aui_positive_seconds "${ACTIONUI_REMOTE_TIMEOUT:-15}"; then
        printf '%s\n' "--timeout must be a number of seconds greater than zero" >&2
        return "$ACTIONUI_EXIT_USAGE"
    fi
    # Pull --part and --content-type out from wherever they sit; keep the rest positional.
    _aui_a1=""; _aui_a2=""; _aui_a3=""; _aui_n=0
    _aui_dashdash=0
    while [ "$#" -gt 0 ]; do
        if [ "$_aui_dashdash" -eq 0 ]; then
            case $1 in
                --part)
                    [ "$#" -ge 2 ] || { printf '%s\n' "--part needs a number" >&2; return "$ACTIONUI_EXIT_USAGE"; }
                    _aui_part=$2; shift 2; continue ;;
                --part=*) _aui_part=${1#--part=}; shift; continue ;;
                --content-type)
                    [ "$#" -ge 2 ] || { printf '%s\n' "--content-type needs a type" >&2; return "$ACTIONUI_EXIT_USAGE"; }
                    _aui_ctype=$2; shift 2; continue ;;
                --content-type=*) _aui_ctype=${1#--content-type=}; shift; continue ;;
                --) _aui_dashdash=1; shift; continue ;;
                -?*)
                    case $1 in
                        -[0-9]*) ;;
                        *) printf '%s\n' "unknown option $1 (put -- before an argument that starts with a dash)" >&2; return "$ACTIONUI_EXIT_USAGE" ;;
                    esac ;;
            esac
        fi
        _aui_n=$((_aui_n + 1))
        case $_aui_n in
            1) _aui_a1=$1 ;;
            2) _aui_a2=$1 ;;
            3) _aui_a3=$1 ;;
            *) printf '%s\n' "too many arguments for $_aui_cmd" >&2; return "$ACTIONUI_EXIT_USAGE" ;;
        esac
        shift
    done
    _aui_int "$_aui_part" "--part" || { printf '%s\n' "$_aui_error" >&2; return "$ACTIONUI_EXIT_USAGE"; }

    # Before the window check, so a handler outside any window is told there is no host (3)
    # whatever the command, rather than that its command line is wrong - as the Python CLI does.
    _aui_endpoint || { printf '%s\n' "$_aui_error" >&2; return "$ACTIONUI_EXIT_NO_HOST"; }

    case $_aui_cmd in
        hello|windows|call) ;;
        *)
            _aui_window || { printf '%s\n' "no window: pass --window or set ACTIONUI_WINDOW_UUID" >&2; return "$ACTIONUI_EXIT_USAGE"; } ;;
    esac

    _aui_args() {   # $1 required count, $2 accepted count, $3 usage
        if [ "$_aui_n" -lt "$1" ] || [ "$_aui_n" -gt "$2" ]; then
            printf '%s\n' "usage: actionui_remote.sh $3" >&2
            return "$ACTIONUI_EXIT_USAGE"
        fi
        return 0
    }
    case $_aui_cmd in
        hello)        _aui_args 0 0 "hello" && actionui_hello ;;
        windows)      _aui_args 0 0 "windows" && actionui_windows ;;
        elements)     _aui_args 0 0 "elements" && actionui_elements ;;
        get-value)    _aui_args 1 1 "get-value VIEWID [--part N]" && actionui_get_value "$_aui_a1" "$_aui_part" ;;
        set-value)    _aui_args 2 2 "set-value VIEWID JSON [--part N]" && actionui_set_value "$_aui_a1" "$_aui_a2" "$_aui_part" ;;
        get-string)   _aui_args 1 1 "get-string VIEWID [--part N] [--content-type TYPE]" && actionui_get_string "$_aui_a1" "$_aui_part" "$_aui_ctype" ;;
        set-string)   _aui_args 2 2 "set-string VIEWID TEXT [--part N] [--content-type TYPE]" && actionui_set_string "$_aui_a1" "$_aui_a2" "$_aui_part" "$_aui_ctype" ;;
        get-rows)     _aui_args 1 1 "get-rows VIEWID" && actionui_get_rows "$_aui_a1" ;;
        set-rows)     _aui_args 2 2 "set-rows VIEWID JSON" && actionui_set_rows "$_aui_a1" "$_aui_a2" ;;
        get-property) _aui_args 2 2 "get-property VIEWID NAME" && actionui_get_property "$_aui_a1" "$_aui_a2" ;;
        set-property) _aui_args 3 3 "set-property VIEWID NAME JSON" && actionui_set_property "$_aui_a1" "$_aui_a2" "$_aui_a3" ;;
        get-state)    _aui_args 2 2 "get-state VIEWID KEY" && actionui_get_state "$_aui_a1" "$_aui_a2" ;;
        set-state)    _aui_args 3 3 "set-state VIEWID KEY JSON" && actionui_set_state "$_aui_a1" "$_aui_a2" "$_aui_a3" ;;
        call)         _aui_args 1 2 "call METHOD [JSON]" && actionui_call "$_aui_a1" "$_aui_a2" ;;
        *)
            printf '%s\n' "unknown command $_aui_cmd" >&2
            _aui_usage >&2
            return "$ACTIONUI_EXIT_USAGE" ;;
    esac
}

# Run the command line only when executed, not when sourced. bash sets BASH_SOURCE to this file
# and $0 to the caller's script when sourced; zsh records the context. Which of the two shells
# this is was settled at the top of the file, so there is no third case here.
_aui_executed=0
if [ -n "${ZSH_VERSION:-}" ]; then
    case ${ZSH_EVAL_CONTEXT:-} in
        toplevel) _aui_executed=1 ;;
    esac
elif [ "${BASH_SOURCE:-}" = "$0" ]; then
    _aui_executed=1
fi
if [ "$_aui_executed" -eq 1 ]; then
    actionui_main "$@"
    exit $?
fi
unset _aui_executed
