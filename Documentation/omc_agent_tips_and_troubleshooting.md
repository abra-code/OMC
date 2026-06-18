# OMC Tips & Troubleshooting for AI Agents

Hard-won lessons from real applet builds by AI agents. Every item here caused a
real failure or hours of confused debugging for at least one agent. Read §1
before writing any shell script; consult the rest when something "should work
but doesn't".

---

## 1. Your scripts run under /bin/sh — macOS bash 3.2 in POSIX mode

**This is the #1 cause of silent, unexplainable applet failures by AI agents.**

macOS ships bash **3.2** (from 2007) and `/bin/sh` is that same bash running in
POSIX mode. There is no bash 4 or 5 on a stock Mac. OMC executes `.sh` action
scripts with `/bin/sh` — the shebang line is ignored.

Syntax you must never use in `.sh` scripts (these are **parse errors** under
`/bin/sh` — the script dies, sometimes mid-file, with no UI feedback):

| Forbidden (bash 4+/bashism) | Use instead |
|---|---|
| `done < <(command)` (process substitution) | pipe into the loop, or redirect from a temp file |
| `mapfile` / `readarray` | `while IFS= read -r line; do …; done < file` |
| `declare -A` (associative arrays) | state files in the scratch dir, or `case` statements |
| `${var,,}` `${var^^}` (case conversion) | `tr 'A-Z' 'a-z'` |
| `[[ str =~ regex ]]` with capture groups | `sed -n 's/…/\1/p'` or `case` patterns |
| `|&`, `&>>` | `2>&1 |`, `>> f 2>&1` |

> **Real failure:** an agent collected discovery results with
> `while read …; done < <(echo "$out")`. The script passed `bash -n`, worked
> perfectly when the agent ran it manually in its (bash) terminal, and died
> with a parse error every time OMC ran it — at the exact line, after the
> early UI updates had already appeared. The agent spent several rounds adding
> logging above the line that could never be reached below it, and never found
> the bug. The sidebar table simply "would not populate".

**Rules:**

1. Validate every script with **`sh -n script.sh`** after every edit —
   `bash -n` will NOT catch these errors. (AppletBuilder's Build and the
   Scripts-tab Validate button do this too: `.sh` is checked with `/bin/sh -n`
   — mirroring the engine — plus a heuristic scan that warns on bash-4+
   constructs which parse fine but fail at runtime, like `declare -A`,
   `mapfile`, and `${var,,}`. Treat those warnings as errors.)
2. When testing logic manually, run scripts with `sh script.sh`, never
   `bash script.sh`.
3. Plain indexed arrays (`a=(x y)`, `"${a[@]}"`), `local`, and `$(( ))` do
   work in macOS sh (it is still bash underneath) — but anything from the
   table above does not.
4. If you genuinely need modern shell features, name the script `.zsh`
   (macOS zsh is current). For heavy parsing prefer a single `awk` program
   or Python (embedded via AppletBuilder when needed).

---

## 2. Test scripts the way OMC runs them

You can exercise nearly all handler logic without launching the applet: stub
the OMC support tools, export the context variables, run with `sh`.

```bash
mkdir -p /tmp/stub
cat > /tmp/stub/omc_dialog_control <<'EOF'
#!/bin/bash
if [ "$3" = "omc_table_set_rows_from_stdin" ]; then
    echo "== table view=$2 rows:"; head -5
else
    echo "== dlg: $*"
fi
EOF
printf '#!/bin/bash\necho "== next: $*"\n' > /tmp/stub/omc_next_command
printf '#!/bin/bash\necho "== notify: $*"\n' > /tmp/stub/notify
chmod +x /tmp/stub/*

export OMC_APP_BUNDLE_PATH=/path/to/MyApp.app
export OMC_OMC_SUPPORT_PATH=/tmp/stub
export OMC_ACTIONUI_WINDOW_UUID=TESTWIN
export OMC_CURRENT_COMMAND_GUID=TESTGUID
export OMC_OBJ_PATH=/path/to/test/input
sh "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/MyApp.some.handler.sh"
```

Simulate control events by exporting the env vars a handler reads
(`OMC_ACTIONUI_VIEW_<N>_VALUE`, `OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE`,
`OMC_ACTIONUI_TRIGGER_VIEW_ID`, `OMC_ACTIONUI_TRIGGER_CONTEXT`) before the call.

---

## 3. Where initialization code belongs

- **`INIT_SUBCOMMAND_ID`** (in `ACTIONUI_WINDOW` / `NIB_DIALOG`) runs **before
  the window appears**. This is the place for discovery, state seeding, and
  populating controls that exist in the top-level JSON.
- **The main command's own script** (`MyApp.main.sh`) must contain **no code**
  when the window is non-blocking (`IS_BLOCKING: false`) — its execution time
  relative to the window is unpredictable. It is only useful for *blocking*
  dialogs, to read the dialog's values before it is torn down. Make it
  `exit 0` with a comment.
- **Views inside a `LoadableView` do not exist yet at init time** —
  `omc_dialog_control` calls targeting them are silently lost. Give every
  LoadableView a `viewDidLoadActionID` and populate it there, reading from
  state files the init script wrote.
- **Signal readiness atomically**: have init write its main state file last,
  via a temp file + `mv`. viewDidLoad handlers poll for it:

```bash
wait_for_state() {
    local i=0
    while [ $i -lt 100 ]; do
        [ -f "$(state_dir)/ready.tsv" ] && return 0
        /bin/sleep 0.1; i=$((i + 1))
    done
    return 1
}
```

---

## 4. Tables: rows, selection, hidden columns

- Feed rows with `omc_table_set_rows_from_stdin` (tab-separated fields, one
  row per line).
