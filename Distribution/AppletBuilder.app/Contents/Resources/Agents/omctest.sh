#!/bin/sh
# omctest.sh - the OMC applet test harness library.
#
# A test file is plain POSIX sh. It sources this library, drives an applet's real
# handler scripts inside a simulated OMC environment, and asserts on everything
# those handlers touch: model files, state directories, exit codes, and what they
# wrote toward the window.
#
# Three sourcing modes, decided by the bootstrap block at the very end of this
# file (ordered and exclusive):
#
#   1. OMCTEST_PREPARED=1 in the environment - the runner has already built the
#      mock environment for this test file. Define functions, attach to it.
#   2. OMCTEST_RUNNER=1 - being sourced by "appletbuilder test" (or by
#      applet_build --test) for the runner functions only. Define functions and
#      do nothing else.
#   3. Neither - standalone mode. Locate the .app, build the whole environment
#      for this one file, install the cleanup trap, and carry on. This is what
#      makes "OMCTEST_APP=./My.app OMCTEST_LIB=... sh Tests/10-x.test.sh" work.
#
# A test-file child inherits BOTH variables from the runner, which is why
# OMCTEST_PREPARED is tested first and wins.
#
# Test-author guide: Documentation/omctest_guide.md.
#
# Dialect: everything here, and every stub emitted from here, runs under
# /bin/sh - macOS bash 3.2 in POSIX mode. No arrays, no process substitution,
# no bash 4 parameter expansions. Validate with "/bin/sh -n" (never "bash -n")
# and with scan_bash4_isms from lib.validate.sh.

OMCTEST_API_VERSION=1
export OMCTEST_API_VERSION

# The four tools this harness always replaces with recording stubs.
OMCTEST_DEFAULT_STUBS="alert notify omc_dialog_control omc_next_command"

# =============================================================================
# The engine contract, pinned
# =============================================================================
#
# Everything omc_run does below is a deliberate reproduction of engine behavior,
# read out of the source rather than remembered. Recorded here with sources so a
# future reader can re-verify rather than re-guess (full write-up in the OMC
# repo's Private/omctest-phase0-findings.md):
#
#   Interpreter map          AbracodeFramework/OmcExecutor.cp:620-635
#                            (sExtensionToShellMap). .sh -> /bin/sh, .zsh ->
#                            /bin/zsh, .bash -> /bin/bash, .py -> see below.
#                            An unknown or absent extension gets kDefaultShell,
#                            /bin/sh.
#   Python resolution        OmcExecutor.cp:664-703. The map's /usr/bin/python3
#                            for .py is a placeholder that is always overridden.
#                            GetEmbeddedPythonPath() accepts
#                            <bundle>/Contents/Library/Python/bin/python3 only
#                            when it is an EXECUTABLE FILE (not merely when a
#                            Library/Python directory exists). Failing that,
#                            FindInstalledPython() (:55-78) tries, in order and
#                            with access(X_OK):
#                              /Library/Frameworks/Python.framework/Versions/Current/bin/python3
#                              /opt/homebrew/bin/python3
#                              /usr/local/bin/python3
#                              /opt/local/bin/python3
#                            and falls back to /usr/bin/python3 untested.
#   Python environment       OmcExecutor.cp:783-827. Exported whenever the app
#                            bundles its own Python, whatever the handler's
#                            language (the engine's own comment at :789-790).
#                            Embedded: PATH gets the embedded bin/,
#                            PYTHONPYCACHEPREFIX is set, and PYTHONPATH gets
#                            Contents/Library/Packages ONLY when that directory
#                            exists (:760-763). No embedded Python and a .py
#                            handler: PATH only (:811-819).
#   Shebang                  never honored. omc_popen.c:253-294 puts the
#                            interpreter in shellPath and appends the script as
#                            the last argv element; posix_spawn (:360-361) execs
#                            the interpreter.
#   Working directory        the engine sets none - the child inherits the
#                            applet's cwd. It is therefore not a contract a
#                            handler may rely on, and omc_run runs handlers from
#                            $OMCTEST_WORK instead.
#   Script resolution        OMCScriptsManager.cpp:66-99. Keys are the filename
#                            with the extension stripped, LOWERCASED, inserted
#                            with CFDictionaryAddValue (first wins) in whatever
#                            order CFBundleCopyResourceURLsOfType enumerates.
#                            Case-insensitivity is real; DUPLICATE-STEM
#                            PRECEDENCE IS UNDEFINED in the engine. omc_run
#                            therefore picks a documented deterministic order:
#                            .sh, .py, .zsh, .bash.
#   One-shot variables       omc_runtime_context_reference.md:166-172 scopes the
#                            OMC_ACTIONUI_TRIGGER_* family to a control-action
#                            dispatch. It says nothing at all about the lifetime
#                            of OMC_DLG_*; clearing that family after every
#                            handler is a HARNESS CONVENTION, adopted because a
#                            leftover OMC_DLG_SAVE_AS_PATH silently answering the
#                            next test's save panel is exactly the bug this
#                            harness exists to prevent.
#
# Two deliberate deviations from the engine, both documented in the guide:
#
#   PYTHONPYCACHEPREFIX      the engine uses /tmp/Pyc and sets it only in the
#                            embedded branch. The harness points it into the
#                            scratch in BOTH branches, so a test run can never
#                            write __pycache__ into the bundle under test and
#                            break its signature seal. Invisible to handler
#                            logic.
#   When it is applied       the engine recomputes the Python environment on
#                            every dispatch; the harness computes it once per
#                            test file, in omctest_prepare_env. Identical
#                            result, and it keeps PATH from growing by one entry
#                            per omc_run.

# =============================================================================
# Small internals
# =============================================================================

# Export a variable whose name is computed at runtime. The eval assigns from the
# positional parameter, so the value is never re-parsed, whatever it contains.
omctest_setvar() { # <name> <value>
    case "$1" in
        ''|*[!A-Za-z0-9_]*|[0-9]*)
            printf 'omctest: refusing invalid variable name [%s]\n' "$1" >&2
            return 1
            ;;
    esac
    eval "$1=\$2"
    export "$1"
}

# Unset every exported variable whose name matches an extended regex.
# NOTE: sed -E, not basic regex - "\|" alternation is a GNU extension that BSD
# sed treats as a literal, which would make this a silent no-op. Known
# limitation: a value containing a newline defeats the env scan; unsetting a
# variable by name always works.
omctest_unset_matching() { # <ere-matching-the-whole-name>
    local pattern="$1" name
    for name in $(env | LC_ALL=C /usr/bin/sed -nE "s/^($pattern)=.*/\\1/p"); do
        unset "$name"
    done
}

# Reduce a string to something safe in a filename or a variable value.
omctest_slug() { # <text>
    printf '%s' "$1" | LC_ALL=C /usr/bin/tr -c 'A-Za-z0-9._-' '_'
}

# The label a test file runs under: its basename with .test.sh (or .sh) removed.
omctest_label_for() { # <testfile>
    local file_path="$1" base
    base=$(/usr/bin/basename "$file_path")
    case "$base" in
        *.test.sh) base=${base%.test.sh} ;;
        *.sh) base=${base%.sh} ;;
    esac
    omctest_slug "$base"
}

# Split a basename into stem and extension the way macOS displays it: a leading
# dot does not start an extension, and a name with no dot has none.
omctest_stem_of() { # <basename>
    local base="$1" stem
    case "$base" in
        *.*) stem=${base%.*} ;;
        *) printf '%s' "$base"; return 0 ;;
    esac
    if [ -z "$stem" ]; then
        printf '%s' "$base"
    else
        printf '%s' "$stem"
    fi
}

omctest_extension_of() { # <basename>
    local base="$1"
    case "$base" in
        *.*) ;;
        *) return 0 ;;
    esac
    if [ -z "${base%.*}" ]; then
        return 0
    fi
    printf '%s' "${base##*.}"
}

# =============================================================================
# The mock environment
# =============================================================================

