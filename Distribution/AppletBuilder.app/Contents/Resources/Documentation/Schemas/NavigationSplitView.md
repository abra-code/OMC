# ActionUI.NavigationSplitView

JSON schema and usage documentation for `NavigationSplitView`.

```jsonc
// Sources/Views/NavigationSplitView.swift
// JSON specification for ActionUI.NavigationSplitView:
// Form 1: Static panes (no destination switching)
 {
   "type": "NavigationSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "sidebar": {          // Required: Single child view for sidebar. Note: Declared as a top-level key in JSON but stored in subviews["sidebar"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "content": {          // Optional: Single child view for content (3-pane). Note: Declared as a top-level key in JSON but stored in subviews["content"].
     "type": "Text", "properties": { "text": "Content" }
   },
   "detail": {           // Required: Single child view for detail. Note: Declared as a top-level key in JSON but stored in subviews["detail"].
     "type": "Text", "properties": { "text": "Detail" }
   },
   "properties": {
     "columnVisibility": "all", // Optional: "automatic", "all", "doubleColumn", "detail"; defaults to "all"
     "style": "balanced" // Optional: "automatic", "balanced", "prominentDetail"; defaults to "automatic"
   }
 }

// Form 2: Selection-driven destination switching (2-pane)
// The sidebar must be a List whose children have a "destinationViewId" property
// linking them to destination views by id. All element ids must be unique.
// Selecting a child in the sidebar shows the corresponding destination in the detail pane.
 {
   "type": "NavigationSplitView",
   "id": 1,
   "sidebar": {
     "type": "List",
     "id": 2,
     "properties": { "actionID": "sidebar.selection.changed" },
     "children": [
       { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
       { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
     ]
   },
   "detail": {
     "type": "Text", "properties": { "text": "Select an item" }
   },
   "destinations": [
     { "type": "VStack", "id": 10, "children": [ ... ] },
     { "type": "VStack", "id": 11, "children": [ ... ] }
   ]
 }
 // Note: Sidebar children link to destinations via "destinationViewId" in properties.
 // NavigationLink is NOT needed in the sidebar for NavigationSplitView.
 // Use NavigationLink only inside NavigationStack for push-based navigation.

 // Note: These properties are specific to NavigationSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).

// Observable state (via getElementState / setElementState):
//   states["columnVisibility"]     String  Current column visibility: "automatic", "all", "doubleColumn", or
//                                          "detail". Updated on user interaction; write to change programmatically.
//   states["selectedDestination"]  Int?    Currently selected destination ID (matches a destination element's id).
//                                          nil when no destination is selected. Write to change programmatically.
```
