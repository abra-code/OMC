# ActionUI.ShareLink

JSON schema and usage documentation for `ShareLink`.

```jsonc
// Sources/Views/ShareLink.swift
// JSON specification for ActionUI.ShareLink:
 {
   "type": "ShareLink",
   "id": 1,
   "properties": {
     "item": "https://example.com", // Optional: URL string, returns EmptyView if nil or invalid
     "subject": "Check this out", // Optional: String for subject, ignored if nil
     "message": "Look at this link!" // Optional: String for message, ignored if nil
   }
   // Note: These properties are specific to ShareLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
