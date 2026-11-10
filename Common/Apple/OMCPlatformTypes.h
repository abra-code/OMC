//
//  OMCPlatformTypes.h (Apple)
//
//  What OMC's portable code takes from the platform beyond CoreFoundation: the classic error codes
//  (noErr, paramErr, userCanceledErr, ...) and, for OMC.h's Apple event entry points, AEDesc. One
//  header per platform, chosen by the header search path (Common/Apple or Common/Linux), as
//  OMCUserTempDirPlatform.h is. Included by OMC.h, and by portable code that names an error code
//  without including OMC.h. Here: CoreServices, which has them all.
//

#pragma once

#include <CoreServices/CoreServices.h>