omctest_cleanup_scratch() {
    if [ "$OMCTEST_KEEP_SCRATCH" = "1" ]; then
        printf 'omctest: scratch kept at %s\n' "$OMCTEST_SCRATCH" >&2
        return 0
    fi
    case "$OMCTEST_SCRATCH" in
        /*/*) /bin/rm -rf "$OMCTEST_SCRATCH" ;;
    esac
}

# Resolve the applet's own embedded Support directory - the tools that ship with
# the app, not AppletBuilder's.
omctest_real_support_dir() { # <app>
    local app_path="$1" versioned flat
    versioned="$app_path/Contents/Frameworks/Abracode.framework/Versions/A/Support"
    flat="$app_path/Contents/Frameworks/Abracode.framework/Support"
    if [ -d "$versioned" ]; then
        printf '%s' "$versioned"
    elif [ -d "$flat" ]; then
        printf '%s' "$flat"
    else
        return 1
    fi
}

# Mirror the engine's Python resolution (see the contract block above) and apply
# the resulting environment once for this test file.
omctest_setup_python() { # <app>
    local app_path="$1" embedded candidate
    embedded="$app_path/Contents/Library/Python/bin/python3"
    OMCTEST_PYTHON=""
    OMCTEST_PYTHON_EMBEDDED=0
    if [ -x "$embedded" ] && [ -f "$embedded" ]; then
        OMCTEST_PYTHON="$embedded"
        OMCTEST_PYTHON_EMBEDDED=1
    else
        for candidate in \
            /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
            /opt/homebrew/bin/python3 \
            /usr/local/bin/python3 \
            /opt/local/bin/python3
        do
            if [ -x "$candidate" ]; then
                OMCTEST_PYTHON="$candidate"
                break
            fi
        done
        # The engine's own last resort, taken without a test.
        [ -n "$OMCTEST_PYTHON" ] || OMCTEST_PYTHON="/usr/bin/python3"
    fi

    OMCTEST_PYTHON_BIN="$(/usr/bin/dirname "$OMCTEST_PYTHON")"

    # Only the EMBEDDED branch prepends PATH for every handler language. With no
    # embedded Python the engine prepends it only for a .py handler
    # (OmcExecutor.cp:811-819), so doing it here would put the developer's
    # framework Python in front of a plain .sh handler's PATH - which live would
    # see the stock one. A shell handler calling bare "python3" would then be
    # tested against an interpreter it will never get, and the machine's Python
    # layout would quietly become part of the test result. omc_run applies it per
    # dispatch instead, inside the subshell, so PATH still does not grow.
    if [ "$OMCTEST_PYTHON_EMBEDDED" = "1" ]; then
        PATH="$OMCTEST_PYTHON_BIN:$PATH"
        export PATH
    fi

    if [ "$OMCTEST_PYTHON_EMBEDDED" = "1" ] && [ -d "$app_path/Contents/Library/Packages" ]; then
        if [ -n "$PYTHONPATH" ]; then
            PYTHONPATH="$app_path/Contents/Library/Packages:$PYTHONPATH"
        else
            PYTHONPATH="$app_path/Contents/Library/Packages"
        fi
        export PYTHONPATH
    fi

    # Deviation from the engine, on purpose: never write __pycache__ into the
    # bundle under test (it would break the code-signature seal), and never into
    # a shared /tmp/Pyc either.
    PYTHONPYCACHEPREFIX="$OMCTEST_SCRATCH/pyc"
    export PYTHONPYCACHEPREFIX
    export OMCTEST_PYTHON OMCTEST_PYTHON_EMBEDDED OMCTEST_PYTHON_BIN
}

# Build the whole mock environment for one test file. In runner mode
# $OMCTEST_SCRATCH already exists and is owned by the runner: reuse it and add
# only this file's subtree. Only standalone mode creates a scratch, and only
# standalone mode installs the cleanup trap.
omctest_prepare_env() { # <app> <label>
    local app_path="$1" label="$2" resolved own_scratch

    resolved=$(cd "$app_path" >/dev/null 2>&1 && pwd)
    if [ -z "$resolved" ] || [ ! -d "$resolved/Contents" ]; then
        printf 'omctest: not an app bundle: %s\n' "$app_path" >&2
        return 1
    fi
    OMCTEST_APP="$resolved"

    own_scratch=0
    if [ -z "$OMCTEST_SCRATCH" ] || [ ! -d "$OMCTEST_SCRATCH" ]; then
        OMCTEST_SCRATCH=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omctest.XXXXXX") || return 1
        own_scratch=1
    fi

    OMCTEST_WORK="$OMCTEST_SCRATCH/$label/work"
    OMCTEST_UI="$OMCTEST_SCRATCH/$label/ui"
    OMCTEST_SUPPORT="$OMCTEST_SCRATCH/$label/support"
    # Removed, not just re-created: the label is slugged, so two files whose
    # names differ only in a folded character share one directory AND one window
    # uuid. Leaving win-* behind let a file that dispatched no handler at all
    # read another file's virtual window and pass.
    /bin/rm -rf "$OMCTEST_UI"
    /bin/mkdir -p "$OMCTEST_SCRATCH/tmp" "$OMCTEST_WORK" "$OMCTEST_UI" "$OMCTEST_SUPPORT" || return 1

    if [ "$own_scratch" = "1" ]; then
        trap 'omctest_cleanup_scratch' EXIT
        trap 'omctest_cleanup_scratch; exit 130' INT
        trap 'omctest_cleanup_scratch; exit 143' TERM
    fi

    # Where the tests live. The runner passes it down; standalone mode guesses
    # the conventional layout of an app with a Tests/ directory beside it.
    if [ -z "$OMCTEST_TESTS" ]; then
        OMCTEST_TESTS="$(/usr/bin/dirname "$OMCTEST_APP")/Tests"
    fi
    OMCTEST_FIXTURES="$OMCTEST_TESTS/fixtures"

    # --- the OMC surface -----------------------------------------------------
    OMC_APP_BUNDLE_PATH="$OMCTEST_APP"
    OMC_OMC_SUPPORT_PATH="$OMCTEST_SUPPORT"
    OMC_OMC_RESOURCES_PATH="$OMCTEST_APP/Contents/Frameworks/Abracode.framework/Versions/A/Resources"
    [ -d "$OMC_OMC_RESOURCES_PATH" ] || \
        OMC_OMC_RESOURCES_PATH="$OMCTEST_APP/Contents/Frameworks/Abracode.framework/Resources"
    # Unique per file AND per run: handlers key their state directory and their
    # pasteboard keys off this, and pasteboard keys outlive the process.
    OMC_ACTIONUI_WINDOW_UUID="OMCTEST-$label-$$"
    OMC_PARENT_DIALOG_GUID=""
    OMC_CURRENT_COMMAND_GUID="OMCTEST-CMD"
    # In the engine's always-exported set. NIB dialogs are out of scope for v1,
    # so handlers see it present and empty rather than absent.
    OMC_NIB_DLG_GUID=""
    OMC_OBJ_PATH=""
    OMC_OBJ_TEXT=""
    export OMC_APP_BUNDLE_PATH OMC_OMC_SUPPORT_PATH OMC_OMC_RESOURCES_PATH
    export OMC_ACTIONUI_WINDOW_UUID OMC_PARENT_DIALOG_GUID OMC_CURRENT_COMMAND_GUID
    export OMC_NIB_DLG_GUID OMC_OBJ_PATH OMC_OBJ_TEXT

    # Applets derive their scratch and state paths from TMPDIR (ICEdit's
    # SCRATCH_DIR, PackageBuilder's state dir), so redirecting it isolates all
    # of that and makes cleanup total. The TRAILING SLASH is not cosmetic:
    # macOS always sets TMPDIR with one (getconf DARWIN_USER_TEMP_DIR), so
    # "${TMPDIR}name" is a legitimate spelling in a handler and must keep
    # working under test.
    TMPDIR="$OMCTEST_SCRATCH/tmp/"
    export TMPDIR

    # --- harness variables ---------------------------------------------------
    # Deliberately NOT 0. "check_status \"it worked\" 0" would otherwise pass
    # before anything had been dispatched, which is a check that cannot fail.
    OMCTEST_STATUS="-"
    [ -n "$OMCTEST_ALERT_RC" ] || OMCTEST_ALERT_RC=0
    export OMCTEST_APP OMCTEST_LIB OMCTEST_TESTS OMCTEST_FIXTURES
    export OMCTEST_SCRATCH OMCTEST_WORK OMCTEST_UI OMCTEST_SUPPORT
    export OMCTEST_STATUS OMCTEST_ALERT_RC

    omctest_setup_python "$OMCTEST_APP"
    omctest_build_support "$OMCTEST_APP" "$OMCTEST_SUPPORT" || return 1

    # Pre-created so the count helpers report 0 rather than empty on a clean run.
    : > "$OMCTEST_UI/journal.tsv"
    : > "$OMCTEST_UI/alerts.log"
    : > "$OMCTEST_UI/notifications.log"
    : > "$OMCTEST_UI/alert_answers"
    : > "$OMCTEST_UI/chain.queue"
    : > "$OMCTEST_UI/chain.log"

    omctest_reset_counts
}

# The interposition directory: symlink the applet's own tools, then replace the
# four that must not run for real. Interception at the filesystem path is what
# makes this language-neutral - a Python handler building its tool paths from
# $OMC_OMC_SUPPORT_PATH hits the same stubs as a shell handler.
omctest_build_support() { # <app> <dest>
    local app_path="$1" dest_dir="$2" real_dir tool stub_name
    real_dir=$(omctest_real_support_dir "$app_path")
    if [ -z "$real_dir" ]; then
        printf 'omctest: no Abracode.framework Support directory in %s\n' "$app_path" >&2
        return 1
    fi
    OMCTEST_REAL_SUPPORT="$real_dir"
    export OMCTEST_REAL_SUPPORT

    /bin/mkdir -p "$dest_dir" || return 1
    for tool in "$real_dir"/*; do
        [ -e "$tool" ] || continue
        /bin/ln -sf "$tool" "$dest_dir/$(/usr/bin/basename "$tool")" 2>/dev/null
    done

    for stub_name in $OMCTEST_DEFAULT_STUBS; do
        omctest_install_default_stub "$stub_name" "$dest_dir" || return 1
    done
}

omctest_install_default_stub() { # <tool> <support-dir>
    local tool_name="$1" dest_dir="$2"
    /bin/rm -f "$dest_dir/$tool_name"
    case "$tool_name" in
        alert) omctest_emit_stub_alert > "$dest_dir/$tool_name" ;;
        notify) omctest_emit_stub_notify > "$dest_dir/$tool_name" ;;
        omc_dialog_control) omctest_emit_stub_omc_dialog_control > "$dest_dir/$tool_name" ;;
        omc_next_command) omctest_emit_stub_omc_next_command > "$dest_dir/$tool_name" ;;
        *) printf 'omctest: no default stub for %s\n' "$tool_name" >&2; return 1 ;;
    esac
    /bin/chmod +x "$dest_dir/$tool_name"
}

# =============================================================================
# The stubs
# =============================================================================
#
# Every here-doc delimiter is single-quoted: a stub is a real file run in its
# own process later, and must expand $OMCTEST_UI from its own environment, not
# from this one.

omctest_emit_stub_alert() {
    /bin/cat <<'STUB'
#!/bin/sh
# alert (omctest stub). The real alert is app-modal: with no user to click it,
# any confirmation path would hang the run forever. Record, then answer.
# One alert, one line. A multi-line body ("Could not save." plus the reason) is
# the norm, and counting raw lines made alerts_count report 2 for a single
# correct alert. Newlines are flattened to spaces, which also keeps
# alerts_mention able to match a phrase that spans a line break.
printf '%s\n' "$(printf '%s' "$*" | /usr/bin/tr '\n' ' ')" >> "$OMCTEST_UI/alerts.log"
q="$OMCTEST_UI/alert_answers"
if [ -s "$q" ]; then
    rc=$(/usr/bin/head -n 1 "$q")
    /usr/bin/tail -n +2 "$q" > "$q.tmp" && /bin/mv "$q.tmp" "$q"
else
    rc="${OMCTEST_ALERT_RC:-0}"
fi
case "$rc" in
    -1) rc=255 ;;
    ''|*[!0-9]*) rc=0 ;;
esac
exit "$rc"
STUB
}

omctest_emit_stub_notify() {
    /bin/cat <<'STUB'
#!/bin/sh
# notify (omctest stub). The real tool posts a Notification Center item: it
# needs permission, pollutes the session, and asserts nothing. Record only.
printf '%s\n' "$(printf '%s' "$*" | /usr/bin/tr '\n' ' ')" >> "$OMCTEST_UI/notifications.log"
exit 0
STUB
}

omctest_emit_stub_omc_next_command() {
    /bin/cat <<'STUB'
#!/bin/sh
# omc_next_command (omctest stub). The real tool asks the app to dispatch
# another command after the current handler exits; queue it instead, so a test
# can assert the request was made and drain it synchronously.
# The real tool writes ONE file named for the GUID with fopen(...,"w"), so two
# calls inside one handler leave only the LAST id for the engine to dispatch.
# Appending here made the harness run both and report a request the engine had
# already discarded. The full history is kept separately, for a test that wants
# to assert the handler asked twice.
if [ $# -ne 2 ] || [ -z "$2" ]; then
    printf 'omc_next_command usage [%s]\n' "$*" >> "$OMCTEST_UI/errors.log"
    exit 255
fi
printf '%s\n' "$2" >> "$OMCTEST_UI/chain.log"
printf '%s\n' "$2" > "$OMCTEST_UI/chain.queue"
exit 0
STUB
}

omctest_emit_stub_omc_dialog_control() {
    /bin/cat <<'STUB'
#!/bin/sh
# omc_dialog_control (omctest recording stub).
# The real tool is a harmless no-op with no window - which is why handlers can
# run headless at all - but a no-op discards the largest observable output most
# handlers have. This one remembers, in two artifacts: a journal of every call
# in order, and a last-write-wins virtual window.
uuid="$1"; target="$2"
# A window uuid is an opaque token, never a path. Unvalidated it was interpolated
# straight into "$OMCTEST_UI/win-$uuid", so a handler passing a path in that slot
# - exactly the kind of bug this harness exists to catch - made the stub write
# outside the scratch and survive the cleanup trap.
case "$uuid" in
    ''|*/*|*..*)
        printf 'bad window uuid [%s]\n' "$uuid" >> "$OMCTEST_UI/errors.log"
        exit 0
        ;;
