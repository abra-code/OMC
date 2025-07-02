/*
	OMCQCView.m
*/

#import "OMCQCView.h"
#import "OMCDialogController.h"

@implementation OMCQCView

@synthesize tag;

- (id)init
{
    self = [super init];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

	return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == nil)
		return nil;

	self.escapingMode = @"esc_none";

    return self;
}

- (NSString *)stringValue
{
	return self.compositionPath;
}

- (void)setStringValue:(NSString *)aString
{
	if(self.compositionPath != nil)
	{
		[self stopRendering];
		[self unloadComposition];
		self.compositionPath = nil;
	}

	if(aString == nil)
		return;

	self.compositionPath = aString;

	BOOL isOK = [self loadCompositionFromFile:self.compositionPath];
	if(!isOK)
		NSLog(@"OMCQCView failed to load composition at \"%@\"", self.compositionPath);

	NSMutableDictionary* userInfo = [self userInfo];
	if( (userInfo != NULL) && (self.target != NULL) && [self.target respondsToSelector:@selector(getContext)])
	{
		id contextInfo = [self.target getContext];
		[userInfo setValue:contextInfo forKey:@"com.abracode.context"];
	}

	[self setAutostartsRendering:YES];
    [self setEventForwardingMask:NSEventMaskAny];
	[self startRendering];
}

- (BOOL) renderAtTime:(NSTimeInterval)time arguments:(NSDictionary*)arguments
{
	BOOL isOK = [super renderAtTime:time arguments:arguments];
	if(isOK)
	{
		NSMutableDictionary* userInfo = [self userInfo];
		if(userInfo != NULL)
		{
			id subcommand = [userInfo objectForKey:@"com.abracode.omc.subcommandId"];
			if( (subcommand != NULL) &&  [subcommand isKindOfClass:[NSString class]] )
			{
				[self setCommandID: (NSString *)subcommand];
				[userInfo removeObjectForKey:@"com.abracode.omc.subcommandId"];//we used it up, now remove from dictionary

				if( (self.target != NULL) && (self.action != NULL) )
				{
					[self.target performSelector:self.action withObject:self]; // = [(OMCDialogController*)_omcTarget handleAction:self];
				}
			}
		}
	}
	return isOK;
}

@end
