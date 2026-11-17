# Menu Bar JSON in Command Workshop Applets (`MainMenu.json`)

Applets build their menu bar in code (since 5.1; since 6.0 a
`MainMenu.nib` is no longer loaded at all). At
launch the applet installs the standard macOS menu bar (App, File, Edit, Format,
Window, Help) and then applies an optional **`MainMenu.json`** in the applet's
`Base.lproj/` that adds, modifies, or removes menus on top of it.

The base JSON format — the array root and the `CommandMenu` / `CommandGroup`
elements (deletion is a `CommandGroup` with `placement: "replacing"` and no
children) — is provided by ActionUI's menu-bar engine and is documented in
**[ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md)**. This guide
covers only what is specific to Command Workshop (formerly OMC) applets.

If an applet ships **no** `MainMenu.json`, it launches with the standard bar
unchanged. An applet made before 5.1 may still carry a `MainMenu.nib` and an
`NSMainNibFile` key: since 6.0 both are ignored (AppletBuilder warns about the key
when it builds), so convert its custom items as below.

**About <App>** opens the Command Engine's own About window, the same on macOS and
Linux: the applet's icon, name, version (`CFBundleShortVersionString` and
`CFBundleVersion`), the Markdown of `Contents/Resources/Credits.md`, and
`NSHumanReadableCopyright`. Put everything else you want to say (authors, license,
website, what the applet uses) in `Credits.md`; AppletBuilder warns about an applet
without one. `Credits.rtf`, which macOS's standard About panel read, is no
longer shown: on macOS, AppletBuilder's Build writes `Credits.md` from it once
(links, italic and bold kept; alignment, fonts and colors dropped), so check the
result and delete `Credits.rtf`. On Linux the item is the last of the header bar's menu. A
`CommandGroup` replacing `appInfo` (or `about`) takes the item away on both
systems, as for any standard item.

## Converting an applet from `MainMenu.nib` to `MainMenu.json`

The programmatic bar already reproduces the entire **standard** menu bar, so a
conversion only needs to re-express the applet's *custom* items — the ones the nib
wired to a command. Everything standard (the App/File/Edit/Format/Window/Help
items, Page Setup, Print, Open Recent) is rebuilt automatically; **do not port
standard wiring.**

**1. Find the custom items in the nib.** A custom item is an `OMCMenuItem` with a
`commandID` user-defined runtime attribute. The nib's `designable.nib` is an
Interface Builder XML document, so list them with:

```sh
grep -nE 'customClass="OMCMenuItem"|keyPath="commandID"' \
  YourApp.app/Contents/Resources/Base.lproj/MainMenu.nib/designable.nib
```

For each match note its **title**, **key equivalent**, the **menu** it lives in,
and its **`commandID`** value. (If the bundle has only the compiled
`keyedobjects.nib`, open the nib in Xcode instead — the compiled form isn't
greppable.)

