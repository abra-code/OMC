# ActionUI.View

JSON schema and usage documentation for `View`.

```jsonc
// Sources/Views/View.swift
// JSON specification for ActionUI.View (base structure for all views):
 {
   "type": "View",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "padding": 10.0,      // Optional: Double for padding around the view, string "default" or EdgeInsets dictionary {"top": 10, "bottom": 10, "leading": 5, "trailing": 5}
     "hidden": false,      // Optional: Boolean to hide the view
     "foregroundStyle": "blue", // Optional: SwiftUI color (e.g., "red", "blue") or semantic style for text/content tint, resolved via foregroundStyle
     "font": "body",       // Optional: String for named text style (e.g., "title", "body") or font name (e.g., "Menlo"),
                           //   or dictionary: { "name": "Menlo", "size": 12, "weight": "bold", "design": "monospaced" }
                           //   "name" (String, optional): font family name; omit for system font
                           //   "size" (Number, required for dict form): point size
                           //   "weight" (String, optional): ultraLight/thin/light/regular/medium/semibold/bold/heavy/black
                           //   "design" (String, optional): default/monospaced/rounded/serif
     "background": "white", // Optional: SwiftUI color (e.g., "red", "blue"), hex (e.g., "#FF0000"), or semantic style for background, resolved via background
     "frame": {            // Optional: Dictionary defining view size, supports two mutually exclusive forms
       // Fixed Frame Form:
       "width": 100.0,     // Optional: Double for fixed width
       "height": 100.0,    // Optional: Double for fixed height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"), defaults to "center"
       // OR Flexible Frame Form:
       "minWidth": 50.0,   // Optional: Double for minimum width
       "idealWidth": 100.0, // Optional: Double for ideal width
       "maxWidth": 200.0,  // Optional: Double for maximum width
       "minHeight": 50.0,  // Optional: Double for minimum height
       "idealHeight": 100.0, // Optional: Double for ideal height
       "maxHeight": 200.0, // Optional: Double for maximum height
       "alignment": "center" // Optional: String ("leading", "center", "trailing", "top", "bottom", "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"), defaults to "center"
     },
     "offset": {           // Optional: Dictionary for relative positioning
       "x": 10.0,          // Optional: Double for horizontal offset
       "y": -5.0           // Optional: Double for vertical offset
     },
     "opacity": 1.0,       // Optional: Double (0.0 to 1.0) for view transparency
     "cornerRadius": 5.0,  // Optional: Double for rounded corners
     "actionID": "view.action", // Optional: String for action identifier
     "valueChangeActionID": "view.valueChanged", // Optional: String for action triggered on any value change initiated by user
     "openURLActionID": "view.openURL", // Optional: String for action identifier triggered on open URL (via .onOpenURL modifier)
     "onAppearActionID": "view.onAppear", // Optional: String for action identifier triggered on view appear (via .onAppear modifier)
     "onDisappearActionID": "view.onDisappear", // Optional: String for action identifier triggered on view disappear (via .onDisappear modifier)
     "keyboardShortcut": { // Optional: Dictionary for keyboard shortcut, supports key with array of modifiers
       "key": "a",         // Required: String for KeyEquivalent (single character like "a" or special key like "return", "space", "upArrow")
       "modifiers": ["command", "shift"] // Optional: Array of strings for modifiers (e.g., ["command", "shift"]), defaults to ["command"], must contain unique elements
     },
     "buttonStyle": "automatic", // Optional: "automatic", "plain", "borderless", "bordered", "borderedProminent"; defaults to "automatic".
                                // Applicable to Button, Menu, Link, NavigationLink. On container views (VStack, HStack, List, Form, etc.) the style propagates to all buttons inside.
     "controlSize": "regular", // Optional: "mini", "small", "regular", "large", "extraLarge"; no default (system default)
     "labelsHidden": true,  // Optional: Boolean to hide labels on child views (e.g., within LabeledContent/Form); defaults to false
     "disabled": false,     // Optional: Boolean to disable user interaction
     "accessibilityLabel": "View", // Optional: Accessibility label for VoiceOver
     "accessibilityHint": "Base view", // Optional: Accessibility hint for VoiceOver
     "accessibilityHidden": false, // Optional: Boolean to hide view from VoiceOver
     "accessibilityIdentifier": "view_1", // Optional: String for UI testing identifier
     "shadow": {           // Optional: Dictionary for shadow styling
       "color": "black",   // Optional: SwiftUI color or hex, defaults to black
       "radius": 5.0,      // Optional: Double for shadow radius
       "x": 0.0,           // Optional: Double for x-offset
       "y": 2.0            // Optional: Double for y-offset
     },
     "border": {           // Optional: Dictionary for border styling
       "color": "blue",   // Optional: SwiftUI color or hex, defaults to black
       "width": 1.0       // Optional: Double for border width, defaults to 1.0
     },
     "navigationSplitViewColumnWidth": {     // Optional – only meaningful when this view is used as sidebar/content/detail in NavigationSplitView
       "ideal": 360.0,                       // Required: preferred column width (Double) – must be provided
       "min": 280.0,                         // Optional: minimum allowed width
       "max": 480.0                          // Optional: maximum allowed width
     },
     "navigationSplitViewColumnWidth": 400.0, // Number – fixed column width
     "navigationTitle": "Detail",            // Optional: String for navigation title (for views navigated to)
     "scrollContentBackground": "visible", // Optional: "visible" or "hidden"; controls the default background of scrollable views (List, TextEditor, Form). Defaults to "visible".
     "popoverArrowEdge": "top",             // Optional: Arrow edge for popover ("top", "bottom", "leading", "trailing"); defaults to "top". Only meaningful when "popover" subview is present.
     "popoverActionID": "view.popover",     // Optional: String for action identifier triggered when the popover is shown. Only meaningful when "popover" subview is present.
     "destinationViewId": 10,               // Optional: Int linking this view to a destination in a navigation container.
                                            // Does not apply any modifier; the value is kept in validatedProperties for navigation logic.
                                            // Used by NavigationLink (Form 2) to identify the push target in NavigationStack,
                                            // and by sidebar List children in NavigationSplitView to select a destination view.
   }
 }

//  NOTE:
//  Supported semantic styles for foregroundStyle/background:
//    - "background", "background.secondary", "background.tertiary", "background.quaternary"
//    - "foreground", "foreground.secondary", "foreground.tertiary", "foreground.quaternary"
//    - "primary", "secondary", "tertiary", "quaternary", "quinary"
//    - "fill", "fill.secondary", "fill.tertiary", "fill.quaternary"
//    - "separator", "placeholder", "link", "selection", "tint", "windowBackground"
//  Supported named colors:
//    - "red", "blue", "green", "yellow", "orange", "purple", "pink", "mint", "teal", "cyan", "indigo", "brown", "gray", "black", "white", "clear", "accentcolor"
//  You can also use hex color strings (e.g., "#FF0000", "#FF000080")
// 
//  Supported modifiers for keyboardShortcut:
//    - "command", "shift", "option", "control", "capsLock"
//    - Must be unique within the array; duplicates are ignored with a warning
// 
//  Supported keys for keyboardShortcut:
//    - Single character (e.g., "a", "1")
//    - Special keys: "upArrow", "downArrow", "leftArrow", "rightArrow", "escape", "delete", "deleteForward", "home", "end", "pageUp", "pageDown", "clear", "tab", "space", "return"
// 
//  Frame Specification Note:
//  The frame dictionary supports two mutually exclusive forms:
//  - Fixed Frame: Uses "width" and/or "height" (both optional) with an optional "alignment". At least one of width or height should be specified for the frame to take effect.
//  - Flexible Frame: Uses "minWidth", "idealWidth", "maxWidth", "minHeight", "idealHeight", "maxHeight" (at least one required) with an optional "alignment".
//  Mixing keys from both forms (e.g., "width" with "minWidth") is invalid and will result in the frame being ignored with a warning.
//  Invalid types for any frame dimension will result in the entire frame being ignored.
// 
//  navigationSplitViewColumnWidth notes:
//  - "ideal" is required in dictionary form to match SwiftUI API.
//  - Modifier is ignored unless view is used inside NavigationSplitView column.
//  - System tries to respect values, but macOS users can still drag divider beyond min/max in some situations.
```
