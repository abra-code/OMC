# omctest - writing tests for an OMC applet

`omctest` runs an applet's real handler scripts inside a simulated OMC environment and lets you assert on everything they touch: files they wrote, exit codes, tools they invoked, and what they pushed toward the window.

You write plain POSIX `sh` files under `Tests/` next to the `.app`, and run them with:

```
appletbuilder test MyApp.app
```

This guide is the reference for writing those files. It assumes no prior context beyond the OMC scripting basics.

---

## 1. Why this exists, and what it does not do

An applet's logic lives entirely in its handler scripts, and those scripts have no callable entry point. The engine runs them in response to UI events, feeds them input through `$OMC_*` environment variables, and receives their output through `omc_dialog_control` calls against a live window. Every contact point assumes a running app with a window on screen.

So without a harness: a change to any of an applet's handlers is verified by launching the app and clicking. The window cannot be inspected headlessly - `screencapture` returns black without screen-recording permission, and `appletbuilder preview` renders a `NavigationStack`-rooted window blank. `alert` is app-modal, so any path that confirms anything either needs a human or hangs forever. And the error paths - a failed save, a timed-out alert, a stale lock, a garbage drop payload - are the least likely to be walked by hand and the most likely to destroy user data when wrong.

omctest replaces the clicking for everything that leaves a trace.

### What is in scope

- Document and model files, and their state machines: open, edit, save, save-as, close, external change.
- Per-window state directories and pasteboard keys.
- What a handler wrote toward the window: control values, table rows, enable/disable, properties, titles, alerts raised, commands chained.
- Tool invocations and their arguments, through spy stubs.
- Handler exit codes, logs, and real artifacts - up to and including building a real `.pkg` and taking it apart with `pkgutil --expand`.
- Shell and Python handlers, with the same harness and the same test-file format.

### What is out of scope, stated plainly

- **No rendering or layout testing.** The harness never creates a window. Spacing, truncation, dark mode, resizing, focus and tab order, drag feedback, animations: a human at the screen must confirm these.
- **No testing of the engine.** The harness *simulates* the engine's contract as documented in `omc_runtime_context_reference.md`; it does not execute the engine. If the simulation and the engine disagree, your tests pass and your app misbehaves. When the engine's behavior is the question, instrument the live app (see `omc_agent_tips_and_troubleshooting.md` section 6) rather than trusting the harness.
- **No synthesized UI events.** Handlers are dispatched directly, so the wiring from a control's `actionID` to the handler is never exercised by a test. A typo'd `actionID` is silent here - `validate` is what catches it, warning for any `*ActionID` in the bundle's JSON that resolves to no command.
- **NIB dialogs are not supported.** ActionUI only.
- **External-world effects are not faked.** Keychain, `notarytool`, `codesign`, network. Handlers call these by absolute path, which the harness cannot redirect. See section 8, the seam contract.

**The honest boundary.** A green `omctest` run plus a green `validate` means the handler logic is correct *given the documented engine contract and given real support tools*. A human must still launch the app once per release and confirm the window looks right, loads, and reacts.

---

## 2. Quick start

Layout - `Tests/` sits **next to** the bundle, never inside it (tests in the bundle would bloat the shipped app and dirty its code signature):

```
MyAppApp/                       the applet project directory
    MyApp.app/
    Tests/
        10-lifecycle.test.sh
        20-editing.test.sh
        lib.test.myapp.sh       app-specific accessors you write
        fixtures/
            Sample.myappdoc
```

A complete first test file:

```sh
#!/bin/sh
# Tests/10-lifecycle.test.sh - document lifecycle
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.myapp.sh"          # your accessors: model, dirty, state_dir...

section "open a document"
sample="$(fixture_copy Sample.myappdoc)"      # copied into $OMCTEST_WORK, writable
omc_object "$sample"
omc_run MyApp.main.init
check "identifier loaded"  "com.example.thing" "$(model /IDENTIFIER)"
check "clean after open"   "0"                 "$(dirty)"
# What the window would show - the model alone does not prove the user sees it.
check "pushed to the field" "com.example.thing" "$(ui_value "$IDENTIFIER_ID")"
check "the table was fed"   "2"                "$(ui_row_count "$TABLE_ID")"
check "no writes to undeclared view ids" ""    "$(ui_unknown_writes)"

section "edit a field"
omc_fire MyApp.field.changed "$IDENTIFIER_ID" "com.example.new"
check "identifier written" "com.example.new"   "$(model /IDENTIFIER)"
check "document is dirty"  "1"                 "$(dirty)"

section "close with unsaved changes: Don't Save discards them"
# The alert stub answers from a scripted queue. The codes are the alert tool's:
# 0 = the OK button, 1 = Cancel, 2 = Other, 3 = timed out, 255 = failed to display.
# This applet's close alert wires its Cancel slot to "Don't Save", so 1 discards.
alert_answer 1
omc_run MyApp.window.close
check "the user was asked"  "1"                "$(alerts_count)"
check_absent "the state directory was removed" "$(state_dir)"

omctest_end
```

Then:

```
appletbuilder test MyApp.app
```

or, with the applet open in AppletBuilder, the **Test** button in the Build & Run pane - same run, transcript in the pane's log.