esac
# The real tool rejects argc < 4 with a usage dump and exit -1 (255), writing
# nothing. "shift 2" alone does not cover this: with exactly two arguments the
# shift SUCCEEDS, the verb becomes the empty string, and the bare-value arm below
# would wipe a table's rows for a call the engine refused outright. Reachable
# from an ordinary handler bug - "$d" "$u" 100 $rows with rows empty.
if [ $# -lt 3 ]; then
    printf 'usage (argc<4) [%s] [%s]\n' "$uuid" "$target" >> "$OMCTEST_UI/errors.log"
    exit 255
fi
shift 2
win="$OMCTEST_UI/win-$uuid"
/bin/mkdir -p "$win"

# 1. Journal every call. A single printf >> is one O_APPEND write, so concurrent
#    handlers interleave whole lines and order IS line order - no counter to
#    race on. Tabs and newlines inside arguments are flattened here; the row
#    files below keep them intact.
printf '%s\t%s\t%s\n' "$uuid" "$target" \
    "$(printf '%s\t' "$@" | /usr/bin/tr '\t\n' '  ')" >> "$OMCTEST_UI/journal.tsv"

# 2. Resolve the target to a file prefix; flag writes to undeclared view ids.
case "$target" in
    omc_window|omc_application|omc_workspace) v="$win/$target" ;;
    *[!0-9]*|'') printf 'bad target [%s]\n' "$target" >> "$OMCTEST_UI/errors.log"; exit 0 ;;
    *)  v="$win/v$target"
        # -s, not -f: a file that exists but is empty means "no ids were
        # extracted", and treating that as "no id is known" flagged every
        # legitimate write. Either way the runner has already said out loud that
        # the check is off, so the stub simply does not run it.
        if [ -s "$OMCTEST_UI/known_ids.txt" ] \
           && ! /usr/bin/grep -q -x -- "$target" "$OMCTEST_UI/known_ids.txt"; then
            printf '%s %s\n' "$target" "$*" >> "$OMCTEST_UI/unknown_ids.log"
        fi ;;
esac

# 3. Scripted failure, for exercising handler error paths (ui_fail).
if [ -f "$win/fail_ids" ] && /usr/bin/grep -q -x -- "$target" "$win/fail_ids"; then
    exit 1
fi

# Prints 0, never empty: "[ "$2" -lt "" ]" is a shell error, and it was landing
# in the handler log for any selection on a view with no rows yet.
row_count() {
    if [ -f "$v.rows" ]; then /usr/bin/awk 'END { print NR }' "$v.rows"; else printf '0'; fi
}

