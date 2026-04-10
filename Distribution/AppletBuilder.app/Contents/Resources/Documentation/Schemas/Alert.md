# ActionUI.Alert / ActionUI.ConfirmationDialog

JSON schema and usage documentation for window-level `alert` and `confirmationDialog` presentations.

These are always **Tier 2 (window-level)** — they are data-driven (title + message + buttons) and have no view sub-tree to declare in JSON. There is no subview key variant; they are always triggered programmatically from action handlers.

```swift
// Sources/Common/ActionUIModel.swift, Common/WindowModalView.swift
```

---

## Alert

```swift
// Present a simple alert
ActionUISwift.presentAlert(
    windowUUID: uuid,
    title: "Connection Failed",
    message: "Please check your network connection.",   // Optional
    buttons: [DialogButton(title: "OK", role: .cancel)] // Optional, defaults to single "OK" button
)

// Present an alert with multiple buttons
ActionUISwift.presentAlert(
    windowUUID: uuid,
    title: "Delete Item",
    message: "This action cannot be undone.",
    buttons: [
        DialogButton(title: "Delete", role: .destructive, actionID: "item.delete.confirmed"),
        DialogButton(title: "Cancel", role: .cancel, actionID: nil)
    ]
)
```

---

## ConfirmationDialog

```swift
// Present a confirmation dialog (action sheet on iOS, menu-style on macOS)
ActionUISwift.presentConfirmationDialog(
    windowUUID: uuid,
    title: "Save changes before closing?",
    message: "Your changes will be lost if you don't save.",   // Optional
    buttons: [
        DialogButton(title: "Save",       role: nil,          actionID: "doc.save"),
        DialogButton(title: "Don't Save", role: .destructive, actionID: "doc.discard"),
        DialogButton(title: "Cancel",     role: .cancel,      actionID: nil)
    ]
)
```

---

## Dismiss

```swift
// Dismiss programmatically (SwiftUI does this automatically when a button is tapped)
ActionUISwift.dismissDialog(windowUUID: uuid)
```

---

## DialogButton

```swift
public struct DialogButton {
    public let title: String        // Button label
    public let role: ButtonRole?    // nil = default, .destructive, .cancel
    public let actionID: String?    // Action fired on tap; nil = dismiss only
}
```

| `role` | Appearance | Notes |
|---|---|---|
| `nil` | Default button | Normal prominence |
| `.cancel` | Cancel | Appears last; bold on iOS |
| `.destructive` | Destructive | Red tint |

---

## Common patterns

### Error handling from a background callback

```swift
ActionUISwift.registerActionHandler(actionID: "data.loadFailed") { _, uuid, _, _, context in
    let message = context as? String ?? "Unknown error"
    ActionUISwift.presentAlert(
        windowUUID: uuid,
        title: "Load Failed",
        message: message
    )
}
```

### Confirmation before destructive action

```swift
ActionUISwift.registerActionHandler(actionID: "list.deleteRow") { _, uuid, _, _, _ in
    ActionUISwift.presentConfirmationDialog(
        windowUUID: uuid,
        title: "Delete this item?",
        buttons: [
            DialogButton(title: "Delete", role: .destructive, actionID: "list.deleteRow.confirmed"),
            DialogButton(title: "Cancel", role: .cancel)
        ]
    )
}
```

### Button action wired to confirmation result

```swift
ActionUISwift.registerActionHandler(actionID: "list.deleteRow.confirmed") { _, uuid, _, _, _ in
    // perform actual deletion
}
```