Three things in that file are the whole idiom, and each is explained below: **you set the environment the engine would have set** (`omc_object`, `omc_fire`), **you dispatch a handler by its script name** (`omc_run` - see 4.3, this is not always the `COMMAND_ID`), and **you assert with `check`** against files, exit codes, and the virtual window.

Note the last assertion uses `check_absent` rather than `check ... "no"`. Both work; the named helper says what it means. A bare `check "state dir gone" "no" "$([ -d "$d" ] && echo yes || echo no)"` reads as though "no" were the thing being asserted, which is a small readability trap worth avoiding.

But notice what that assertion depends on: if `state_dir()` computes the wrong path, `check_absent` passes forever and proves nothing. **Any absence assertion against a path your own lib computes needs a positive control somewhere** - one `check_exists` on the same accessor, in a section where the directory is supposed to be there. Then a wrong path fails loudly instead of passing quietly.

`omctest_end` prints the file's summary, writes machine-readable counts for the runner, and **exits**. It is not a `return` - nothing after it runs. It also fails a file that ran zero checks, because a file that asserts nothing is broken rather than passing.

---

## 3. The mock environment

### 3.1 One environment per test file

Every test file gets its own environment. Files cannot contaminate one another, and an override in one never leaks into the next.

```
$OMCTEST_SCRATCH/                mktemp -d, removed on exit
    tmp/                         exported as TMPDIR for everything the tests run
    <testfile-label>/
        support/                 the interposition directory (3.2)
        work/                    $OMCTEST_WORK - your writable area, the default
                                 destination of fixture_copy, and the cwd handlers run in
        ui/                      $OMCTEST_UI - the recording area
            journal.tsv          every omc_dialog_control call, in order
            win-<uuid>/          virtual window state, last write wins
            alerts.log           every alert raised
            notifications.log    every notify
            chain.queue          the pending omc_next_command request
            chain.log            the full history of chain requests
            handlers.log         stdout+stderr of every handler dispatch
            errors.log           harness-detected misuse (bad target, bad argc)
            known_ids.txt        every view id declared anywhere in the bundle
            unknown_ids.log      writes to ids not in known_ids.txt
            suspect_writes.log   bare value writes that clobbered a rows file
            counts.pass/.fail    one byte per check
```

Variables a test file can read:

| Variable | Points at |
|---|---|
| `OMCTEST_APP` | the `.app` under test |
| `OMCTEST_LIB` | `omctest.sh` itself - source it first, always |
| `OMCTEST_TESTS` | the `Tests/` directory - source your app lib from here |
| `OMCTEST_FIXTURES` | `$OMCTEST_TESTS/fixtures` |
| `OMCTEST_WORK` | this file's writable scratch, and the handlers' cwd |
| `OMCTEST_UI` | the recording area above |
| `OMCTEST_SUPPORT` | the interposition directory |
| `OMCTEST_STATUS` | exit code of the last `omc_run`; the string `-` before any dispatch, so `check_status "..." 0` cannot pass vacuously |
| `OMCTEST_ALERT_RC` | the alert stub's answer when the scripted queue is empty (default `0`) |
| `OMCTEST_PYTHON`, `OMCTEST_PYTHON_EMBEDDED` | the resolved interpreter, and whether it is the bundle's own |
| `OMCTEST_API_VERSION` | `2` - assert a minimum if you use something new. `2` added `omc_control_defaults`. |

What the harness exports into every handler:

| Variable | Value | Why |
|---|---|---|
| `OMC_APP_BUNDLE_PATH` | the `.app` under test | handlers locate their own Scripts/ and libs through it |
| `OMC_OMC_SUPPORT_PATH` | the interposition directory | the single interception point for every runtime tool |
| `OMC_OMC_RESOURCES_PATH` | the real framework Resources | some handlers read framework resources; kept real |
| `OMC_ACTIONUI_WINDOW_UUID` | `OMCTEST-<label>-<pid>` | unique per file and per run: isolates state directories and pasteboard keys |
| `OMC_PARENT_DIALOG_GUID` | empty until `omc_child_sheet` | the child-sheet convention |
| `OMC_CURRENT_COMMAND_GUID` | `OMCTEST-CMD` | consumed by `omc_next_command`, which is stubbed |
| `TMPDIR` | `$OMCTEST_SCRATCH/tmp/` | applets derive state and scratch paths from `$TMPDIR`, so redirecting it isolates all of that and makes cleanup total |

**The window UUID is why per-window state is inspectable.** Handlers key their state directory and pasteboard keys off `$OMC_ACTIONUI_WINDOW_UUID` (or `$OMC_PARENT_DIALOG_GUID` inside a child sheet). Your test lib should recompute that path the same way the applet does - interpolating the variable, never hardcoding - so that a change to the applet's naming shows up as a missing file rather than as a test quietly asserting about a directory nobody writes.

`TMPDIR` keeps its trailing slash, because that is what macOS gives an app. If the applet builds `"${TMPDIR:-/tmp}/foo-$uuid"` it produces a doubled slash, and your test lib must reproduce that character for character if it ever compares the path as a *string*.

