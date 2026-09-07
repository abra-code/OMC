# AppletBuilder Agent CLI

`appletbuilder` is a command-line front end to AppletBuilder.app, for AI agents and
scripts. It performs the same operations a human does in the GUI — create an applet
from a template, validate the command manifest / scripts / ActionUI JSON, prettify
and preview ActionUI, rebuild, and thin an applet's embedded Python - by calling the
**same** shared library code the GUI uses (`Contents/Resources/Scripts/lib.*.sh`), so results are identical.

The tool lives inside the app bundle and finds everything it needs relative to
itself; just run it by path:

```
<AppletBuilder.app>/Contents/Resources/Agents/appletbuilder <command> [args]
```

## Output & exit codes

- **stderr** — all progress and validation detail (the equivalent of the GUI's log
  pane and error windows). In the GUI these go to windows; for an agent they go to
  stderr so nothing pops up.
- **stdout** — only results worth capturing: a created applet's path, prettified
  JSON, a screenshot path, or list output.
- **exit code** — `0` ok · `2` warnings only · `1` errors. Usage mistakes also exit `2`.

## Commands

### create — new applet from a template

```
appletbuilder create (--template <name|path> | --clone <App.app>) \
                     --name <Name> --dest <dir> \
                     [--bundle-id <id>] [--python] [--icon <name|path>] \
                     [--identity <id>] [--no-codesign]
```

- `--template <name|path>` — a template name from `list-templates` (e.g.
  `"ActionUI Window"`) or a path to a `.applet`/`.app` to copy.
- `--clone <App.app>` — clone an existing applet instead of a template (Python use
  is auto-detected from its scripts).
- `--name` — the applet name; also becomes the executable name and script prefix.
- `--dest` — directory the new `<Name>.app` is created in.
- `--bundle-id` — `CFBundleIdentifier`; defaults to the remembered prefix + name.
- `--python` — embed the Python runtime and start from a `<Name>.main.py` script.
- `--icon <name|path>` — an icon name from `list-icons` (e.g. `Bolt`) or a path to a
  `.icon`/`.icns`/image; omit to keep the template's icon.
- `--identity <id>` — codesigning identity (default ad-hoc `-`).
- `--no-codesign` — skip codesigning.

On success the new applet's path is printed to **stdout**. Example:

```
NEWAPP=$(appletbuilder create --template "ActionUI Window" \
           --name MyApp --dest ~/Desktop --python --icon Bolt)
```

### validate — validate a bundle or a single file

```
appletbuilder validate <App.app | Command.json | UI.json | script-file>
```

Auto-detects the target:

