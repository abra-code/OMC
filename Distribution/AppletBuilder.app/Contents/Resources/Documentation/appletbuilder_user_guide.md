# AppletBuilder User Guide

AppletBuilder (`Distribution/AppletBuilder.app`) is the GUI tool for creating and editing OMC applets. It is itself an OMC applet.

This guide describes the AppletBuilder UI workflows. It is intended for human users navigating the app. AI agents cannot drive AppletBuilder directly — they should ask the user to perform UI steps and then read/edit the resulting bundle files.

## Creating a New Applet

Drop an existing `.app` onto AppletBuilder to open it for editing, or launch AppletBuilder without a drop to open the **New Applet** dialog.

| Template | What it creates |
|----------|----------------|
| `Empty` | Minimal bundle; shell main script; no dialog |
| `ActionUI Window` | ActionUI JSON dialog + init script; `ACTIONUI_WINDOW` in Command.plist |
| `ActionUI Web` | ActionUI dialog with embedded WebView |
| `Nib Window` | NIB (Interface Builder) dialog |
| `Nib Web` | NIB dialog with embedded WebView |

Fields: **Name** (becomes the executable name, COMMAND_ID prefix, and script prefix), **Bundle ID**, optional icon, Python toggle (installs embedded Python distribution).

AppletBuilder copies the template, renames all files to match the applet name, installs `Abracode.framework`, codesigns the bundle, and opens the project editor.

## Project Editor Tabs

**General** — Applet name, bundle ID, version, minimum OS, icon. Add or edit System Services. Save writes to `Info.plist`.

**Build & Run** — Codesign identity picker + build log, the three buttons that act on the applet (**Build**, **Test**, **Run**), and an **Embedded Python Thinning** group in the second column.

Click **Build** to validate the project (Info.plist, Command.plist, scripts, ActionUI JSON) and then sign the applet; required after editing scripts or binaries. Validation errors halt the build before signing; warnings are reported and can be made blocking via the "Treat Validation Warnings As Errors" toggle. A failed architecture slice halts it too - if "Thin Universal Executables" is set and a binary cannot be sliced to that architecture, the build stops rather than signing an applet that still carries the architecture you asked to drop, and the log says the bundle was modified and left unsigned. Other options: "Force Update Binaries" re-copies the framework/executable even when unchanged; "Thin Universal Executables" slices the binaries (and embedded Python) to a single architecture; "Update Embedded Python" allows replacing the applet's working embedded Python with AppletBuilder's runtime (off by default — it overwrites `Contents/Library/Python` wholesale and wipes anything pip-installed into its `site-packages`; a missing or broken runtime is always installed regardless). Install third-party modules into `Contents/Library/Packages` so they survive Python upgrades.

Click **Test** to run the applet's `omctest` suite — every `*.test.sh` in the `Tests/` directory **next to** the `.app`. The bundle is validated first (a bash 4-ism or a dangling `COMMAND_ID` is named in one line here instead of surfacing as a baffling mid-test handler failure), then each test file runs in its own simulated OMC environment; the whole transcript streams into the same log as the build. This is the GUI equivalent of `appletbuilder test <App.app>`. Applets with no `Tests/` directory get a one-line note in the log — see the [omctest guide](omctest_guide.md) for how to write a suite. Build does not run tests, deliberately: an applet whose tests are momentarily red still has to be re-signable mid-refactor. For the scripted "only sign a green build" flow, use `appletbuilder build <App.app> --test`.

Use the **Embedded Python Thinning** group, in the second column of the pane, to strip the unused parts of the applet's embedded Python - a full universal distribution of some 60 MB, of which a typical applet imports a small slice. Two checkboxes say what its **Execute** button does and a third qualifies them: **Write Thinning Plan** analyzes the applet and writes `<App>.thinning-plan.json` next to the bundle without touching the applet (the analysis runs on a clone); **Apply Plan** removes what the plan names from the real interpreter and then verifies against the workload the plan recorded, restoring automatically if that workload breaks; **Dry Run** turns an apply into a listing of what it would remove, ending in a summary of the sizes involved - the embedded Python as it stands, what the plan's modules occupy, and what would be left. Ticking both boxes plans and applies in one click - the shortcut for a distribution copy you have just made. Dry Run is available only while Apply Plan is ticked, and the button is live only when there is something for it to do. Everything that removes modules asks for confirmation first, naming the applet and the plan, and the transcript streams into the same log as a build.

The whole group is disabled, with a note saying so, for an applet that bundles no Python - there is nothing to thin. A build can install a runtime into an applet with Python handlers that had none, so the group is re-checked after every build.

The usual flow is to write and review the plan against your development copy - planning cannot damage it - commit the plan beside the applet, then open the release copy and apply. An apply with no plan beside the bundle falls back to the last plan AppletBuilder wrote for that applet - matched on its bundle identifier, so another applet of the same name cannot lend you its plan - and says so in the log; since verification only re-runs what that plan recorded, launch the applet once after applying a plan written against a different build. AppletBuilder will not apply a plan to itself - the thinning runs under its own interpreter - nor one whose `Packages` section names a directory in another bundle. The "Thin Universal Executables" choice is carried into the plan, so an applet sliced to one architecture gets an interpreter sliced the same way. Thinning is deliberately not part of Build. The CLI equivalent is `appletbuilder thin-python plan|apply|plan-apply <App.app>`; `Documentation/omc_python_scripting_guide.md` has the full workflow, including the optional `<App>.thinning-keep.txt` force-keep list.

**Commands** — Table of `Command.plist` entries. Right panel: Plist editor for the selected command. Buttons:
- **Validate** — runs `plutil -lint` (syntax) then the Python Command.plist verifier (`Contents/Library/command_verifier/validate_command_plist.py`): key/type/enum/required checks, conditional rules (e.g. `CUSTOM_*` need `WINDOW_TYPE=custom`), deprecated/removed keys, and Layer-2 bundle cross-references (script files, `JSON_NAME`/`NIB_NAME` resources, subcommand IDs, duplicate `COMMAND_ID`s, and every `actionID` in the bundle's JSON UI documents).
- **Save** — writes to `Command.plist`
- external editor

**Scripts** — Table of files in `Scripts/`. Right panel: text editor. Buttons: Save, external editor, reveal in Finder.

**UI Files** — Table of ActionUI JSON files (`.json` in `Base.lproj/` and `Resources/`). Right panel: text editor. Buttons:
- **Validate** — runs the Python ActionUI verifier (`Contents/Library/actionui_verifier/validate_actionui.py`)
- **Preview** — opens in ActionUIViewer
- **Prettify** — formats JSON
- **Save** — writes to disk
- **Edit** — opens in external editor

The Element template picker (top right of UI Files panel) inserts a starter snippet for any element type.

## Common Workflows

**Add a command**: Commands tab → `+` → New Command dialog (Name, COMMAND_ID, execution mode, activation mode, script type) → Create. AppletBuilder appends the entry to `Command.plist` and creates the matching script file in `Scripts/`.

**Edit a script**: Scripts tab → select file → edit in panel → Save.

**Edit ActionUI JSON**: UI Files tab → select file → edit → Validate → Preview → Save.

**Reload**: The reload button (↻) in the Scripts and UI Files tabs re-reads the file from disk, discarding unsaved edits.

## What AppletBuilder Cannot Do

AppletBuilder does not edit `Info.plist` directly beyond the General tab fields. For adding custom `NSDocumentTypes`, or URL schemes, edit `Info.plist` manually using Xcode or `plutil`.
