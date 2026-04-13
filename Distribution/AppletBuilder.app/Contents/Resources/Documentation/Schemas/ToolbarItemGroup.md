# ActionUI.ToolbarItemGroup

JSON schema and usage documentation for `ToolbarItemGroup`.

```jsonc
// Sources/Views/ToolbarItemGroup.swift
/*
 ToolbarItemGroup declares a group of related items at a specific placement in a view's
 toolbar or navigation bar. Like ToolbarItem, it lives inside the "toolbar" subview array
 and is never rendered standalone — the parent view's .toolbar modifier consumes it.

 The key difference from ToolbarItem: SwiftUI's ToolbarItemGroup renders multiple children
 with platform-appropriate spacing and overflow behavior, rather than leaving layout to the
 content view. Prefer ToolbarItemGroup when placing two or more related controls at the same
 placement (e.g., a pair of Edit/Add buttons in topBarTrailing).

 Sample JSON for two trailing buttons grouped at the same placement:
 {
   "type": "VStack",
   "toolbar": [
     {
       "type": "ToolbarItemGroup",
       "id": 10,                         // Optional: Non-zero positive integer
       "properties": {
         "placement": "topBarTrailing"   // Optional: placement string; defaults to "automatic"
       },
       "children": [
         { "type": "Button", "properties": { "title": "Edit",  "actionID": "toolbar.edit"  } },
         { "type": "Button", "properties": { "title": "Share", "actionID": "toolbar.share" } }
       ]
     }
   ]
 }

 For a single control, prefer ToolbarItem. For two or more controls at the same placement,
 ToolbarItemGroup lets the system manage grouping and spacing.

 Supported placement values are identical to ToolbarItem — see ToolbarItem.swift for the full list.
 Platform-unavailable placements fall back to "automatic" at runtime without warning.
 ToolbarItemGroup elements are never rendered standalone. Their content is built by ToolbarModifierView.
*/
```
