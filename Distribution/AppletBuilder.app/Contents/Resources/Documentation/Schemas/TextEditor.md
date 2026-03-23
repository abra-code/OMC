# ActionUI.TextEditor

JSON schema and usage documentation for `TextEditor`.

```jsonc
// Sources/Views/TextEditor.swift
// JSON specification for ActionUI.TextEditor:
 {
   "type": "TextEditor",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Initial content",        // Optional: String initial value, defaults to ""
     "placeholder": "Enter text here", // Optional: String, no default value if omitted or empty
     "readOnly": false                 // Optional: Boolean; when true, text is selectable and scrollable but not editable. Defaults to false.
                                       //   Unlike "disabled" (which prevents all interaction including selection and scrolling),
                                       //   "readOnly" allows the user to select, scroll, and copy text but not modify it.
                                       //   Content can still be set programmatically via setElementValue.
   }
   // Note: These properties are specific to TextEditor. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   value (String)   Current text content of the editor (via getElementValue / setElementValue).
```
