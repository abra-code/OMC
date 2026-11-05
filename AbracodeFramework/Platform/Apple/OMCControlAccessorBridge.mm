//
//  OMCControlAccessorBridge.mm
//  Abracode
//
//  The Objective-C half of OMCDialog's control access, moved here from OMCDialog.mm.
//

#include "OMCControlAccessorBridge.h"

namespace
{

class OMCControlAccessorBridge final : public OMCDialogControlAccessor
{
public:
	explicit OMCControlAccessorBridge(id<OMCControlAccessor> inController)
		: mController(inController)
	{
	}

	void SetControlValues(CFDictionaryRef inControlDict) noexcept override
	{
		@try
		{
			id<OMCControlAccessor> controller = mController;
			if((controller != nil) && (inControlDict != NULL))
				[controller setControlValues:inControlDict];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDialog SetControlValues received exception: %@", localException);
		}
	}

	void CopyAllControlValues(CFMutableDictionaryRef ioControlValues, CFMutableDictionaryRef ioCustomProperties,
							SelectionIterator *inSelIterator) noexcept override
	{
		@try
		{
			id<OMCControlAccessor> controller = mController;
			if(controller != nil)
				[controller allControlValues:(__bridge NSMutableDictionary *)ioControlValues
							   andProperties:(__bridge NSMutableDictionary *)ioCustomProperties
								withIterator:inSelIterator];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDialog CopyAllControlValues received exception: %@", localException);
		}
	}

	CFTypeRef CopyControlValue(CFStringRef inControlID, CFStringRef inControlPart, SelectionIterator *inSelIterator,
							CFDictionaryRef *outCustomProperties) noexcept override
	{
		if(outCustomProperties != NULL)
			*outCustomProperties = NULL;

		id outValue = nil;
		@try
		{
			id<OMCControlAccessor> controller = mController;
			if(controller != nil)
				outValue = [controller controlValueForID:(__bridge NSString *)inControlID
												 forPart:(__bridge NSString *)inControlPart
											withIterator:inSelIterator
										   outProperties:outCustomProperties];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCDialog CopyControlValue received exception: %@", localException);
		}
		return (CFTypeRef)CFBridgingRetain(outValue);
	}

private:
	__weak id<OMCControlAccessor> mController;
};

} // namespace

std::unique_ptr<OMCDialogControlAccessor>
OMCMakeControlAccessorBridge(id<OMCControlAccessor> inController)
{
	return std::make_unique<OMCControlAccessorBridge>(inController);
}