**Under test that doubling can appear twice over, and not always on both sides.** The harness makes its scratch with `mktemp -d "${TMPDIR:-/tmp}/omctest.XXXXXX"` under a `TMPDIR` that already ends in a slash, so the `TMPDIR` your handlers see can carry an interior `//` of the harness's own making. Whether it survives depends on what touched the path: Python's `os.path.join` preserves it, while a path that has been through `realpath`, a tool's own output, or a shell `cd`/`pwd -P` comes back normalized. So the same directory can have two spellings *inside one applet*.

The rule that actually works: **compare paths as paths, not as strings.** Assert on `[ -e ]`, or normalize both sides before comparing. Reserve exact string comparison for the case where the literal recorded text is the thing under test - and when you do that, reproduce the applet's construction exactly.

### 3.2 The interposition directory

Handlers reach every runtime tool through `$OMC_OMC_SUPPORT_PATH`. The harness builds a directory of symlinks to the applet's own tools, then replaces individual ones with stubs. Because interception is at the filesystem path, it is **language-neutral**: a Python handler doing `subprocess.run([os.path.join(SUPPORT, "omc_dialog_control"), ...])` hits the same stub as a shell handler.

The tools come from the applet's *own* embedded framework, not AppletBuilder's - what is tested is the version that ships with the app.

### 3.3 Which tools are stubbed

| Tool | Disposition | Why |
|---|---|---|
| `alert` | **stub, mandatory** - spy plus scripted exit codes | app-modal; with no user to click, every confirmation path would hang forever. The scripted code is also the only way to reach the Cancel, timed-out and failed-to-display branches. |
| `notify` | stub, spy | the real tool posts real Notification Center items: needs permission, pollutes the session, asserts nothing. |
| `omc_dialog_control` | **recording stub** - the virtual window | the real tool is a harmless no-op with no window, which is why handlers can run at all; recording it turns the largest observable output of most handlers into something assertable. |
| `omc_next_command` | recording stub - chain queue | headless there is no app to ask; recording lets you assert on chaining and drain it synchronously. |
| `plister` | real | handlers depend on its exact read/write semantics; faking it would test the fake. |
| `pasteboard` | real | handlers must read back what they wrote. |
| `b64`, `filt`, `loco` | real | pure text and data filters, safe headless. |

Every stub records before it responds. A stub that only returns an exit code answers "did the handler survive"; a spy answers "did the handler do the right thing".

---

## 4. API reference

Everything below is a shell function available after sourcing `$OMCTEST_LIB`.

### 4.1 Driving the window

| Helper | Signature | Effect |
|---|---|---|
| `omc_control` | `<view-id> <value>` | sets `OMC_ACTIONUI_VIEW_<id>_VALUE`. Persists. |
| `omc_table_cell` | `<table-id> <column> <value>` | sets `OMC_ACTIONUI_TABLE_<t>_COLUMN_<c>_VALUE`. Columns are 1-based; `0` is the whole row, tab-joined. Persists. |
| `omc_trigger` | `<view-id> [part-id] [context]` | sets the trigger family. An empty `part-id` or `context` **unsets** the variable rather than exporting it empty, matching the engine. One-shot. |
| `omc_drop` | `<path> [path ...]` | builds the ActionUI DropHelper context `{"items":[...],"location":{"x":0,"y":0}}` into `OMC_ACTIONUI_TRIGGER_CONTEXT`. One-shot. Needs a view id too - set one with `omc_trigger` first if the handler reads it. |
| `omc_reset_controls` | none | unsets **every** `OMC_ACTIONUI_VIEW_*` and `_TABLE_*`. There is no per-id reset. |
| `omc_control_defaults` | `<document-name>` | resets, then sets every control to the value its ActionUI document **declares**. This is the freshly-opened window. Sets `OMCTEST_DEFAULTS_APPLIED` to the number of controls written. |

**`omc_reset_controls` is not the state a user ever sees, and for most applets it is the wrong place to start.** It unsets everything, and a window where every toggle is off and every picker is empty is a window that cannot exist. QuickPDF ships eleven toggles `isOn`; a blanked Optimize run emits different qpdf flags than a real one, so a test written against the blank state passes while describing something no user has ever seen. Start sections from the declared state instead:

```sh
omc_control_defaults QuickPDF      # the window as it opens
omc_control 60 encrypt             # then the one thing this section is about
```

Four details worth knowing:

- **It takes a document name, not a path.** `QuickPDF` means `Base.lproj/QuickPDF.json`, resolved through any `.lproj`. An unknown name fails loudly rather than silently applying nothing.
- **Naming the document is required, and there is deliberately no "all windows" form.** Ids are unique only *within* a document: QuickPDF's main window and its Quick Look window both declare an id 200, so a union would let one window's default answer for the other's control.
- **An omitted property is still a declared default.** A `Toggle` with no `isOn` ships off and a `TextField` with no `text` ships empty - six of QuickPDF's toggles are off by saying nothing at all. Where omission has no defined meaning, such as a `Slider` with no `value`, nothing is invented.
- **A `prompt` is placeholder wording, not a value.** Only `text` is read, so a field showing gray hint text correctly reads back as empty.

Which element types carry a value, and which property declares it, are read from the ActionUI element schemas shipped alongside the harness rather than restated in it - the same reason a test lib imports an applet's view ids instead of retyping them. A `Picker` resolves to the first option that can actually be delivered: the first `{"title","tag"}` entry's tag, skipping `{"section": ...}` headers, or the 1-based index when options are plain strings.

