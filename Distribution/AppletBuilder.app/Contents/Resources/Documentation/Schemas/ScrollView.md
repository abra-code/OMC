# ActionUI.ScrollView

JSON schema and usage documentation for `ScrollView`.

```jsonc
// Sources/Views/ScrollView.swift
// JSON specification for ActionUI.ScrollView:
 {
   "type": "ScrollView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view or array of views. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Scrollable content" }
   },
   "properties": {
     "axis": "vertical",  // Optional: "vertical", "horizontal", or "both"; defaults to "vertical"
     "showsIndicators": true, // Optional: Boolean for scroll indicators, defaults to true
     "onRefreshActionID": "scroll.refresh" // Optional: String. When set, enables pull-to-refresh; fires this actionID on pull. The spinner stays until the client delivers fresh data to this view or anything inside it (any setElementRows/setElementValue/setElementState call targeting this view or a descendant), or a safety timeout elapses.
   }
   // Note: These properties are specific to ScrollView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
```
