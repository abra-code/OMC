# ActionUI.ScrollViewReader

JSON schema and usage documentation for `ScrollViewReader`.

```jsonc
// Sources/Views/ScrollViewReader.swift
// JSON specification for ActionUI.ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view (typically ScrollView). Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } }
   },
   "properties": {
     "scrollTo": 5,       // Optional: Integer ID to scroll to, defaults to nil
     "anchor": "top"      // Optional: "top", "center", "bottom"; defaults to "center"
   }
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
