# ActionUI.DisclosureGroup

JSON schema and usage documentation for `DisclosureGroup`.

```jsonc
// Sources/Views/DisclosureGroup.swift
// JSON specification for ActionUI.DisclosureGroup:
 {
   "type": "DisclosureGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Details",  // Non-optional: String for the disclosure title; set to nil if invalid
     "isExpanded": true   // Optional: Boolean for initial expanded state; set to nil if invalid
   },
   "children": [
     { "type": "Text", "properties": { "text": "Content" } }
   ]
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   states["isExpanded"] Bool   true when the group is expanded, false when collapsed.
//                               Reflects user interaction; write to expand/collapse programmatically
//                               (via getElementState / setElementState).
```
