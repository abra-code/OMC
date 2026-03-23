# ActionUI.Group

JSON schema and usage documentation for `Group`.

```jsonc
// Sources/Views/Group.swift
// JSON specification for ActionUI.Group:
 {
   "type": "Group",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: Group has no specific properties and does not control layout geometry, relying on the parent container for alignment and spacing. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are supported and applied via ActionUIRegistry.shared.applyModifiers to the group as a whole.
 }
```
