//
//  OMCActionUIRemoteHost.h
//  Abracode
//
//  Process-wide owner of the ActionUI remote bridge: the Unix-socket JSON-RPC server that lets
//  a command handler read and drive the ActionUI windows of the applet that spawned it.
//
//  The server itself lives in the ActionUIRemote Swift package (see ActionUIRemote/PROTOCOL.md
//  for the wire contract); this file owns only its lifetime inside an OMC host, and the
//  OMC_ACTIONUI_REMOTE_ENDPOINT alias for the endpoint variable ActionUIRemote exports.
//
//  Lifetime, deliberately:
//
//   - Started lazily, from the first ActionUI window that is created, not at engine init. A
//     command file with no ActionUI window never binds a socket.
//   - Never stopped when the last window closes. The endpoint is inherited by children through
//     the environment, so tearing it down and rebinding on the next window would invalidate a
//     path an already-running script is holding, to save one file descriptor.
//   - Stopped once when the app terminates, so the socket file is removed.
//
//  Read-only by design: the bridge adds what OMC could not do before, which is READING window
//  state out of process. Mutation continues to go through omc_dialog_control, which already
//  covers every verb, so no omc.* extension methods are registered here.
//
//  Main thread only. OMCEnsureActionUIRemoteBridgeStarted is called when an ActionUI window is
//  created and OMCStopActionUIRemoteBridge when the app terminates, both main-thread events.
//
//  Portable C++ (OMCActionUIRemoteHost.cpp), with a plain C interface so that C, C++ and
//  Objective-C callers all reach it.
//
#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bind the server and publish the endpoint. A no-op once a bind has been attempted, whether it
/// succeeded or failed: a failure is logged once and not retried, so a broken temp directory
/// cannot produce one log line per window. OMCStopActionUIRemoteBridge clears that latch, so a
/// stopped bridge can be started again by the next window.
void OMCEnsureActionUIRemoteBridgeStarted(void);

/// Stop the server, remove its socket file, and unset both endpoint variables. Safe to call when
/// nothing was ever started. Leaves the host able to bind again.
void OMCStopActionUIRemoteBridge(void);

/// The running server's socket path, or NULL when this process serves no bridge.
///
/// It forwards to ActionUIRemote, so it answers for THIS process only - an OMC applet launched by
/// another one inherits OMC_ACTIONUI_REMOTE_ENDPOINT in its environment, and reading that back
/// would make the child advertise its parent's windows as its own.
const char *OMCGetActionUIRemoteEndpoint(void);

/// Start the bridge now, bound at `inSocketPath`, instead of lazily from the first ActionUI window.
/// For a test launch (OMCTestHost.h), whose harness picks the path in a private directory of its
/// own and connects there. Main thread. Returns false when a bind was already attempted in this
/// process, or when this one failed (logged).
bool OMCStartActionUIRemoteBridgeAtPath(const char *inSocketPath);

/// A host method for the bridge, as ActionUIRemote's actionUIRemoteRegisterMethod takes it: called
/// on the main thread with the request's params as JSON text, it returns a JSON reply,
/// {"result": ...} or {"error": {"code": ..., "message": ...}}, in a malloc buffer the bridge frees.
typedef char *(*OMCActionUIRemoteMethod)(void *inContext, const char *inMethod, const char *inParamsJSON);

/// Register a host method on the running bridge (forwards to actionUIRemoteRegisterMethod). False
/// when no bridge runs or the name is refused (not namespaced, or in actionui.).
bool OMCRegisterActionUIRemoteMethod(const char *inMethod, OMCActionUIRemoteMethod inCallback, void *inContext);

/// Turn on the bridge's actionui.performAction, which fires an element's action as a click would
/// (forwards to actionUIRemoteEnablePerformAction). Only a test launch does this. False when no
/// bridge runs.
bool OMCEnableActionUIRemotePerformAction(void);

/// Register a token the caller was handed, under inLabel (forwards to actionUIRemoteAddToken).
/// False when no bridge runs or an argument is empty.
bool OMCAddActionUIRemoteToken(const char *inToken, const char *inLabel);

/// The descriptor a spawned handler reads its token from, and the number the engine exports as
/// ACTIONUI_REMOTE_TOKEN_FD. 3 because that is what the shell clients' `actionui_handoff` uses
/// and what ActionUIRemote/Shell/README.md documents, so the two creators of these pipes agree.
#define kOMCActionUIRemoteTokenFD 3

/// Big enough for anything OMCMintActionUIRemoteToken produces (64 hex characters and a
/// terminator today), with room to spare so a caller's fixed array need not track the encoding.
#define kOMCActionUIRemoteTokenBufferSize 128

/// Mint one token for a unit of work, register it with the running server under `inLabel`, and
/// copy it into `outToken`.
///
/// The engine calls this once per spawned handler, labeling with the command's GUID so that one
/// command's grants can be withdrawn together. The token is then handed to the child on a
/// descriptor by omc_popen_with_token and never appears in its environment - see omc_popen.h for
/// why that distinction is the whole point.
///
/// Returns false when this process serves no bridge, when the label is empty, or when the buffer
/// is too small; nothing is written to `outToken` in that case and the caller spawns without a
/// token, exactly as before.
bool OMCMintActionUIRemoteToken(const char *inLabel, char *outToken, size_t inTokenSize);

/// Withdraw every token minted under `inLabel`. Not called per command today - see the commit
/// note on the revocation policy - but the engine's route to a tighter one, and the reason the
/// labels are command GUIDs rather than anything coarser.
void OMCRevokeActionUIRemoteTokens(const char *inLabel);

#ifdef __cplusplus
}
#endif