**2. Write `MainMenu.json`** (an array root) with one `CommandGroup` per custom
item. Each item becomes a `Button` whose **`actionID` is the old `commandID`**,
carrying the same `title` and `keyboardShortcut` (see
[Wiring a menu item](#wiring-a-menu-item-to-a-command-actionid)). Pick the
placement by what the nib item was:

- It **customized a standard slot** (New, Open…, Close, the Help item, …) →
  `replacing` that item by its stable **id** (`new`, `open`, `close`, `help`, …;
  full list in [ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md)).
  The replacement keeps the slot's position and, on macOS 26+, its system icon.
- It **has no standard counterpart** (e.g. Settings…, Save) → add it with
  `before` / `after` an anchor (an item id, or a SwiftUI group placement such as
  `appSettings` / `saveItem`). Give it a `systemImage` if you want an icon.

**3. Place `MainMenu.json` in `Base.lproj/`** (where the nib was). The Command Engine resolves it
as a localized resource.

**4. Remove `NSMainNibFile` from `Info.plist`.** Since 6.0 the applet's
executable ignores the key and always builds the bar in code; AppletBuilder warns
while it is there. Leave `NSPrincipalClass` (`NSApplication`) in place.

**5. Delete `MainMenu.nib`** from `Base.lproj/`.

**6. Refresh the binaries.** The bar is built by code in the applet's executable (a
copy of the master applet's, CommandApplet; OMCApplet before 6.0) and its embedded
`Command.framework`, which must come from the same release. An applet last built before 6.0 must update both: its old executable
does not launch with a 6.0 framework. In **AppletBuilder ▸ Build & Run**,
use **Force Update Binaries** — required when the Command Engine version string is unchanged
(e.g. when the Command Engine version string is the same in both builds, the normal
version-based update check won't trigger a refresh).

**7. Re-codesign** the bundle after editing it (`codesign_applet.sh YourApp.app -`)
and **validate** the result (AppletBuilder validates `MainMenu.json` on select, or
run the verifier).

A converted applet that needs no custom items at all can simply drop the nib and
`NSMainNibFile` and ship **no** `MainMenu.json` — it gets the standard bar.

## The Commands menu (`autoPopulate`)

The standard applet template ships exactly one menu addition:

```json
[
  { "type": "CommandMenu", "properties": { "name": "Commands", "autoPopulate": true } }
]
```

`autoPopulate` is a Command Workshop extension. When `true`, the Command Engine fills the menu's items from
the applet's `Command.json` at launch — one item per top-level command — so the
menu always mirrors the applet's commands without listing them by hand. Omit
`children` when `autoPopulate` is set.

## Wiring a menu item to a command (`actionID`)

Hand-authored menu items use ActionUI's native **`actionID`** — no Command Workshop-specific
property. In a Command Workshop applet the `actionID` **is** the command id to run: the Command Engine builds
the item as an `OMCMenuItem` wired to `executeCommand:`, the same path the old nib
menu used.

```json
{
  "type": "CommandMenu",
  "properties": { "name": "Tools" },
  "children": [
    { "type": "Button", "properties": {
        "title": "Run Report",
        "actionID": "tools.report",
        "keyboardShortcut": { "key": "r", "modifiers": ["command", "shift"] } } }
  ]
}
```

Menu-bar items are action-sending (not Picker-style selection), so `actionID`
alone is sufficient — there is no `mappedValue` or `escapingMode` for menu-bar
buttons.

## Trimming the standard bar

To drop default items, use a `CommandGroup` with `placement: "replacing"` and no
children. Target an individual item by its **id** to remove just that one, a
SwiftUI **group** to remove a whole group, or a **menu title** to remove a whole
menu. For example, an inspector applet that doesn't create documents can drop
just **New** (keeping Open) and remove the Format menu:

```json
[
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "new" } },
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "Format" } }
]
```

Prefer item ids for single items: a group placement like `newItem` removes the
whole New/Open group (New *and* Open), per SwiftUI's behavior. The full id list
is in [ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md).

## Open Recent

The Command Engine adds and maintains the **File ▸ Open Recent** submenu itself — the standard
programmatic bar does not include one, because AppKit only auto-populates Open
Recent for nib menus. The applet's document controller (`OMCAppletController`,
named `OMCDropletController` before 6.0)
inserts the submenu after **Open…** and rebuilds it on demand from the shared
`NSDocumentController`'s recent documents. Choosing an entry runs the applet's
default command on that file, the same path used for drops and File ▸ Open….

Recent documents are recorded automatically when the applet opens a file,
provided the applet declares `CFBundleDocumentTypes` in its `Info.plist`. No
`MainMenu.json` entry is needed for Open Recent.

## New / Open and enabled state

**New** (`newDocument:`) and **Open…** (`openDocument:`) are standard
first-responder document actions. They are enabled by default because
`OMCAppletController` (the applet's document controller and app delegate)
validates them and implements opening — selecting **Open…** runs the applet's
default command on the chosen file.

## Validation & preview in AppletBuilder

- **Validation** detects the array root and validates `MainMenu.json` as a
  menu-bar document (element types, required properties, children). Menu items use
  the native `actionID`; the `autoPopulate` host extension is accepted.
- **Preview** shows a textual menu summary rather than launching ActionUIViewer,
  because a menu bar is not a renderable view.
- The **(?)** help button for a selected `MainMenu.json` opens the base
  [ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md).
