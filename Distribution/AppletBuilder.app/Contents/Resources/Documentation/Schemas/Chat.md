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
                                          //   "dual": outgoing (self) trailing with the role tint, incoming leading -
                                          //   the messaging-app layout for person-to-person / group chat.
       "showRoleLabels": true,            //   Show a small role label above each message; default true.
       "theme": "auto",                   //   "auto" | "light" | "dark"; default "auto".
       "showTimestamps": true,            //   Time caption under a run + day separators; default true in "dual",
                                          //   false in "single". Renders only on items that carry a timestamp.
       "showAvatars": false,              //   Sender avatar (initials disc when none resolves) beside incoming
                                          //   messages; default false (opt-in).
       "showDeliveryStatus": true         //   Delivery caption (Sending / Sent / Delivered / Read, Failed w/ retry)
                                          //   under the last own message of a run; default true. Renders only on
                                          //   messages that carry a status (v1 messages never do).
     },
     "roles": {                           // Optional: per-role label / tint / side. In "dual", self (role "local"
                                          //           or a participant marked isSelf) aligns trailing and others
                                          //           leading; an explicit per-role "side" overrides that.
       "local": { "label": "You",   "tint": "accent" },
       "agent": { "label": "Agent", "tint": "secondary" }
     },
     "features": {                        // Optional: person-to-person / group affordances the document enables.
       "reactions": false,                //   All default false (opt-in). An affordance appears only when the
       "editing": false,                  //   document enables it AND the active transport advertises the matching
       "deletion": false,                 //   capability. reactions: emoji reactions (quick row + chips). editing:
       "replies": false                   //   edit own messages ("(edited)" badge). deletion: delete own messages
     },                                   //   ("Message deleted" tombstone). replies: reply to / quote a message.
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
     "attachActionID": "chat.attach",     // Optional: shows the composer's attach (paperclip) button; fired on tap.
                                          //           The host mediates the picker and hands the file to its transport
                                          //           out of band. The ONLY person-to-person host action ID - every
                                          //           other v2 affordance (reactions, edits, replies, deletes, read
                                          //           marks, paging, typing) flows to the transport as a command.
     "entryActionID": "chat.entry",       // Optional: fired per FINALIZED transcript entry (message, thought,
                                          //           completed/failed tool call, image, system, error, plan,
                                          //           usage) with a JSON envelope { sequence, type, id, data } as
                                          //           the action context, for crash-safe incremental persistence.
                                          //           A message that states["lead"] lines were placed in front of
                                          //           also carries them, as placed, under "lead".
                                          //           Never fired on streaming deltas.
     "resumeCheckpointActionID": "chat.checkpoint",
                                          // Optional: the resume cursor that pairs with entryActionID, as
                                          //           { afterSeq, sessionId } JSON in the action context. Fired only
                                          //           while the transcript is QUIESCENT (a turn boundary, or catching
                                          //           up after an attach), never mid-stream, and only when
                                          //           entryActionID is ALSO set - a host that is not storing entries
                                          //           is not offered a cursor. Persist it atomically with the
                                          //           entries: a newer cursor loses what is in between, an older one
                                          //           duplicates it, and storing neither half is always safe. Feed it
                                          //           back as the transport's "resumeAfterSeq" (with "session").
                                          //           Only the "acp-remote" protocol produces one.
     "showFindBar": true,                 // Optional (default true, so every existing document gains it): the find
                                          //           bar over the conversation - Cmd-F opens it, and while it is shown
                                          //           Cmd-G / Shift-Cmd-G walk the hits across messages (opening a
                                          //           folded thought or tool card the hit is in) and Escape closes; its
                                          //           menu widens the scope to thoughts and tool calls and toggles
                                          //           case / whole-word / diacritic matching. false removes the bar
                                          //           and the Cmd-F (which one element per window should own); a
                                          //           states["search"] query still highlights.
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
                                         //           agent over stdio. "acp-remote" (same module) drives an ACP agent
                                         //           on ANOTHER machine over a WebSocket to a chatview-acp-bridge;
                                         //           it owns no subprocess, so it is not macOS-only. A protocol whose
                                         //           module the host did not register degrades to "local".
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
                                         //           "acp-remote" honors "session" ("new" by default, or a bridge
                                         //           session id to rejoin) and "resumeAfterSeq" (the afterSeq from
                                         //           the last resumeCheckpointActionID cursor - ignored unless
                                         //           "session" names a session). This is the return half of the
                                         //           persistence round trip: store the cursor with the transcript,
                                         //           then inject the transcript into states["content"] and the
                                         //           cursor here, and the bridge replays only what came after it.
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
// session/cancel. The same module also registers "acp-remote", which speaks that protocol to an agent
// on ANOTHER machine over a WebSocket to a chatview-acp-bridge, on every platform - it owns no
// subprocess, and it is the only transport that emits resume checkpoints. And the first M5
// session-status surfaces: the agent's evolving plan pinned above the transcript (routed by
// surfaces.plan; ACP `plan`), plus a status line under the composer showing the
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
// modules behind a registry: "local" (a scripted echo / agentic demo) and "local-p2p" (a scripted
// person-to-person / group demo) are built in, and a host adds another protocol by linking its
// module (ActionUIChatOpenAI for "openai-sse", ActionUIChatACP for both "acp" and "acp-remote")
// and calling its register() - or by linking the umbrella ActionUIChat product, whose register()
// wires every bundled transport at once; a
// protocol whose module was not registered degrades to "local". The "openai-sse" transport streams an
// OpenAI-compatible /v1/chat/completions endpoint (llama-server, mlx_lm.server, or any compatible server):
// plain streaming chat with reasoning folded into thoughts, tool calls rendered as (unexecuted) cards, and
// token usage in the status bar - no agent process required.
//
// And person-to-person / group chat (appearance.alignment "dual"): your messages align trailing with the
// role tint, everyone else's leading, the messaging-app layout. It adds - all additive, all optional, so a
// v1 document is unchanged - message timestamps and day separators, per-sender names and avatars (or an
// initials disc), delivery status (Sending / Sent / Delivered / Read, and Failed with tap-to-retry), emoji
// reactions, replies (a tappable quoted-excerpt block), message editing and deletion (a tombstone), member
// and call events (centered captions), file and voice-message items (a transfer progress bar / an audio
// player), a typing indicator, and paged history (scroll to the top to load earlier). Each interactive
// affordance appears only when the document enables it (the "features" object) AND the active transport
// advertises the matching capability; those conversation actions flow to the transport as commands, and the
// sole new host action ID is "attachActionID" (the composer's attach button). The built-in "local-p2p"
// transport scripts all of it with no wire (the ChatPeople / ChatGroup examples). The remaining surfaces
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
//
// APPENDING ONE ITEM: states["append"] takes a single serialized ChatItem and adds it to the END of the
// conversation already on screen. states["content"] cannot serve this - it REPLACES the transcript and
// re-primes the agent - so a host with one line to add had to choose between re-priming the whole
// conversation to show it and not showing it until the next load. The case this exists for is a session
// marker: which model is about to answer, or that the conversation was resumed against a summary of its
// older half. Setting this state appends and nothing else - no transport traffic, no re-prime.
//   setElementState(window, chatID, "append",
//                   {"type":"sessionEvent","sessionEvent":{"id":"se-1","kind":"resumed","model":"Qwen3 4B"}})
// LIKE states["content"], IT DOES NOT COME BACK THROUGH entryActionID. Both are the host saying "here is
// something you already have"; persistence flows the other way, per finalized entry, and a host that
// appends an item it just wrote to its own store would otherwise receive it back and write it twice.
// The id is the dedup key: the state re-delivers on every state change, so re-setting the same item is a
// no-op rather than a second line, and an id already in the transcript is ignored.
// Appending a MESSAGE rather than a marker puts a line on screen the agent was never given - the element
// reports its context as pending and the next send re-primes, so the status indicator does not claim the
// model holds something it does not.
//
// LEADING THE NEXT MESSAGE: states["lead"] takes serialized ChatItems - ONE PER LINE - and HOLDS them
// until the user sends, then places them in front of that message. states["append"] cannot serve this,
// and the reason is a matter of timing rather than taste: a host learns a message exists when its entry
// finalizes, by which time it has been on screen since the user pressed Return, so the marker naming the
// model it was sent INTO lands underneath it. There is no "insert before"; what was missing was a way to
// say "when there is a next message, this goes in front of it".
//   setElementState(window, chatID, "lead",
//                   "{\"type\":\"sessionEvent\",\"sessionEvent\":{\"id\":\"se-1\",\"kind\":\"resumed\"}}")
// THE WAITING IS THE OTHER HALF OF THE POINT. A conversation the user opened and read is not a
// conversation resumed, so a marker shown when the transcript was displayed announces a handover that
// never happened - once per row the user clicks through. Held here, the line exists only if a message
// follows it, which is also the moment a host records one.
// THE VALUE IS THE WHOLE WAITING LIST: set it again, with every line, to add one; set it to "" to take the
// lines back when the conversation they belong to is replaced (an empty array, or text with no lines in
// it, withdraws the same way, while a value NONE of whose lines decode is not obeyed as a withdrawal and
// leaves the list as it was). A line already placed is never placed again, whatever the channel goes on
// resting on, and a line whose id is already in the transcript is not placed. One line that will not
// decode costs that line, not the list.
// THE LINES FIRE NO ENTRY OF THEIR OWN, BUT THE MESSAGE THEY LEAD REPORTS THEM: its entryActionID envelope
// carries them under "lead", as placed, and that is where a host records them from. As placed, because the
// element changes one thing: a line handed over without a timestamp is stamped with the moment it is
// placed. The host hands the line over when it learns it will be needed - the conversation displayed, the
// engine loaded - and the user may not type for an hour; the line says what happened when the message was
// sent, and only the send knows that moment. A host that stamps its lines keeps its stamps.
//
// SEARCHING THE CONVERSATION: states["search"] takes a query String. A non-empty value runs the transcript
// find - the same engine as the Cmd-F bar: Markdown bodies matched as RENDERED text, so a bold "fox" is
// found by "fox"; thoughts and tool calls only when the bar's scope includes them - highlights every hit,
// scrolls to the first, and presents the bar with the term when "showFindBar" is on; "" dismisses. This is how a
// host's OWN search field (a chat list filtered by a term) opens a conversation with the reason it matched
// already lit, without taking the keyboard focus from the host's field. Always a String, never an object
// (the element seeds the key as one, so any text is accepted), and nil - the key never set - is no
// opinion. The channel re-delivers its current value
// on every states change, so a value equal to the last one applied is ignored: the reader can close the
// bar without it springing back; to re-open with the same term, set "" and then the term again.
//   setElementState(window, chatID, "search", "deployment")
// The search needs no element at all for a host that filters a chat list: ChatSearch (re-exported from
// ChatView) runs the same rules over a decoded ChatTranscript, and ChatItem.searchableText gives an
// indexer the plain text a reader sees.
//
// Two TRANSIENT keys ride on that injected object alongside version / items, and neither is ever
// persisted - the transcript codec drops both, so they cannot reach storage or a later restore:
//   "prime": how the restored transcript relates to the agent's CONTEXT, which is a separate thing from
//            what is displayed. true / absent - replay it into the agent now (the default). false -
//            display it against a FRESH, empty context, so continuing types against nothing rather than
//            against a conversation the agent never received. "defer" - display only and sync lazily on
//            the next send, which is what makes browsing a session list free: switching costs nothing
//            until the user actually says something.
//   "condense": { "keepRecentTurns": 6, "maxDigestTokens": 700 } - ask the agent to SUMMARIZE the older
//            part of the restore instead of replaying all of it, keeping the trailing messages verbatim.
//            Both bounds are optional and the agent clamps them; PRESENCE OF THE KEY IS THE REQUEST, so
//            an empty object means "summarize, your defaults" rather than "do nothing". Needs a transport
//            whose agent supports it (the ACP `session/prime` condense extension); anything else ignores
//            it. THE FALLBACK IS FULL FIDELITY, NEVER TRUNCATION - an agent that cannot summarize, or
//            declines to, primes the COMPLETE history, so a caller that ignores the outcome still gets a
//            correct session and merely pays for a slower first turn.
// When a restore IS condensed the element appends a sessionEvent item carrying the digest - which model
// wrote the summary, how many messages it replaced, and the summary itself in sections. That item is a
// normal transcript entry (entryActionID fires for it, and it persists with the conversation), because a
// summary the model holds and the reader cannot see is a context loss they can only infer from the answers
// getting worse; shown it, they can restate whatever it missed.
//
// The non-visual settings (protocol, transport) are NOT a document field: the element is built inert
// (no transport, disabled composer) and a HOST injects them at runtime into states["config"] via
// setElementState, after the element is built - the canonical embedding loads a static document, then
// injects the runtime/session-specific config (resolved agent path, working directory), then shows the
// view (see DemoApp). The transport is built when the first VIABLE config arrives. Re-injecting an
// IDENTICAL config afterwards is a no-op - the channel re-delivers its current value on every states
// change - while a DIFFERENT viable config RE-CONFIGURES the element in place: a turn in flight is
// closed first (its partial answer kept, its entries fired), the old transport is stopped (an ACP agent
// gets SIGTERM, then SIGKILL after a grace), and the new one is attached and primed from the transcript
// on screen. That is how a host changes the model or the agent behind a LIVE conversation - inject the
// new {protocol, transport} and the conversation carries over, no new element needed. A config that
// differs only in a key the transport ignores counts as different, which is the way to force a fresh
// process from otherwise identical settings (add e.g. "sessionEpoch").
//
// Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
// cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
