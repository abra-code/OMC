# ActionUI.ZStack

JSON schema and usage documentation for `ZStack`.

```jsonc
// Sources/Views/ZStack.swift
// JSON specification for ActionUI.ZStack:
 {
   "type": "ZStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "alignment": "center" // Optional: String ("topLeading", "top", "topTrailing", "leading", "center", "trailing", "bottomLeading", "bottom", "bottomTrailing")
   },
   "children": [         // Static children — mutually exclusive with "template"
     { "type": "Text", "properties": { "text": "Background" } },
     { "type": "Text", "properties": { "text": "Foreground" } }
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
   // Note: The alignment property is specific to ZStack. Baseline View properties (padding, hidden,
   // foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //
   // "actionID" is the exception. A ZStack carrying one becomes tappable as a WHOLE - the
   // rich-cell idiom: one tap target for an avatar + name + status line, instead of a small
   // Button wedged inside the cell. It is wired by ContainerAction.apply
   // (Helpers/ContainerActionHelper.swift), called from ActionUIRegistry.applyViewModifiers
   // AFTER the baseline modifiers, so the target covers the container's FINAL box - frame,
   // padding and background included. Inside a template row it dispatches with the owning
   // container's id as viewID and the row index as viewPartID, exactly as a Button in that
   // row does; outside one, with its own id and viewPartID 0. The innermost action wins: a
   // nested Button, a nested tappable container, or an enclosing List row's selection never
   // fire alongside it. The cell is also announced as a single button to VoiceOver. A blank
   // actionID is ignored, and a disabled container (or one inside a disabled ancestor) is
   // inert.
 }
```