# ActionUI.ZStack

JSON schema and usage documentation for `ZStack`.

```jsonc
// Sources/Views/ZStack.swift
// JSON specification for ActionUI.ZStack:
 {
   "type": "ZStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "alignment": "center" // Optional: String ("topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing")
   },
   "children": [
     { "type": "Text", "properties": { "text": "Background" } },
     { "type": "Text", "properties": { "text": "Foreground" } }
   ]
   // Note: The alignment property is specific to ZStack. Common SwiftUI.View properties (padding, hidden, foregroundColor, font, background, frame, offset, opacity, cornerRadius, actionID, disabled, accessibilityLabel, accessibilityHint, accessibilityHidden, accessibilityIdentifier, shadow) are inherited and applied via ActionUIRegistry.shared.applyModifiers (from View.applyModifiers).
 }
```