- **Never set a Table's *value* to select a row** (`omc_dialog_control <win>
  <tableID> "text"`) — it replaces the table's *rows* with that single string,
  not the selection. A real build wiped a freshly fed 12-row sidebar down to one
  blank-looking row this way.
- **Select rows with the dedicated verbs** (work on Table *and* List):
  - `omc_select_row <0-based index>` — select by position; an out-of-range
    index clears the selection.
  - `omc_select_row_with_content <text> [1-based column]` — select the
    *first* row whose column equals `text` (exact, case-sensitive). Omit the
    column (or pass `0`) to match against *any* column, including hidden ones;
    the 1-based column numbering matches `$OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE`.
  - `omc_deselect` — clear the selection.

  These set the selection without touching the rows and fire **no** actionID
  (programmatic selection is silent — no selection-changed feedback loop). Apply
  them *after* feeding rows; read the result back from `$OMC_ACTIONUI_VIEW_<id>_VALUE`
  (or the per-column `$OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE`). They apply to
  Table, homogeneous List, and template List; heterogeneous List children (which
  select by child element ID) are not covered. You may still want to keep the
  "current item" in a state file so handlers don't depend on a visual selection.
- **Hidden data columns**: feed *more* tab-separated fields than the JSON
  declares as columns. Extras are invisible but readable in handlers via
  `$OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE` (1-based across declared +
  hidden fields). Canonical use: visible `[Name, Type]` + hidden full path as
  column 3.
- Selection-changed actions also fire on **deselection** with empty COLUMN
  values — handle the empty case first.
- In the JSON, declare per-column `minWidths` — ActionUI's default minimum is
  10 pt, which lets columns collapse to unreadable slivers.

---

## 5. Pickers and control value semantics

- **A Picker's value and trigger context are the 1-based option INDEX**, not
  the option title (observed with segmented and plain-string-options pickers:
  clicking the second segment delivers `"2"`). Setting the selection
  programmatically also takes the index — `set value "arm64"` is a silent
  no-op; `set value "2"` selects the second option.
- Keep each picker's option list (in display order) in a state file so any
  handler can map index → name:

```bash
# picker_resolve <raw value> <space-separated option names in order>
picker_resolve() {
    local val="$1" list="$2"
    case " $list " in *" $val "*) echo "$val"; return ;; esac   # name/tag
    case "$val" in
        ''|*[!0-9]*) echo "" ;;                                  # bogus
        *) echo $list | /usr/bin/awk -v n="$val" '{print $n}' ;; # index
    esac
}
```

- **TabView is different**: its `actionID` delivers the **0-based tab index**
  as trigger context.
- Programmatic `omc_set_property options …` / value updates can fire the
  control's actionID with stale or bogus values. **Validate every value that
  arrives from a control event** before writing it to state — especially
  before it ends up in a CLI invocation. (A real build passed an unvalidated
  picker value to `otool -arch` and every tab filled with otool usage text.)
- In a handler shared by several controls, `$OMC_ACTIONUI_TRIGGER_VIEW_ID`
  identifies which control fired.
- Only set properties that exist in the ActionUI schema for that element —
  e.g. there is no `selection` property on Table or Picker; setting it does
  nothing and misleads your debugging.

---

## 6. When you cannot tell from the code: instrument, don't guess

Runtime semantics (what a trigger context contains, whether an event fires,
ordering of viewDidLoad vs init) are not always derivable from documentation.
Add cheap logging, ask the human to perform the UI operation once, read the
log back:

```bash
# In the shared lib — enabled by `touch /tmp/myapp-debug-on`
dbg() {
    [ -f /tmp/myapp-debug-on ] || return 0
    echo "$(/bin/date +%H:%M:%S) [$(/usr/bin/basename "$0" .sh)] $*" \
        >> /tmp/myapp-debug.log
}
dbg_trigger() {
    dbg "trigger view=$OMC_ACTIONUI_TRIGGER_VIEW_ID part=$OMC_ACTIONUI_TRIGGER_VIEW_PART_ID ctx=$OMC_ACTIONUI_TRIGGER_CONTEXT"
}
```

Call `dbg_trigger` first in every event handler and `dbg` around every state
decision. One round of "please click the control, then I'll read the log"
resolves questions that hours of code-rereading cannot. (This is how the
picker index semantics in §5 were discovered.)

Other live-debugging tools:
- **Ctrl-click** the control that triggers a command → its stdout/stderr
  appears in an output window.
- `printenv | sort` inside a handler dumps the full OMC context.

---

## 7. Pre-flight checklist before asking the user to Build

1. `sh -n` passes for every `.sh` script (see §1).
2. Command verifier passes against the **bundle** (`validate_command_plist.py
   MyApp.app`) — catches dangling COMMAND_IDs, missing scripts, missing
   dialog resources.
3. ActionUI verifier passes for every JSON in `Base.lproj/`.
4. Every `actionID` / `valueChangeActionID` / `viewDidLoadActionID` in the
   JSON has a matching `COMMAND_ID` in the command file, and each COMMAND_ID's
   script filename matches it exactly (`MyApp.foo.bar` ↔ `MyApp.foo.bar.sh`).
5. Resource edits (scripts, JSONs) don't block launch during development —
   applets are signed for local execution and macOS (as of 26) tolerates
   modified resources. Re-sign (**Build** in AppletBuilder, or
   `codesign_applet.sh`) after binary/framework changes, before distributing,
   or if the OS refuses to launch the app.
6. State written under `$TMPDIR/<app>-<window-uuid>/` and cleaned in the
   `END_CANCEL_SUBCOMMAND_ID` handler (plus an `app.will.terminate` sweep).
