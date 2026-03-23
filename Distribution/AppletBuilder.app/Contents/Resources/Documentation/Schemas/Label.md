# ActionUI.Label

JSON schema and usage documentation for `Label`.

```jsonc
// Sources/Views/Label.swift
// JSON specification for ActionUI.Label:
 {
   "type": "Label",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Title",    // Optional: String for title text, defaults to ""
     "systemImage": "star.fill", // Optional: String for SF Symbol, defaults to nil
     "imageName": "customIcon" // Optional: String for asset catalog image, defaults to nil
   }
   // Note: These properties are specific to Label. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
