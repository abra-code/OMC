# ActionUI.CachedImage

JSON schema and usage documentation for `CachedImage` (ActionUICachedImage add-on).

```jsonc
// Add-ons/ActionUICachedImage/Sources/CachedImage.swift
// JSON specification for ActionUI.CachedImage:
 {
   "type": "CachedImage",
   "id": 1,                  // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/photo.jpg", // Optional: web / file / data URL of the image; seeds the element
                                             //           value. Nil or invalid shows the placeholder.
     "intrinsicSize": { "width": 1024, "height": 768 }, // Optional: the source's natural size, if known ahead of
                                             //           load (e.g. server metadata). Reserves the exact box up
                                             //           front so the image hydrates with ZERO reflow.
     "contentMode": "fill",                  // Optional: "fit" or "fill" - how the image fills the reserved box;
                                             //           default "fill" (CachedImage's own default).
     "maxPixelWidth": 840,                   // Optional: cap the DECODED width in pixels (downscaled off-main) to
                                             //           bound memory for large sources; omit for natural resolution.
     "cornerRadius": 12                      // Optional: Number; rounds the image (a continuous-corner clip applied
                                             //           by CachedImage itself, so it rounds the visible image).
   }
 }
// A cached, off-main image view backed by AsyncImageCache's ImageStore, implemented as an ActionUI
// add-on (registered via ActionUICachedImage.register()):
//   macOS / iOS / visionOS - AsyncImageCache.CachedImage (a SwiftUI View; AsyncImageCache's platforms).
// Bytes are fetched / decoded / downscaled OFF the main thread and served from a two-tier (memory +
// on-disk) cache; the natural pixel size is known up front (persisted as a file extended attribute) so
// layout reserves the exact box with no reflow on hydration, even across relaunch.
//
// Observable state (via getElementValue / setElementValue):
//   value (String)   Current image URL string. Write a new URL to load a different image; "" or nil
//                    shows the placeholder.
//
// Note: "cornerRadius" is the standard View property name, but this element rounds the image itself (the
// baseline cornerRadius modifier would round only the transparent outer frame, not the aspect-fit image).
// Sizing uses baseline "frame". Other baseline View properties (padding, hidden, background, frame,
// opacity, actionID, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