`OMCTEST_DEFAULTS_APPLIED` exists so a test can assert the extraction did something, rather than trusting a mechanism that is silently inert when it matches nothing:

```sh
check "the window's defaults loaded" "yes" \
    "$([ "$OMCTEST_DEFAULTS_APPLIED" -gt 25 ] && echo yes || echo no)"
```

**Not every control has a view id.** A window-level `searchable` modifier, for instance, has no `id` of its own: its query reaches the handler only as the trigger context. Pass an empty view id and put the payload in the context:

```sh
omc_trigger "" "" "the search text"
omc_run MyApp.filter.changed
```

An empty view id is accepted - what `omc_control` and `omc_trigger` refuse is an id that would build an invalid variable *name*, not an empty value.

### 4.2 Dialogs and the current object

| Helper | Signature | Effect |
|---|---|---|
| `omc_dialog_answer` | `<save_as\|choose_file\|choose_folder\|choose_object\|input_text> <value>` | sets the whole derived family for that channel, not just the path: `_PATH`, `_PARENT_PATH`, `_NAME`, `_NAME_NO_EXTENSION`, `_EXTENSION_ONLY`. An **empty value simulates Cancel** and unsets the family. One-shot. |
| `omc_object` | `<path>` | sets `OMC_OBJ_PATH` and its derived family - the current object. **Persists**, because it is the document, not event data. `omc_object ""` clears it. `OMC_OBJ_DISPLAY_NAME` is approximated by the basename; the engine's localized display name is not reproduced. |
| `omc_clear_event` | none | clears the trigger **and** dialog families now. `omc_run` calls it for you; calling it by hand also discards a dialog answer you may have meant to keep. |

### 4.3 Dispatching handlers

| Helper | Signature | Effect |
|---|---|---|
| `omc_run` | `<script-stem>` | resolves `Scripts/<stem>.<ext>` case-insensitively, runs it under the right interpreter with `$OMCTEST_WORK` as cwd, appends output to `handlers.log`, records the exit code in `$OMCTEST_STATUS`, then clears the one-shot variables. Returns the handler's exit code, or `127` when no script matches. |
| `omc_fire` | `<command-id> <view-id> [value]` | `omc_control` (when a value is given) + `omc_trigger` + `omc_run`. The common three-liner. |

Extension precedence is `.sh`, `.py`, `.zsh`, `.bash`, extensionless, then any other extension - the engine's order. No shebang is honored, exactly like OMC.

**What `omc_run` takes is the script's file stem, not the manifest's `COMMAND_ID`.** For most commands these are the same string, which is why it is easy to believe otherwise - and why the distinction only bites on the one command that matters most.

**An applet's primary command usually has no `COMMAND_ID` at all.** It is the first entry in `COMMAND_LIST`, it carries the `ACTIONUI_WINDOW`, and the convention is that its handler is named `<NAME>.main.<ext>`. There is no id to dispatch. Run it by its stem:

```sh
omc_run Zip.main            # the primary command - no COMMAND_ID exists for it
omc_run Zip.window.close    # a subcommand - here the stem and the COMMAND_ID agree
```

If the applet declares an `INIT_SUBCOMMAND_ID` on its window, that is the handler which runs when the window opens, and it is usually the one a lifecycle test should dispatch first. Read `Command.json` and the `Scripts/` directory together before writing the first `omc_run`: the manifest tells you what the engine would call, the directory tells you what `omc_run` can resolve.

### 4.4 Alerts, notifications, chains

| Helper | Signature | Effect |
|---|---|---|
| `alert_answer` | `<rc> [rc ...]` | queues scripted answers for the next alerts. Codes: `0` OK, `1` Cancel, `2` Other, `3` timed out, `255` failed to display. When the queue empties the stub falls back to `$OMCTEST_ALERT_RC`. The queue pop is unlocked, so tests raising alerts from **concurrent** handlers must set `OMCTEST_ALERT_RC` instead. |
| `alerts_reset` | none | truncates `alerts.log` - the record of alerts raised. Call it before a section that counts. |
| `alert_answers_reset` | none | truncates the queue of **scripted answers**. Call it before a section that scripts one. |
| `alerts_count` | none | number of alerts raised. Counts an alert with empty text, because that is still an alert the user was shown. |
| `alerts_mention` | `<pattern>` | how many alerts match. This is a **regex**, not a fixed string. |
| `notify_count` / `notify_mention` | as above | the same, for `notify`. |
| `chain_requested` | `<command-id>` | `1` when that id is the **currently pending** chain request. The real `omc_next_command` truncates its file, so two requests in one handler leave only the last - this can read `0` for an id that was genuinely requested and then overwritten. |
| `chain_asked` | `<command-id>` | how many times the id was requested across the whole history. This is the one that answers "did the handler ask". |
| `chains_reset` | none | forgets every chain request, pending and historical. The counterpart of `alerts_reset`. |
| `omc_drain_chain` | `[max-depth, default 25]` | runs queued chain requests synchronously, in order. Returns the **worst** status across the chain, so a mid-chain failure is not masked by a later success. |

