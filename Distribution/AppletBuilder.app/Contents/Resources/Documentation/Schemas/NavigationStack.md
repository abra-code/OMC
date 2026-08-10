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

// Persistent toolbar: items that stay in the bar on every screen inside the stack
// (the root and every pushed destination), rather than only on the screen that declares them.
// Same ToolbarItem / ToolbarItemGroup shapes as the per-screen "toolbar" key, and they
// compose with it - a destination's own items and the persistent ones share one bar.
 {
   "type": "NavigationStack",
   "id": 1,
   "persistentToolbar": [
     { "type": "ToolbarItem", "id": 16, "properties": { "placement": "topBarTrailing" },
       "content": { "type": "Image", "id": 17, "properties": { "systemName": "arrow.clockwise" } } }
   ],
   "content": { ... },
   "destinations": [ ... ]
 }
 // A "toolbar" declared on the NavigationStack itself is a DEPRECATED ALIAS for
 // "persistentToolbar"; it still works and logs a one-time warning. It was never a SCREEN
 // toolbar: macOS put it in the shared window toolbar, where it already persisted, and iOS
 // rendered it nowhere unless the stack was nested inside another navigation container, in
 // which case it surfaced in the OUTER bar. That last case is the one this changes - those
 // items now appear on every screen inside this stack instead of on the screen outside it.
 // To give only the root screen a toolbar, declare it on "content". There is no
 // per-destination opt-out: set "hidden" on the item's CONTENT to blank it - note that hides the
 // content without reclaiming the slot, so it still counts against the bar's space.
 // Implemented on all four hosts. On the web, persistent items authored "secondaryAction" get their
 // own overflow menu rather than joining the screen's, so a document using that placement on BOTH
 // a screen and its container shows two "..." menus there where Apple shows one.

 // Observable state (via getElementState / setElementState):
 //   states["navigationPath"]  [Int]   Current navigation path as array of destination IDs.
 //                                     Empty when at root. Write to push/pop programmatically:
 //                                     setElementState(windowUUID:, viewID:, key: "navigationPath", value: [destId])

 // Note: These properties are specific to NavigationStack. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
```
