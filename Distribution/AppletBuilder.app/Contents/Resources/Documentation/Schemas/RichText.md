# ActionUI.RichText

JSON schema and usage documentation for `RichText` (ActionUIRichText add-on).

```jsonc
// Add-ons/ActionUIRichText/Sources/RichText.swift
// JSON specification for ActionUI.RichText:
 {
   "type": "RichText",
   "id": 1,                  // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "markdown": "# Title\n\nA **bold** word, a `code` span, and a [link](https://example.com).",
                                             // Optional: Markdown source to render; seeds the element value.
                                             //           "" or nil renders an empty document.
     "baseFontSize": 15,                     // Optional: Number; base font point size. Omit for Dynamic Type body.
     "syntaxHighlighting": true,             // Optional: Bool; color fenced code blocks by language. Default from
                                             //           the RichText theme.
     "widthBehavior": "fill",                // Optional: "fill" (default) fills the proposed width, left-aligned -
                                             //           block / document layout. "hug" sizes to the content
                                             //           width, wrapping only when it exceeds the proposal (the
                                             //           messaging-bubble idiom; pair with frame.maxWidth to cap).
     "showFindBar": false                    // Optional: Bool (default false); a find bar over this document
                                             //           (Cmd-F to open, Cmd-G / Shift-Cmd-G next / previous, Escape
                                             //           to close, options for case / whole word / diacritics).
                                             //           Matches are painted behind the text without re-laying it
                                             //           out. Off, states["search"] still highlights (see below).
   }
 }
// A rich-text DISPLAY element backed by the RichText package, implemented as an ActionUI add-on
// (registered via ActionUIRichText.register()):
//   macOS / iOS / visionOS - RichText.RichText (a SwiftUI View; RichText's platforms).
// A whole Markdown document (headings, code blocks, quotes, lists, GFM tables, inline styling, links) is
// laid out into ONE native text view, so the entire document is selectable and copyable as a single unit
// (copy is table-aware: RTF / HTML / Markdown).
//
// Observable state (via getElementValue / setElementValue):
//   value (String)   Current Markdown source. Write new Markdown to re-render; "" or nil renders empty.
//
// Runtime state (via setElementState):
//   states["search"] (String)   A query: a non-empty value highlights every match and presents the find
//                               bar with the term when "showFindBar" is on (without taking the keyboard focus);
//                               "" clears. The element seeds the key as a String, so any text is accepted
//                               (core fixes a state key's type on its first write). The channel re-delivers
//                               its value on every states change, so a value equal to the last applied one
//                               is ignored - the reader can close the bar without it springing back; to
//                               re-open with the same term, set "" and then the term again.
//                               The element highlights; it does not scroll. Bringing the current match
//                               into view needs a scroller that reads RichText's current-match anchor,
//                               which ActionUI's ScrollView does not yet, and the bar is inset on the
//                               element itself, so a long document is best given its own ScrollView.
//                               Cmd-F belongs to the element with "showFindBar" on; two in one window contend
//                               for it. Cmd-G / Shift-Cmd-G / Escape exist only while the bar is shown.
//
// Note: baseline View properties (padding, hidden, background, frame, opacity, cornerRadius, actionID,
// onAppearActionID, onDisappearActionID, etc.) are inherited from base View. The document is read-only but
// selectable, self-sizes to its content for the proposed width, and handles its own links (http/https/mailto/tel).
```