**`chain_asked` is cumulative across the file, which makes it treacherous in a negative assertion.** "The run did not start" is the commonest thing a router test wants to say, and the natural way to say it is `check "the run did not start" "0" "$(chain_asked MyApp.run)"`. That check is correct in the first section that uses it and quietly wrong in every later one, because an earlier section that legitimately started a run has already put a line in the history. Call `chains_reset` at the top of any section asserting a chain did *not* happen. Reaching for `chain_requested` instead is not a fix: it reads the pending slot, which still holds whatever the previous section left there.

`alerts_reset` and `alert_answers_reset` are two different resets and you usually want both. An answer the handler never consumed stays queued and silently answers the *next* section's alert - which is confusing at the best of times and actively misleading while mutation-testing, where a mutation that removes an alert makes failures appear several sections away from the change.

### 4.5 Assertions

| Helper | Signature | Effect |
|---|---|---|
| `check` | `<description> <expected> <actual>` | string comparison; prints `ok` or `FAIL` with both values to stderr. |
| `check_exists` / `check_absent` | `<description> <path>` | the path does / does not exist. |
| `check_grep` | `<description> <pattern> <file>` | pattern present in file. Regex. |
| `check_status` | `<description> <expected-rc>` | against the last dispatch. Reads the recorded **file**, so it is still correct when `omc_run` ran inside a subshell. |
| `section` | `<header>` | prints a header and groups the output. Not an assertion. |
| `omctest_end` | none | summary, counts file, **exit**. |

The counters are files, one byte appended per check, not shell variables. This matters: a variable incremented inside a pipeline, a command substitution or a `( )` group is incremented in a subshell and the value dies with it - so the natural way to assert over rows,

```sh
ui_rows 100 | while read -r row; do check "..." "..." "$row"; done
```

would print `FAIL` lines and then report "0 failed". With file counters it does not.

### 4.6 Reading the virtual window back

All of these take an optional trailing window UUID, defaulting to the current window. A missing file reads as empty rather than as an error.

| Helper | Signature | Returns |
|---|---|---|
| `ui_value` | `<view-id> [uuid]` | the control's current value |
| `ui_content_type` | `<view-id> [uuid]` | `markdown`, `html`, ... when one was set |
| `ui_enabled` / `ui_visible` | `<view-id> [uuid]` | `1`, `0`, or **empty meaning never touched** - empty is not "disabled" |
| `ui_rows` | `<view-id> [uuid]` | the table's rows, one per line |
| `ui_row_count` | `<view-id> [uuid]` | how many rows |
| `ui_columns` | `<view-id> [uuid]` | the column titles |
| `ui_selection` | `<view-id> [uuid]` | the selected row index, empty when none |
| `ui_prop` / `ui_state` | `<view-id> <key> [uuid]` | a property or state value set at runtime |
| `ui_title` | `[uuid]` | the window title |
| `ui_calls` | `<pattern>` | how many journal lines match - for "was this called at all, and how often" |
| `ui_unknown_writes` | none | writes to view ids the bundle does not declare. Assert this is empty. Each line is `<id> <args>`, so an id written with no arguments leaves a trailing space - compare against empty rather than against a specific id. |
| `ui_suspect_writes` | none | bare value writes that clobbered a table's rows - almost always the "never set a Table's value to select a row" mistake |
| `ui_errors` | none | harness-detected misuse: bad target, wrong argument count |
| `ui_alert_action` | `<button-title> [uuid]` | the actionID wired to that button of the pending alert. Button specs are `title:role:actionID`, so **a title containing a colon misparses**. |
| `ui_alert_title` / `ui_alert_message` | `[uuid]` | the pending alert's text |
| `ui_fail` | `<view-id> ...` | make `omc_dialog_control` return failure for those ids, to test a handler's error path |
| `ui_reset` | none | wipes the virtual windows and the journal. Does **not** touch alerts, notifications, chains or the check counters. |

`ui_unknown_writes` deserves a standing check at the end of every file. `unknown_ids.log` is cumulative across the file, so one assertion covers everything above it:

```sh
section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"
```

Two caveats. It is silently inert if the bundle's known-id extraction produced nothing - the runner says so loudly on stderr when that happens, so read that line. And the id set is a **union across every ActionUI document in the bundle**, so a typo'd id can be masked by a legitimate id of the same number in an unrelated sheet.

### 4.7 Fixtures and scratch

| Helper | Signature | Effect |
|---|---|---|
| `fixture` | `<name>` | prints the absolute path of `$OMCTEST_FIXTURES/<name>`; fails loudly if missing |
| `fixture_copy` | `<name> [dest-dir]` | copies it into `$OMCTEST_WORK` (or `dest-dir`) and makes it writable; prints the new path |

### 4.8 Windows and sheets

| Helper | Signature | Effect |
|---|---|---|
| `omc_window_switch` | `<name>` | a fresh window UUID - simulates a second document window |
| `omc_child_sheet` | `<name>` | sets `OMC_PARENT_DIALOG_GUID` to the current window and issues a new window UUID. This is the `document_uuid="${parent_uuid:-$window_uuid}"` convention applets use to keep a sheet's state with its parent document. **One level deep** - it saves a single slot, not a stack. |
| `omc_leave_sheet` | none | restores what `omc_child_sheet` saved |

