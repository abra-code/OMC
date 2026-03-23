# ActionUI.VSplitView

JSON schema and usage documentation for `VSplitView`.

```jsonc
// Sources/Views/VSplitView.swift
// JSON specification for ActionUI.VSplitView (macOS only):
 {
   "type": "VSplitView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "TextEditor", "id": 2, "properties": { "text": "Top pane" } },
     { "type": "TextEditor", "id": 3, "properties": { "text": "Bottom pane" } }
   ]
   // Note: VSplitView arranges children vertically with a draggable divider between them.
   // Use frame properties (minHeight, idealHeight, maxHeight) on children to control pane sizing.
   // On macOS, the first child's idealHeight (from its frame properties) is used to set the
   // initial divider position, working around SwiftUI.VSplitView's default 50/50 split.
   // macOS only — on other platforms, falls back to VStack.
   // Note: These properties are specific to VSplitView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
```
