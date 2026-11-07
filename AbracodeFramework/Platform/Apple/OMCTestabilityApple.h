//
//  OMCTestabilityApple.h
//  Abracode
//
//  The parts of Platform/Apple/OMCTestability.mm that the engine tests call directly: the decision
//  on its own, and the same reading of a signature applied to code on disk, so that tests can sign
//  a copy of a binary in each way and check the answer. The engine itself calls only
//  OMCGetTestSurfaceStatus (Platform/OMCTestability.h).
//

#pragma once

#include "OMCTestability.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif //__cplusplus

// The rule, from the facts a signature gives: whether it is valid, whether its certificate is a
// Developer ID or App Store one, whether it carries com.apple.security.get-task-allow, and its
// static code directory flags (kSecCodeInfoFlags).
OMCTestSurfaceStatus OMCDecideTestSurfaceStatus(bool inIsValid, bool inIsDistributionSigned, bool inHasGetTaskAllow, uint32_t inStaticFlags);

// The answer for the code at inPath (a Mach-O file or a bundle), validated statically, as if it
// were the running applet.
OMCTestSurfaceStatus OMCGetTestSurfaceStatusForCodeAtPath(const char *inPath);

#ifdef __cplusplus
}
#endif //__cplusplus