Inside a sheet, assert parent-window effects by passing the parent's uuid explicitly: `ui_value 62 "$OMC_PARENT_DIALOG_GUID"`.

**This is one of two sheet conventions, so check which one your applet uses.** `omc_child_sheet` models a sheet that gets its *own* window uuid with the parent's guid alongside - the `document_uuid="${parent_uuid:-$window_uuid}"` shape. An applet that raises its sheets through `omc_present_modal` instead keeps them in the **parent window's** control pool: there is no second uuid, the sheet's controls are read with plain `ui_value` against the current window, and `omc_child_sheet` is the wrong tool. Read the applet's own sheet-raising code before reaching for either.

### 4.9 Waiting

| Helper | Signature | Effect |
|---|---|---|
| `omc_wait_for` | `'<predicate>' [timeout-seconds, default 5]` | polls the predicate at 10 Hz; returns 0 as soon as it succeeds, 1 on timeout |

Use this for handlers that background a pipeline or debounce. Never scatter `sleep` through tests.

```sh
omc_run MyApp.build &
check "the tool started" "yes" "$(omc_wait_for "[ -f \"$(state_dir)/tool.pid\" ]" && echo yes || echo no)"
```

### 4.10 Stubbing tools

```sh
omc_stub plister <<'SH'
#!/bin/sh
exit 1
SH
...
omc_unstub plister
```

`omc_stub` suits whole-tool failure ("plister is broken"). It is not a substitute for finer-grained surgery: to make one *write* fail while every *read* still succeeds, manipulate the state the tool acts on instead - delete the parent container, `chmod` the directory.

**`omc_unstub` on `alert`, `notify`, `omc_dialog_control` or `omc_next_command` restores the recording stub, not the real tool.** Restoring the real `alert` would hang the suite.

---

## 5. Which omc_dialog_control verbs replay

The recording stub journals **every** call, so `ui_calls` can assert on any verb. Only some verbs additionally update the virtual window that `ui_value` and friends read.

**Replayed into the virtual window:**

```
(bare value)                       omc_set_value_from_stdin
omc_enable  omc_disable            omc_show  omc_hide
omc_table_set_rows                 omc_table_set_rows_from_stdin
omc_table_set_rows_from_file       omc_table_add_rows
omc_table_add_rows_from_stdin      omc_table_add_rows_from_file
omc_table_remove_all_rows          omc_table_prepare_empty
omc_table_set_columns              omc_list_set_items
omc_list_set_items_from_stdin      omc_list_set_items_from_file
omc_list_append_items              omc_list_append_items_from_stdin
omc_list_append_items_from_file    omc_list_remove_all
omc_select_row                     omc_select_row_with_content
omc_deselect                       omc_set_property
omc_set_state                      omc_present_alert
omc_present_confirmation_dialog    omc_insert_element
omc_insert_element_row             omc_remove_element
```

Special targets `omc_window`, `omc_application` and `omc_workspace` are recognized; a window title set through `omc_window` is readable with `ui_title`.

**Journaled only** - everything else, including `omc_resize`, `omc_move`, `omc_scroll` and `omc_invoke`. Assert on those with `ui_calls`.

The engine has 46 verbs and matches them **exactly and case-sensitively**; anything unrecognized falls back to setting the control's value. The stub reproduces that, and it reproduces the engine's silent no-ops deliberately - `omc_select_row` with no index or a non-numeric one stores nothing and says nothing, leaving the previous selection intact, and a `*_from_file` verb whose file cannot be opened leaves the rows alone. A handler relying on either is a live defect, and the harness must not paper over it.

---

## 6. Lifetime: what persists and what does not

The engine exports current control values on every dispatch, but trigger context and dialog results only for the event that produced them. The harness mirrors that:

| Family | Lifetime |
|---|---|
| `OMC_ACTIONUI_VIEW_*`, `OMC_ACTIONUI_TABLE_*` | **persist** until overwritten or `omc_reset_controls` |
| `OMC_OBJ_*` | **persist** - the current object, not event data |
| `OMC_ACTIONUI_TRIGGER_*` | **one-shot** - cleared after every `omc_run` |
| `OMC_DLG_*` | **one-shot** - cleared after every `omc_run` |

This prevents the classic harness bug where a leftover `OMC_DLG_SAVE_AS_PATH` from one test silently answers the next test's save dialog.

Two consequences worth internalizing:

**A backgrounded dispatch must own its one-shot variables.** These are process environment variables. If you background three handlers with different control values, set each one inside its own subshell, or all three see whichever value was set last and the test proves nothing:

```sh
( omc_control 150 "title A"; omc_trigger 150; omc_run MyApp.field.changed ) &
( omc_control 129 "name B";  omc_trigger 129; omc_run MyApp.field.changed ) &
wait
```

**A New-document scenario needs `omc_object ""`.** Because the object persists, a section that means "no document open" has to say so; otherwise it inherits the previous section's document.

### The generosity gap, stated honestly

The engine only exports scanned variables when they appear in the command definition, and `exe_script_file` bodies are not scanned at all - `ENVIRONMENT_VARIABLES` exists for that. The harness is **more generous**: it exports whatever the test sets. So a handler that reads a variable the engine will not actually deliver passes under test and fails live. There is no `--strict-env` mode yet. When a handler reads something unusual, check the command definition.

