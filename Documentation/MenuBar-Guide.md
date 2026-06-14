# Menu Bar JSON in OMC Applets (`MainMenu.json`)

OMC 5.1 applets build their menu bar in code instead of from `MainMenu.nib`. At
launch the applet installs the standard macOS menu bar (App, File, Edit, Format,
Window, Help) and then applies an optional **`MainMenu.json`** in the applet's
`Base.lproj/` that adds, modifies, or removes menus on top of it.

The base JSON format — the array root and the `CommandMenu` / `CommandGroup` /
`RemoveMenu` / `RemoveItem` elements — is provided by ActionUI's menu-bar engine
and is documented in **[ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md)**. This
guide covers only what is specific to OMC applets.

If an applet ships **no** `MainMenu.json`, it launches with the standard bar
unchanged. An applet uses *either* `MainMenu.nib` *or* `MainMenu.json`, never
both; nib-based applets are described in [Nib-Guide.md](Nib-Guide.md).

## The Commands menu (`autoPopulate`)

The standard applet template ships exactly one menu addition:

```json
[
  { "type": "CommandMenu", "properties": { "name": "Commands", "autoPopulate": true } }
]
```

`autoPopulate` is an OMC extension. When `true`, OMC fills the menu's items from
the applet's `Command.json` at launch — one item per top-level command — so the
menu always mirrors the applet's commands without listing them by hand. Omit
`children` when `autoPopulate` is set.

## Wiring a menu item to a command (`actionID`)

Hand-authored menu items use ActionUI's native **`actionID`** — no OMC-specific
property. In an OMC applet the `actionID` **is** the command id to run: OMC builds
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

Use `RemoveItem` / `RemoveMenu` to drop default items the applet doesn't need.
For example, a droplet whose only action is "open" needs no separate **New**
item (New and Open do the same thing), so it removes New:

```json
[
  { "type": "RemoveItem", "properties": { "menu": "File", "title": "New" } }
]
```

## Open Recent

OMC adds and maintains the **File ▸ Open Recent** submenu itself — the standard
programmatic bar does not include one, because AppKit only auto-populates Open
Recent for nib menus. The applet's document controller (`OMCDropletController`)
inserts the submenu after **Open…** and rebuilds it on demand from the shared
`NSDocumentController`'s recent documents. Choosing an entry runs the applet's
default command on that file, the same path used for drops and File ▸ Open….

Recent documents are recorded automatically when the applet opens a file,
provided the applet declares `CFBundleDocumentTypes` in its `Info.plist`. No
`MainMenu.json` entry is needed for Open Recent.

## New / Open and enabled state

**New** (`newDocument:`) and **Open…** (`openDocument:`) are standard
first-responder document actions. They are enabled by default because
`OMCDropletController` (the applet's document controller and app delegate)
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
