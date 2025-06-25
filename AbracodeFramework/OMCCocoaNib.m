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
    self = [super init];
 	if(self == nil)
		return nil;

    NSArray *topLevelObjects = nil;
	if( (inNib != nil) && [inNib instantiateWithOwner:self topLevelObjects:&topLevelObjects] )
	{
        self.topLevelNibObjects = topLevelObjects;
		//NSLog(@"mTopLevelNibObjects=%@", mTopLevelNibObjects);
	}

    return self;
}

- (id)initWithNibNamed:(NSString *)inNibName bundle:(NSBundle *)inBundle
{
    self = [super init];
	if(self == nil)
		return nil;

	NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:inBundle];
	if(myNib != nil)
	{
        NSArray *topLevelObjects = nil;
		if ([myNib instantiateWithOwner:self topLevelObjects:&topLevelObjects])
		{
            self.topLevelNibObjects = topLevelObjects;
			//NSLog(@"mTopLevelNibObjects=%@", mTopLevelNibObjects);
		}
	}

    return self;
}

- (NSWindow *)getFirstWindow
{
    NSArray *topLevelObjects = self.topLevelNibObjects;
	if(topLevelObjects == nil)
		return nil;
	
	NSWindow *firstWindow = nil;
    for (id topObject in topLevelObjects)
    {
        if( [topObject isKindOfClass:[NSWindow class]] )
        {
            firstWindow = (NSWindow *)topObject;
            break;
        }
    }

	return firstWindow;
}

@end
