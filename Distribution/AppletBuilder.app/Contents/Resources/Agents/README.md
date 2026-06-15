# AppletBuilder Agent CLI

`appletbuilder` is a command-line front end to AppletBuilder.app, for AI agents and
scripts. It performs the same operations a human does in the GUI — create an applet
from a template, validate the command manifest / scripts / ActionUI JSON, prettify
and preview ActionUI, and rebuild — by calling the **same** shared library code the
GUI uses (`Contents/Resources/Scripts/lib.*.sh`), so results are identical.

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
(exit `1`) before signing if validation finds errors.

- `--identity <id>` — codesigning identity (default ad-hoc `-`).
- `--thin arm64|x86_64` — thin universal binaries to one architecture (`none` = skip).
- `--warnings-as-errors` — treat validation warnings as build-halting errors.
- `--force` — force the framework/executable refresh even if versions match, and
  answer the Python major-version-upgrade prompt with "yes" (non-interactive).

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
