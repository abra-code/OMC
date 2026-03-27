# ActionUI.ColorPicker

JSON schema and usage documentation for `ColorPicker`.

```jsonc
// Sources/Views/ColorPicker.swift
// JSON specification for ActionUI.ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Pick a Color", // Optional: String for title, defaults to empty in buildView
     "selectedColor": "#FF0000", // Optional: Initial color (hex or named color), defaults to clear in buildView
     "actionID": "colorpicker.action" // Optional: String for action identifier, triggers on color change
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)   Selected color as a hex string (e.g., "#FF0000FF") (via getElementValue / setElementValue).
//                    Write a hex or named color string to change the selected color programmatically.
```
