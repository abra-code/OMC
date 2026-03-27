# ActionUI.Popover

JSON schema and usage documentation for the `popover` modifier.

The `popover` modifier is not a standalone view — it is a baseline View modifier attachable to any element. When present, a floating popover anchored to the element is shown or hidden based on the `popoverVisible` state.

```jsonc
// Sources/Views/View.swift, Helpers/PopoverHelper.swift
// JSON specification for the popover modifier:
 {
   "type": "Button",        // Any view type
   "id": 1,                 // Required: positive integer (used to look up ViewModel for popover state)
   "properties": {
     "title": "Show Info",
     "popoverArrowEdge": "top", // Optional: "top", "bottom", "leading", "trailing"; defaults to "top"
     "popoverActionID": "popover.shown", // Optional: action identifier triggered when the popover is shown
   },
   "popover": {             // Optional: Single child view displayed inside the popover
     "type": "Text",
     "properties": { "text": "Popover content" }
   }
   // The popover child can be any view or container (VStack, HStack, Form, etc.)

   // Note: popoverArrowEdge is a baseline View property validated in View.swift.
   // The "popover" key is a top-level JSON key stored in subviews["popover"], following the same
   // pattern as "content", "destination", "sidebar", and "detail".
 }
// Observable state:
//   states["popoverVisible"] (Bool)   Whether the popover is currently shown (via getElementState / setElementState).
//                                     Views with a "popover" subview toggle this state automatically on tap.
```
