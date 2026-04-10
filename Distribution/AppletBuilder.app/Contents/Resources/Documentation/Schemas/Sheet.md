# ActionUI.Sheet / ActionUI.FullScreenCover

JSON schema and usage documentation for the `sheet` and `fullScreenCover` modifiers, and the window-level `presentModal` API.

Both modifiers follow the same two-tier design:

- **Tier 1 (view-attached):** Declare content as a subview key — same pattern as `popover`. Open via `setElementState`.
- **Tier 2 (window-level):** Load any JSON at runtime via `ActionUIModel.presentModal(windowUUID:data:format:style:)` — fully decoupled from the element tree.

`fullScreenCover` is iOS-only; on macOS it falls back to `.sheet` transparently.

---

## Tier 1 — View-Attached (subview key)

```jsonc
// Sources/Views/View.swift, Helpers/SheetHelper.swift
{
  "type": "Button",           // Any view type; Button opens the sheet on tap automatically
  "id": 1,                    // Required: positive integer — needed for setElementState calls
  "properties": {
    "title": "Open Sheet",
    "sheetOnDismissActionID": "sheet.dismissed"  // Optional: fires when sheet is dismissed
  },
  "sheet": {                  // Optional: declares sheet content (any view or container)
    "type": "VStack",
    "children": [
      { "type": "Text", "properties": { "text": "Sheet content" } }
    ]
  }
}

// fullScreenCover works identically — use "fullScreenCover" key and "fullScreenCoverOnDismissActionID"
{
  "type": "Button",
  "id": 2,
  "properties": {
    "title": "Go Full Screen",
    "fullScreenCoverOnDismissActionID": "cover.dismissed"
  },
  "fullScreenCover": {
    "type": "Text",
    "properties": { "text": "Full screen content" }
  }
}

// Observable states (read/write via getElementState / setElementState):
//   states["sheetVisible"]            (Bool) — true = sheet shown
//   states["fullScreenCoverVisible"]  (Bool) — true = cover shown

// To open programmatically from any action handler:
//   ActionUISwift.setElementState(windowUUID: uuid, viewID: 1, key: "sheetVisible", value: true)
//
// To dismiss programmatically:
//   ActionUISwift.setElementState(windowUUID: uuid, viewID: 1, key: "sheetVisible", value: false)
```

### Button behavior

When a `Button` element declares a `sheet` or `fullScreenCover` subview, tapping the button automatically sets `sheetVisible = true` / `fullScreenCoverVisible = true`. This mirrors the popover toggle on Button.

### Properties (Tier 1)

| Property | Type | Default | Description |
|---|---|---|---|
| `sheetOnDismissActionID` | String | — | Action fired when the sheet is dismissed |
| `fullScreenCoverOnDismissActionID` | String | — | Action fired when the full-screen cover is dismissed |

---

## Tier 2 — Window-Level (programmatic)

No JSON declaration needed. Call from any action handler, background callback, or code path:

```swift
// Present a sheet with JSON loaded from any source
let jsonData = try Data(contentsOf: settingsURL)
try ActionUISwift.presentModal(
    windowUUID: uuid,
    data: jsonData,
    format: "json",         // "json" or "plist"
    style: .sheet,          // .sheet or .fullScreenCover
    onDismissActionID: "settings.closed"   // Optional
)

// Dismiss the active modal (also fires onDismissActionID)
ActionUISwift.dismissModal(windowUUID: uuid)
```

The modal's ViewModels are registered in the window's pool on `presentModal` and automatically removed on `dismissModal`. The `WindowModalView` wrapper (applied to the window root by `FileLoadableView` / `RemoteLoadableView` when `isContentView == true`) renders the modal and handles the SwiftUI binding lifecycle.
