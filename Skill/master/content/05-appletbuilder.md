---
id: appletbuilder
level: 1
flavors: [claude, capable, lite]
---

## AppletBuilder

AppletBuilder (`Distribution/AppletBuilder.app`) is the tool for creating and
maintaining applets. Humans use its GUI; **AI agents drive the same operations from
the command line** via the bundled `appletbuilder` CLI — create from a template,
validate, prettify/preview ActionUI, and rebuild — running the *same* underlying
code as the GUI.

### Agent CLI

```
Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder <command> [args]
```

Progress and validation detail go to **stderr**; capturable results (a created
applet's path, prettified JSON, a screenshot path, listings) go to **stdout**.
Exit codes: `0` ok · `2` warnings · `1` errors.

| Command | Does |
|---------|------|
| `create (--template <name|path> \| --clone <App.app>) --name <N> --dest <dir> [--bundle-id <id>] [--python] [--icon <name|path>]` | Copy a template (or clone an applet), rename it, install the framework/executable (and Python if `--python`), set the icon, and codesign. Prints the new `.app` path. |
| `validate <App.app \| Command.json \| UI.json \| script>` | Auto-detects the target and runs the matching validator(s). For a bundle: `Info.plist` + command manifest (Layer 1/2) + every script + every ActionUI JSON. |
| `build <App.app> [--identity <id>] [--thin arm64\|x86_64] [--warnings-as-errors] [--update-python] [--force]` | Full validation, then refresh framework/executable (newer version auto-copies; `--force` re-copies even when unchanged), thin, and codesign. Halts before signing on validation errors. Independently, a working embedded Python is left untouched unless `--update-python` is given; a missing/broken runtime is always installed. Replacing the runtime wipes anything pip-installed into its `site-packages` — install deps into `Contents/Library/Packages` (on `PYTHONPATH`) so they survive. |
| `prettify <file.json> [--stdout]` | Reformat JSON in place (or to stdout). |
| `preview <UI.json> [--screenshot <out.png>]` | Render an ActionUI view to a PNG (read it to inspect the layout); a `MainMenu.json` menu-bar doc prints a text summary instead. Needs a GUI session. |
| `list-templates` / `list-icons` | Names for `--template` / `--icon`. |

Example — create a Python applet, then validate and build it:

```bash
AB="Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder"
NEWAPP=$("$AB" create --template "ActionUI Window" --name MyApp --dest ~/Desktop --python --icon Bolt)
"$AB" validate "$NEWAPP"
"$AB" build "$NEWAPP" --thin arm64
```

Full reference: `Distribution/AppletBuilder.app/Contents/Resources/Agents/README.md`.

### Templates

| Template | Use when |
|----------|----------|
| `Empty` | Minimal bundle; no dialog |
| `ActionUI Window` | ActionUI JSON dialog (recommended for OMC 5.0+) |
| `ActionUI Web` | ActionUI dialog with embedded WebView |
| `Nib Window` | NIB (Interface Builder) dialog |
| `Nib Web` | NIB dialog with embedded WebView |

The **Name** also becomes the executable name and script prefix. New applets are
created with a `Command.json` manifest. Humans can do the same from the GUI's New
Applet panel.

### For an existing applet

Edit the bundle's files directly:
- `Contents/Resources/Command.json` (or `Command.plist` — OMC reads either, preferring `Command.json` when both exist)
- `Contents/Resources/Scripts/*`
- `Contents/Resources/Base.lproj/*.json` (ActionUI) or `*.nib` (NIB — edit in Xcode)

After editing, run `appletbuilder validate <App.app>` to catch problems.

### Code signing during development

Applets are signed for local execution; editing bundle resources (scripts, ActionUI JSONs, `Command.json`) does not stop the app from launching during development — macOS (as of 26) does not block resource-modified locally-signed apps. Re-sign — `appletbuilder build <App.app>`, the **Build** button in AppletBuilder's Build & Run pane, or `Scripts/codesign_applet.sh` — after changing binaries/frameworks, before distributing, or if the OS refuses to launch the app.

For full GUI-navigation help (Project Editor tabs, Commands editor, UI Files Validate/Preview/Prettify buttons, etc.), see `docs/appletbuilder_user_guide.md`.
