---
id: testing
level: 2
flavors: [claude, capable]
---

## Testing an Applet (omctest and omcitest)

An applet's logic lives in handler scripts that have no callable entry point:
the engine runs them in response to UI events, feeds them `$OMC_*` variables,
and receives their output through `omc_dialog_control` calls against a live
window. Without a harness, every change is verified by launching the app and
clicking — and the error paths, which are the ones that destroy user data, are
the least likely to be walked by hand.

`appletbuilder test <App.app>` runs the applet's real handlers against a
simulated OMC environment. **Read `docs/omctest_guide.md` before writing tests**
— it is the full API reference. This section is the shape and the traps.

### Layout and the run

`Tests/` sits **next to** the bundle, never inside it (tests in the bundle bloat
the shipped app and dirty its code signature):

```
MyAppApp/
    MyApp.app/
    Tests/
        lib.test.myapp.sh        your applet's accessors, sourced by every file
        10-window.test.sh        numbered; they run in lexical order
        20-....test.sh
        helpers/                 fakes and scripts too big to inline
        fixtures/                read-only; fixture_copy makes a writable copy
```

```bash
appletbuilder test MyApp.app [--filter '20-*'] [--verbose] [--keep-scratch]
appletbuilder build MyApp.app --test      # run the suite before codesigning
```

A human at the GUI has the same thing on the **Test** button in AppletBuilder's
Build & Run pane (next to Build and Run), which logs into the build log. Plain
`build`, and the Build button, do not run tests.

Each file gets its own scratch tree, its own window UUID, and its own
interposition directory. `alert`, `notify`, `omc_dialog_control` and
`omc_next_command` are stubbed (the first would hang forever with no user, the
third becomes the virtual window you assert against); `plister`, `b64`, `filt`
and `loco` are real. `pasteboard` is a stub that keeps each board as a file in
the file's scratch (API 6), so a handler reads back what it wrote and nothing
reaches the machine-global pasteboard server. Each file also gets its own
`$HOME` (API 3) and `$TMPDIR`.

### The idiom

```sh
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.myapp.sh"

section "opening a document"
omc_object "$(fixture_copy Sample.myappdoc)"   # what the engine would set
omc_run MyApp.main.init                        # dispatch by SCRIPT STEM
check "the field was populated" "com.example.thing" "$(ui_value "$NAME_ID")"
check "the table was fed"       "2"               "$(ui_row_count "$TABLE_ID")"
check_status "it exited cleanly" 0

# Cumulative across the file (API 4+): one check at the end covers everything.
section "no writes to undeclared view ids"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end                                    # summary + counts; this EXITS
```

**A Python handler that reads its window** (API 7+) talks to a real ActionUI host the harness stands up, and two more assertions read what it did:

```sh
omc_run MyApp.refresh
check "the table was filled" "1"     "$(bridge_called actionui.setRows)"
check "the field says ready" "ready" "$(bridge_value 101)"
```

`omc_run` takes the script's **file stem**, not the `COMMAND_ID`. They are
usually the same string — except for the primary command, which typically has no
`COMMAND_ID` at all and is dispatched as `<NAME>.main`.

### The seam contract — the thing most applets have to change

The harness intercepts OMC support tools by rebuilding `$OMC_OMC_SUPPORT_PATH`.
It **cannot** reach anything named by an absolute path or a bundle-relative one.
So anything an applet must not really do under test has to be named through an
overridable variable in its shared lib:

```sh
# One variable per binary - a variable holds one word, so a multi-word
# invocation keeps its subcommand at the call site: "$xcrun_tool" notarytool ...
codesign_tool="${MYAPP_CODESIGN_TOOL:-/usr/bin/codesign}"
xcrun_tool="${MYAPP_XCRUN_TOOL:-/usr/bin/xcrun}"
```

**It is not only binaries.** Three other kinds of seam are needed just as often,
and each is easy to forget until a test edits the machine it runs on:

- **State the applet reaches by name rather than through `$HOME`.** Paths built
  from `"$HOME"` are covered: each file gets its own home. A variable seam such
  as `prefs_dir="${MYAPP_PREFS_DIR:-$HOME/Library/Application Support/MyApp}"`
  is still the way to point one test at a prepared folder.
- **Background workers the handler spawns.** A poll loop or a downloader started
  with `&` keeps running and keeps writing into the window, which races every
  assertion in the file. Name the script through a variable, point it at a
  recorder, and assert that the right worker was launched with the right
  arguments — which is all a handler is responsible for.
- **Anything the applet reaches through `defaults` on a DOMAIN, or through a path
  built from `/Users/$USER` rather than `"$HOME"`.** Neither can be intercepted -
  cfprefsd keys the user domain by uid, and redirecting an absolute path would
  need a mount namespace - so a test that reaches them touches the real home of
  whoever runs the suite. The suite names every such line at startup. Fix them in
  the applet: `"$HOME"` is the same path in production and under test.

Where a tool is deterministic and safe, **run it for real** (`ditto`, `plutil`,
`xar`, `textutil`, `pkgbuild`): that is what makes the assertions about its
output worth anything. An applet that skips a seam simply has those handlers
excluded from coverage — say so in the test file rather than implying they are
covered.

### Traps that produce green tests that prove nothing

1. **A handler's write does not become the next dispatch's input.** The engine
   exports current control values on every dispatch; the harness records what a
   handler wrote but does **not** feed it back as
   `OMC_ACTIONUI_VIEW_<id>_VALUE`. A field one handler prefilled is invisible to
   the next unless the test bridges it:
   `omc_control "$ID" "$(ui_value "$ID")"`. Same for a table:
   `omctest_setvar "OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS" "$rows"`.
2. **A backgrounded worker has not necessarily run when `omc_run` returns.**
   Poll for its record with `omc_wait_for`; never `sleep`.
3. **Compare paths as paths, not as strings.** `$TMPDIR` keeps its trailing
   slash, so an applet's own construction can carry an interior `//` that
   `cd -P`/`pwd -P`/`realpath` normalize away — and `/var` resolves to
   `/private/var`. Build the expected value the same way the applet builds the
   actual one, or assert with `[ -e ]`.
4. **The trigger and dialog families are one-shot**, cleared after every
   `omc_run`. A second dispatch needs its own `omc_trigger` / `omc_dialog_answer`
   — without it the handler exits at its guard and every check about it passes
   vacuously.
5. **`omc_control_defaults <DocName>`, not `omc_reset_controls`.** A window where
   every toggle is off cannot exist; a test written against it describes
   something no user has ever seen.
6. **The pasteboard outlives the process.** `omc_child_sheet`/`omc_window_switch`
   derive their UUID from the name you pass, so two sections using the same name
   share keys - clear every key your applet uses in your reset helper. What you
   no longer have to handle is the *cross-run* half: every board is a file in
   this file's scratch (API 6), so a stale value from another run, or from the
   copy of the applet you have running, can no longer arrive in a handler. A
   test lib that snapshots and restores global keys itself can drop that
   machinery; an applet that grew a `PB_PREFIX` seam only for testing no longer
   needs it.
7. **`ui_enabled` / `ui_visible` return empty for NEVER TOUCHED**, not just for
   off. `check "the button is off" "" "$(ui_enabled "$ID")"` therefore passes
   when the handler never ran at all, and worse: it pins the omission, so the
   obvious fix — adding the missing `omc_disable` — turns the test red. Assert
   the state the *user* meets (`"$(ui_enabled "$ID")" = 1` or not), so both
   routes to a disabled button satisfy it and a handler that skipped the element
   entirely does not.