# 4. Replay the verb onto the virtual window.
verb="$1"
case "$verb" in
    omc_enable)  printf '1' > "$v.enabled" ;;
    omc_disable) printf '0' > "$v.enabled" ;;
    omc_show)    printf '1' > "$v.visible" ;;
    omc_hide)    printf '0' > "$v.visible" ;;
    omc_set_value_from_stdin)
        /bin/cat > "$v.value"
        # Its optional contentType is gated on argc == 5 too (main.c:403-405).
        [ $# -eq 2 ] && printf '%s' "$2" > "$v.content_type" ;;
    omc_table_set_columns)
        shift; : > "$v.columns"
        for col; do printf '%s\n' "$col" >> "$v.columns"; done ;;
    omc_table_remove_all_rows|omc_table_prepare_empty|omc_list_remove_all) : > "$v.rows" ;;
    # The tool's fgets loop drops empty lines ("if there is an empty line, we eat
    # it and not add to the list"), so a trailing newline or a blank line in the
    # middle does NOT become a row. Feeding rows from a find or grep pipeline
    # with a trailing blank is ordinary, and ui_row_count is a headline
    # assertion, so keeping them would over-report on the most common shape.
    # The argv forms below deliberately do NOT filter: the tool keeps an empty
    # ARGUMENT as an empty row.
    omc_table_set_rows_from_stdin|omc_list_set_items_from_stdin)
        /usr/bin/grep -v '^$' > "$v.rows" ;;
    omc_table_add_rows_from_stdin|omc_list_append_items_from_stdin)
        /usr/bin/grep -v '^$' >> "$v.rows" ;;
    # -r, not -f: a file that exists but cannot be opened leaves the rows alone
    # in the tool, because its fopen returns NULL - truncating here would be a
    # divergence in the direction that hides a handler bug.
    omc_table_set_rows_from_file|omc_list_set_items_from_file)
        [ -r "$2" ] && /usr/bin/grep -v '^$' "$2" > "$v.rows" ;;
    omc_table_add_rows_from_file|omc_list_append_items_from_file)
        [ -r "$2" ] && /usr/bin/grep -v '^$' "$2" >> "$v.rows" ;;
    omc_table_set_rows|omc_list_set_items)
        shift; : > "$v.rows"
        for row; do printf '%s\n' "$row" >> "$v.rows"; done ;;
    omc_table_add_rows|omc_list_append_items)
        shift
        for row; do printf '%s\n' "$row" >> "$v.rows"; done ;;
    omc_select_row)
        # No index, or a non-numeric one, is a SILENT NO-OP: the tool's
        # one-argument branch is gated on itemCount == 5, so with anything else
        # nothing is stored and the previous selection survives. Clearing here
        # instead would test the classic handler bug - omc_select_row "$idx"
        # with $idx empty - as "the selection was cleared" while the live app
        # keeps the old row selected. Phase 0 records this no-op as worth
        # reproducing exactly rather than papering over.
        case "$2" in
            ''|*[!0-9]*) : ;;
            *) if [ "$2" -lt "$(row_count)" ]; then printf '%s' "$2" > "$v.selection"
               else : > "$v.selection"; fi ;;   # out of range clears, like the real tool
        esac ;;
    omc_select_row_with_content)
        /usr/bin/awk -F '\t' -v text="$2" -v col="${3:-0}" '
            { hit = 0
              if (col > 0) { if ($col == text) hit = 1 }
              else { for (i = 1; i <= NF; i++) if ($i == text) { hit = 1; break } }
              if (hit) { printf "%d", NR - 1; exit } }' \
            "$v.rows" > "$v.selection" 2>/dev/null ;;
    omc_deselect) : > "$v.selection" ;;
    omc_set_property)
        key=$(printf '%s' "$2" | /usr/bin/tr -c 'A-Za-z0-9_.-' '_')
        printf '%s' "$3" > "$v.prop.$key" ;;
    omc_set_state)
        key=$(printf '%s' "$2" | /usr/bin/tr -c 'A-Za-z0-9_.-' '_')
        printf '%s' "$3" > "$v.state.$key" ;;
    omc_present_alert|omc_present_confirmation_dialog)
        { printf 'title\t%s\nmessage\t%s\n' "$2" "$3"
          if [ $# -gt 3 ]; then
              shift 3
              for b; do printf 'button\t%s\n' "$b"; done
          fi; } > "$win/pending_alert"                                 # latest, for ui_alert_action
        /bin/cat "$win/pending_alert" >> "$win/present_alerts.log" ;;  # full history
    # Journal-only: real verbs whose effect the virtual window does not model.
    # This is an EXPLICIT list, not an "omc_*" glob, and the difference matters.
    # The real tool's GetInstructionID (omc_dialog_control/main.c:138-165) falls
    # back to omc_set_control_value for ANY word it does not match exactly - so a
    # typo'd verb is not ignored by the engine, it is written into the control as
    # a value, destroying a table's rows on the way. A glob here would swallow
    # that and let the test pass while the app misbehaves. Anything not named in
    # this list or replayed above therefore falls through to the bare-value arm,
    # exactly as the real tool does. The roster is the full 46 from main.c:82-127
    # (28 replayed above, the 17 below, and one empty entry that can never match).
    omc_table_set_column_widths|omc_set_command_id|omc_resize|omc_move|omc_scroll|\
    omc_select|omc_terminate_ok|omc_terminate_cancel|omc_invoke|omc_present_modal|\
    omc_dismiss_modal|omc_present_toast|omc_dismiss_toast|omc_dismiss_dialog|\
    omc_insert_element|omc_insert_element_row|omc_remove_element) : ;;
    *)  # Not an instruction word, so GetInstructionID falls back to
        # omc_set_control_value. The contentType is decided by ARGUMENT COUNT,
        # not by a word list: main.c:317-323 takes argv[3] as the content type
        # for ANY unrecognized word whenever argc is exactly 5. The five names in
        # the usage text are documentation, not a parser table - "mytype" works
        # just as well, and "json a b" (argc 6) is NOT a content-type call.
        if [ $# -eq 2 ]; then
            printf '%s' "$verb" > "$v.content_type"
            val="$2"
        else
            val="$verb"
        fi
        # On a row-bearing view the real engine REPLACES the rows with this
        # single string - reproduce the destruction, and flag it, because it is
        # almost always a bug. This applies to the content-type form too, which
        # is why it is no longer a separate arm that skipped the rows entirely.
        if [ -f "$v.rows" ]; then
            printf '%s\n' "$val" > "$v.rows"
            printf '%s bare value onto rows: %s\n' "$target" "$val" >> "$OMCTEST_UI/suspect_writes.log"
        fi
        printf '%s' "$val" > "$v.value" ;;
esac
exit 0
STUB
}

# =============================================================================
# Per-file tool overrides
# =============================================================================

# Replace a support tool for this test file. The body is read from stdin:
#
#   omc_stub plister <<'SH'
#   #!/bin/sh
#   exit 1
#   SH
#
# Whole-tool failure is what this is for. Finer-grained failure - one write
# failing while every read still succeeds - still wants state surgery on the
# model, not a stub.
omc_stub() { # <tool>   (body on stdin)
    local tool_name="$1"
    if [ -z "$tool_name" ]; then
        printf 'omctest: omc_stub needs a tool name\n' >&2
        return 1
    fi
    /bin/rm -f "$OMC_OMC_SUPPORT_PATH/$tool_name"
    /bin/cat > "$OMC_OMC_SUPPORT_PATH/$tool_name" || return 1
    /bin/chmod +x "$OMC_OMC_SUPPORT_PATH/$tool_name"
}

# Undo omc_stub. For one of the four tools the harness always stubs, "restore"
# means the default recording stub, not the real tool - running the real alert
# would hang the suite.
omc_unstub() { # <tool>
    local tool_name="$1" stub_name
    if [ -z "$tool_name" ]; then
        printf 'omctest: omc_unstub needs a tool name\n' >&2
        return 1
    fi
    for stub_name in $OMCTEST_DEFAULT_STUBS; do
        if [ "$stub_name" = "$tool_name" ]; then
            omctest_install_default_stub "$tool_name" "$OMC_OMC_SUPPORT_PATH"
            return $?
        fi
    done
    /bin/rm -f "$OMC_OMC_SUPPORT_PATH/$tool_name"
    /bin/ln -sf "$OMCTEST_REAL_SUPPORT/$tool_name" "$OMC_OMC_SUPPORT_PATH/$tool_name"
}

# =============================================================================
# Simulating the OMC input surface
# =============================================================================
#
# Lifetime, mirroring the engine: OMC_ACTIONUI_VIEW_* / OMC_ACTIONUI_TABLE_* and
# the OMC_OBJ_* family PERSIST, like a real window's controls and its document,
# until overwritten or explicitly reset. OMC_ACTIONUI_TRIGGER_* and OMC_DLG_* are
# ONE-SHOT: omc_run clears them after every handler.

omc_control() { # <view-id> <value>
    omctest_setvar "OMC_ACTIONUI_VIEW_$1_VALUE" "$2"
}

omc_table_cell() { # <table-id> <column> <value>   (columns 1-based; 0 = whole row, tab-joined)
    omctest_setvar "OMC_ACTIONUI_TABLE_$1_COLUMN_$2_VALUE" "$3"
}

omc_trigger() { # <view-id> [part-id] [context]
    local view_id="$1" part_id="$2" context="$3"
    omctest_setvar "OMC_ACTIONUI_TRIGGER_VIEW_ID" "$view_id" || return 1
    # An empty argument leaves the variable unset, matching the engine's rule
    # that an absent value omits the variable rather than exporting it empty.
    if [ -n "$part_id" ]; then
        omctest_setvar "OMC_ACTIONUI_TRIGGER_VIEW_PART_ID" "$part_id"
    else
        unset OMC_ACTIONUI_TRIGGER_VIEW_PART_ID
    fi
    if [ -n "$context" ]; then
        omctest_setvar "OMC_ACTIONUI_TRIGGER_CONTEXT" "$context"
    else
        unset OMC_ACTIONUI_TRIGGER_CONTEXT
    fi
}

# Build the drop context ActionUI's DropHelper produces:
# {"items":[String],"location":{"x":Double,"y":Double}}. python3 is used only to
# quote the paths correctly.
omc_drop() { # <path> [path ...]
    local context
    context=$(/usr/bin/python3 -c 'import json,sys; print(json.dumps({"items": sys.argv[1:], "location": {"x": 0.0, "y": 0.0}}))' "$@") || return 1
    omctest_setvar "OMC_ACTIONUI_TRIGGER_CONTEXT" "$context" || return 1
    # A drop without a preceding omc_trigger still needs a view id.
    [ -n "$OMC_ACTIONUI_TRIGGER_VIEW_ID" ] || OMC_ACTIONUI_TRIGGER_VIEW_ID=""
    export OMC_ACTIONUI_TRIGGER_VIEW_ID
}

