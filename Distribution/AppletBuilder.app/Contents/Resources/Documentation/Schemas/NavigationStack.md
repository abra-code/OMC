# ActionUI.NavigationStack

JSON schema and usage documentation for `NavigationStack`.

```jsonc
// Sources/Views/NavigationStack.swift
// JSON specification for ActionUI.NavigationStack:
// Form 1: NavigationLink-based navigation (no selection binding)
 {
   "type": "NavigationStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Home" }
   },
   "destinations": [ // Optional, needed if in "content" you placed NavigationLink(s) with destinationViewId
     { "type": "Text", "id": 10, "properties": { "text": "Destination View 10" } },
     { "type": "Text", "id": 11, "properties": { "text": "Destination View 11" } }
   ]
 }

// Form 2: Selectable List with programmatic push navigation
// When content is a List with actionID and children have destinationViewId,
// NavigationStack uses List(selection:) with path-based navigation.
// This mirrors NavigationSplitView's sidebar pattern but with push navigation.
 {
   "type": "NavigationStack",
   "id": 1,
   "content": {
     "type": "List",
     "id": 2,
     "properties": { "actionID": "navstack.list.selection.changed" },
     "children": [
       { "type": "Label", "id": 100, "properties": { "title": "Item A", "systemImage": "1.circle", "destinationViewId": 10 } },
       { "type": "Label", "id": 101, "properties": { "title": "Item B", "systemImage": "2.circle", "destinationViewId": 11 } }
     ]
   },
   "destinations": [
     { "type": "Text", "id": 10, "properties": { "text": "Detail A" } },
     { "type": "Text", "id": 11, "properties": { "text": "Detail B" } }
   ]
 }

 // Observable state (via getElementState / setElementState):
 //   states["navigationPath"]  [Int]   Current navigation path as array of destination IDs.
 //                                     Empty when at root. Write to push/pop programmatically:
 //                                     setElementState(windowUUID:, viewID:, key: "navigationPath", value: [destId])

 // Note: These properties are specific to NavigationStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
```