- **applet bundle** — runs the full build-time validation: `Info.plist`, the command
  manifest (syntax + Layer 1/2 cross-references), every script (per-type syntax,
  plus a bash-4+ portability scan), and every ActionUI JSON. Exit `0` clean / `1`
  errors (warnings are printed but don't fail the bundle, matching the GUI build).
- **Command.json / Command.plist** — the command verifier.
- **`.json`** — the ActionUI verifier (also accepts `MainMenu.json` menu-bar docs).
- **script** (`.sh` `.bash` `.zsh` `.py` `.js` `.applescript` `.scpt`) — a syntax
  check using the same interpreter OMC will use (`.sh` → `/bin/sh`, i.e. bash 3.2),
  plus the bash-4+ portability scan for shell scripts.

Single-file results exit `0`/`2`/`1`. This is the same validation the GUI runs on its
Validate buttons and on Build.

### build — rebuild an applet

```
appletbuilder build <App.app> [--identity <id>] [--thin arm64|x86_64|none] \
                    [--warnings-as-errors] [--force]
```

Runs full validation, then refreshes `Abracode.framework` + the executable (and the
embedded Python runtime for Python applets) from this AppletBuilder, removes
`__pycache__`, optionally thins universal binaries, and codesigns. The build halts
(exit `1`) before signing if validation finds errors, or if `--thin` was asked for and
a binary could not be sliced to that architecture - including the case the underlying
tool reports as a warning and exits 0 on, since signing then ships the architecture you
asked to drop. A halt on that path leaves the bundle modified and unsigned: other
binaries were already rewritten before the failing one.

- `--identity <id>` — codesigning identity (default ad-hoc `-`).
- `--thin arm64|x86_64|none` — thin universal binaries to one architecture (`none` = skip). Anything else is a usage error.
- `--warnings-as-errors` — treat validation warnings as build-halting errors.
- `--force` — force the framework/executable refresh even if versions match, and
  answer the Python major-version-upgrade prompt with "yes" (non-interactive).
- `--test` - run the applet's `Tests/` suite after the runtime refresh and before
  signing, and halt the build if it fails. Running it there is the point: it
  tests the tool versions that will actually ship. Tests are not run by default,
  because they are applet-authored code with arbitrary runtime and a developer
  mid-refactor must be able to rebuild an app whose tests are momentarily red.
  Gating belongs at release, by convention. `--test` with no `Tests/` directory
  beside the applet is an error, not a silent skip. The suite's whole transcript,
  including its `omctest: <N> passed, ...` summary, goes to stderr on this path
  along with the rest of the build's progress output; the summary reaches stdout
  only under `appletbuilder test`. Consume `build --test` by its exit status.

`validate` (and therefore every `build`) emits one `[INFO]` line when an applet
has no `Tests/` directory. It is advisory and never affects the exit status.

### test - run an applet's test suite

```
appletbuilder test <App.app> [--tests <dir>] [--filter <glob>] [--verbose] \
                   [--keep-scratch] [--list]
```

Runs the applet's `Tests/*.test.sh` files against its real handler scripts inside a
simulated OMC environment: a scratch mock of the engine's variable surface, an
interposition directory holding the applet's own runtime tools with `alert`,
`notify`, `omc_dialog_control` and `omc_next_command` replaced by recording stubs,
and a per-file `TMPDIR` so state directories are isolated and cleanup is total.
Tests live *next to* the bundle, never inside it. Full bundle validation runs first
and validation errors abort the run before any test executes; warnings do not.

The GUI equivalent, for a human with the applet open, is the **Test** button in
AppletBuilder's Build & Run pane - same validation, same runner, transcript in the
pane's log. It takes no flags; `--filter` and `--keep-scratch` are the CLI's.

- `--tests <dir>` - where the test files are (default `Tests/` beside the `.app`).
- `--filter <glob>` - run only the files whose name matches, e.g. `20-*`.
- `--verbose` - also stream each handler's stdout and stderr as it is produced.
- `--keep-scratch` - skip the cleanup trap and print the scratch path, so the
  virtual window's recorded state can be inspected after the run.
- `--list` - print the test files that would run, one per line, and stop.

Per-check `ok`/`FAIL` lines and section headers go to stderr as the run proceeds;
the one machine-readable line on stdout is `omctest: <N> passed, <M> failed, <K>
files`. A test file that exits before calling `omctest_end` is reported as
`CRASH <file> (exit <rc>)` and counted as a failure, never silently dropped.
Exit: `0` all passed, `1` any failure or crash, `2` usage errors or no tests found.

A single file can also be run by hand, without the CLI, which is the debug loop
for one failing test:

```
OMCTEST_APP=./MyApp.app \
OMCTEST_LIB=<AppletBuilder.app>/Contents/Resources/Agents/omctest.sh \
    sh Tests/10-lifecycle.test.sh
```

See `omctest_guide.md` in the Documentation folder for the test-author API.

### thin-python - strip the applet's embedded Python

```
appletbuilder thin-python plan|apply|plan-apply <App.app> \
                   [--plan <file>] [--dry-run] [--skip-verify] [--thin arm64|x86_64|none]
```

Closure-thins the interpreter an applet bundles - a full universal distribution of
some 60 MB, of which a typical applet imports a small slice. Two phases with a
reviewable JSON plan in between:

- `plan` - analyze the applet and write `<App>.thinning-plan.json` beside the
  bundle. The applet is never modified: the analysis clones it and executes only
  the clone, every traced subprocess confined by `sandbox-exec` with no network
  and no writes outside the staging area. Commit the plan next to the applet.
- `apply` - remove what the plan names from the real interpreter, then verify by
  re-running the plan's workload. A verification failure restores the backup the
  applier took, so a plan that removed too much leaves a working applet behind.
  `--dry-run` lists the removal and performs none of it.
- `plan-apply` - both, for a distribution copy just made from a planned applet.
  With `--dry-run`, writes the plan and then lists what applying it would remove.

Only applets that bundle their own Python can be thinned; one that does not is
refused by name rather than failing obscurely. The verb is the confirmation - the
CLI does not prompt, where the GUI's **Execute** button asks before any
removal. `--dry-run` is refused on `plan`, which removes nothing to preview,
rather than being ignored there.

- `--plan <file>` - a plan elsewhere. Without it: beside the bundle, then the last
  plan AppletBuilder wrote for that applet, matched on its bundle identifier
  (said so in the log).
- `--thin arm64|x86_64|none` - also record that slice in the plan, so the interpreter
  is thinned the same way `build --thin` slices the applet's other binaries. Anything
  else is a usage error rather than a silently universal plan.
- `--skip-verify` - skip the post-removal re-run. Rarely right: that re-run is
  what makes a wrong plan recoverable.

An optional `<App>.thinning-keep.txt` beside the bundle (one module name per line)
is picked up automatically - the escape hatch for a module no analysis can
discover. `Documentation/omc_python_scripting_guide.md` has the full workflow. The same
front end, with the advanced options this subcommand does not surface (`--trace`
for out-of-process entry points, `--keep`, `--execute-entry-points`), is the
vendored copy inside this bundle:

```
<AppletBuilder.app>/Contents/Library/python_thinning/thin_applet_python.py
```

(`Distribution/Scripts/thin_applet_python.py` in an OMC checkout is the same file.)

### prettify — reformat ActionUI / JSON

```
appletbuilder prettify <file.json> [--stdout]
```

Reformats the JSON in place (or prints to **stdout** with `--stdout`). Invalid JSON
exits `1` with the parse error on stderr.

### preview — render an ActionUI view to an image

```
appletbuilder preview <UI.json> [--screenshot <out.png>]
```

- For a normal ActionUI **view**, renders it with `ActionUIViewer` and writes a PNG,
  printing the image path to **stdout** (a temp file if `--screenshot` is omitted).
  Read that PNG to inspect the layout and catch problems early.
- For a **menu-bar** document (`MainMenu.json`, a top-level array — not a view), prints
  a textual menu summary to stdout instead.

**Requires a logged-in GUI / window-server session** (it briefly opens a window to
capture it). It will report a failure if run headless.

### list-templates / list-icons

```
appletbuilder list-templates    # template names for --template
appletbuilder list-icons        # icon names for --icon
```

## Notes

- Editing an applet's scripts / ActionUI JSON / `Command.json` doesn't stop it from
  launching during development. Re-`build` (or codesign) after changing binaries or
  frameworks, before distributing, or if macOS refuses to launch it.
- The validators and verifiers are the single source of truth shared with the GUI —
  fixing what `validate`/`build` report here fixes what the GUI reports too.
- For authoring `Command.json` and ActionUI JSON by hand, see the OMC skill
  (`Skill/SKILL.md`) and the ActionUI skill.
