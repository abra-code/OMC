# ActionUI.Link

JSON schema and usage documentation for `Link`.

```jsonc
// Sources/Views/Link.swift
// JSON specification for ActionUI.Link:
 {
   "type": "Link",
   "id": 1,
   "properties": {
     "title": "Visit Site", // Optional: String for title, defaults to "Link" in buildView
     "url": "https://example.com" // Optional: URL string, returns EmptyView if nil or invalid
                          // (as Apple's URL(string:) reads it: not trimmed, so " https://example.com" is invalid).
                          // A URL without a scheme ("example.com", "docs/page") shows a link that opens nothing.
                          // The same on every platform; the web also opens nothing for javascript:, vbscript: and data:.
   }
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
