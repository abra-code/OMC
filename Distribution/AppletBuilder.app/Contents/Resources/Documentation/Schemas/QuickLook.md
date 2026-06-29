# ActionUI.QuickLook

JSON schema and usage documentation for `QuickLook` (ActionUIQuickLook add-on).

```jsonc
// Add-ons/ActionUIQuickLook/Sources/QuickLook.swift
// JSON specification for ActionUI.QuickLook:
 {
   "type": "QuickLook",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "filePath": "/path/to/file.pdf",     // Optional: Absolute local path to preview; seeds the element value
     "previewStyle": "normal",            // Optional: macOS only; "normal" or "compact"; default "normal"; ignored on iOS/visionOS
     "showsChrome": false,                // Optional: Bool; show preview chrome - a nav bar (title + share/actions) on
                                          //           iOS, or a header (file name + share/open) on macOS; default false
     "valueChangeActionID": "ql.changed"  // Optional: Fired after the previewed item changes (a reload is dispatched)
   }
 }
// An embedded, in-process Quick Look preview pane, implemented as an ActionUI add-on (registered via
// ActionUIQuickLook.register()):
//   macOS          - QLPreviewView (NSViewRepresentable).
//   iOS / visionOS - QLPreviewController (UIViewControllerRepresentable, inline child).
//   tvOS / watchOS - a graceful "not available" label.
// Quick Look previews local files only, so there is no remote "url" property - just "filePath" / the value.
//
// Observable state (via getElementValue / setElementValue):
//   value (String)   Current source file path. Write a local file path to preview a different file;
//                    valueChangeActionID fires after the preview reloads. "" means no source (shows nothing).
//
// Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
// cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
