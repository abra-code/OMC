# omcitest - integration tests for an OMC applet

`appletbuilder itest <App.app>` runs the `*.itest.sh` files beside an applet against the **real applet, launched by the real OMC engine**, and drives its windows over the ActionUI bridge. This guide is for writing those files, by a person or by an agent that has never seen the applet.

Read `omctest_guide.md` first if you have not: the unit suites (`*.test.sh`) and these integration tests share their words (`section`, `check`, `alert_answer`, ...), and most of an applet's coverage belongs in the unit suites.

---

## 1. Which kind of test, and when

| | omctest (`*.test.sh`) | omcitest (`*.itest.sh`) |
|---|---|---|
| Runs | one handler at a time, in a shell | the applet itself, one fresh process per file |
| Window | a virtual one the harness records | the real ActionUI window, read and driven over the bridge |
| Engine | not involved: you set `$OMC_*` yourself | the real one: it sets the environment, chains commands, opens panels |
| Speed | milliseconds per handler | seconds per file; windows open on screen and take the focus |
| Catches | handler logic, error paths, edge values | what only the engine shows: launch chains, `INIT_SUBCOMMAND_ID` and LoadableView handlers running in their real order and concurrency, panels, chained commands, close handlers, races between handlers |

Write the unit suites for the logic. Write one integration test file per applet for the paths a user walks: launch, open something, the main window's first state, one or two actions, close. Integration tests have found bugs the unit suites could not: a Libraries tab left empty because two view handlers raced (OTool), a test launch's files leaking into the user's Open Recent (the engine), the host's environment reaching the applet under test (AppletBuilder).

---

## 2. Requirements

- **The applet carries an OMC 5.5 engine.** An older engine has no test launch: the harness reports "the applet did not come up for the test". AppletBuilder's **Build** puts AppletBuilder's engine into the applet.
- **The applet is signed for local use**: ad hoc, self-signed, or a development certificate (get-task-allow). A Developer ID, App Store, TestFlight or other distribution signature, or the hardened runtime without get-task-allow, refuses the test launch: the applet prints `OMC test launch refused: <reason>` and exits with status 78. Build with "Sign to Run Locally (ad-hoc)".
- **A logged-in GUI session.** Real windows open and take the focus while a file runs.
- **For an agent:** the harness talks to the applet over a Unix socket, which the agent sandbox blocks, so a run needs the sandbox off. Tools the applet runs through `xcrun` shims (`otool`, `nm`, `lipo`, `clang`) may print "couldn't create cache file" inside a sandbox; that is the sandbox, not the applet.

---

## 3. Running

```bash
appletbuilder itest MyApp.app [--tests <dir>] [--filter <glob>] [--verbose] [--keep] [--list]
```

- `--tests` defaults to the `Tests/` folder beside the bundle; `--filter` picks files by name (`--filter 'speech*'`); `--list` prints the files that would run.
- `--verbose` prints the applet's own output (stdout and stderr) after each file: the first place to look when a window never opens.
- `--keep` keeps each file's private folder (the applet's home, temp folder and `applet.log`) and prints where it is.
- The summary line is `itest: N passed, M failed, K files`. The exit status is 0 only when everything passed; 2 means bad arguments or no test files.

In AppletBuilder, the **Integration Test** button in the Build & Run pane runs the same command on the loaded applet and streams the transcript into the pane's log. If a copy of the applet is already running, it asks to quit it first (normal quit, so the copy may ask about unsaved work); the tests never run beside a running copy.

**The button tests the applet in place.** `ITEST_APP` is then the bundle in your repository, not a copy. A test must never write into `ITEST_APP` (no signing, no stapling, no copying into it).

For OMC engine development, `Tools/omcitest_tests/run_fixture.sh` runs the same tests against a copy of an applet, optionally with an engine you just built:

```bash
Tools/omcitest_tests/run_fixture.sh --app ~/git/MyAppApp/MyApp.app \
    --framework ~/Library/Developer/Xcode/DerivedData/OMC-*/Build/Products/Release/Abracode.framework \
    [--filter <glob>] [--keep] [--verbose]
```

With no `--app` it runs the ITestFixture applet, the end-to-end check of the harness itself. `--keep` keeps the copy as well as each file's private folder.

---

## 4. A first test file

Layout, beside the bundle:

```
MyAppApp/
    MyApp.app/
    Tests/
        10-window.test.sh        unit suites (omctest)
        lib.test.myapp.sh
        myapp.itest.sh           integration tests: *.itest.sh
        make-fixtures.sh         optional: builds what the tests open
```

A complete file:

