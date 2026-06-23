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
     "tint": "red",        // Optional: SwiftUI color for tinting interactive controls (buttons, toggles, sliders, etc.), resolved via tint
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
     "clipShape": "circle",    // Optional: clip view to named shape: "circle" | "capsule" | "rectangle" | "ellipse"
     "clipShape": {            // Optional: dict form for rounded rectangle
       "type": "roundedRectangle",  // Required: only "roundedRectangle" supported in dict form
       "cornerRadius": 12.0,        // Uniform corner radius — OR use per-axis form:
       "cornerRadiusX": 12.0,       // Horizontal radius (used together with cornerRadiusY)
       "cornerRadiusY": 8.0         // Vertical radius
     },
     "rotationEffect": 45.0, // Optional: Double — rotation angle in degrees (positive = clockwise). Negative values rotate counter-clockwise.
     "scaleEffect": 1.5,   // Optional: Uniform scale factor (Double), or dictionary for non-uniform scaling:
     "scaleEffect": {      // Optional: Dictionary form for per-axis scaling
       "x": 1.5,           // Optional: Double for horizontal scale; defaults to 1.0
       "y": 0.8,           // Optional: Double for vertical scale; defaults to 1.0
       "anchor": "center"  // Optional: UnitPoint anchor for scaling origin; defaults to "center"
                           //   Allowed: "center", "leading", "trailing", "top", "bottom",
                           //            "topLeading", "topTrailing", "bottomLeading", "bottomTrailing"
     },
     "animation": "spring", // Optional: String shorthand (curve name), or dictionary:
     "animation": {        // Optional: Dictionary form for full control
       "curve": "spring",  // Required: animation curve. Allowed: "default", "linear", "easeIn",
                           //   "easeOut", "easeInOut", "spring", "bouncy", "smooth", "snappy",
                           //   "interactiveSpring".
       "duration": 0.3,    // Optional: positive Double — seconds. Applies to time-based curves.
       "delay": 0.1,       // Optional: non-negative Double — seconds before animation starts.
       "speed": 1.0,       // Optional: positive Double — speed multiplier.
       "value": "opacity"  // Optional: String — property name or state key to watch.
                           //   When set, animation fires only when that property/state changes.
                           //   When omitted, animation fires on any mutation (setElementProperty,
                           //   setElementState, setElementValue).
     },
     "transition": "opacity", // Optional: how this view animates when it is inserted/removed at runtime
     "transition": {          //   (via insertElement / removeElement). String shorthand ("opacity",
                              //   "slide", "scale", "identity") or a dictionary:
       "type": "move",        // Required: "opacity", "slide", "scale", "move", "offset", "identity",
                              //   or "asymmetric".
       "edge": "bottom",      // For "move": edge to move from/to ("top"/"bottom"/"leading"/"trailing"; default "bottom").
       "scale": 0.5,          // For "scale": start/end scale factor (Double; default 0).
       "anchor": "center",    // For "scale": the scale anchor (UnitPoint; default "center").
       "x": 0.0, "y": 20.0,   // For "offset": the start/end offset.
       "insertion": "opacity",// For "asymmetric": the insertion transition (shorthand or dict).
       "removal": { "type": "move", "edge": "bottom" } // For "asymmetric": the removal transition.
     },
     "transition": ["opacity", { "type": "scale" }], // Array form: the transitions combined.
                              //   A view without "transition" is inserted/removed instantly (the default).
                              //   Platform note: Apple animates both insertion and removal; Android and Web
                              //   animate the insertion (entrance) only - removal is instant there.
                              //   Container note: stack containers (VStack/HStack/ZStack/LazyVStack/LazyHStack)
                              //   honor the full transition (geometry + fade). SwiftUI's List substitutes its
                              //   own row animation - on iOS only the opacity (fade) survives, custom geometry
                              //   (move/slide/scale) is not honored, and macOS List does not animate row
                              //   insert/remove at all - so use a stack container when you need the motion.
     "actionID": "view.action", // Optional: String for action identifier
     "valueChangeActionID": "view.valueChanged", // Optional: String for action triggered on any value change initiated by user
     "openURLActionID": "view.openURL", // Optional: String for action identifier triggered on open URL (via .onOpenURL modifier)
     "onAppearActionID": "view.onAppear", // Optional: String for action identifier triggered on view appear (via .onAppear modifier)
     "onDisappearActionID": "view.onDisappear", // Optional: String for action identifier triggered on view disappear (via .onDisappear modifier)
     "onHoverActionID": "view.hovered", // Optional: String for action identifier triggered when the pointer enters or exits this view (via .onHover modifier).
                           //   macOS primary; iPadOS with pointer. Silently ignored on other platforms.
                           //   Context: { "isHovering": Bool }
     "onDropTypes": ["public.utf8-plain-text"], // Optional: [String] of UTType identifiers this view accepts as a drop target. Required alongside onDropActionID.
                           //   Must be a non-empty array of strings. Discarded otherwise.
                           //   Common values: "public.utf8-plain-text", "public.plain-text", "public.url", "public.file-url"
     "onDropActionID": "view.dropped", // Optional: String for action identifier triggered when a valid drop lands on this view.
                           //   Requires onDropTypes to be set and non-empty; ignored without it.
                           //   Items are extracted as UTF-8 text before firing; non-extractable items are omitted.
                           //   Context: { "items": [String], "location": { "x": Double, "y": Double } }
     "onDropTargetedActionID": "view.dropTargeted", // Optional: String for action identifier triggered when a drag enters or exits this drop zone.
                           //   Use to drive visual feedback (border, scale) via setElementState.
                           //   Context: { "isTargeted": Bool }
     "keyboardShortcut": { // Optional: Dictionary for keyboard shortcut, supports key with array of modifiers
       "key": "a",         // Required: String for KeyEquivalent (single character like "a" or special key like "return", "space", "upArrow")
       "modifiers": ["command", "shift"] // Optional: Array of strings for modifiers (e.g., ["command", "shift"]), defaults to ["command"], must contain unique elements
     },
     "buttonStyle": "automatic", // Optional: "automatic", "plain", "borderless", "bordered", "borderedProminent"; defaults to "automatic".
                                // Applicable to Button, Menu, Link, NavigationLink. On container views (VStack, HStack, List, Form, etc.) the style propagates to all buttons inside.
     "controlSize": "regular", // Optional: "mini", "small", "regular", "large", "extraLarge"; no default (system default)
     "labelsHidden": true,  // Optional: Boolean to hide labels on child views (e.g., within LabeledContent/Form); defaults to false
     "disabled": false,     // Optional: Boolean to disable user interaction
     "help": "Run action",  // Optional: String for help tooltip 
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
     "scrollContentBackground": "visible",   // Optional: "visible", "hidden" or "automatic"; controls the default background of scrollable views (List, TextEditor, Form). Defaults to "automatic".
     "popoverArrowEdge": "top",             // Optional: Arrow edge for popover ("top", "bottom", "leading", "trailing"); defaults to "top". Only meaningful when "popover" subview is present.
     "popoverActionID": "view.popover",     // Optional: String for action identifier triggered when the popover is shown. Only meaningful when "popover" subview is present.
     "sheetOnDismissActionID": "sheet.dismissed",           // Optional: String for action identifier triggered when the sheet is dismissed. Only meaningful when "sheet" subview is present.
     "fullScreenCoverOnDismissActionID": "cover.dismissed", // Optional: String for action identifier triggered when the full-screen cover is dismissed. Only meaningful when "fullScreenCover" subview is present.
     "searchable": { "prompt": "Search", "actionID": "view.search" }, // Optional: Adds a search field (.searchable) to a List / NavigationStack. "actionID" (required String) fires on each query change with the query string as the action context; "prompt" (optional String) is the placeholder. The host filters and re-pushes rows.
     "toolbarTitleDisplayMode": "automatic", // Optional: Navigation title display mode; "automatic", "inline", "large", "inlineLarge".
                                            // Meaningful when the view is inside a NavigationStack or NavigationSplitView.
                                            // "automatic": platform default. "inline": compact nav bar title.
                                            // "large": large expandable title (iOS style). "inlineLarge": collapses on scroll (iOS 17+).
     "destinationViewId": 10,               // Optional: Int linking this view to a destination in a navigation container.
                                            // Does not apply any modifier; the value is kept in validatedProperties for navigation logic.
                                            // Used by NavigationLink (Form 2) to identify the push target in NavigationStack,
                                            // and by sidebar List children in NavigationSplitView to select a destination view.
     "textSelection": "enabled",            // Optional: "enabled" or "disabled". Controls whether the user can select text in this view.
                                            // SwiftUI does not enable text selection by default; set "enabled" to allow it.
                                            // Applies to Text and any container holding Text views.
     "multilineTextAlignment": "center",   // Optional: "leading", "center", or "trailing". Aligns wrapped lines within a text block.
                                            // Also propagates to child Text views when set on a container (VStack, HStack, etc.).
      "zIndex": 0.0,                        // Optional: Number for layer ordering within a container (e.g. ZStack)
                                            // Higher values render in front of lower values. Defaults to 0.0.
      "ignoresSafeArea": true,             // Optional: extend this view into the safe area (e.g. a background under the notch /
                                            // home indicator). true = all edges+regions; or an object to narrow:
                                            // { "edges": "top"|"bottom"|"leading"|"trailing"|"horizontal"|"vertical"|"all",
                                            //   "regions": "all"|"container"|"keyboard" }. SwiftUI's .ignoresSafeArea(_:edges:).
    },
    // contextMenu (optional): a context menu attached to ANY view — long-press (iOS) / right-click (macOS).
    // A TOP-LEVEL subview key (sibling of "properties"), modeled as two slots to match SwiftUI's
    // `.contextMenu(menuItems:preview:)`, which is itself two ViewBuilders:
    "contextMenu": [                        // The menu's action items: an array of real elements (Buttons carry their own
      { "type": "Button", "properties": { "title": "Rename", "systemImage": "pencil", "actionID": "view.rename" } },   //   title / systemImage / role / actionID), plus Divider / Section / sub-Menu.
      { "type": "Divider" },                //   These render as native menu rows.
      { "type": "Button", "properties": { "title": "Delete", "systemImage": "trash", "role": "destructive", "actionID": "view.delete" } }
    ],
    "contextMenuPreview": {                 // Optional: a single arbitrary view shown enlarged above the menu (iOS only;
      "type": "Image", "properties": { "systemName": "photo", "imageScale": "large" }   //   macOS right-click menus have no preview). Any element — an Image, an HStack of items, etc.
    },
    // swipeActions (optional): leading/trailing swipe-to-action Buttons on a List row — SwiftUI's
    // `.swipeActions(edge:allowsFullSwipe:)`. A TOP-LEVEL subview key (sibling of "properties"), honored only inside a List.
    "swipeActions": [                       // An array of real Button elements. Each carries its own title / systemImage / role / tint / actionID,
      { "type": "Button", "properties": { "title": "Flag", "systemImage": "flag", "tint": "orange", "edge": "leading", "actionID": "row.flag" } },     //   plus an optional "edge" ("leading"/"trailing", default trailing) and
      { "type": "Button", "properties": { "title": "Delete", "systemImage": "trash", "role": "destructive", "edge": "trailing", "actionID": "row.delete" } }  //   "allowsFullSwipe" (default true; a full swipe fires that edge's first button).
    ],
    // safeAreaInset (optional): a single view placed in the safe area on an edge; the main content insets to avoid it
    // (SwiftUI's `.safeAreaInset(edge:alignment:spacing:)` — e.g. a bottom bar that scrollable content clears). A TOP-LEVEL
    // subview key. The inset view's own properties parameterize it (safe-area-specific names): "safeAreaEdge"
    // ("top"/"bottom"/"leading"/"trailing", default bottom), "safeAreaAlignment", "safeAreaSpacing".
    "safeAreaInset": {
      "type": "HStack", "properties": { "safeAreaEdge": "bottom", "padding": 10.0, "background": "bar" },
      "children": [ { "type": "Text", "properties": { "text": "Bottom bar in the safe area" } } ]
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
