//
//  OMCCocoaNib.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/17/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCCocoaNib.h"


@implementation OMCCocoaNib

- (id)initWithNib:(NSNib *)inNib
{
	mTopLevelNibObjects = NULL;

    self = [super init];
 	if(self == NULL)
		return NULL;

	if( (inNib != NULL) && [inNib instantiateWithOwner:self topLevelObjects:&mTopLevelNibObjects] )
	{
		[mTopLevelNibObjects retain];
		//NSLog(@"mTopLevelNibObjects=%@", mTopLevelNibObjects);
	}

    return self;
}

- (id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)inBundle
{
	mTopLevelNibObjects = NULL;

    self = [super init];
	if(self == NULL)
		return NULL;

	NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:inBundle];
	if(myNib != NULL)
	{
		if ([myNib instantiateWithOwner:self topLevelObjects:&mTopLevelNibObjects])
		{
			[mTopLevelNibObjects retain];
			//NSLog(@"mTopLevelNibObjects=%@", mTopLevelNibObjects);
		}
		[myNib release];
	}

    return self;
}

- (NSWindow *)getFirstWindow
{
	if(mTopLevelNibObjects == NULL)
		return NULL;
	
	NSWindow *firstWindow = NULL;
	NSUInteger topObjectCount = [mTopLevelNibObjects count];
	NSUInteger index = 0;
	for(index = 0; index < topObjectCount; index++)
	{
		id topObject = [mTopLevelNibObjects objectAtIndex:index];
		if( (topObject != NULL) && [topObject isKindOfClass:[NSWindow class]] )
		{
			firstWindow = (NSWindow *)topObject;
			break;
		}
	}

#if _DEBUG_
	
	for(index += 1; index < topObjectCount; index++)
	{
		id topObject = [mTopLevelNibObjects objectAtIndex:index];
		if( (topObject != NULL) && [topObject isKindOfClass:[NSWindow class]] )
		{
			NSLog(@"More than one window in the nib, only the first one can be used");
			break;
		}
	}
#endif //_DEBUG_

	return firstWindow;
}

- (void)dealloc
{
	[mTopLevelNibObjects release];
	[super dealloc];
}


@end