---

## 7. Python applets

Nothing in the test-file format changes. Test files are POSIX `sh` even for a fully Python applet, because the assertion surface - files, exit codes, recorded window writes - is language-neutral, and a parallel Python test API would be a second implementation to keep in sync forever.

What the harness does for you:

- **Interpreter resolution mirrors the engine.** `.py` runs under the applet's embedded `Contents/Library/Python/bin/python3` when the bundle has one, else `/usr/bin/python3`. `.sh` runs under `/bin/sh` - which is bash 3.2 in POSIX mode, never `bash`.
- **The Python environment mirrors the engine.** With an embedded runtime the harness prepends its `bin/` to `PATH` and prepends `Contents/Library/Packages` to `PYTHONPATH` when that directory exists.
- **Interception needs nothing extra.** A Python lib that builds tool paths from `os.environ["OMC_OMC_SUPPORT_PATH"]` hits the stubs exactly as a shell handler does.
- **`$TMPDIR` is redirected**, so a Python applet deriving a scratch directory from it lands inside the harness scratch and gets cleaned up.

One deliberate deviation: the harness sets `PYTHONPYCACHEPREFIX` into the scratch for **both** the embedded and the system-Python branch, where the engine sets it only for the embedded branch. This keeps test runs from writing `__pycache__` into the bundle, which would dirty its signature seal. It is invisible to handler logic.

A Python applet also gains something free: your assertions can shell out to the applet's own interpreter to call its lib functions directly, unit-testing them rather than only whole handlers. This is the Python counterpart of the shell `pb_call` pattern in section 9, and it is worth writing once into your app lib:

```sh
# Evaluate a Python expression with the applet's lib importable, under the same
# interpreter the engine would use. Arguments arrive as a list named "args".
zip_eval() { # <expression> [arg ...]
    local expression="$1"; shift
    "$OMCTEST_PYTHON" -c '
import sys, os
sys.path.insert(0, os.path.join(os.environ["OMC_APP_BUNDLE_PATH"],
                                "Contents", "Resources", "Scripts"))
import lib_zip
args = sys.argv[2:]
sys.stdout.write(str(eval(sys.argv[1])))
' _ "$expression" "$@"
}

check "a tab is escaped"  "a\\tb"  "$(zip_eval 'lib_zip.escape(args[0])' "$(printf 'a\tb')")"
```

**Pass arguments as `argv`, never interpolated into the expression string.** The obvious first version builds `"lib_zip.escape('$1')"` and it is a quoting bug the moment a test does its job - the values worth testing are exactly the ones with quotes, tabs, backslashes and newlines in them. `$OMCTEST_PYTHON` is the interpreter the harness resolved, so the bridge uses the same one the handlers do.

---

## 8. The seam contract: what cannot be intercepted

The interposition directory covers only tools reached through `$OMC_OMC_SUPPORT_PATH`. OMC convention calls system binaries by absolute path - `/usr/bin/codesign`, `/usr/bin/xcrun notarytool`, `/usr/bin/security` - and neither the support directory nor `$PATH` can redirect those.

So the harness cannot, by itself, make a notarization submit step or keychain access testable. The answer is a **convention in the applet**, not a mechanism in the harness. An applet that wants those paths under test routes external binaries through overridable variables in its shared lib:

```sh
# One variable per binary - a variable holds exactly one word, so multi-word
# invocations keep the subcommand at the call site: "$xcrun_tool" notarytool ...
codesign_tool="${MYAPP_CODESIGN_TOOL:-/usr/bin/codesign}"
xcrun_tool="${MYAPP_XCRUN_TOOL:-/usr/bin/xcrun}"
```

A test then exports the override to point at a fake that records its arguments. An applet that skips the seam simply has those handlers excluded from coverage - say so in the test file rather than implying they are covered.

Note the opposite case is real too: where a tool is deterministic and safe to run for real, **run it for real**. PackageBuilder needed no seam because `pkgbuild` and `pkgutil` are safe, and running them genuinely is what makes its `PackageInfo` and BOM assertions worth anything.

---

## 9. Fixtures

- **Fixtures are read-only, always.** `fixture <name>` gives you the path to read; `fixture_copy <name>` gives you a writable copy in `$OMCTEST_WORK`. Check fixtures in with read-only permissions and let `fixture_copy` handle the rest - note that a plain `cp` of a read-only fixture is itself read-only, which fails later in ways that look like an applet defect.
- **Synthesize rather than commit, where you can.** Build a bundle fixture from `/bin/echo` plus a here-doc `Info.plist` at run time instead of committing binaries. No binaries in the repository, and the block that builds them is a readable statement of exactly which properties the assertions depend on. Reserve committed fixtures for documents whose byte-exactness is the point.
- **State an environmental precondition as a check.** If a synthesized fixture depends on something about this machine - that `/bin/echo` is a universal binary, say - assert it where the fixture is built. Otherwise the day it stops being true, the failure appears 200 lines away and reads like an applet bug.

### Your app lib

Per-applet accessors live in `Tests/lib.test.<app>.sh`, sourced after `omctest.sh`. The harness deliberately does not absorb them: they encode the applet's private state layout, which the harness has no business knowing.

