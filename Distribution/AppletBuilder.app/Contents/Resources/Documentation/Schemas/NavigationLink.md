# ActionUI.NavigationLink

JSON schema and usage documentation for `NavigationLink`.

```jsonc
// Sources/Views/NavigationLink.swift
// JSON specification for ActionUI.NavigationLink:
// Form 1: Inline destination view (destination provided with the link)
 {
   "type": "NavigationLink",
   "id": 1,
   "destination": {      // Optional: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["destination"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "title": "Go to Detail" // Optional: String for title, defaults to "Link" in buildView
   }
 }

// Form 2: Destination by reference (views declared in parent NavigationStack's "destinations")
 {
   "type": "NavigationLink",
   "id": 1,
   "properties": {
     "title": "Go to Detail", // Optional: String for title, defaults to "Link" in buildView
     "destinationViewId": 10  // Base View property (Int): identifies the push target in NavigationStack.
                              // Ignored when an inline "destination" view is provided.
   }
 }

 // Note: "destinationViewId" is a base View property validated by View.validateProperties.
 // NavigationLink uses it specifically to create SwiftUI.NavigationLink(title, value: destinationViewId)
 // for push-based navigation inside NavigationStack.
 // The same property is also used by sidebar List children in NavigationSplitView to select a destination view.
 // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
```
