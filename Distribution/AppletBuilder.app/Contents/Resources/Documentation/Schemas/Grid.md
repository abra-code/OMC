# ActionUI.Grid

JSON schema and usage documentation for `Grid`.

```jsonc
// Sources/Views/Grid.swift
// JSON specification for ActionUI.Grid:
 {
   "type": "Grid",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "rows": [             // Required: Array of arrays of ActionUIElementBase objects. Note: Declared as a top-level key in JSON but stored in subviews["rows"] by ActionUIElement.init(from:).
     [
       { "type": "Text", "properties": { "text": "Cell1" } },
       { "type": "Button", "properties": { "title": "Click" } }
     ],
     [
       { "type": "Image", "properties": { "systemName": "star" } }
     ]
   ],
   "properties": {
     "alignment": "center",        // Optional: "topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing"
     "horizontalSpacing": 8.0,    // Optional: Double for horizontal spacing between columns
     "verticalSpacing": 8.0       // Optional: Double for vertical spacing between rows
   }
   // Note: These properties (alignment, horizontalSpacing, verticalSpacing) are specific to Grid. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Performance: Child ActionUIView instances leverage Equatable conformance to optimize rendering, reducing re-renders for unchanged cells in large grids.
 }
```
