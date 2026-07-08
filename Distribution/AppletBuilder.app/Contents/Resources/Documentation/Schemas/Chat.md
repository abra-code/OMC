# ActionUI.Chat

JSON schema and usage documentation for `Chat` (ActionUIChat add-on).

```jsonc
// Add-ons/ActionUIChat/Sources/Core/Chat.swift
// JSON specification for ActionUI.Chat:
 {
   "type": "Chat",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "appearance": {                      // Optional: transcript appearance
       "alignment": "single",             //   "single" (default): leading / full-width, parties by tint + label.
                                          //   "dual" (later): incoming leading, outgoing trailing.
       "showRoleLabels": true,            //   Show a small role label above each message; default true.
       "theme": "auto"                    //   "auto" | "light" | "dark"; default "auto".
     },
     "roles": {                           // Optional: per-role label / tint (and side, used by "dual" later)
       "local": { "label": "You",   "tint": "accent" },
       "agent": { "label": "Agent", "tint": "secondary" }
     },
     "input": {                           // Optional: composer
       "enabled": true,                   //   Default true.
       "placeholder": "Message",          //   Default "Message".
       "submitOn": "return"               //   "return" (default), "modifier-return" (Cmd+Return), "shift-return-newline".
     },
     "surfaces": {                        // Optional: routing for agentic transport items
       "toolCalls": "inline",             //   "inline" (default: a status card; its detail - file reads,
                                          //   diffs, raw I/O - stays FOLDED until tapped, and long content
                                          //   is truncated) | "collapsed" (a compact one-line row) |
                                          //   "hidden". "panel" renders inline for now.
       "thoughts": "collapsed",           //   "collapsed" (default: folded) | "inline" | "hidden"
       "plan": "panel",                   //   The agent's task plan, pinned ABOVE the transcript (never
                                          //   interleaved as chat): "panel" (default: expanded) |
                                          //   "collapsed" (pinned, folded) | "hidden".
       "diffs": "inline"                  //   Agent-proposed file diffs, rendered in the tool card's detail
                                          //   as a real line diff (the standalone DiffView component: hunks,
                                          //   old / new line-number gutters, +/- markers): "inline" (default)
                                          //   | "hidden" (dropped). "collapsed" / "panel" are accepted but
                                          //   coerced to inline (the card's fold already covers collapsing;
                                          //   a diff side panel is a later surface).
     },
     "sendActionID": "chat.send",         // Optional: fired when the user submits a message
     "stopActionID": "chat.stop",         // Optional: fired when the user cancels an in-flight turn
     "messageActionID": "chat.message",   // Optional: fired per finalized message (user and agent)
     "errorActionID": "chat.error",       // Optional: fired on a transport / parse error
     "approveToolActionID": "chat.tool.approve", // Optional: fired when an agent requests tool permission
     "entryActionID": "chat.entry",       // Optional: fired per FINALIZED transcript entry (message, thought,
                                          //           completed/failed tool call, image, system, error, plan,
                                          //           usage) with a JSON envelope { sequence, type, id, data } as
                                          //           the action context, for crash-safe incremental persistence.
                                          //           Never fired on streaming deltas.
     "readOnly": false                    // Optional (default false): read-only viewer mode - hides the composer and
                                          //           menus and needs no states["config"] injection (there is no
                                          //           transport to start). Pair with a runtime
                                          //           setElementState("content", ...) to show a saved session.
                                          // (Session data is NOT carried in the document - see "Session transcript" below.
                                          //  "properties.content" pre-populates a transcript for previews / testing only.)
   }
 }
// The document above declares ONLY properties - it is inert (composer disabled, no transport) until a HOST
// injects protocol/transport into runtime state, after the element is built:
//   setElementState(windowUUID, chatID, "config", ["protocol": "openai-sse",
//                                                   "transport": ["baseURL": "http://127.0.0.1:8080/v1"]])
// The value under states["config"] is the WHOLE object below (not a document field, not split across keys):
 {
   "protocol": "local",                  // Transport selector. "local" (default) is built in and streams a
                                         //           scripted reply. Every other protocol is provided by a separate
                                         //           transport module the host links and registers; the umbrella
                                         //           ActionUIChat product bundles them and wires them in register().
                                         //           "openai-sse" (the ActionUIChatOpenAI module) streams an
                                         //           OpenAI-compatible /v1/chat/completions endpoint (llama-server,
                                         //           mlx_lm.server, ...). "acp" (the ActionUIChatACP module, macOS
                                         //           only: the agent is a subprocess) runs an Agent Client Protocol
                                         //           agent over stdio. A protocol whose module the host did not
                                         //           register degrades to "local".
   "transport": { "echo": true }         // Protocol-specific settings (interpreted by the chosen transport).
                                         //           "local" honors "echo" (default true: stream a demo reply),
                                         //           "reply" ("echo" default | "markdown" | "agentic": a scripted
                                         //           agent turn with thoughts, tool calls, and a permission gate),
                                         //           and "chunkMs" (demo streaming pace, default 45).
                                         //           "openai-sse" requires "baseURL" (the endpoint, e.g.
                                         //           "http://127.0.0.1:8080/v1") and honors "model" (default "auto":
                                         //           resolved from GET {baseURL}/models), "apiKey" (default ""),
                                         //           "systemPrompt" (default ""), and "params" (merged into the
                                         //           request body, e.g. { "temperature": 0.8, "max_tokens": 0 };
                                         //           max_tokens 0 means unlimited and is omitted).
                                         //           "acp" requires "command" (the agent argv, e.g. ["claude-code-acp"])
                                         //           and honors "cwd" (the session root; "~" expands, default: the
                                         //           host's current directory) and "mcpServers" (an array of MCP
                                         //           server declarations passed to the agent verbatim).
 }
// A native chat surface, implemented as an ActionUI add-on (registered via ActionUIChat.register()).
// A transcript above a composer; the transport (selected by "protocol") drives the conversation and the
// element pre-filters its stream so chat text lands in the transcript. The element is GENERIC: the same
// element backs AI-agent chat and person-to-person chat - the transport and appearance differ, not the view.
//
// Landed so far: the "local" transport and single-alignment transcript (M1); streaming Markdown message
// bodies plus standalone image items (M2); the agentic surfaces (M3) - streamed reasoning folded behind
// a "Thoughts" disclosure, tool-call cards that mutate in place through their pending / in-progress /
// completed / failed lifecycle, and a permission gate that pins an approval card above the composer and
// pauses input until answered ("surfaces" routes each of these; the local transport's "agentic" reply
// style demonstrates them all); and the ACP transport (M3, macOS) - the element launches any Agent
// Client Protocol agent as a subprocess (newline-delimited JSON-RPC over stdio), negotiates capabilities
// (advertising no fs / terminal services), opens a session, and demuxes the session/update stream onto
// those same surfaces, with session/request_permission wired to the approval card and Stop wired to
// session/cancel. And the first M5 session-status surfaces: the agent's evolving plan pinned above the
// transcript (routed by surfaces.plan; ACP `plan`), plus a status line under the composer showing the
// session's model / mode and token / cost usage (ACP `usage_update`) - the local transport's "agentic"
// reply style demos all of it with no agent installed. The model / mode entries are MENUS when the
// agent offers choices: selecting sends session/set_config_option (with the spec's session/set_mode /
// set_model as fallbacks) and the display updates on the agent's confirmation, never optimistically.
// Plus the composer's slash-command menu: when a transport advertises commands (ACP
// `available_commands_update`), typing "/" lists and filters them and a tap fills the draft - the
// command still sends as ordinary prompt text for the agent to interpret. And agent-proposed file diffs
// now render inside the tool card's detail as a real line diff (the DiffView product of the sibling
// ActionUIDiff add-on, which these tool cards consume: hunks, old / new line-number gutters, +/-
// markers; routed by surfaces.diffs, "hidden" drops them). Transports are separate, statically linked
// modules behind a registry: "local" is the only built-in, and a host adds a protocol by linking its
// module (ActionUIChatOpenAI for "openai-sse", ActionUIChatACP for "acp") and calling its register() - or
// by linking the umbrella ActionUIChat product, whose register() wires every bundled transport at once; a
// protocol whose module was not registered degrades to "local". The "openai-sse" transport streams an
// OpenAI-compatible /v1/chat/completions endpoint (llama-server, mlx_lm.server, or any compatible server):
// plain streaming chat with reasoning folded into thoughts, tool calls rendered as (unexecuted) cards, and
// token usage in the status bar - no agent process required. Dual alignment and the remaining M5 surfaces
// (terminals, multi-session) arrive in later milestones (see Private/chat-element-design.md).
//
// Session transcript (P0-2): the element has no scalar value - its session transcript is CONTENT. A host
// RESTORES a saved session at runtime by injecting a serialized ChatTranscript (version, items, usage, plan,
// title) into states["content"], AFTER the interface is built - the same place Table / List keep their
// content, and the right vehicle for session DATA (a static UI document describes how to build the interface,
// not the conversation, and does not scale to carrying a transcript). Restore with a STABLE representation so
// REPEATED restores work (e.g. a session switcher reusing one element): pass a JSON string (or a native
// object) via setElementState("content", ...) - the store decodes either. setElementStateFromString is a
// one-time restore only (it stores a JSON-inferred object the first time, which core's type guard then
// refuses to re-set from a string); the simplest robust pattern is a fresh Chat element per session. readOnly
// makes it a pure viewer (no composer, no transport). Persistence flows the other way:
// entryActionID fires per finalized transcript entry with that entry's JSON, so the host stores incrementally
// as the conversation happens (keep the handler inexpensive - usage / plan updates can fire several times per
// turn). Session identity (ids, titles) stays app-side; the component only passes the optional title through
// untouched. `properties.content` pre-populates a transcript for previews / basic internal testing only - it
// is NOT the production restore path.
// The non-visual settings (protocol, transport) are NOT a document field: the element is built inert
// (no transport, disabled composer) and a HOST injects them at runtime into states["config"] via
// setElementState, after the element is built - the canonical embedding loads a static document, then
// injects the runtime/session-specific config (resolved agent path, working directory), then shows the
// view (see DemoApp). The transport is built once a viable config arrives and then FROZEN for that
// element's lifetime; a later states["config"] update does not rebuild it - use a fresh Chat element to
// switch protocol or transport.
//
// Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
// cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
