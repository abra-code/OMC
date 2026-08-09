---
id: testing
level: 2
flavors: [claude, capable]
---

## Testing an Applet (omctest)

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
third becomes the virtual window you assert against); `plister`, `pasteboard`,
`b64`, `filt` and `loco` are real.

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

# ui_reset DELETES this log, so check before every reset, not once at the end.
section "no writes to undeclared view ids"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end                                    # summary + counts; this EXITS
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

- **State that lives under `$HOME`.** `prefs_dir="${MYAPP_PREFS_DIR:-$HOME/Library/Application Support/MyApp}"`.
  `$TMPDIR` is redirected for you; `$HOME` is not.
- **Background workers the handler spawns.** A poll loop or a downloader started
  with `&` keeps running and keeps writing into the window, which races every
  assertion in the file. Name the script through a variable, point it at a
  recorder, and assert that the right worker was launched with the right
  arguments — which is all a handler is responsible for.
- **Global pasteboard keys**, the kind an applet uses to hand a value from one
  window to another. They live in the login pasteboard server and are shared with
  every other omctest run on the machine. Give the applet a prefix
  (`PB_PREFIX="${MYAPP_PB_PREFIX:-}"`, empty in production) and let the test set
  a per-run value. See trap 6.

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
6. **The pasteboard outlives the process, and it is not coherent across them.**
   `omc_child_sheet`/`omc_window_switch` derive their UUID from the name you
   pass, so two sections using the same name share keys - clear every key your
   applet uses in your reset helper. Worse, a GLOBAL key (one an applet uses to
   hand a value from one window to another) is shared with every *other* omctest
   run on the machine, and a value from an earlier run has been measured arriving
   in a later run's handler. Waiting for the value does not fix it - the stale
   reading is non-empty and wrong. Give the applet a key **prefix** seam and let
   the test set a per-run value; that is a seam of the same kind as a binary.
7. **`ui_reset` deletes `unknown_ids.log`, `suspect_writes.log` and
   `errors.log`.** A single `ui_unknown_writes` check at the end of a file
   therefore only ever sees the last section — it reads as a standing check and
   is inert. Call it inside your reset helper, before the wipe.
8. **Chain history is cumulative.** `chains_reset` before any section that
   asserts a chain did *not* happen.
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

### Out of scope, permanently

No rendering or layout. No synthesized UI events, so a typo'd `actionID` is
silent here — `appletbuilder validate` is what catches that, so read its
warnings. No NIB dialogs. A green `omctest` plus a green `validate` means the
handler logic is correct *given the documented engine contract*; a human still
launches the app once per release and confirms the window looks right.
