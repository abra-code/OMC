# Menu Bar JSON Guide (`MainMenu.json`)

ActionUI's `ActionUIMenuBar` library builds an application's macOS menu bar in
code (a programmatic replacement for `MainMenu.nib`) and then applies an optional
JSON document — conventionally **`MainMenu.json`** — that adds, modifies, or
removes menus on top of the standard bar.

This guide describes that JSON format. It complements the view format in
[ActionUI-JSON-Guide.md](ActionUI-JSON-Guide.md); a **view** document has an
**object** root, whereas a **menu-bar** document has an **array** root.

The library builds menu *structure* (titles, shortcuts, grouping, placement);
the **host** supplies the action wiring for each item through an injected item
builder. ActionUI's own app host routes a Button's `actionID` to its action
model; other hosts wire items their own way. The engine therefore reads only the
structural properties below and leaves any host-specific properties to the host.

---

## 1. The standard bar (always present)

Before any JSON is applied, this bar is installed. The JSON layers on top of it.

| Menu | Default items |
|------|---------------|
| **App** (process / bundle name) | About, Settings…¹, Services ▸, Hide, Hide Others, Show All, Quit |
| **File** | New, Open…, Close |
| **Edit** | Undo, Redo, Cut, Copy, Paste, Delete, Select All |
| **Format** | Font ▸ (Show Fonts, Bold, Italic, Underline, Bigger, Smaller, Kern ▸, Ligatures ▸, Baseline ▸, Show Colors, Copy/Paste Style), Text ▸ (Align Left/Center/Justify/Right, Writing Direction ▸, Show/Copy/Paste Ruler) |
| **Window** | Minimize, Zoom, Bring All to Front |
| **Help** | `<App>` Help |

¹ The App menu also carries empty *sentinel* separators that mark regions for
`CommandGroup` placement (see §4). All default items use standard
first-responder selectors, so they are enabled when something in the responder
chain handles them and disabled otherwise.

The standard File menu does **not** include an "Open Recent" submenu: AppKit only
auto-populates that submenu for nib-based menus, and a programmatic submenu stays
empty unless a host drives it. A host that wants Open Recent builds and maintains
it itself.

---

## 2. Document structure

A menu-bar document is a **JSON array** of *menu-bar elements*:

```json
[
  { "type": "CommandMenu", "properties": { "name": "Tools" }, "children": [ /* Button | Divider */ ] },
  { "type": "CommandGroup", "properties": { "placement": "after", "placementTarget": "newItem" }, "children": [ /* … */ ] },
  { "type": "RemoveMenu", "properties": { "name": "Format" } },
  { "type": "RemoveItem", "properties": { "menu": "File", "title": "New" } }
]
```

Elements are applied in array order. The four top-level element types are:

