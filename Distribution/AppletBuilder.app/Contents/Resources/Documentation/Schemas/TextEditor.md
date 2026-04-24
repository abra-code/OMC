# ActionUI.TextEditor

JSON schema and usage documentation for `TextEditor`.

```jsonc
// Sources/Views/TextEditor.swift
// JSON specification for ActionUI.TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Initial content",              // Optional: String initial value, defaults to ""
     "markdown": "**Bold** _italic_",  // Optional: Markdown string (macOS 26, iOS 26+). Rendered with markdown formatting; takes precedence over "text". Value is the AttributedString of the current content; accepts AttributedString or markdown String via setElementValue.
     "placeholder": "Enter text here",       // Optional: String, no default value if omitted or empty
     "readOnly": false                        // Optional: Boolean; when true, text is selectable and scrollable but not editable. Defaults to false.
                                              //   Unlike "disabled" (which prevents all interaction including selection and scrolling),
                                              //   "readOnly" allows the user to select, scroll, and copy text but not modify it.
                                              //   Content can still be set programmatically via setElementValue.
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)         Current plain-text content (via getElementValue / setElementValue).
//   value (AttributedString) Current attributed content when markdown is used (macOS 26, iOS 26+). setElementValue accepts AttributedString directly or a markdown String.
```