# Answer a file/save/input dialog. The engine exports the whole derived family,
# not just the path, so a handler reading OMC_DLG_SAVE_AS_NAME must see it. An
# empty value simulates Cancel: the family is unset, which is what the engine
# leaves behind.
omc_dialog_answer() { # <save_as|choose_file|choose_folder|choose_object|input_text> <value>
    local channel="$1" value="$2" prefix base

    if [ "$channel" = "input_text" ]; then
        if [ -n "$value" ]; then
            omctest_setvar "OMC_DLG_INPUT_TEXT" "$value"
        else
            unset OMC_DLG_INPUT_TEXT
        fi
        return 0
    fi

    case "$channel" in
        save_as) prefix="OMC_DLG_SAVE_AS" ;;
        choose_file) prefix="OMC_DLG_CHOOSE_FILE" ;;
        choose_folder) prefix="OMC_DLG_CHOOSE_FOLDER" ;;
        choose_object) prefix="OMC_DLG_CHOOSE_OBJECT" ;;
        *)
            printf 'omctest: unknown dialog channel [%s]\n' "$channel" >&2
            return 1
            ;;
    esac

    if [ -z "$value" ]; then
        unset "${prefix}_PATH" "${prefix}_PARENT_PATH" "${prefix}_NAME" \
              "${prefix}_NAME_NO_EXTENSION" "${prefix}_EXTENSION_ONLY"
        return 0
    fi

    base=$(/usr/bin/basename "$value")
    omctest_setvar "${prefix}_PATH" "$value"
    omctest_setvar "${prefix}_PARENT_PATH" "$(/usr/bin/dirname "$value")"
    omctest_setvar "${prefix}_NAME" "$base"
    omctest_setvar "${prefix}_NAME_NO_EXTENSION" "$(omctest_stem_of "$base")"
    omctest_setvar "${prefix}_EXTENSION_ONLY" "$(omctest_extension_of "$base")"
}

# The current object - the file or folder the command is acting on. Part of the
# engine's always-exported set, so it persists across handlers until changed;
# omc_object "" clears the family.
omc_object() { # <path>
    local object_path="$1" base parent
    if [ -z "$object_path" ]; then
        unset OMC_OBJ_PATH OMC_OBJ_PARENT_PATH OMC_OBJ_NAME OMC_OBJ_NAME_NO_EXTENSION \
              OMC_OBJ_EXTENSION_ONLY OMC_OBJ_PATH_NO_EXTENSION OMC_OBJ_DISPLAY_NAME
        OMC_OBJ_PATH=""
        export OMC_OBJ_PATH
        return 0
    fi
    base=$(/usr/bin/basename "$object_path")
    parent=$(/usr/bin/dirname "$object_path")
    omctest_setvar "OMC_OBJ_PATH" "$object_path"
    omctest_setvar "OMC_OBJ_PARENT_PATH" "$parent"
    omctest_setvar "OMC_OBJ_NAME" "$base"
    omctest_setvar "OMC_OBJ_NAME_NO_EXTENSION" "$(omctest_stem_of "$base")"
    omctest_setvar "OMC_OBJ_EXTENSION_ONLY" "$(omctest_extension_of "$base")"
    omctest_setvar "OMC_OBJ_PATH_NO_EXTENSION" "$parent/$(omctest_stem_of "$base")"
    # Approximated by the basename: the engine asks the file system for the
    # localized display name, which the harness does not reproduce.
    omctest_setvar "OMC_OBJ_DISPLAY_NAME" "$base"
}

omc_clear_event() {
    omctest_unset_matching 'OMC_ACTIONUI_TRIGGER_[A-Za-z0-9_]*|OMC_DLG_[A-Za-z0-9_]*'
}

omc_reset_controls() {
    omctest_unset_matching 'OMC_ACTIONUI_(VIEW|TABLE)_[A-Za-z0-9_]*'
}

# =============================================================================
# omc_run - dispatching a handler the way the engine would
# =============================================================================

