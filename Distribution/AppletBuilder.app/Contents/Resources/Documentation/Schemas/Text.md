# ActionUI.Text

JSON schema and usage documentation for `Text`.

```jsonc
// Sources/Views/Text.swift
// JSON specification for ActionUI.Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!",               // Optional: String, defaults to empty string
     "markdown": "**Bold** _italic_"  // Optional: Markdown string. Rendered with markdown formatting; takes precedence over "text". Value is the markdown source string.
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
