# ActionUI JSON Guide

ActionUI renders native SwiftUI views from JSON descriptions. The JSON layout maps directly to SwiftUI — the same rules for stacking, alignment, spacing, and modifiers apply. If you know SwiftUI, you know ActionUI JSON.

## Requirements

- macOS 14.6+ (iOS 17.6+, tvOS 17.6+, watchOS 10.6+, visionOS 2.6+)

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

- **`type`** — the SwiftUI view name: `"VStack"`, `"Button"`, `"TextField"`, etc.
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

## Layout Containers

Layout follows SwiftUI stacking rules:

| Container | Description |
|-----------|-------------|
| `HStack` | Horizontal layout |
| `VStack` | Vertical layout |
| `ZStack` | Overlay (back to front) |
| `Form` | macOS/iOS settings-style grouped layout |
| `Grid` | Two-dimensional grid |
| `ScrollView` | Scrollable content |
| `TabView` | Tabbed interface |
| `HSplitView` | Horizontal split (macOS) |
| `VSplitView` | Vertical split (macOS) |
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
| `Table` | Multi-column data table (macOS) |
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

## Examples

Working examples of every element type are available at:
https://github.com/abra-code/ActionUI/tree/main/ActionUISwiftTestApp/Resources/

## License

ActionUI is licensed under the [PolyForm Small Business License 1.0.0](https://polyformproject.org/licenses/small-business/1.0.0) — free for personal projects, open source, education, internal tools, and qualifying small businesses (fewer than 100 people and under ~$1.3M adjusted revenue). Larger commercial use requires a paid license.