```bash
# Tests/myapp.itest.sh - MyApp through the real engine (appletbuilder itest, OMC 5.5).

# View ids from the applet, never restated; check the import, or a renamed constant reads empty.
eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$ITEST_APP/Contents/Resources/Scripts/lib.myapp.sh")"
check "the view ids imported" "10 20" "$TABLE_ID $STATUS_ID"

rows() { # <window> <view-id> -> the table's rows (JSON)
    itest_call actionui.getRows "{\"window\": \"$1\", \"viewID\": $2}"
}

section "A bare launch opens the main window"
# The harness already waited for the launch; this one reports a slow first window as a timeout.
itest_wait_idle 60
window="$(itest_windows)"
check "one window" "1" "$(printf '%s\n' "$window" | /usr/bin/grep -c .)"
check "the status says what to do" "Drop files here" "$(itest_value "$window" "$STATUS_ID")"

section "A file opened with the app gets its own window"
SAMPLE="$ITEST_WORK/sample.txt"
printf 'hello\n' > "$SAMPLE"
before="$(itest_windows)"
itest_run MyApp --file "$SAMPLE" > /dev/null
itest_wait_idle 60
second="$(itest_new_window "$before")"
check "a new window" "yes" "$([ -n "$second" ] && printf yes || printf no)"
check_contains "listing the file" "sample.txt" "$(rows "$second" "$TABLE_ID")"

section "Closing a window runs its end command"
itest_close "$second" > /dev/null
itest_wait_idle 60
check "the window is gone" "" "$(itest_windows | /usr/bin/grep -x -- "$second")"
```

There is no `omctest_end`: the runner sources the file inside a function, counts the checks, and quits the applet afterwards (so `app.will.terminate` runs).

---

## 5. What a test file runs in

Each file gets a **fresh applet process**, launched with the applet's own executable, and its own private folder under `/tmp/omcit.*`, removed afterwards.

| Variable | What it is |
|---|---|
| `ITEST_APP` | the applet under test (in place when run from the button or the CLI; a copy under `run_fixture.sh`) |
| `ITEST_WORK` | a private folder for the test's own files: fixtures, samples, outputs |
| `ITEST_HOME` | the applet's `$HOME` for this file, with `Library/Application Support`, `Preferences` and `Caches` |
| `ITEST_TMPDIR` | the applet's `$TMPDIR` for this file; per-window state folders appear here |
| `ITEST_PASTEBOARD_PREFIX` | the run's pasteboards are `<prefix>.<name>`; the applet never touches the user's |
| `OMCTEST_UI` | where the alert and notify stand-ins record (read through `alerts_count` and friends) |

To find the folder the test file sits in (to run a fixture builder beside it): `tests_dir="$(/usr/bin/dirname "${BASH_SOURCE[0]}")"`.

**Isolated for you:**

