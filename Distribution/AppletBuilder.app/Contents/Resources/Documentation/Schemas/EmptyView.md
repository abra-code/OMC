# ActionUI.EmptyView

JSON schema and usage documentation for `EmptyView`.

```jsonc
// Sources/Views/EmptyView.swift
// JSON specification for ActionUI.EmptyView:
 {
   "type": "EmptyView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {}
   // Note: EmptyView has no specific properties. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers to the group as a whole.
 }
```
