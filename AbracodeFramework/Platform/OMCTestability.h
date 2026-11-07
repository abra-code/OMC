//
//  OMCTestability.h
//  Abracode
//
//  Whether this process may serve the integration-test surface: the omc.test.* bridge methods
//  that `appletbuilder itest` uses to drive a real applet (Private/applet-integration-testing-design.md).
//  The surface lets another process run the applet's commands and answer its panels without the
//  Accessibility permission, so it must not exist in a build that is distributed. The rule is that
//  it exists only where a process of the same user can already run its own code inside the applet,
//  so it grants nothing new there. Platform code:
//  - macOS: from the running applet's own code signature (Platform/Apple/OMCTestability.mm).
//    Allowed only when the signature is valid, is not from a Developer ID or App Store certificate,
//    and either carries com.apple.security.get-task-allow (a debug build, which a debugger can
//    attach to) or has none of the hardened runtime, library validation and restrict flags (so
//    DYLD_INSERT_LIBRARIES already works on it). AppletBuilder's ad hoc and self-signed builds are
//    the second kind; its Developer ID builds always get the hardened runtime.
//  - Linux: no code signing, and LD_PRELOAD works on any process of the same user, so it is a build
//    setting instead: allowed when OMC_TEST_SURFACE is defined to 1, which debug builds do
//    (Platform/Linux/OMCTestability.cpp).
//
//  Even where it is allowed, the surface stays dormant unless the applet is launched with a test
//  token, so an applet the user opened normally cannot be taken over.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

typedef enum OMCTestSurfaceStatus
{
	kOMCTestSurface_Allowed = 0,
	kOMCTestSurface_NoValidSignature,		// unsigned, invalid, or the signature could not be read
	kOMCTestSurface_DistributionSigned,		// Developer ID or App Store certificate
	kOMCTestSurface_Hardened,				// hardened runtime, library validation or restrict, without get-task-allow
	kOMCTestSurface_NotInThisBuild			// a build that leaves the surface out (Linux without OMC_TEST_SURFACE)
} OMCTestSurfaceStatus;

// The answer for this process. Computed on the first call and the same afterwards. Any thread.
OMCTestSurfaceStatus OMCGetTestSurfaceStatus(void);

// A short English reason for a status, for the log line a refused test launch writes. Never NULL.
const char *OMCGetTestSurfaceStatusDescription(OMCTestSurfaceStatus inStatus);

#ifdef __cplusplus
}
#endif //__cplusplus
