# ActionUI.HostSurface

JSON schema and usage documentation for `HostSurface` (ActionUIHostSurface add-on).

```jsonc
// Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurface.swift
// JSON specification for ActionUI.HostSurface:
 {
   "type": "HostSurface",
   "id": 5,                       // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "surfaceName": "viewport",   // Required: String; binds the element to the client registered under this
                                  //           name (actionUIHostSurfaceSetDelegate). Fixed at load.
     "kind": "native",            // Optional: "native" (default): a CAMetalLayer on macOS and iOS, a frame sink
                                  //           on Linux. "sink": a frame sink on every platform (the client
                                  //           presents pixels). "gl": a GL area (Linux). A kind the platform
                                  //           lacks ("gl" on Apple) draws a placeholder.
                                  //           Fixed at load.
     "continuous": false,         // Optional: Bool, default false; a frame callback at every display refresh
                                  //           while the surface is on screen. Otherwise one per requestFrame.
     "preferredFrameRate": 0,     // Optional: Number, default 0 (the display rate); frames per second hint
     "focusable": true,           // Optional: Bool, default true; a click or tap gives the surface keyboard
                                  //           focus. It never takes focus unasked; Tab moves focus on.
     "opaque": true,              // Optional: Bool, default true; false lets content behind the element show
                                  //           through transparent pixels the client draws
     "idealWidth": 320,           // Optional: Number, default 320; natural width in points
     "idealHeight": 240           // Optional: Number, default 240; natural height in points
   }
 }
// A rectangle in the layout whose pixels a client program draws with its own renderer (Metal, wgpu,
// MoltenVK, ANGLE). ActionUI lays it out like any other leaf; the client gets the CAMetalLayer, the
// size in points and pixels, the scale, frame ticks and input through the C interface in
// include/ActionUIHostSurface.h, or the Swift API (ActionUIHostSurface.setDelegate).
//
// Size: the element takes the size its parent proposes; where a dimension is unspecified it uses the
// ideal size. frame and padding work as usual.
//
// States: "size", [width, height] in points, updated when the surface size changes.
//
// No observable value (valueType Void).
//
// Baseline View properties (padding, hidden, frame, opacity, cornerRadius, disabled, accessibilityLabel,
// etc.) are inherited from base View. "hidden" is applied by the element itself, on the native view, so
// hiding never destroys the client's surface; a hidden surface is suspended and takes no input.
// "disabled" stops input and gives up keyboard focus.
```

## The client side

A program binds to every HostSurface element with a given `surfaceName`, in any window, before or
after the document loads:

- C, C++, Rust: `actionUIHostSurfaceSetDelegate(name, &delegate, userData)` with the callbacks in
  `AUIHostSurfaceDelegate` (header `ActionUIHostSurface.h`). Register the element first with
  `ActionUIHostSurface_register()`.
- Swift: `ActionUIHostSurface.setDelegate(client, forSurfaceName: name)` with a `HostSurfaceDelegate`.
  Register the element first with `ActionUIHostSurface.register()`.

The client then gets these events for each surface, all on the main thread:

| Event | Meaning | What the client does |
|---|---|---|
| created | The surface has a window, a nonzero pixel size and this client. Comes with a new `surfaceID`. | Build its renderer on the layer, sized in pixels. |
| changed | The size or the scale changed. | Resize to the new pixel size before the next frame. |
| suspended | The surface is off screen: hidden, zero pixels, an occluded or minimized window, an app in the background, or about to be torn down. | Stop asking the layer for drawables. |
| resumed | The surface is on screen again. | Draw again. |
| destroyed | The surface is gone, or this client was replaced or unbound. | Stop all use of the layer before returning: join a render thread, drop the swapchain. |

Frame callbacks arrive at each display refresh while `continuous` is true, or once after each
`actionUIHostSurfaceRequestFrame(surfaceID)`, and never while the surface is suspended. A client may
render on its own thread, paced by the frame callback; it must not then call the ActionUI C functions
that wait for the main thread (`actionUIGet...`, `actionUIInsertElement`, ...) while "destroyed" may be
joining it.

Input comes to the `input` callback (`hostSurfaceInput` in Swift) while the surface is on screen,
not hidden, and its element is enabled:

- Pointer down, up, move, drag, enter, exit and cancel, for the mouse, touches (one event per touch,
  with a `pointerID`) and the pen (pressure, tilt). Positions are in points from the top-left corner.
- Scroll: deltas are how far the content should move, positive to the right and down, in points
  (trackpad) or wheel steps, with a phase (began, changed, ended, momentum). The surface takes the
  wheel, so an enclosing scroll view does not scroll as well.
- Magnify and rotate: trackpad gestures on macOS, two-finger pinch and rotation on iOS.
- Keys while the surface has keyboard focus: the platform key code, the W3C UI Events `code`
  (`KeyA`, `ArrowLeft`, `ShiftLeft`), the modifiers, and the produced text. Modifier keys come as key
  down and up of their own. Tab and Shift-Tab move focus and are not delivered.
- Focus in and focus out. The surface never takes focus unasked: a click or tap focuses it when
  `focusable` is true.

`actionUIHostSurfaceSetCursor(surfaceID, cursor)` sets the cursor over the surface (arrow, I-beam,
crosshair, hands, resize arrows, not allowed, hidden).

Rules the add-on keeps:

- Binding replays: a client bound after the surface appeared gets "created" at once.
- Replacing or unbinding a client sends "destroyed" to the old one first.
- A client bound or unbound inside a callback takes effect when that callback returns.
- Changing `hidden` or `padding`, or any other property, never destroys the surface; SwiftUI may rebuild
  the element's view, and the surface moves into the new one.
- Removing the element or closing its window sends "destroyed". Process exit sends nothing.

Captures that draw the view tree into a bitmap (the ActionUI MCP server's window capture, offscreen
renders) leave the Metal layer's content out; a window-server capture (`screencapture -l`) shows it.
