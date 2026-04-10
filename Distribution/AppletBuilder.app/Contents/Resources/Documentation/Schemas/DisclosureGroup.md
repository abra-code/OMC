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
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
     "type": "Text",
     "properties": { "text": "$1" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  — column 0 (first column, 1-based)
   //   $2  — column 1 (second column, 1-based)
   //   $N  — column N-1
   //   $0  — all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   // states["content"] ([[String]]) holds the current rows.
   //
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden,
   // foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
// Observable state:
//   states["isExpanded"] Bool   true when the group is expanded, false when collapsed.
//                               Reflects user interaction; write to expand/collapse programmatically
//                               (via getElementState / setElementState).
//   states["content"]  [[String]]   All items in template mode; each inner array holds the item string and any optional
//                               hidden-column data. Access via getElementRows / setElementRows /
//                               appendElementRows / clearElementRows.
```