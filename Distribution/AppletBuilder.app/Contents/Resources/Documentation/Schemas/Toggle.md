# ActionUI.Toggle

JSON schema and usage documentation for `Toggle`.

```jsonc
// Sources/Views/Toggle.swift
// JSON specification for ActionUI.Toggle:
 {
   "type": "Toggle",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "isOn": true,              // Optional: Boolean initial state, defaults to false
     "title": "Enable Feature", // Optional: String, defaults to "Toggle"
     "style": "switch",        // Optional: "switch" (iOS/macOS/visionOS), "checkbox" (macOS only), "button" (iOS/macOS/visionOS); defaults to "switch"
   }
   // Note: These properties are specific to Toggle. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (Bool)   Current on/off state of the toggle (via getElementValue / setElementValue).
```