8. **Chain history is cumulative.** `chains_reset` before any section that
   asserts a chain did *not* happen. So are the three diagnostic logs, as of API
   4 — if your lib checks them per section and then resets, call
   `ui_reset_diagnostics` after the check or one real hit is reported once per
   remaining section, naming the wrong one each time. Ids the applet mints at
   runtime (`omc_insert_element`) are not in the statically-extracted
   `known_ids.txt`: declare them with `ui_declare_ids 2000 2010`, one id at a
   time rather than a range, so the check stays live for everything else.
9. **Import view ids from the applet, never restate them** — and guard the
   import, or a renamed constant expands to empty and every check fails with no
   hint why. Match the applet's own spelling: `NAME_ID=129`, `ID_TABLE = 10`
   (Python), and `MODEL_PICKER=25` (bare, no suffix) all need different patterns.

### Writing checks that can actually fail

**A check that cannot fail is worse than no check**, because it reads as
coverage. Before believing a new assertion, break the thing it names — delete
the guard, make the function a no-op — and confirm it goes red, then restore.
Prefer assertions that name a value the code must *produce*; when you must
assert absence, pair it with a positive control in the same section.

### Out of scope for omctest

No rendering or layout. No synthesized UI events, so a typo'd `actionID` is
silent here — `appletbuilder validate` is what catches that, so read its
warnings. No NIB dialogs. A green `omctest` plus a green `validate` means the
handler logic is correct *given the documented engine contract*. What the
engine itself does (launch chains, the order and overlap of view handlers,
panels, close handlers) is what the integration tests below are for; a human
still looks at the window once per release.

### Integration tests (omcitest, OMC 5.5)

`appletbuilder itest <App.app>` runs the `*.itest.sh` files in `Tests/` against
the **real applet through the real engine**: one fresh applet process per file,
its windows driven over the ActionUI bridge. **Read `docs/omcitest_guide.md`
before writing one** - it has the API, what is and is not isolated, and the
patterns below in full. AppletBuilder's **Integration Test** button runs the
same command.

Requirements: the applet carries a 5.5 engine (**Build** updates it) and is
signed for local use (ad hoc or a development certificate; a distribution
signature refuses the launch with exit 78). It opens real windows, and an agent
needs the sandbox off (the bridge is a Unix socket).

```bash
# Tests/myapp.itest.sh - no omctest_end; the runner counts and quits the applet.
eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$ITEST_APP/Contents/Resources/Scripts/lib.myapp.sh")"
section "A file opened with the app gets a window"
itest_wait_idle 60                                # the launch's own main command
before="$(itest_windows)"
itest_run MyApp --file "$ITEST_WORK/sample.txt" > /dev/null   # primary command by NAME
itest_wait_idle 60
window="$(itest_new_window "$before")"
check "the status line" "Ready" "$(itest_value "$window" "$STATUS_ID")"
check_contains "the row" "sample.txt" \
    "$(itest_call actionui.getRows "{\"window\": \"$window\", \"viewID\": $TABLE_ID}")"
itest_close "$window" > /dev/null; itest_wait_idle 60      # its end command runs
```

Rules that bite:

- **`itest_wait_idle` after every run, click and close**, before checking what it
  did. Work that starts after idle (a LoadableView's handlers, a poller) needs a
  deadline poll on its result, not a sleep.
- **A command that takes a file asks for one on a bare launch**; with no answer
  queued the harness cancels the panel, so no window opens. Queue
  `itest_answer_open <path>` before `itest_run <NAME> --open-panel`, or pass
  `--file`.
- **A Tab:** `itest_click` fires its action but does not show it. Set the
  TabView's value (0-based index) first, then click the Tab.
- **Not isolated:** `NSUserDefaults`/`defaults` domains, `/usr/bin/pbcopy`,
  `/usr/bin/open`, the keychain, the network. Do not click what reaches them.
- **`ITEST_APP` is the developer's applet in place** under the button and the
  CLI: never write into it. Guard any click that would do something real
  (upload, sign, delete) on the state its handler reads.
- **Bridge JSON has spaces** (`["a", "b"]`): use `check_contains`, or strip them.