| Type | Purpose |
|------|---------|
| [`CommandMenu`](#3-commandmenu) | Add a new top-level menu (inserted before Window). |
| [`CommandGroup`](#4-commandgroup) | Insert/replace items inside an existing menu at a named region. |
| [`RemoveMenu`](#5-removemenu) | Delete a whole top-level menu by title. |
| [`RemoveItem`](#6-removeitem) | Delete a single item by title. |

`Button` and `Divider`/`Separator` are the only valid **children** of
`CommandMenu` and `CommandGroup` (see [§7](#7-children-button--divider)).

---

## 3. CommandMenu

Adds a new top-level menu, inserted before the Window menu (or Help if no Window
menu is present).

```json
{
  "type": "CommandMenu",
  "properties": { "name": "Tools" },
  "children": [
    { "type": "Button", "properties": { "title": "Run Report", "actionID": "tools.report",
        "keyboardShortcut": { "key": "r", "modifiers": ["command", "shift"] } } },
    { "type": "Divider" }
  ]
}
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `name` | string | yes | Non-empty menu title shown in the menu bar. |

A host may define additional properties on a `CommandMenu` to drive behaviour the
engine doesn't model (for example, populating the menu's items dynamically at
launch rather than from `children`). The engine ignores properties it doesn't
consume, so such host extensions pass through untouched.

See also [Schemas/CommandMenu.md](Schemas/CommandMenu.md).

---

## 4. CommandGroup

Inserts items into — or replaces a region of — an **existing** menu, located by a
named sentinel (`placementTarget`) and a `placement`.

```json
{
  "type": "CommandGroup",
  "properties": { "placement": "replacing", "placementTarget": "newItem" },
  "children": [
    { "type": "Button", "properties": { "title": "New Window", "actionID": "win.new",
        "keyboardShortcut": { "key": "n" } } }
  ]
}
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `placement` | string | no | `"replacing"`, `"before"`, or `"after"`. Default `"after"`. |
| `placementTarget` | string | no | A region name (below). Default `"help"`. |

### placementTarget regions

Grouped by the menu they belong to:

- **App** — `appInfo`, `appSettings`, `systemServices`, `appVisibility`, `appTermination`
- **File** — `newItem`, `saveItem`, `importExport`, `printItem`
- **Edit** — `undoRedo`, `pasteboard`, `textEditing`, `textFormatting`
- **Window** — `windowSize`, `windowArrangement`, `windowList`, `singleWindowList`
- **Help** — `help`
- **View** — `toolbar`, `sidebar` *(the standard bar has no View menu; these fall back to a positional heuristic and warn if no View menu exists)*

`placement` relative to the sentinel:
- `"after"` — insert the children just after the region marker (most common).
- `"before"` — insert just before it.
- `"replacing"` — remove the sentinel and put the children in its place.

See also [Schemas/CommandGroup.md](Schemas/CommandGroup.md).

---

## 5. RemoveMenu

Deletes a whole top-level menu by its title. Use it to pare the standard bar down
to what an app needs.

```json
{ "type": "RemoveMenu", "properties": { "name": "Format" } }
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `name` | string | yes | Title of the top-level menu to remove (e.g. `"Format"`). |

---

## 6. RemoveItem

Deletes a single item by title, optionally scoped to one menu.

```json
{ "type": "RemoveItem", "properties": { "menu": "File", "title": "New" } }
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `title` | string | yes | Title of the item to remove (e.g. `"New"`). |
| `menu` | string | no | Restrict the search to this top-level menu (e.g. `"File"`). When omitted, the first match across all menus is removed. |

---

## 7. Children: Button & Divider

Only `CommandMenu` and `CommandGroup` take children, and only these two types:

### Button

```json
{ "type": "Button", "properties": {
    "title": "Save As…",
    "actionID": "file.saveAs",
    "keyboardShortcut": { "key": "s", "modifiers": ["command", "shift"] }
} }
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `title` | string | yes | Menu item title. |
| `actionID` | string | host | Action identifier the host dispatches when the item is chosen. |
| `keyboardShortcut` | object | no | See below. |

The engine fills in the item's title and shortcut; the **host** turns the action
identifier into a wired menu item. The ActionUI app host uses `actionID`; a host
that routes items differently may read its own property instead. Provide whatever
identifier your host expects.

### keyboardShortcut

```json
"keyboardShortcut": { "key": "r", "modifiers": ["command", "shift"] }
```

- `key` — a single character (`"a"`), or a named key: `return`/`enter`, `tab`,
  `space`, `escape`, `delete`/`backspace`, `deleteForward`, the arrows
  (`upArrow`…), `home`, `end`, `pageUp`, `pageDown`, `f1`–`f12`.
- `modifiers` — array of `"command"`, `"shift"`, `"option"`, `"control"`,
  `"capsLock"`. Defaults to `["command"]` when omitted.

### Divider

```json
{ "type": "Divider" }
```

`"Separator"` is accepted as a synonym.

---

## 8. Examples

### Add a Tools menu

```json
[
  { "type": "CommandMenu", "properties": { "name": "Tools" },
    "children": [
      { "type": "Button", "properties": { "title": "Run Report", "actionID": "tools.report" } }
    ] }
]
```

### Add items after File ▸ New, drop the Format menu

```json
[
  { "type": "CommandGroup", "properties": { "placement": "after", "placementTarget": "newItem" },
    "children": [
      { "type": "Button", "properties": { "title": "Import…", "actionID": "file.import" } },
      { "type": "Divider" }
    ] },
  { "type": "RemoveMenu", "properties": { "name": "Format" } }
]
```

### Minimal bar (no MainMenu.json)

Ship no `MainMenu.json` at all — the app launches with the standard bar unchanged.

---

## 9. Validation & preview

- **Validate**: the ActionUI verifier (`Tools/verifier/validate_actionui.py`)
  detects an array root and validates it as a menu-bar document — element types,
  required properties, and `CommandMenu`/`CommandGroup` children. Exit code `0`
  (valid), `1` (errors), `2` (warnings).
- **Preview**: a menu bar is not a view, so it cannot be rendered by
  `ActionUIViewer`.

---

## 10. Notes & limits

- Elements apply in array order; removals act on the standard bar, so order among
  unrelated elements rarely matters.
- Removal matches by **title**, so it tracks the title the engine assigns (e.g.
  `"New"`). Keep this in mind if a host relabels default items.
- A full-custom bar (defining every top-level menu from scratch) is not
  expressible; the model is "standard bar + add / modify / remove".
