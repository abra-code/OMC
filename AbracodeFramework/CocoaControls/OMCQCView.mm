/*
	OMCQCView.m
*/

#import "OMCQCView.h"
#import "OMCDialogController.h"

@implementation OMCQCView

@synthesize commandID;
@synthesize tag;
@synthesize escapingMode;

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

- (void)dealloc
{
	self.escapingMode = nil;
	self.commandID = nil;
	[_compositionPath release];
	[_omcTarget release];
    [super dealloc];
}

- (id)target
{
	return _omcTarget;
}

- (void)setTarget:(id)anObject;
{
	[anObject retain];
	[_omcTarget release];
	_omcTarget = anObject;	
}

- (void)setAction:(SEL)aSelector
{
	_omcTargetSelector = aSelector;
}


- (NSString *)stringValue
{
	return _compositionPath;
}

- (void)setStringValue:(NSString *)aString
{
	if(_compositionPath != nil)
	{
		[self stopRendering];
		[self unloadComposition];
		[_compositionPath release];
		_compositionPath = nil;
	}

	if(aString == NULL)
		return;

	_compositionPath = [aString retain];

	BOOL isOK = [self loadCompositionFromFile:_compositionPath];
	if(!isOK)
		NSLog(@"OMCQCView failed to load composition at \"%@\"", _compositionPath);

	NSMutableDictionary* userInfo = [self userInfo];
	if( (userInfo != NULL) && (_omcTarget != NULL) && [_omcTarget respondsToSelector:@selector(getCFContext)])
	{
		id contextInfo = [_omcTarget getCFContext];
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

				if( (_omcTarget != NULL) && (_omcTargetSelector != NULL) )
				{
					[_omcTarget performSelector:_omcTargetSelector withObject:self]; // = [(OMCDialogController*)_omcTarget handleAction:self];
				}
			}
		}
	}
	return isOK;
}

@end