A good app lib holds: the state directory path (recomputed the way the applet computes it), model readers, pasteboard key accessors, log greps, and any direct calls into the applet's libraries. Two patterns worth copying from `PackageBuilderApp/Tests/lib.test.packagebuilder.sh`:

**Import view ids from the applet, do not restate them.** If the applet names its views in a lib, extract those rather than writing a second list that can disagree with the first. **Match the applet's own naming** - the pattern below fits a shell lib writing `NAME_ID=129`, and a Python lib writing `ID_TABLE = 10` needs a different one (prefix on the other side, spaces around the `=`). Read the applet's lib before copying this:

```sh
# A shell lib: NAME_ID=129
eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.myapp.sh")"

# A Python lib: ID_TABLE = 10
eval "$(/usr/bin/sed -n 's/^\(ID_[A-Z0-9_]*\) *= *\([0-9][0-9]*\)$/\1=\2/p' \
    "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib_myapp.py")"

[ -n "$NAME_ID" ] || { printf 'no view ids imported\n' >&2; exit 1; }
```

The guard matters more than the pattern: without it a missing id expands to the empty string, `omc_control` writes `OMC_ACTIONUI_VIEW__VALUE`, and every check fails one by one with no hint why. With it, a pattern that matches nothing fails once, immediately, and says so.

**Call library functions directly, in a subshell.** Whole-handler tests are coarse; the rules usually live in named functions.

```sh
pb_call() {
    ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.myapp.sh" >/dev/null 2>&1
      "$@" )
}
check "a slash is refused" "no" "$(pb_call valid_name 'a/b' && echo yes || echo no)"
```

The subshell keeps the library's own state out of the test file and stops a function that `exit`s from taking the suite with it. Note that arguments are expanded by the *calling* shell, so a call that must name one of the library's own constants needs an `eval` variant that defers expansion into the subshell. For a Python applet the equivalent bridge is in section 7.

**A "reset" helper has to reset everything the applet keeps, not just its directory.** The obvious one-liner is `reset_state() { /bin/rm -rf "$(state_dir)"; }`, and it is complete only for an applet that keeps all its state in that directory. An applet that also keeps per-window pasteboard keys needs those cleared too - the pasteboard lives in the per-login server and outlives the process, so a leftover key silently answers a question about a document that no longer exists. Enumerate the keys your applet uses and clear them alongside the directory.

---

## 10. Running and debugging

### The whole suite

```
appletbuilder test MyApp.app [--tests <dir>] [--filter <glob>] [--verbose] [--keep-scratch] [--list]
```

Or, with the applet open in AppletBuilder: the **Test** button in the Build & Run pane, next to Build and Run. It runs the same thing with the same validation first, and streams the transcript into the pane's log. No flags there - `--filter` and `--keep-scratch` are the CLI's.

Bundle validation runs first, and validation errors abort before any test executes - a bash-4 syntax error would otherwise surface as a baffling mid-test handler failure. Files run in lexical order, each in its own environment. Detail goes to stderr; the last line on stdout is machine-readable: `omctest: 624 passed, 0 failed, 8 files`.

Exit codes: `0` all passed, `1` any failure, `2` usage error or no tests found.

`build --test` runs the suite after refreshing the framework and before codesigning, halting on failure. Plain `build` does not run tests.

### One file by hand

```sh
OMCTEST_APP=./MyApp.app \
OMCTEST_LIB=<AppletBuilder.app>/Contents/Resources/Agents/omctest.sh \
    sh Tests/10-lifecycle.test.sh
```

The library self-initializes when sourced outside the runner. Note that standalone mode has no `known_ids.txt`, so `ui_unknown_writes` is inert there - it says so on stderr.

### When something fails

- **`--keep-scratch`** prints the scratch path and skips cleanup. Then look at `ui/win-<uuid>/` to see what the window actually contained, `ui/journal.tsv` for the call order, and `ui/handlers.log` for what the handler printed.
- **`--verbose`** streams handler output live as it is produced.
- **`CRASH <file> (exit N)`** means the file exited non-zero before reaching `omctest_end`.
- **`INCOMPLETE <file>`** means it exited *zero* before reaching the end - an `exit` in a helper, or a handler that took the shell with it. Everything after that point never ran.
- **`FAIL this file ran no checks at all`** means the file reached the end having asserted nothing.

### Writing checks that can actually fail

This is the discipline that matters most, and it is worth more than any amount of coverage. **A check that cannot fail is worse than no check**, because it reads as coverage.

Before believing a new assertion, break the thing it names and confirm it goes red. Edit the handler, delete the guard, make the function a no-op - then restore. Real examples from PackageBuilder's suite, all found this way:

- An injection test whose vector could not fire, asserting on output that command substitution would have captured anyway. It passed with the guard deleted.
- A "did not kill the wrong process" test whose only assertion was that a directory got swept - and the sweep happens on both the safe and the dangerous path.
- A "the document fell back to a new one" test that expected an empty model, which is equally what "no model was created at all" produces.
- An out-of-range check that cleared the selection immediately before testing it, so the expected state was already the starting state.

Prefer assertions that name a value the code must *produce* over assertions that something is absent or empty, and when you must assert absence, pair it with a positive control in the same section.
