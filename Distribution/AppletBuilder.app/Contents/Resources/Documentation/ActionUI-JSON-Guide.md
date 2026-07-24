# ActionUI JSON Guide

ActionUI renders native views from JSON descriptions across **three platforms from one document**: SwiftUI on Apple, Jetpack Compose on Android, and DOM/CSS in the browser. The JSON vocabulary is SwiftUI's — the same rules for stacking, alignment, spacing, and modifiers — and the Android and Web renderers reproduce that same schema. If you know SwiftUI, you know ActionUI JSON, on every platform.

Everything in this guide is **cross-platform unless a row or note marks it otherwise**. The [Cross-Platform and Platform-Specific Behavior](#cross-platform-and-platform-specific-behavior) section explains how the same document behaves across the three renderers and what to expect where they differ.

## Platforms

| Platform | Minimum | Native layer |
|----------|---------|--------------|
| macOS | 14.6+ | SwiftUI |
| iOS / iPadOS | 17.6+ | SwiftUI |
| watchOS | 10.6+ | SwiftUI |
| tvOS | 17.6+ | SwiftUI |
| visionOS | 2.6+ | SwiftUI |
| Android | 12.0+ | Jetpack Compose |
| Web | Any modern browser | DOM / CSS (no build step) |

## JSON Structure

Every element has a `type`, an optional integer `id`, and a `properties` object. Container elements have a `children` array.

```json
{
  "type": "ElementType",
  "id": 1,
  "properties": {
    "key": "value"
  },
  "children": []
}
```

- **`type`** — the element name, using SwiftUI's vocabulary as the shared cross-platform name: `"VStack"`, `"Button"`, `"TextField"`, etc.
- **`id`** — positive integer for programmatic access (get/set values, enable/disable). Views without an `id` are static.
- **`properties`** — element-specific and universal modifier properties.
- **`children`** — ordered list of child elements (for containers only).

## Window Content

A window content JSON defines the root view. The root is typically a layout container:

```json
{
  "type": "VStack",
  "properties": {
    "spacing": 12,
    "alignment": "leading",
    "padding": "default",
    "frame": {
      "minWidth": 400,
      "minHeight": 300,
      "idealWidth": 600,
      "idealHeight": 400
    }
  },
  "children": [
    {
      "type": "Text",
      "properties": {
        "text": "Hello, ActionUI!",
        "font": "title"
      }
    },
    {
      "type": "Button",
      "id": 1,
      "properties": {
        "title": "Click Me",
        "buttonStyle": "borderedProminent",
        "actionID": "button.clicked"
      }
    }
  ]
}
```

## Cross-Platform and Platform-Specific Behavior

One JSON document is meant to render on all three renderers. In practice that breaks down into three categories:

**Cross-platform (the default).** The structure, element types, properties, universal modifiers, actions, and runtime get/set behavior described in this guide work the same on Apple, Android, and Web. You author once and the same document drives all three. The great majority of elements and modifiers fall here.

**Same intent, native appearance.** An element that is cross-platform still adopts each platform's look and conventions rather than emulating one everywhere. A `Toggle` is an AppKit/UIKit switch on Apple, a Material switch on Android, and a styled checkbox/switch on Web; a window-level toast is a styled overlay on Apple and a Material snackbar on Android; semantic system colors resolve to each platform's adaptive theme. The JSON does not change — the rendering honors the host.

**Platform-specific (marked explicitly).** A few elements or property values only exist where the underlying framework provides them. These are called out with a platform marker in the tables below (for example **macOS** on `HSplitView`). On a platform that lacks a given element, ActionUI **degrades gracefully**: the element is skipped and a validation warning is emitted rather than crashing, so a document that leans on a macOS-only element still loads elsewhere with that piece absent.

**Marker legend used below:** an unmarked row is cross-platform. **macOS** / **iOS** / **Apple** / **Android** / **Web** in a Description cell means the element or behavior is limited to, or only meaningful on, those platforms.

### Per-Platform Property Overrides

When you want the *same* element to carry a different value on one platform, suffix the property key with `:<platform>`. At load time each renderer keeps the variant matching the platform it runs on and drops the rest, so one document holds per-platform values with no host code. This is resolved uniformly on Apple, Android, and Web.

```json
{
  "type": "Text",
  "properties": {
    "text": "Settings",
    "font": "title",
    "font:android": "headline",
    "padding:macos": "default"
  }
}
```

Here `font` is `"headline"` on Android and `"title"` everywhere else, and the `padding` applies on macOS only.

Resolution rules:

- **Recognized tokens:** `ios`, `macos`, `tvos`, `watchos`, `visionos`, `apple` (matches any Apple platform), `android`, and `web`. (`androidtv`, `wear`, and `desktop` are reserved for future use and match nothing today.)
- **Specificity:** a specific token beats `apple`, which beats the unsuffixed key. So with `title`, `title:apple`, and `title:macos` all present, macOS uses `title:macos`, other Apple platforms use `title:apple`, and non-Apple platforms use `title`.
- **Fallback:** the unsuffixed key is used when no suffixed variant matches the current platform.
- **Inactive platform:** a key aimed at a recognized but non-active platform (e.g. `font:ios` seen on Android) is dropped silently.
- **Typos:** an unrecognized suffix (e.g. `font:Android` with a capital A) is dropped **and logs a warning**, so mistakes surface instead of passing through.

The suffix works on any key at any depth — top-level properties, nested objects, even Canvas operation entries — and the key is split on its **last** colon, so base names may themselves contain colons.

## Layout Containers

Layout follows SwiftUI stacking rules:

| Container | Description |
|-----------|-------------|
| `HStack` | Horizontal layout |
| `VStack` | Vertical layout |
| `ZStack` | Overlay (back to front) |
| `Form` | Settings-style grouped layout (inset-grouped on mobile) |
| `Grid` | Two-dimensional grid |
| `ScrollView` | Scrollable content |
| `TabView` | Tabbed interface (collapses to a bottom tab bar on phones) |
| `HSplitView` | Horizontal split — **macOS** |
| `VSplitView` | Vertical split — **macOS** |
| `NavigationSplitView` | Sidebar + detail |
| `Group` | Logical grouping without visual effect |
| `GroupBox` | Bordered group with optional title |
| `Section` | Labeled section within Form or List |

## Input Controls

| Element | Description | Value type |
|---------|-------------|------------|
| `TextField` | Single-line text input | String |
| `SecureField` | Password input | String |
| `TextEditor` | Multi-line text editor | String |
| `Picker` | Dropdown or segmented selection | String (tag) |
| `DatePicker` | Date/time selection | Date string |
| `ColorPicker` | Color selection | Color string |
| `Toggle` | On/off switch | Bool |
| `Slider` | Numeric range | Double |
| `Button` | Clickable action trigger | — |

## Display Elements

| Element | Description |
|---------|-------------|
| `Text` | Static or dynamic text |
| `Label` | Text + icon |
| `Image` | System symbol, asset, or file image |
| `AsyncImage` | Image loaded from URL |
| `ProgressView` | Determinate or indeterminate progress |
| `Gauge` | Value indicator |
| `Table` | Multi-column data table — **macOS, iPadOS, Web** (Web shows a stacked-card layout on narrow screens) |
| `List` | Scrollable list of items |
| `Divider` | Visual separator |
| `Spacer` | Flexible space |

## Universal Modifiers

All elements support these properties (inherited from the base View):

**Layout:** `padding`, `frame`, `background`, `cornerRadius`, `position`, `offset`
**Styling:** `foregroundStyle`, `font`, `opacity`, `shadow`, `border`
**Sizing:** `controlSize` (`"mini"`, `"small"`, `"regular"`, `"large"`, `"extraLarge"`)
**Behavior:** `hidden`, `disabled`, `actionID`, `keyboardShortcut`
**Accessibility:** `accessibilityLabel`, `accessibilityHint`, `accessibilityIdentifier`

## Actions

Views with an `actionID` property fire action callbacks on user interaction. The host application receives the action ID string and can respond accordingly.

```json
{
  "type": "Button",
  "id": 10,
  "properties": {
    "title": "Save",
    "actionID": "document.save",
    "keyboardShortcut": {
      "key": "s",
      "modifiers": ["command"]
    }
  }
}
```

## View IDs and Programmatic Access

Views with an integer `id` can be read and modified at runtime:

- **Get/set value** — read text from a TextField, set text on a Label
- **Enable/disable** — toggle interactivity
- **Show/hide** — control visibility
- **Get/set properties** — modify any property dynamically

## Element Reference

See [ActionUI-Elements.md](ActionUI-Elements.md) for the full list of all elements with:
- **Schema** (.md) — complete JSON specification with all properties documented
- **Template** (.json) — clean, copy-paste-ready JSON for each element

## Menu Bar

A **view** document has an object root (above). A **menu-bar** document
(`MainMenu.json`) has an **array** root and customizes the application menu bar —
adding menus, inserting/replacing items in the standard menus, or removing them.
See [ActionUI-MenuBar-JSON-Guide.md](ActionUI-MenuBar-JSON-Guide.md).

The application menu bar is a **macOS** concept. The same document is reinterpreted as a top app bar on Android and Web; watchOS/tvOS have no menu bar and ignore it.

## Examples

Working examples of every element type are available at:
https://github.com/abra-code/ActionUI/tree/main/ActionUISwiftTestApp/Resources/

## License

ActionUI is licensed under the [PolyForm Small Business License 1.0.0](https://polyformproject.org/licenses/small-business/1.0.0) — free for personal projects, open source, education, internal tools, and qualifying small businesses (fewer than 100 people and under ~$1.3M adjusted revenue). Larger commercial use requires a paid license.
