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
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "new" } },
  { "type": "CommandGroup", "properties": { "placement": "after", "placementTarget": "newItem" }, "children": [ /* … */ ] },
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "Format" } }
]
```

Elements are applied in array order. There are just two top-level element types:

| Type | Purpose |
|------|---------|
| [`CommandMenu`](#3-commandmenu) | Add a new top-level menu (inserted before Window). |
| [`CommandGroup`](#4-commandgroup) | Insert, replace, or delete — targeting a single item (by id), a SwiftUI group, or a whole top-level menu. |

`Button` and `Divider`/`Separator` are the only valid **children** of
`CommandMenu` and `CommandGroup` (see [§5](#5-children-button--divider)).

> **Deletion.** There is no separate "remove" element. To delete, use a
> `CommandGroup` with `placement: "replacing"` and **no children** — it removes
> its target: a single item (by id), a SwiftUI group, or a whole top-level menu.
> Targeting one item by id is surgical; targeting a group removes the whole group
> (see [§4](#4-commandgroup)).

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

Targets part of the standard bar and inserts, replaces, or deletes there. The
target is named by `placementTarget`; how the children relate to it is set by
`placement`.

```json
{
  "type": "CommandGroup",
  "properties": { "placement": "replacing", "placementTarget": "new" },
  "children": [
    { "type": "Button", "properties": { "title": "New Project", "actionID": "doc.new",
        "keyboardShortcut": { "key": "n" } } }
  ]
}
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `placement` | string | no | `"replacing"`, `"before"`, or `"after"`. Default `"after"`. |
| `placementTarget` | string | no | An **item id**, a **group placement**, or a **top-level menu title** — resolved in that order. Default `"help"`. |

`placement` applies to whatever the target resolves to:

- `"after"` — insert the children just after the target (most common).
- `"before"` — insert just before it.
- `"replacing"` — remove the target and put the children in its place. With **no
  children**, this deletes the target (see [§2](#2-document-structure)).

`placementTarget` is resolved in order of specificity:

### 4.1 Individual item — by id (surgical, recommended)

The way to touch exactly one default item. Every default item has a stable,
**locale-independent** id (set on the item itself — never its displayed title, so
it works in any localization). `replacing` / `before` / `after` affect **only
that item**.

```json
{ "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "new" } }
```

deletes only **New** (and leaves Open untouched). The complete set of assigned
item ids:

| Menu | Item ids |
|------|----------|
| **App** | `about`, `services`, `hide`, `hideOthers`, `showAll`, `quit` |
| **File** | `new`, `open`, `close` |
| **Edit** | `undo`, `redo`, `cut`, `copy`, `paste`, `delete`, `selectAll` |
| **Window** | `minimize`, `zoom`, `bringAllToFront` |
| **Help** | `help` |

The App menu's Settings slot has no default item (so no id — add Settings with
`after` `about`). The Format menu's Font/Text submenus aren't individually
addressable; target the whole `Format` menu by title (§4.3).

**Icon inheritance (macOS 26+).** macOS 26 shows an SF Symbol next to many
standard menu items. When you `replacing` such an item, the replacement keeps
that system icon automatically — so a custom *Help* command still shows the help
symbol. Set an explicit `systemImage` on the replacement to override it, or use
an item with no system icon (older macOS) to get none. Inheritance applies only
to single-item `replacing` (§4.1), not group (§4.2) or menu-title (§4.3) targets.

### 4.2 SwiftUI group placement — ⚠️ the WHOLE group

> **⚠️ Group placements are coarse.** A group name follows SwiftUI's
> `CommandGroupPlacement`, where a single name covers *several* items.
> `replacing` a group removes **all** of them. In particular **`newItem` is the
> New *and* Open group**, so `replacing newItem` deletes **both** — not just New.
> This is SwiftUI's (frequently surprising) behavior, kept here for parity. To
> affect one item, use its **item id** from §4.1 instead.

`placement` acts on the whole group span. Group names, with the defaults each
covers in parentheses:

- **App** — `appInfo` (About), `appSettings`, `systemServices` (Services), `appVisibility` (Hide / Hide Others / Show All), `appTermination` (Quit)
- **File** — `newItem` (New / Open), `saveItem` (Close / Save), `importExport`, `printItem`
- **Edit** — `undoRedo` (Undo / Redo), `pasteboard` (Cut / Copy / Paste / Delete / Select All), `textEditing`, `textFormatting`
- **Window** — `windowSize` (Minimize / Zoom), `windowArrangement` (Bring All to Front), `windowList`, `singleWindowList`
- **Help** — `help`
- **View** — `toolbar`, `sidebar` *(no View menu in the standard bar; falls back to a positional heuristic and warns)*

Group names with no parenthesised items (e.g. `appSettings`, `importExport`,
`printItem`, `textEditing`, `textFormatting`, `windowList`) are empty
placeholders; `after`/`before` still target them so you can add items there.
(`help` is both an item id and a group name; item-first resolution targets the
Help item — equivalent in practice, since the group holds only that item.)

### 4.3 Top-level menu — by title

When `placementTarget` is a top-level menu title, `replacing` operates on the
whole menu — **no children** deletes it; with children its items are replaced
(title kept). `before`/`after` are not supported on a menu title (use
`CommandMenu` to add one).

```json
{ "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "Format" } }
```

See also [Schemas/CommandGroup.md](Schemas/CommandGroup.md).

---

## 5. Children: Button & Divider

Only `CommandMenu` and `CommandGroup` take children, and only these two types:

### Button

```json
{ "type": "Button", "properties": {
    "title": "Save As…",
    "actionID": "file.saveAs",
    "systemImage": "square.and.arrow.down",
    "keyboardShortcut": { "key": "s", "modifiers": ["command", "shift"] }
} }
```

| Property | Type | Required | Notes |
|----------|------|----------|-------|
| `title` | string | yes | Menu item title. |
| `actionID` | string | host | Action identifier the host dispatches when the item is chosen. |
| `systemImage` | string | no | SF Symbol name for a leading icon (e.g. `"gear"`). Rendered as a template image; AppKit sizes it for the menu. |
| `keyboardShortcut` | object | no | See below. |

The engine fills in the item's title, icon, and shortcut; the **host** turns the action
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

## 6. Examples

### Add a Tools menu

```json
[
  { "type": "CommandMenu", "properties": { "name": "Tools" },
    "children": [
      { "type": "Button", "properties": { "title": "Run Report", "actionID": "tools.report" } }
    ] }
]
```

### Delete only File ▸ New (keep Open)

```json
[
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "new" } }
]
```

### Replace only New with a custom command (keep Open)

```json
[
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "new" },
    "children": [
      { "type": "Button", "properties": { "title": "New Project", "actionID": "doc.new", "keyboardShortcut": { "key": "n" } } }
    ] }
]
```

### Add items after the File ▸ New/Open group, and delete the Format menu

```json
[
  { "type": "CommandGroup", "properties": { "placement": "after", "placementTarget": "newItem" },
    "children": [
      { "type": "Button", "properties": { "title": "Import…", "actionID": "file.import" } },
      { "type": "Divider" }
    ] },
  { "type": "CommandGroup", "properties": { "placement": "replacing", "placementTarget": "Format" } }
]
```

### Minimal bar (no MainMenu.json)

Ship no `MainMenu.json` at all — the app launches with the standard bar unchanged.

---

## 7. Validation & preview

- **Validate**: the ActionUI verifier (`Tools/verifier/validate_actionui.py`)
  detects an array root and validates it as a menu-bar document — element types,
  required properties, and `CommandMenu`/`CommandGroup` children. Exit code `0`
  (valid), `1` (errors), `2` (warnings).
- **Preview**: a menu bar is not a view, so it cannot be rendered by
  `ActionUIViewer`.

---

## 8. Notes & limits

- Elements apply in array order; since each element targets an item, group, or
  menu by name, order among unrelated elements rarely matters.
- To affect **one** item, target it by **item id** (§4.1) — surgical. A **group
  placement** (§4.2) targets the whole group: `replacing newItem` affects New
  *and* Open together (SwiftUI's behavior). Item ids resolve before group names.
- Matching is by stable **id**, never the displayed title, so it is unaffected by
  localization.
- A full-custom bar (defining every top-level menu from scratch) is not
  expressible; the model is "standard bar + add / modify / replace / delete".
