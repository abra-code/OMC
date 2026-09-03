//
//  OMCActionUIRemoteHost.h
//  Abracode
//
//  Process-wide owner of the ActionUI remote bridge: the Unix-socket JSON-RPC server that lets
//  a command handler read and drive the ActionUI windows of the applet that spawned it.
//
//  The server itself lives in the ActionUIRemote Swift package (see ActionUIRemote/PROTOCOL.md
//  for the wire contract); this class owns only its lifetime inside an OMC host, and the
//  OMC_ACTIONUI_REMOTE_ENDPOINT alias for the endpoint variable ActionUIRemote exports.
//
//  Lifetime, deliberately:
//
//   - Started lazily, from the first ActionUI window that is created, not at engine init. A
//     command file with no ActionUI window never binds a socket.
//   - Never stopped when the last window closes. The endpoint is inherited by children through
//     the environment, so tearing it down and rebinding on the next window would invalidate a
//     path an already-running script is holding, to save one file descriptor.
//   - Stopped once from -appWillTerminate: so the socket file is removed.
//
//  Read-only by design: the bridge adds what OMC could not do before, which is READING window
//  state out of process. Mutation continues to go through omc_dialog_control, which already
//  covers every verb, so no omc.* extension methods are registered here.
//
//  Main thread only. -ensureStarted is called from ActionUI window controller init and -stop
//  from the app-termination notification, both of which are main-thread events.
//
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The OMC-specific alias for ActionUIRemote's own ACTIONUI_REMOTE_ENDPOINT, exported so that OMC
/// scripts can use the OMC_-prefixed spelling every other engine variable uses.
extern NSString * const kOMCActionUIRemoteEndpointVariable;

@interface OMCActionUIRemoteHost : NSObject

/// The process's one host. Never nil.
+ (instancetype)shared;

/// Bind the server and publish the endpoint. A no-op once a bind has been attempted, whether it
/// succeeded or failed: a failure is logged once and not retried, so a broken temp directory
/// cannot produce one log line per window. `-stop` clears that latch, so a stopped bridge can be
/// started again by the next window.
- (void)ensureStarted;

/// Stop the server, remove its socket file, and unset both endpoint variables. Safe to call when
/// nothing was ever started. Leaves the host able to bind again.
- (void)stop;

/// The bound socket path while the server runs, nil otherwise.
@property (readonly, nonatomic, copy, nullable) NSString *endpoint;

@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
extern "C" {
#endif

/// The running server's socket path, or NULL when this process serves no bridge.
///
/// A plain C accessor because OnMyCommand.cp is compiled as C++ and cannot see an Objective-C
/// interface. It forwards to ActionUIRemote, so it answers for THIS process only - an OMC applet
/// launched by another one inherits OMC_ACTIONUI_REMOTE_ENDPOINT in its environment, and reading
/// that back would make the child advertise its parent's windows as its own.
const char *OMCGetActionUIRemoteEndpoint(void);

#ifdef __cplusplus
}
#endif
