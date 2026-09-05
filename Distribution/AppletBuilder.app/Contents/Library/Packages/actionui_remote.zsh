#!/bin/zsh
# actionui_remote.zsh - actionui_remote.sh with zsh's own socket module as the transport.
#
# Everything about the API, the commands, the exit codes and the token is in actionui_remote.sh,
# which this file sources; read that first. What this file changes is only how a request reaches
# the host: instead of one nc process and a pair of FIFOs per request, zsh connects to the Unix
# socket itself (zsh/net/socket, shipped with /bin/zsh) and keeps the connection open for the
# rest of the script, the way the Python client does. No helper process runs, and /bin/zsh is a
# restricted Apple binary, so the token never sits in the environment of anything that ps can
# read - the same guarantee as the sh version, with less machinery and less latency.
#
# Use as a library:
#
#     . /path/to/actionui_remote.zsh
#     actionui_set_string 4 "Working..."
#
# Use as a command, exactly like actionui_remote.sh:
#
#     actionui_remote.zsh --window UUID get-value 5
#
# Connection handling, matching the Python client: connected on first use; a request that fails
# to send reconnects once and resends, since nothing reached the host; a failure while waiting
# for the reply is reported, not retried, since the request may already have been applied. A
# change of ACTIONUI_REMOTE_ENDPOINT between calls reconnects. actionui_disconnect closes the
# connection early; otherwise it closes when the shell exits.
#
# One side effect to know about: while a request is being written, SIGPIPE is ignored, so that a
# host that went away is reported as a failed send instead of killing the script. The previous
# disposition is restored to the default afterwards, which drops a PIPE trap of the script's own
# if it had set one; set it again after the first call if you need it.

if [[ -z ${ZSH_VERSION:-} ]]; then
    printf '%s\n' "actionui_remote.zsh must be run or sourced by zsh; use actionui_remote.sh from other shells" >&2
    return 2 2>/dev/null || exit 2
fi

zmodload zsh/net/socket 2>/dev/null
if [[ $? -ne 0 ]]; then
    printf '%s\n' "actionui_remote.zsh: the zsh/net/socket module is not available in this zsh; use actionui_remote.sh" >&2
    return 3 2>/dev/null || exit 3
fi

_AUI_ZFD=""             # the open socket, or empty
_AUI_ZENDPOINT=""       # the endpoint it was opened to

# Close the connection, if any.
actionui_disconnect() {
    if [[ -n $_AUI_ZFD ]]; then
        # No other redirection may appear on this line: `exec` with only redirections applies
        # every one of them to the shell itself, so a 2>/dev/null here would silence the script's
        # stderr for good.
        exec {_AUI_ZFD}>&-
    fi
    _AUI_ZFD=""
    _AUI_ZENDPOINT=""
    return 0
}

# Make sure a connection to _aui_ep is open. zsocket reports its own errors on stderr in its own
# words; they are silenced here and replaced with the message the other clients give.
_aui_zsh_connect() {
    if [[ -n $_AUI_ZFD && $_AUI_ZENDPOINT == "$_aui_ep" ]]; then
        return 0
    fi
    actionui_disconnect
    local REPLY=""      # zsocket's out-parameter; local, so the caller's REPLY is untouched
    zsocket "$_aui_ep" 2>/dev/null
    if [[ $? -ne 0 || -z $REPLY ]]; then
        if [[ -e $_aui_ep ]]; then
            _aui_error="no ActionUI host is listening at $_aui_ep (Connection refused)"
        else
            _aui_error="no ActionUI host is listening at $_aui_ep (No such file or directory)"
        fi
        return "$ACTIONUI_EXIT_NO_HOST"
    fi
    _AUI_ZFD=$REPLY
    _AUI_ZENDPOINT=$_aui_ep
    return 0
}

# The transport actionui_remote.sh calls: send one line, receive the reply into _aui_reply.
# $1 the request line, $2 the id to wait for ("" for a batch). Defined before the .sh is sourced,
# so the .sh keeps this one instead of defining its nc version.
_aui_send_receive() {
    _aui_endpoint || return $?
    _aui_timeout
    local _aui_attempt _aui_sent
    for _aui_attempt in 1 2; do
        _aui_zsh_connect || return $?
        trap '' PIPE
        print -r -u "$_AUI_ZFD" -- "$1" 2>/dev/null
        _aui_sent=$?
        trap - PIPE
        if [[ $_aui_sent -eq 0 ]]; then
            break
        fi
        # The host closed an idle connection, or went away. Nothing reached it: reconnect, resend.
        actionui_disconnect
        if [[ $_aui_attempt -eq 2 ]]; then
            _aui_error="cannot send to $_aui_ep: the connection was closed"
            return "$ACTIONUI_EXIT_NO_HOST"
        fi
    done
    _aui_reply=""
    while true; do
        _aui_line=""
        IFS= read -r -t "$_aui_to" -u "$_AUI_ZFD" _aui_line
        _aui_read=$?
        if [[ $_aui_read -ne 0 && -z $_aui_line ]]; then
            # zsh's read does not distinguish a timeout from the host closing the connection.
            actionui_disconnect
            _aui_error="no reply from $_aui_ep within $_aui_to s, or the host closed the connection"
            return "$ACTIONUI_EXIT_NO_HOST"
        fi
        _aui_reply_matches "$_aui_line" "$2"
        _aui_match=$?
        if [[ $_aui_match -eq 0 ]]; then
            _aui_reply=$_aui_line
            return 0
        fi
        if [[ $_aui_match -eq 2 ]]; then
            actionui_disconnect
            _aui_error="malformed reply from host: $_aui_line"
            return "$ACTIONUI_EXIT_NO_HOST"
        fi
        # Not ours: a reply to nothing we sent, or a line from a later protocol version. Skip it.
    done
}

# Now the API. When this file is executed as a command, the .sh sees itself sourced (it is) and
# returns without running the command line; that is done here, after both files are loaded.
_aui_zsh_dir=${${(%):-%x}:A:h}
source "$_aui_zsh_dir/actionui_remote.sh"
unset _aui_zsh_dir
# The .sh turns itself away when its awk programs are not beside it, and says so itself. What is
# tested here is what it was supposed to leave behind rather than the status it returned, because
# a status is a proxy and the API is the thing that matters. actionui_main is the last thing the
# .sh defines, and $+functions asks whether it is a function rather than whether the name resolves
# to something - a stray executable of that name on PATH must not read as a loaded API. The
# transport above was defined before the source and would otherwise survive it, actionui_disconnect
# included.
if (( ! ${+functions[actionui_main]} )); then
    unset -f actionui_disconnect _aui_zsh_connect _aui_send_receive 2>/dev/null
    unset _AUI_ZFD _AUI_ZENDPOINT
    return 2 2>/dev/null || exit 2
fi

if [[ ${ZSH_EVAL_CONTEXT:-} == toplevel ]]; then
    actionui_main "$@"
    _aui_zsh_rc=$?
    actionui_disconnect
    exit $_aui_zsh_rc
fi