- `$HOME` and `$TMPDIR`, for everything the handlers do through them. An applet that keeps its settings under `$HOME/Library/Application Support/<App>` starts every file with none.
- Pasteboards that go through OMC (`pasteboard`, and the engine's own clipboard reads).
- `alert` and `notify` in handlers: stand-ins that record and answer, never show anything.
- The engine's own panels and alerts: answered from a queue (section 6), never shown.
- `PASTE_AFTER_EXECUTION`: no keystrokes are sent; `omc.test.status` counts them as `skippedPastes`.
- Recent documents: a test launch adds nothing to the user's Open Recent or Recent Items; `omc.test.status` counts them as `skippedRecentDocuments`.
- The host's environment: when AppletBuilder runs the tests, its own `OMC_*`, `ACTIONUI_*` and `PYTHONPATH` are removed before the applet starts.

**Not isolated, and a test must avoid it:**

- Anything that asks the system for the home folder instead of `$HOME`: `NSHomeDirectory`, `NSUserDefaults`, `CFPreferences`, `defaults` on a domain, a framework's own Application Support lookup. These are the user's real ones.
- Tools a handler runs by absolute path: `/usr/bin/pbcopy` and `pbpaste` (the real clipboard), `/usr/bin/open` (Finder, other apps), `security` (the real keychain), network tools (the real network). Do not click what runs them, or give the applet a seam (`omctest_guide.md`, the seam contract).
- `ITEST_APP` itself, when the button runs the tests in place (section 3).
- The applet's debug logs or flags under fixed paths like `/tmp/<app>-debug.log`.

---

## 6. The API

Every function prints its result on stdout; failures go to stderr and fail the check that reads them.

### Checks

| Function | Use |
|---|---|
| `section <header>` | a heading in the output |
| `check <description> <expected> <actual>` | exact string comparison |
| `check_contains <description> <needle> <haystack>` | plain substring |

### Commands and waiting

| Function | Use |
|---|---|
| `itest_run <command-id> [--text T] [--file PATH]... [--open-panel] [--window W] [--key-window]` | runs a command as its menu item would; prints the run number. The primary command, which has no `COMMAND_ID`, is run by the applet's `NAME`. `--file` gives it a file context. `--open-panel`: a command that needs files and got none asks for them in the open panel, which takes a queued answer. `--window W`: as window W's subcommand, as a menu bar command runs for the key window (a test launch has no key window) |
| `itest_wait_idle [seconds]` | waits until no command runs and the applet has settled; fails the file's check on timeout. Default 20 s (`OMCITEST_IDLE_TIMEOUT`) |
| `itest_output <run>` / `itest_run_finished <run>` | what a run's tasks printed; `yes` once all of them ended |
| `itest_call <method> [params-json]` | any bridge method, raw; prints the JSON result |
| `itest_quit` | quits now (the runner does this after the file anyway) |

### Windows and controls

| Function | Use |
|---|---|
| `itest_windows` | the open ActionUI windows, one uuid per line |
| `itest_new_window <before>` | the window in `itest_windows` that was not in `<before>` |
| `itest_value <window> <view-id> [part]` | a control's value as text |
| `itest_set_value <window> <view-id> <text> [part]` | sets a value as the user's typing would end up; fires no action |
| `itest_click <window> <view-id> [part]` | fires the control's `actionID` as a click does; prints the actionID |
| `itest_close <window>` | closes the window as its close button does, so its `END_CANCEL_SUBCOMMAND_ID` runs |
| `itest_call actionui.getRows '{"window": "...", "viewID": N}'` | a table's rows, as JSON |
| `itest_call actionui.getProperty '{"window": "...", "viewID": N, "name": "disabled"}'` | a property: `disabled`, `hidden`, `options`, ... as JSON |

### Panels and engine alerts

| Function | Use |
|---|---|
| `itest_answer_open <path>...` / `itest_answer_save <path>` / `itest_answer_cancel` | queues the answer for the next panel. Queue it **before** the action that opens the panel |
| `itest_answer_alert <default\|alternate\|other>` | answers the next engine alert (a `WARNING` confirmation, a version warning), from the same queue |
| `itest_panel_count`, `itest_panel <index\|last> <field>` | what was shown: `kind` (open, save, alert, notice), `message`, `defaultName`, `canceled`, `problem`, ... |
| `itest_panels_clear` | forgets the records and any answers not yet taken |

A panel with no answer queued is **canceled** and recorded. An answer the panel could not have given (a missing file, a folder for a files-only panel) cancels it too, and `problem` says why.

### Handler alerts, notifications, pasteboards

| Function | Use |
|---|---|
| `alert_answer <rc>...` | answers for the next `alert` a handler runs (0 OK, 1 Cancel, 2 Other); with none queued an alert answers 0 |
| `alerts_count`, `alerts_mention <text>`, `alerts_reset`, `alert_answers_reset` | what handlers showed |
| `notify_count`, `notify_mention <text>` | the same for `notify` |
| `itest_pasteboard [name]` / `itest_set_pasteboard <text> [name]` | the run's own pasteboards (default `general`) |

### Status

`itest_call omc.test.status` returns `{idle, activeCommands, scheduledRuns, scheduledCloses, activity, pasteboardPrefix, skippedPastes, skippedRecentDocuments, supportPath}`.

---

## 7. Patterns

**The launch.** The engine runs the primary command on a bare launch, as it does for a user. What that shows depends on the command:

- An `act_always` command opens its window: wait idle, then `itest_windows`.
- A command that takes a file or folder (`act_file`, `act_file_or_folder`) asks for one in the open panel. With no answer queued the harness cancels it, so no window opens. Check the panel record (`itest_panel last message`, `itest_panel last canceled`), then open something yourself.

**Opening something.**

- **As a drop or "Open With":** `itest_run <NAME> --file <path>`.
- **Through the open panel:** `itest_answer_open <path>`, then `itest_run <NAME> --open-panel`. This also checks the panel's message and filters.
- A file the test opens should be its own, under `$ITEST_WORK`. Opening the applet's own bundle (`$ITEST_APP`) works for an applet that inspects apps, as long as nothing writes to it.

**Waiting.** `itest_wait_idle` after every `itest_run`, `itest_click`, `itest_close` and `itest_set_value` that triggers work. Some work happens after idle:

- a LoadableView's handlers run when the view loads;
- a poller keeps running;
- a background job finishes later.

Poll for its result with a deadline instead of sleeping:

```bash
wait_until() { # <seconds> <command...>
    local _deadline=$(( SECONDS + $1 ))
    shift
    while [ "$SECONDS" -lt "$_deadline" ]; do
        "$@" && return 0
        /bin/sleep 0.25
    done
    "$@"
}
has_rows() { case "$(rows "$1" "$2" 2>/dev/null)" in ''|'[]') return 1 ;; esac; return 0; }
wait_until 30 has_rows "$window" "$TABLE_ID"
check "the table was filled" "0" "$?"
```

**A TabView.** `itest_click` on a Tab fires its `actionID` but does not show the tab, so a LoadableView inside it never loads and the bridge answers `Unknown view N`. Do what a click does: first set the TabView's value to the tab's 0-based index (the tab shows, its views load), then click the Tab:

```bash
itest_set_value "$window" "$TAB_VIEW_ID" 4 > /dev/null
itest_wait_idle 60
itest_click "$window" "$SYMBOLS_TAB_ID" > /dev/null
itest_wait_idle 60
```

**Selecting a table row.** A table's handler reads the selected row (`OMC_ACTIONUI_TABLE_<id>_COLUMN_<n>_VALUE`). Select the row over the bridge, which fires nothing, then click the table, which fires its `actionID` with that row:

```bash
itest_call actionui.selectRow "{\"window\": \"$window\", \"viewID\": $TABLE_ID, \"index\": 0}" > /dev/null
itest_click "$window" "$TABLE_ID" > /dev/null
itest_wait_idle 60
```

Do not set a table's value to select a row: that replaces its rows.

**Reading JSON.** `actionui.getProperty` and `getRows` answer with JSON as Python prints it: `["x86_64", "arm64"]`, with a space after each comma. Compare with `check_contains` on one element, or strip the spaces (`| /usr/bin/tr -d ' '`).

**Per-window state.** Applets keep a window's state in `$TMPDIR/<app>-state-<window-uuid>`. Under test that is `$ITEST_TMPDIR/...`, and the uuid is the one `itest_windows` prints. Check that the folder exists before asserting that closing removed it, or a wrong path passes forever.

**Fixtures.** Build what the tests open at test time, from a script beside them (`make-fixtures.sh "$ITEST_WORK/fixtures"`), rather than committing binaries: the script states what each fixture contains, which is what the checks read back. Check its exit status as the first check.

**Guard the dangerous click.** When a button would do something real if a precondition were missing (upload, sign, delete, send), check the precondition from the state the handler reads, and skip the click if it is not met:

```bash
# Notarize: with a notary profile to pick, the next click would sign and upload.
if [ "$profiles" = "[]" ] && [ "$profile_rows" = "0" ]; then
    itest_click "$window" "$NOTARIZE_BTN_ID" > /dev/null
    ...
fi
```

**Prove the applet was only read.** When the tests open `$ITEST_APP` or another file that must not change, take a digest at the start and compare at the end:

```bash
app_digest="$(/bin/cat "$ITEST_APP/Contents/_CodeSignature/CodeResources" "$executable" | /sbin/md5 -q)"
...
check "the applet was not changed" "$app_digest" "$(/bin/cat ... | /sbin/md5 -q)"
```

---

## 8. Traps

1. **A check before the work is done.** `itest_close` and `itest_click` return when the request is taken, not when the handler ends. Without `itest_wait_idle`, "the state folder is gone" fails or, worse, an absence check passes because nothing ran yet.
2. **Checks against empty text pass when the bridge call failed.** A failed `itest_value` prints nothing, so `check "the log is empty" "" "$(itest_value ...)"` cannot tell an empty log from a dead bridge. Pair it with a positive check on the same window in the same section.
3. **A test file that writes into `ITEST_APP`.** Under the button it is the developer's applet in its repository.
4. **The real user state.** Anything listed under "Not isolated" in section 5 reaches the developer's machine. Read the handler behind every click.
5. **Tab content that never loaded.** See the TabView pattern; `Unknown view N` from the bridge means the view is not on screen.
6. **Two copies.** A copy of the applet the developer has running shares its preferences domain and anything under its bundle. The button refuses to run beside one; from the CLI, quit it first.
7. **Answers queued for the wrong panel.** Panels and engine alerts share one queue, in order. An answer that was not taken stays queued for the next one: `itest_panels_clear` at the start of a section that counts.
8. **Engine version.** A test that reads a newer `omc.test.status` field (such as `skippedRecentDocuments`) fails against an applet built with an older 5.5 engine. Build the applet with the current AppletBuilder first.

---

## 9. When it fails

| Symptom | Likely cause |
|---|---|
| `OMC test launch refused: <reason>` | the signature (section 2) |
| `the applet did not come up for the test` | an engine older than 5.5, or the applet crashed at launch: rerun with `--verbose` |
| `Unknown view N in window ...` | the view is not loaded: a tab not shown, a sheet not open, a LoadableView not yet loaded |
| a window never opens | the primary command takes a file: check `itest_panel last kind` for a canceled open panel |
| `params are not JSON` | quoting in an `itest_call` parameter: build the JSON in one double-quoted string with `\"` around each key |
| tool output with "couldn't create cache file" | the agent sandbox blocking `xcrun`; run with the sandbox off |

`--verbose` prints the applet's own output after each file; `--keep` keeps each file's private folder (the applet's home, temp folder and `applet.log`) to look into afterwards.
