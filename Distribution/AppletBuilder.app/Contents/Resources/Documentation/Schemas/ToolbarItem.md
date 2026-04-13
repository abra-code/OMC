# ActionUI.ToolbarItem

JSON schema and usage documentation for `ToolbarItem`.

```jsonc
// Sources/Views/ToolbarItem.swift
/*
 ToolbarItem declares a single item at a specific placement in a view's toolbar or navigation
 bar. ToolbarItem elements are declared inside the "toolbar" subview array on any view, not
 rendered standalone — the parent view's .toolbar modifier, applied through View.applyModifiers,
 consumes them.

 Sample JSON for a navigation bar button (iOS trailing position):
 {
   "type": "VStack",
   "toolbar": [
     {
       "type": "ToolbarItem",
       "id": 10,                        // Optional: Non-zero positive integer
       "properties": {
         "placement": "topBarTrailing"  // Optional: placement string; defaults to "automatic"
       },
       "content": { "type": "Button", "properties": { "title": "Done", "actionID": "toolbar.done" } }
     }
   ]
 }

 Multiple ToolbarItem entries in "toolbar" create separate items at their respective placements.
 "content" is a single view — use Button, Menu, ControlGroup, Image, or any layout container
 (HStack, ZStack, etc.) when you need to compose multiple views into one toolbar slot.

 Supported placement values:
   Cross-platform:
     "automatic"          — System-chosen default placement
     "principal"          — Center of the toolbar / navigation bar (title area)
     "confirmationAction" — Platform primary confirmation action (e.g., "Done", "Save")
     "cancellationAction" — Platform cancel action (e.g., "Cancel")
     "destructiveAction"  — Platform destructive action (e.g., "Delete")
     "primaryAction"      — macOS/iPadOS primary toolbar action (leading toolbar area)
     "secondaryAction"    — Secondary toolbar action
   iOS / visionOS only:
     "topBarLeading"      — Navigation bar leading edge
     "topBarTrailing"     — Navigation bar trailing edge
     "bottomBar"          — Bottom toolbar bar
     "keyboard"           — Above the software keyboard
   macOS only:
     "navigation"         — Leading portion of the toolbar (before back/forward navigation)
     "status"             — Bottom status bar of the macOS app window

 Note: Platform-unavailable placements fall back to "automatic" at runtime without warning.
 ToolbarItem elements are never rendered standalone. Their content is built by ToolbarModifierView.
*/
```
