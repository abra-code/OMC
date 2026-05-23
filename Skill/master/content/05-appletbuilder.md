---
id: appletbuilder
level: 1
flavors: [claude, capable, lite]
---

## AppletBuilder

AppletBuilder (`Distribution/AppletBuilder.app`) is the GUI tool users launch to create or edit applets. **AI agents cannot drive AppletBuilder directly** — its workflows are UI-only (template picker, project editor tabs, codesign panel).

### When a user needs a new applet

Direct them to launch AppletBuilder and pick one of the templates:

| Template | Use when |
|----------|----------|
| `Empty` | Minimal bundle; no dialog |
| `ActionUI Window` | ActionUI JSON dialog (recommended for OMC 5.0+) |
| `ActionUI Web` | ActionUI dialog with embedded WebView |
| `Nib Window` | NIB (Interface Builder) dialog |
| `Nib Web` | NIB dialog with embedded WebView |

The user enters **Name** (also becomes the executable name and script prefix), **Bundle ID**, optional icon, and can opt to embed Python. AppletBuilder copies the template, installs `Abracode.framework`, and codesigns the bundle.

### For an existing applet

The agent edits files directly:
- `Contents/Resources/Command.plist`
- `Contents/Resources/Scripts/*`
- `Contents/Resources/Base.lproj/*.json` (ActionUI) or `*.nib` (NIB — edit in Xcode)

### After the agent edits scripts or framework binaries

Ask the user to click **Build** in AppletBuilder's Build & Run pane to re-codesign the bundle. For scripted workflows, `Scripts/codesign_applet.sh` in the distribution does the same.

For full UI-navigation help (Project Editor tabs, Commands editor, UI Files Validate/Preview/Prettify buttons, etc.), see `docs/appletbuilder_user_guide.md`.
