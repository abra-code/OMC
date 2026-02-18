//
//  OMCActionUIWindowController.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 2/17/26.
//  Copyright 2026 Abracode. All rights reserved.
//

#import "OMCActionUIWindowController.h"
#import "OMCActionUIDialog.h"
#import "OMCControlAccessor.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"
#include "ACFDict.h"
#include "OMCStrings.h"

@import ActionUIObjCAdapter;

@implementation OMCActionUIWindowController

- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super initWithOmc:inOmc commandRuntimeData:inCommandRuntimeData];
	if(self == nil)
		return nil;
    
    mOMCDialogProxy.Adopt( new OMCActionUIDialog() );
    mOMCDialogProxy->SetControlAccessor((__bridge void *)self);
    self->mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

	CommandDescription &currCommand = self->mPlugin->GetCurrentCommand();

	ACFDict params( currCommand.actionUIWindow );
    CFObj<CFStringRef> jsonName;
	params.CopyValue( CFSTR("JSON_NAME"), jsonName );

	if(jsonName == nullptr)
		return self;//no json name, no dialog
    
    NSString *__strong dialogJsonName = (NSString *)CFBridgingRelease(jsonName.Detach());

    CFObj<CFStringRef> initSubcommandID;
	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), initSubcommandID );
    self.dialogInitSubcommandID = (NSString *)CFBridgingRelease(initSubcommandID.Detach());
    
    CFObj<CFStringRef> endOKSubcommandID;
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), endOKSubcommandID );
    self.endOKSubcommandID = (NSString *)CFBridgingRelease(endOKSubcommandID.Detach());

    CFObj<CFStringRef> endCancelSubcommandID;
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), endCancelSubcommandID );
    self.endCancelSubcommandID = (NSString *)CFBridgingRelease(endCancelSubcommandID.Detach());

	Boolean isBlocking = true;//default is modal
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;

	//now we need to find out where our json is

	CFURLRef jsonURL = NULL;

	if(mExternBundleRef != NULL)
	{
		CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( mExternBundleRef ) );
		if(bundleURL != NULL)
		{
			CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
			if(bundlePath != nullptr)
			{
				NSString *path = (__bridge NSString *)bundlePath.Get();
				NSString *resourcePath = [[NSBundle bundleWithPath:path] resourcePath];
				if(resourcePath != nil)
				{
					NSString *fullPath = [resourcePath stringByAppendingPathComponent:dialogJsonName];
					if([[NSFileManager defaultManager] fileExistsAtPath:fullPath])
					{
						jsonURL = (__bridge CFURLRef)[NSURL fileURLWithPath:fullPath];
					}
				}
			}
		}
	}

	if(jsonURL == NULL)
	{
		NSString *mainResourcePath = [[NSBundle mainBundle] resourcePath];
		if(mainResourcePath != nil)
		{
			NSString *fullPath = [mainResourcePath stringByAppendingPathComponent:dialogJsonName];
			if([[NSFileManager defaultManager] fileExistsAtPath:fullPath])
			{
				jsonURL = (__bridge CFURLRef)[NSURL fileURLWithPath:fullPath];
			}
		}
	}

	if(jsonURL == NULL)
	{
		CFBundleRef frameworkBundleRef = mPlugin->GetBundleRef();
		if(frameworkBundleRef != NULL)
		{
			CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( frameworkBundleRef ) );
			if(bundleURL != NULL)
			{
				CFObj<CFStringRef> bundlePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
				if(bundlePath != nullptr)
				{
					NSString *path = (__bridge NSString *)bundlePath.Get();
					NSString *resourcePath = [[NSBundle bundleWithPath:path] resourcePath];
					if(resourcePath != nil)
					{
						NSString *fullPath = [resourcePath stringByAppendingPathComponent:dialogJsonName];
						if([[NSFileManager defaultManager] fileExistsAtPath:fullPath])
						{
							jsonURL = (__bridge CFURLRef)[NSURL fileURLWithPath:fullPath];
						}
					}
				}
			}
		}
	}

#if DEBUG
	NSLog(@"[OMCActionUIWindowController initWithOmc], jsonURL=%@", (__bridge id)jsonURL);
#endif

    return self;
}

#pragma mark - OMCControlAccessor protocol

- (void)setControlValues:(CFDictionaryRef)inControlDict
{
}

- (void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator
{
}

- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties
{
    return nil;
}

@end
