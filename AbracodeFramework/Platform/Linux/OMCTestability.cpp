//
//  OMCTestability.cpp
//  Abracode
//
//  Linux implementation of Platform/OMCTestability.h. Not built yet: the Linux port has no build.
//  Linux has no code signing to read, and LD_PRELOAD already works on any process of the same user,
//  so the choice is made when OMC is built: a debug build defines OMC_TEST_SURFACE to 1, and so may a
//  special build made for testing. A release build leaves it out.
//

#include "OMCTestability.h"

OMCTestSurfaceStatus
OMCGetTestSurfaceStatus(void)
{
#if defined(OMC_TEST_SURFACE) && (OMC_TEST_SURFACE == 1)
	return kOMCTestSurface_Allowed;
#else
	return kOMCTestSurface_NotInThisBuild;
#endif
}

const char *
OMCGetTestSurfaceStatusDescription(OMCTestSurfaceStatus inStatus)
{
	switch(inStatus)
	{
		case kOMCTestSurface_Allowed:
			return "allowed: this build of OMC includes the test surface";
		case kOMCTestSurface_NoValidSignature:
			return "refused: the applet has no valid code signature, or it could not be read";
		case kOMCTestSurface_DistributionSigned:
			return "refused: the applet is signed with a distribution certificate";
		case kOMCTestSurface_Hardened:
			return "refused: the applet is hardened against code injection";
		case kOMCTestSurface_NotInThisBuild:
			return "refused: this build of OMC leaves the test surface out (build with OMC_TEST_SURFACE=1)";
	}
	return "refused: unknown status";
}
