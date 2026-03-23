# ActionUI.Menu

JSON schema and usage documentation for `Menu`.

```jsonc
// Sources/Views/Menu.swift
// JSON specification for ActionUI.Menu:
 {
   "type": "Menu",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Options",  // Optional: String for title, defaults to "Menu"
   },
   "children": [
     { "type": "Button", "properties": { "title": "Option 1" } }
   ] // Required: Array of child views (typically Buttons)
   // Children can include Divider and Section to organize menu items:
   //   { "type": "Divider" }                                                          — visual separator line
   //   { "type": "Section", "properties": { "header": "Group" }, "children": [...] }  — named group with header

   // Note: These properties are specific to Menu. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
