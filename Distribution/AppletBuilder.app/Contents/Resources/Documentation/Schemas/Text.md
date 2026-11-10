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
     "markdown": "**Bold** _italic_"  // Optional: Markdown string. Rendered with markdown formatting; takes precedence over "text".
                                            //   Value is the AttributedString of the current content; accepts AttributedString or markdown String via setElementValue.
   }
   // Note: These properties are specific to Text. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used or an AttributedString is set via setElementValue.
//                            setElementValue accepts AttributedString directly or a markdown String.
//   "text" and "markdown" are the first content only: the value is set from them when the description loads, and
//   from then on the Text shows its value. To change what it shows at run time, set the value (setElementValue);
//   setting the "text" or "markdown" property afterwards changes nothing on screen.
```