# Resolve Scripts/<command-id>.<ext> case-insensitively, as the engine does.
# When several extensions share a stem the engine's answer is undefined (see the
# contract block); the harness commits to .sh, .py, .zsh, .bash.
omctest_resolve_script() { # <command-id>
    local command_id="$1" scripts_dir wanted ext candidate stem base
    scripts_dir="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts"
    wanted=$(printf '%s' "$command_id" | LC_ALL=C /usr/bin/tr 'A-Z' 'a-z')
    # The documented precedence first, then everything else. The engine keys on
    # the lowercased stem with ANY extension stripped and leaves duplicate-stem
    # precedence undefined, so the four below are this harness's deterministic
    # choice - but a .pl, .rb, .applescript or extensionless handler must still
    # resolve, and used to read as "no script for command id".
    for ext in sh py zsh bash ''; do
        for candidate in "$scripts_dir"/*; do
            [ -f "$candidate" ] || continue
            base=$(/usr/bin/basename "$candidate")
            case "$ext" in
                '')
                    # The catch-all pass: skip the four already tried.
                    case "$base" in *.sh|*.py|*.zsh|*.bash) continue ;; esac
                    ;;
                *)
                    case "$base" in *."$ext") ;; *) continue ;; esac
                    ;;
            esac
            # omctest_stem_of, not basename -s: it implements the macOS dotfile
            # rule, so ".zshrc" keeps its whole name as the stem.
            stem=$(omctest_stem_of "$base" | LC_ALL=C /usr/bin/tr 'A-Z' 'a-z')
            if [ "$stem" = "$wanted" ]; then
                printf '%s' "$candidate"
                return 0
            fi
        done
    done
    return 1
}

omctest_interpreter_for() { # <script-path>
    local script_path="$1" base
    base=$(/usr/bin/basename "$script_path")
    case "$base" in
        *.sh) printf '/bin/sh' ;;
        *.zsh) printf '/bin/zsh' ;;
        *.bash) printf '/bin/bash' ;;
        *.py) printf '%s' "$OMCTEST_PYTHON" ;;
        *.pl) printf '/usr/bin/perl' ;;
        *.rb) printf '/usr/bin/ruby' ;;
        *.applescript|*.scpt) printf '/usr/bin/osascript' ;;
        # kDefaultShell: an unknown or absent extension runs under /bin/sh.
        *) printf '/bin/sh' ;;
    esac
}

# Emits the handler's own output on stdout/stderr and its exit code into a file,
# so the caller can capture the output either way without a pipeline eating the
# status.
omctest_dispatch() { # <command-id> <interpreter> <script> <status-file>
    printf -- '-- %s --\n' "$1"
    # stdin from /dev/null: the engine's omc_popen gives a script-file handler no
    # meaningful stdin, and without this a handler that reads stdin inherits the
    # runner's terminal and hangs the whole suite with no diagnostic and no
    # timeout.
    ( cd "$OMCTEST_WORK" 2>/dev/null || exit 127
      # The non-embedded PATH prepend is a .py-only thing in the engine, and it
      # lives here so it applies to one dispatch and never leaks.
      if [ "$OMCTEST_PYTHON_EMBEDDED" != "1" ]; then
          case "$3" in
              *.py) PATH="$OMCTEST_PYTHON_BIN:$PATH"; export PATH ;;
          esac
      fi
      "$2" "$3" </dev/null )
    printf '%s\n' "$?" > "$4"
}

omc_run() { # <command-id>
    local command_id="$1" script_path interpreter status_file
    if [ -z "$command_id" ]; then
        printf 'omctest: omc_run needs a command id\n' >&2
        return 127
    fi

    script_path=$(omctest_resolve_script "$command_id")
    if [ -z "$script_path" ]; then
        printf 'omctest: no script for command id [%s] in %s\n' \
            "$command_id" "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts" >&2
        OMCTEST_STATUS=127
        export OMCTEST_STATUS
        # Recorded in the same file every other dispatch writes: check_status
        # reads that file, so skipping it here left the PREVIOUS run's status in
        # place and "check_status ... 127" compared against a stale 0.
        printf '127\n' > "$OMCTEST_UI/.last_status"
        # Cleared here too. A typo'd or renamed COMMAND_ID is exactly how a test
        # file reaches this branch, and leaving the one-shot variables armed
        # would hand them to the NEXT dispatch - "a leftover
        # OMC_DLG_SAVE_AS_PATH silently answering the next test's save panel" is
        # the thing this clearing exists to prevent.
        omc_clear_event
        return 127
    fi
    interpreter=$(omctest_interpreter_for "$script_path")
    status_file="$OMCTEST_UI/.last_status"

    if [ "$OMCTEST_VERBOSE" = "1" ]; then
        omctest_dispatch "$command_id" "$interpreter" "$script_path" "$status_file" 2>&1 \
            | /usr/bin/tee -a "$OMCTEST_UI/handlers.log" >&2
    else
        omctest_dispatch "$command_id" "$interpreter" "$script_path" "$status_file" \
            >> "$OMCTEST_UI/handlers.log" 2>&1
    fi

    OMCTEST_STATUS=$(/bin/cat "$status_file" 2>/dev/null)
    case "$OMCTEST_STATUS" in
        ''|*[!0-9]*) OMCTEST_STATUS=127 ;;
    esac
    export OMCTEST_STATUS

    # One-shot clearing is unconditional: it happens even when the handler
    # failed, because the engine's next dispatch would not carry these either.
    omc_clear_event

    return "$OMCTEST_STATUS"
}

# The common three-liner: set a value, say which control fired, dispatch.
omc_fire() { # <command-id> <view-id> [value]
    local command_id="$1" view_id="$2"
    if [ $# -ge 3 ]; then
        omc_control "$view_id" "$3" || return 1
    fi
    omc_trigger "$view_id" || return 1
    omc_run "$command_id"
}

# =============================================================================
# Alerts, notifications, chains
# =============================================================================

# Script a SEQUENCE of alert answers for the handler runs that follow. When the
# queue is empty the stub falls back to $OMCTEST_ALERT_RC (default 0 = OK).
# Codes follow the tool: 0 OK, 1 Cancel, 2 Other, 3 timed out, 255 error.
# The queue pop is a read-modify-write with no lock, so tests that raise alerts
# from CONCURRENT handlers must use OMCTEST_ALERT_RC instead.
alert_answer() { # <rc> [rc ...]
    local rc
    for rc; do
        printf '%s\n' "$rc" >> "$OMCTEST_UI/alert_answers"
    done
}

alerts_reset() { : > "$OMCTEST_UI/alerts.log"; }
# Counts LINES, not non-empty lines: one alert is one line, and an alert raised
# with empty text is still an alert the user was shown.
alerts_count() { /usr/bin/awk 'END { print NR }' "$OMCTEST_UI/alerts.log" 2>/dev/null; }
alerts_mention() { /usr/bin/grep -c -- "$1" "$OMCTEST_UI/alerts.log" 2>/dev/null | /usr/bin/tr -d ' '; }

notify_count() { /usr/bin/grep -c . "$OMCTEST_UI/notifications.log" 2>/dev/null | /usr/bin/tr -d ' '; }
notify_mention() { /usr/bin/grep -c -- "$1" "$OMCTEST_UI/notifications.log" 2>/dev/null | /usr/bin/tr -d ' '; }

# Was a chained command requested? Asserts on the queue without draining it.
# -F, because a command id is a literal, not a pattern: every OMC command id
# contains dots, and as a regex "MyApp.close" also matches "MyAppXclose".
# check_grep and ui_calls are documented pattern helpers and stay regexes.
# What the engine would dispatch NEXT - the one pending slot, not a history.
chain_requested() { # <command-id>
    /usr/bin/grep -c -F -x -- "$1" "$OMCTEST_UI/chain.queue" 2>/dev/null | /usr/bin/tr -d ' '
}

# How many times a chain to this id was ASKED for, across the whole file. Two
# requests in one handler leave one pending slot but two history lines, which is
# the only way to tell that a handler overwrote its own request.
chain_asked() { # <command-id>
    /usr/bin/grep -c -F -x -- "$1" "$OMCTEST_UI/chain.log" 2>/dev/null | /usr/bin/tr -d ' '
}

# Run what omc_next_command queued, in order. Queue-then-drain reproduces the
# engine's actual semantics - the chained command runs after the current script
# exits - rather than the tempting-but-wrong recursive dispatch. The depth limit
# turns a circular chain into a named failure instead of a hung run.
omc_drain_chain() { # [max-depth, default 25]
    local max_depth="${1:-25}" depth=0 next_id chain_rc worst_rc=0
    while [ -s "$OMCTEST_UI/chain.queue" ]; do
        if [ "$depth" -ge "$max_depth" ]; then
            printf 'omctest: chain depth %s exceeded (circular chain?)\n' "$max_depth" >&2
            return 1
        fi
        next_id=$(/usr/bin/head -n 1 "$OMCTEST_UI/chain.queue")
        /usr/bin/tail -n +2 "$OMCTEST_UI/chain.queue" > "$OMCTEST_UI/chain.tmp"
        /bin/mv "$OMCTEST_UI/chain.tmp" "$OMCTEST_UI/chain.queue"
        omc_run "$next_id"
        chain_rc=$?
        # The worst status across the whole chain, not just the last link's: a
        # handler that failed in the middle was invisible, because only the final
        # omc_run's status survived in OMCTEST_STATUS.
        [ "$chain_rc" -eq 0 ] || worst_rc="$chain_rc"
        depth=$((depth + 1))
    done
    return "$worst_rc"
}

# =============================================================================
# Windows and sheets
# =============================================================================

omc_window_switch() { # <name>
    OMC_ACTIONUI_WINDOW_UUID="OMCTEST-$(omctest_slug "$1")-$$"
    export OMC_ACTIONUI_WINDOW_UUID
}

# The child-sheet convention both Notarize and ICEdit implement:
# document_uuid="${parent_uuid:-$window_uuid}". One level deep, which is all any
# applet uses.
omc_child_sheet() { # <name>
    OMCTEST_SAVED_WINDOW_UUID="$OMC_ACTIONUI_WINDOW_UUID"
    OMCTEST_SAVED_PARENT_GUID="$OMC_PARENT_DIALOG_GUID"
    OMC_PARENT_DIALOG_GUID="$OMC_ACTIONUI_WINDOW_UUID"
    OMC_ACTIONUI_WINDOW_UUID="OMCTEST-$(omctest_slug "$1")-$$"
    export OMC_ACTIONUI_WINDOW_UUID OMC_PARENT_DIALOG_GUID
}

omc_leave_sheet() {
    [ -n "$OMCTEST_SAVED_WINDOW_UUID" ] || return 1
    OMC_ACTIONUI_WINDOW_UUID="$OMCTEST_SAVED_WINDOW_UUID"
    OMC_PARENT_DIALOG_GUID="$OMCTEST_SAVED_PARENT_GUID"
    export OMC_ACTIONUI_WINDOW_UUID OMC_PARENT_DIALOG_GUID
    OMCTEST_SAVED_WINDOW_UUID=""
    OMCTEST_SAVED_PARENT_GUID=""
}

# Poll a predicate at 10 Hz - for handlers that background a pipeline or
# debounce. Returns 0 as soon as the predicate succeeds, 1 on timeout.
omc_wait_for() { # '<predicate command>' [timeout-seconds, default 5]
    local predicate="$1" timeout_s="${2:-5}" ticks limit
    limit=$(/usr/bin/awk -v t="$timeout_s" 'BEGIN { printf "%d", (t * 10) + 0.5 }')
    ticks=0
    while [ "$ticks" -le "$limit" ]; do
        if /bin/sh -c "$predicate" >/dev/null 2>&1; then
            return 0
        fi
        /bin/sleep 0.1
        ticks=$((ticks + 1))
    done
    return 1
}

# =============================================================================
# The check vocabulary
# =============================================================================
#
# Deliberately tiny. Anything else is plain shell against the file system, which
# is the point of choosing shell-native test files.

# The counters are FILES, not shell variables, and that is the whole point.
#
# A shell variable incremented inside a pipeline, a command substitution or a
# "( )" group is incremented in a subshell and the value is lost when it exits.
# So with variable counters, this:
#
#     ui_rows 100 | while read -r row; do check "row $row" ... ; done
#
# - the natural way to assert over rows - printed its FAIL lines to stderr and
# then reported "1 passed, 0 failed" and exited 0. A harness that prints a
# failure and calls the run green is worse than no harness at all, and this was
# the one shape that could do it. Only a file survives a subshell.
#
# One byte appended per check, counted with "wc -c": no read-modify-write, so
# concurrent handlers cannot lose each other's counts either.
check() { # <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf 'p' >> "$OMCTEST_UI/counts.pass"
        printf 'ok   %s\n' "$1" >&2
    else
        printf 'f' >> "$OMCTEST_UI/counts.fail"
        printf 'FAIL %s\n       expected [%s]\n       actual   [%s]\n' "$1" "$2" "$3" >&2
    fi
}

# How many checks of one kind have been counted. Prints 0 rather than nothing
# when none have, so a caller can do arithmetic on it.
omctest_count() { # <pass|fail>
    local kind="$1" counted
    if [ ! -f "$OMCTEST_UI/counts.$kind" ]; then
        printf '0'
        return 0
    fi
    counted=$(/usr/bin/wc -c < "$OMCTEST_UI/counts.$kind" | /usr/bin/tr -d ' ')
    printf '%s' "${counted:-0}"
}

# Reset the counters for one test file's run.
omctest_reset_counts() {
    : > "$OMCTEST_UI/counts.pass"
    : > "$OMCTEST_UI/counts.fail"
    # No dispatch has happened yet in this file, so there must be no status for
    # check_status to find.
    /bin/rm -f "$OMCTEST_UI/.last_status" "$OMCTEST_UI/plan"
}

section() { # <header>
    printf '\n== %s ==\n' "$1" >&2
}

check_exists() { # <description> <path>
    check "$1" "yes" "$([ -e "$2" ] && printf 'yes' || printf 'no')"
}

check_absent() { # <description> <path>
    check "$1" "no" "$([ -e "$2" ] && printf 'yes' || printf 'no')"
}

check_grep() { # <description> <pattern> <file>
    check "$1" "yes" "$(/usr/bin/grep -q -- "$2" "$3" 2>/dev/null && printf 'yes' || printf 'no')"
}

# Reads the status FILE rather than the variable, so this is still correct when
# omc_run was called inside a subshell (where the variable assignment is lost).
# Before any dispatch the file does not exist and the variable is "-", so
# check_status can never pass without a handler having run.
check_status() { # <description> <expected-rc>
    local recorded
    if [ -f "$OMCTEST_UI/.last_status" ]; then
        recorded=$(/bin/cat "$OMCTEST_UI/.last_status" 2>/dev/null)
    else
        recorded="$OMCTEST_STATUS"
    fi
    check "$1" "$2" "$recorded"
}

# Summary, machine-readable counts for the runner, and the file's exit status.
omctest_end() {
    local passed failed planned total
    passed=$(omctest_count pass)
    failed=$(omctest_count fail)
    if [ -f "$OMCTEST_UI/plan" ]; then
        planned=$(/bin/cat "$OMCTEST_UI/plan")
        total=$((passed + failed))
        if [ "$total" -ne "$planned" ]; then
            printf 'FAIL planned %s checks but ran %s\n' "$planned" "$total" >&2
            printf 'f' >> "$OMCTEST_UI/counts.fail"
            failed=$((failed + 1))
        fi
    fi
    printf -- '\n-- %s passed, %s failed --\n' "$passed" "$failed" >&2
    if [ -n "$OMCTEST_COUNTS" ]; then
        printf '%s\t%s\n' "$passed" "$failed" > "$OMCTEST_COUNTS"
    fi
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

# Declare how many checks this file intends to run. omctest_end then refuses a
# run whose count does not match, which is the only thing that catches a file
# that aborted quietly partway through: without it, a file that stops on line 5
# of 50 still reports "4 passed, 0 failed" and the suite is green.
omctest_plan() { # <count>
    case "$1" in
        ''|*[!0-9]*)
            printf 'omctest: omctest_plan needs a count\n' >&2
            return 1
            ;;
    esac
    printf '%s' "$1" > "$OMCTEST_UI/plan"
}

# =============================================================================
# Reading the virtual window back
# =============================================================================
#
# Every helper takes an optional trailing window UUID and defaults to the
# current one. That argument is not a corner case: inside a child sheet real
# applets address omc_dialog_control with BOTH uuids, so a sheet test asserts
# sheet controls with "ui_value 71" and parent-window effects with
# "ui_value 62 \"$OMC_PARENT_DIALOG_GUID\"".

omctest_win_dir() { # [window-uuid]
    printf '%s/win-%s' "$OMCTEST_UI" "${1:-$OMC_ACTIONUI_WINDOW_UUID}"
}

omctest_read_file() { # <path>
    [ -f "$1" ] || return 0
    /bin/cat "$1" 2>/dev/null
}

ui_value() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.value"
}

ui_content_type() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.content_type"
}

# Empty means the control was never touched - which is itself assertable.
ui_enabled() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.enabled"
}

ui_visible() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.visible"
}

ui_rows() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.rows"
}

ui_row_count() { # <view-id> [window-uuid]
    local rows_file
    rows_file="$(omctest_win_dir "$2")/v$1.rows"
    if [ -f "$rows_file" ]; then
        /usr/bin/awk 'END { print NR }' "$rows_file"
    else
        printf '0\n'
    fi
}

ui_columns() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.columns"
}

# 0-based index; empty means no selection.
ui_selection() { # <view-id> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$2")/v$1.selection"
}

ui_prop() { # <view-id> <key> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$3")/v$1.prop.$(printf '%s' "$2" | /usr/bin/tr -c 'A-Za-z0-9_.-' '_')"
}

ui_state() { # <view-id> <key> [window-uuid]
    omctest_read_file "$(omctest_win_dir "$3")/v$1.state.$(printf '%s' "$2" | /usr/bin/tr -c 'A-Za-z0-9_.-' '_')"
}

ui_title() { # [window-uuid]
    omctest_read_file "$(omctest_win_dir "$1")/omc_window.value"
}

ui_calls() { # <grep-pattern>
    /usr/bin/grep -c -- "$1" "$OMCTEST_UI/journal.tsv" 2>/dev/null | /usr/bin/tr -d ' '
}

# Empty output means clean. A warning channel rather than a hard failure,
# because omc_insert_element legitimately mints ids at run time; a test that
# wants it strict asserts check "no unknown writes" "" "$(ui_unknown_writes)".
# Honesty note for v1: known_ids.txt is a UNION across every ActionUI document
# in the bundle, so a typo'd write of id 1 to the main window is masked by a
# legitimate id 1 in an unrelated sheet's JSON.
ui_unknown_writes() {
    omctest_read_file "$OMCTEST_UI/unknown_ids.log"
}

ui_suspect_writes() {
    omctest_read_file "$OMCTEST_UI/suspect_writes.log"
}

ui_errors() {
    omctest_read_file "$OMCTEST_UI/errors.log"
}

# Make subsequent writes to these ids fail, so a handler's error path runs.
ui_fail() { # <view-id> [view-id ...]
    local win_dir view_id
    win_dir=$(omctest_win_dir)
    /bin/mkdir -p "$win_dir"
    for view_id; do
        printf '%s\n' "$view_id" >> "$win_dir/fail_ids"
    done
}

# The actionID of a button in the most recent omc_present_alert. Button specs
# are "title:role:actionID"; a title containing a colon misparses, which is
# documented rather than worked around. The test then fires that command itself
# with omc_run, which is the same dispatch the engine would perform.
ui_alert_action() { # <button-title> [window-uuid]
    /usr/bin/awk -F '\t' -v want="$1" '
        $1 == "button" {
            n = split($2, parts, ":")
            if (parts[1] == want) { print (n >= 3 ? parts[3] : ""); exit }
        }' "$(omctest_win_dir "$2")/pending_alert" 2>/dev/null
}

ui_alert_title() { # [window-uuid]
    /usr/bin/awk -F '\t' '$1 == "title" { print $2; exit }' \
        "$(omctest_win_dir "$1")/pending_alert" 2>/dev/null
}

ui_alert_message() { # [window-uuid]
    /usr/bin/awk -F '\t' '$1 == "message" { print $2; exit }' \
        "$(omctest_win_dir "$1")/pending_alert" 2>/dev/null
}

# Wipe every virtual window and the journal - a mid-file reset.
ui_reset() {
    local win_dir
    for win_dir in "$OMCTEST_UI"/win-*; do
        [ -d "$win_dir" ] || continue
        /bin/rm -rf "$win_dir"
    done
    : > "$OMCTEST_UI/journal.tsv"
    /bin/rm -f "$OMCTEST_UI/unknown_ids.log" "$OMCTEST_UI/suspect_writes.log" \
               "$OMCTEST_UI/errors.log"
}

# =============================================================================
# Fixtures
# =============================================================================
#
# Fixtures are read-only, always. Anything a handler might write to gets copied
# into the test file's own writable area first. Prefer synthesizing a fixture in
# the test file over committing one; reserve committed fixtures for documents
# whose byte-exactness is the point.

fixture() { # <name>
    local name="$1"
    if [ ! -e "$OMCTEST_FIXTURES/$name" ]; then
        printf 'omctest: no such fixture: %s\n' "$OMCTEST_FIXTURES/$name" >&2
        return 1
    fi
    printf '%s' "$OMCTEST_FIXTURES/$name"
}

fixture_copy() { # <name> [dest-dir, default $OMCTEST_WORK]
    local name="$1" dest_dir="${2:-$OMCTEST_WORK}" source_path base
    source_path=$(fixture "$name") || return 1
    /bin/mkdir -p "$dest_dir" || return 1
    /bin/cp -R "$source_path" "$dest_dir/" || return 1
    base=$(/usr/bin/basename "$name")
    /bin/chmod -R u+w "$dest_dir/$base" 2>/dev/null
    printf '%s' "$dest_dir/$base"
}

# =============================================================================
# Runner functions
# =============================================================================
#
# Used by "appletbuilder test" and by applet_build --test. A test file never
# calls these.

# Every "id" in every ActionUI document in the bundle, deduped, one per line.
# The union is v1's admitted masking limitation (see ui_unknown_writes).
omctest_extract_known_ids() { # <app> <out-file>
    local app_path="$1" out_file="$2"
    /usr/bin/python3 - "$app_path" "$out_file" <<'PYEOF'
import json, os, sys

app_path, out_path = sys.argv[1], sys.argv[2]
found = []
seen = set()

def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "id" and isinstance(value, (str, int)) and not isinstance(value, bool):
                text = str(value)
                if text not in seen:
                    seen.add(text)
                    found.append(text)
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)

resources = os.path.join(app_path, "Contents", "Resources")
for dirpath, dirnames, filenames in os.walk(resources):
    if not dirpath.endswith(".lproj"):
        continue
    for name in sorted(filenames):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(dirpath, name)) as handle:
                walk(json.load(handle))
        except Exception:
            continue

with open(out_path, "w") as handle:
    for text in found:
        handle.write(text + "\n")
PYEOF
}

# Run one test file in its own subshell with its own mock environment. Returns 0
# when the file wrote its counts and 1 when it crashed before doing so; the
# counts and the exit code are both read from files under the file's own scratch
# subtree.
#
# NOTHING travels on stdout. It used to: the suite read this function through a
# command substitution, so a test file's own "printf" prepended itself to the
# counts line and was parsed as part of the number - silently inflating the
# totals, or, with a newline in it, producing an arithmetic syntax error that
# killed the whole runner mid-loop and skipped every remaining file. Debug
# output from a test file is the normal case, not an exotic one, and a harness
# that miscounts because of it is worse than no harness. The test file's stdout
# now goes to the handler log; its ok/FAIL lines were always on stderr.
omctest_run_file() { # <app> <testfile>
    local app_path="$1" test_file="$2" label counts_file rc_file rc
    label=$(omctest_label_for "$test_file")
    /bin/mkdir -p "$OMCTEST_SCRATCH/$label" || return 1
    counts_file="$OMCTEST_SCRATCH/$label/counts"
    rc_file="$OMCTEST_SCRATCH/$label/rc"
    /bin/rm -f "$counts_file" "$rc_file"

    (
        OMCTEST_COUNTS="$counts_file"
        export OMCTEST_COUNTS
        omctest_prepare_env "$app_path" "$label" || exit 70
        # Loud on failure. The stub skips the undeclared-id check entirely when
        # known_ids.txt is absent, so a silent failure here turns the
        # recommended "no unknown writes" assertion into a vacuous pass.
        if ! omctest_extract_known_ids "$app_path" "$OMCTEST_UI/known_ids.txt" \
           || [ ! -s "$OMCTEST_UI/known_ids.txt" ]; then
            printf 'omctest: no view ids extracted - the undeclared-id check is OFF for this file\n' >&2
        fi
        OMCTEST_PREPARED=1
        export OMCTEST_PREPARED
        # stdout only - stderr carries the ok/FAIL lines and must keep streaming.
        /bin/sh "$test_file" >> "$OMCTEST_UI/handlers.log"
    )
    rc=$?
    # The caller reads this function through a command substitution, which is
    # itself a subshell - so a variable set here would never reach it. The exit
    # code of a crashed file travels by file instead.
    printf '%s\n' "$rc" > "$rc_file"

    [ -f "$counts_file" ]
}

# Run every *.test.sh in a directory, in lexical order, and aggregate. Detail to
# stderr, one machine-readable line on stdout. Exit 0 all passed, 1 any failure
# or crash, 2 no tests found.
omctest_run_suite() { # <app> <tests-dir> [filter-glob]
    local app_path="$1" tests_dir="$2" filter="$3"
    local own_scratch=0 total_pass=0 total_fail=0 file_count=0
    local test_file base label counts pass_n fail_n crash_rc

    if [ ! -d "$tests_dir" ]; then
        printf 'omctest: no tests directory at %s\n' "$tests_dir" >&2
        return 2
    fi

    if [ -z "$OMCTEST_SCRATCH" ] || [ ! -d "$OMCTEST_SCRATCH" ]; then
        OMCTEST_SCRATCH=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/omctest.XXXXXX") || return 1
        export OMCTEST_SCRATCH
        own_scratch=1
        trap 'omctest_cleanup_scratch' EXIT
        trap 'omctest_cleanup_scratch; exit 130' INT
        trap 'omctest_cleanup_scratch; exit 143' TERM
    fi

    OMCTEST_TESTS="$tests_dir"
    export OMCTEST_TESTS

    for test_file in "$tests_dir"/*.test.sh; do
        [ -f "$test_file" ] || continue
        base=$(/usr/bin/basename "$test_file")
        if [ -n "$filter" ]; then
            case "$base" in
                $filter) ;;
                *) continue ;;
            esac
        fi
        label=$(omctest_label_for "$test_file")
        if [ -d "$OMCTEST_SCRATCH/$label" ]; then
            # Two matched files slug to one label, so they would share a scratch
            # subtree and a window uuid. Refused rather than run: the second one
            # would read the first one's virtual window and could pass having
            # dispatched nothing.
            printf 'omctest: two test files use the label "%s" - rename one (%s)\n' \
                "$label" "$base" >&2
            total_fail=$((total_fail + 1))
            continue
        fi
        file_count=$((file_count + 1))
        printf '\n### %s\n' "$base" >&2

        if ! omctest_run_file "$app_path" "$test_file"; then
            # A file that exits without writing its counts crashed. Never
            # silently dropped: it counts as a failure and is named.
            crash_rc=$(/bin/cat "$OMCTEST_SCRATCH/$label/rc" 2>/dev/null)
            printf 'CRASH %s (exit %s)\n' "$base" "${crash_rc:-?}" >&2
            total_fail=$((total_fail + 1))
            continue
        fi
        counts=$(/bin/cat "$OMCTEST_SCRATCH/$label/counts" 2>/dev/null)
        pass_n=$(printf '%s' "$counts" | /usr/bin/cut -f 1)
        fail_n=$(printf '%s' "$counts" | /usr/bin/cut -f 2)
        # Guarded before the arithmetic: a non-numeric field would be a shell
        # syntax error, which is fatal in a non-interactive shell and would take
        # the rest of the suite with it.
        case "$pass_n" in ''|*[!0-9]*) pass_n=0 ;; esac
        case "$fail_n" in ''|*[!0-9]*) fail_n=1 ;; esac
        total_pass=$((total_pass + pass_n))
        total_fail=$((total_fail + fail_n))
    done

    if [ "$file_count" -eq 0 ]; then
        printf 'omctest: no test files matched in %s\n' "$tests_dir" >&2
        return 2
    fi

    printf 'omctest: %s passed, %s failed, %s files\n' "$total_pass" "$total_fail" "$file_count"
    if [ "$own_scratch" = "1" ] && [ "$OMCTEST_KEEP_SCRATCH" = "1" ]; then
        printf 'omctest: scratch kept at %s\n' "$OMCTEST_SCRATCH" >&2
    fi
    [ "$total_fail" -eq 0 ] || return 1
    return 0
}

# =============================================================================
# Bootstrap
# =============================================================================
#
# Ordered and exclusive. The runner exports OMCTEST_RUNNER=1 in its own process,
# so a test-file child inherits BOTH variables - OMCTEST_PREPARED must therefore
# be tested first and win.

# Standalone mode: no runner built anything, so build it here. The .app comes
# from $OMCTEST_APP, or from the single *.app beside the test file's Tests/
# directory.
omctest_standalone_init() {
    local test_file test_dir project_dir candidate app_path count

    test_file="$0"
    test_dir=$(cd "$(/usr/bin/dirname "$test_file")" >/dev/null 2>&1 && pwd)
    [ -n "$test_dir" ] || test_dir=$(pwd)

    if [ -n "$OMCTEST_APP" ]; then
        app_path="$OMCTEST_APP"
    else
        project_dir=$(/usr/bin/dirname "$test_dir")
        app_path=""
        count=0
        for candidate in "$project_dir"/*.app; do
            [ -d "$candidate" ] || continue
            app_path="$candidate"
            count=$((count + 1))
        done
        if [ "$count" -ne 1 ]; then
            printf 'omctest: expected exactly one .app beside %s (found %s) - set OMCTEST_APP\n' \
                "$test_dir" "$count" >&2
            return 1
        fi
    fi

    OMCTEST_TESTS="$test_dir"
    export OMCTEST_TESTS
    omctest_prepare_env "$app_path" "$(omctest_label_for "$test_file")" || return 1
    # Same loud failure the runner path has: silence here would leave the
    # undeclared-id check off and the recommended assertion passing vacuously.
    if ! omctest_extract_known_ids "$OMCTEST_APP" "$OMCTEST_UI/known_ids.txt" \
       || [ ! -s "$OMCTEST_UI/known_ids.txt" ]; then
        printf 'omctest: no view ids extracted - the undeclared-id check is OFF\n' >&2
    fi
}

if [ -n "$OMCTEST_PREPARED" ]; then
    # The runner already built everything. Attach: reset this file's counters.
    omctest_reset_counts
elif [ -n "$OMCTEST_RUNNER" ]; then
    # Sourced for the runner functions. Define and do nothing.
    :
else
    omctest_standalone_init || return 1
fi
