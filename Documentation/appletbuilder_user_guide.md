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

**Build & Run** — Codesign identity picker + build log. Click Build to sign the applet; required after editing scripts or binaries.

**Commands** — Table of `Command.plist` entries. Right panel: Plist editor for the selected command. Buttons: Validate (runs `plutil -lint`), Save, external editor.

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
