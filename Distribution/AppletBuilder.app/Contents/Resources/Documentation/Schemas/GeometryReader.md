# ActionUI.GeometryReader

JSON schema and usage documentation for `GeometryReader`.

```jsonc
// Sources/Views/GeometryReader.swift
// JSON specification for ActionUI.GeometryReader:
 {
   "type": "GeometryReader",
   "id": 1,              // Required: Non-zero positive integer (size is reported via states on this model)
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Content" }
   },
   "properties": {
     "alignment": "center"  // Optional: Content alignment — "topLeading" (SwiftUI default), "center", "top",
                             //   "bottom", "leading", "trailing", "topTrailing", "bottomLeading", "bottomTrailing".
   }
   // Behavior: GeometryReader is a greedy container — it expands to fill all available space offered by its parent.
   // SwiftUI default alignment is .topLeading (not .center like most containers).
   // As a subview of HStack/VStack, it consumes all remaining flexible space, pushing siblings to their minimum size.
   // Note: These properties are specific to GeometryReader. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   states["size"]  [Double, Double]   Container width and height as [width, height].
//                                      Updated when the container's size changes.
//                                      Read via getElementState(windowUUID:, viewID:, key: "size").
```
