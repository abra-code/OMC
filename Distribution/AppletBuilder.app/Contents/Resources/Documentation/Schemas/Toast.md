# ActionUI.Toast / Snackbar

JSON schema and usage documentation for the window-level `toast` (snackbar) presentation.

A toast is a transient, auto-dismissing message pinned at the top of the window content, optionally
with one inline action button (e.g. "Undo"). On Apple platforms it follows the native
transient-banner idiom (notification-style banners slide in from the top on iOS/macOS); the Android
renderer uses the bottom Material-snackbar placement. Like `alert` and `presentModal`, it is always
**Tier 2 (window-level)**: it is data-driven (message + optional action + duration) and has no view
sub-tree to declare in JSON. There is no subview key variant; it is always triggered programmatically
from action handlers.

The framework owns the cross-cutting details that are easy to get wrong per-host:

- Top / safe-area pinning and deterministic z-order (rendered as a top overlay on the window root by
  `WindowModalView` -> `ToastOverlayView`).
- The auto-dismiss timer.
- Coalescing / queueing of rapid posts (toasts are shown one at a time, in order).
- A VoiceOver / TalkBack announcement so the toast is conveyed non-visually.
- Reduce-motion: the slide-in transition collapses to a plain fade when Reduce Motion is on.

```swift
// Sources/Common/ActionUIModel.swift, Common/ToastOverlayView.swift, Common/WindowModalView.swift
```

---

## Present a toast

```swift
// Simple message, default 4.0s auto-dismiss
ActionUISwift.presentToast(
    windowUUID: uuid,
    message: "Logged Evening meds"
)

// With a custom duration and one inline action button
ActionUISwift.presentToast(
    windowUUID: uuid,
    message: "Logged Evening meds",
    duration: 5.0,             // Optional, defaults to 4.0
    actionTitle: "Undo",       // Optional; pass together with actionID
    actionID: "task.undo"      // Fired when the inline button is tapped (then the toast dismisses)
)
```

`actionTitle` and `actionID` must be supplied together to add an inline action; supplying only one
yields a message-only toast.

---

## Queueing

If a toast is already visible, the next `presentToast` call is queued and shown after the current one
dismisses. This coalesces rapid posts into an ordered sequence rather than stacking or clobbering.

```swift
ActionUISwift.presentToast(windowUUID: uuid, message: "Logged Morning meds",   duration: 2.0)
ActionUISwift.presentToast(windowUUID: uuid, message: "Logged Afternoon meds", duration: 2.0) // queued
ActionUISwift.presentToast(windowUUID: uuid, message: "Logged Evening meds",   duration: 2.0) // queued
```

---

## Dismiss

```swift
// Dismiss the current toast and promote the next queued toast if any.
// The auto-dismiss timer and the inline action button call this for you.
ActionUISwift.dismissToast(windowUUID: uuid)
```

---

## Common patterns

### Confirm a logged action with an Undo affordance

```swift
ActionUISwift.registerActionHandler(actionID: "task.markDone") { _, uuid, _, _, _ in
    // ... log the completion first (the toast is progressive enhancement, not a dependency) ...
    ActionUISwift.presentToast(
        windowUUID: uuid,
        message: "Logged Evening meds",
        actionTitle: "Undo",
        actionID: "task.undo"
    )
}

ActionUISwift.registerActionHandler(actionID: "task.undo") { _, uuid, _, _, _ in
    // ... revert the completion ...
}
```

### Brief confirmation from a background callback

```swift
ActionUISwift.registerActionHandler(actionID: "sync.completed") { _, uuid, _, _, _ in
    ActionUISwift.presentToast(windowUUID: uuid, message: "All changes synced")
}
```

---

## Notes

- The toast is a progressive enhancement: log/commit the underlying action before showing the toast
  so the core path never depends on it.
- No ViewModels are allocated for a toast; its content is a message, a duration, and an optional
  `ToastAction(title:actionID:)`.
