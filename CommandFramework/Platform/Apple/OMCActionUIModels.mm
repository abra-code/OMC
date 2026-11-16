//
//  OMCActionUIModels.mm
//  Abracode
//
//  macOS implementation of OMCPlatformForgetActionUIModel (Platform/OMCActionUIModels.h).
//

#include "OMCActionUIModels.h"
#import <Foundation/Foundation.h>
@import ActionUIObjCAdapter;

void
OMCPlatformForgetActionUIModel(CFStringRef inWindowUUID)
{
	if(inWindowUUID == nullptr)
		return;
	[ActionUIObjC removeWindowWithWindowUUID:(__bridge NSString *)inWindowUUID];
}
