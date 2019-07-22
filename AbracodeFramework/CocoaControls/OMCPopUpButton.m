/*
	OMCPopUpButton.m
*/

#import "OMCPopUpButton.h"
#import "OMCMenuItem.h"

@implementation OMCPopUpButton

@synthesize commandID;

- (id)init
{
    self = [super init];
	if(self == NULL)
		return NULL;
	commandID = NULL;
    return self;
}

- (void)dealloc
{
    [commandID release];
    [super dealloc];
}


- (NSString *)escapingMode
{
	NSMenuItem *selItem = [self selectedItem];
	if( selItem != NULL )
	{
		if( [selItem respondsToSelector:@selector(escapingMode)] )
		{
			NSString *escMode = [selItem performSelector:@selector(escapingMode)];
			if( escMode != NULL )
				return escMode;
		}
	}

	return @"esc_none";
}


- (NSString *)stringValue
{
	NSMenuItem *selItem = [self selectedItem];
	if( selItem != NULL )
	{
		if( [selItem respondsToSelector:@selector(mappedValue)] )
		{
			//OMCMenuItem responds to that and may have a mapping
			NSString *mappedValue = [selItem performSelector:@selector(mappedValue)];
			if( mappedValue != NULL )
				return mappedValue;
		}
		//default implementation returns selected menu item number. OMC returns menu item string
		return [selItem title];
	}

	return [super stringValue];
}

//do the mapping here or fall back to NSPopUpButton implementation
- (void)selectItemWithTitle:(NSString *)title
{
	NSArray *itemArray = [self itemArray];
	if( (itemArray == NULL) || (title == NULL) )
		return;

	int itemCount = [itemArray count];
	int itemIndex;
	for(itemIndex = 0; itemIndex < itemCount; itemIndex++)
	{
		NSMenuItem *menuItem = [itemArray objectAtIndex:itemIndex];
		if( (menuItem != NULL) && [menuItem respondsToSelector:@selector(mappedValue)] )
		{
			NSString *mappedValue = [menuItem performSelector:@selector(mappedValue)];
			if( (mappedValue != NULL) && [mappedValue isEqualToString:title] )
			{
				[self selectItemAtIndex:itemIndex];
				return;
			}
		}
	}
	
	return [super selectItemWithTitle:title];
}

//legacy encoder/decoder support - custom control data no longer serialized into nibs
//custom properties get set later on nib load by calling proprty setters

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
	if(self == NULL)
		return NULL;

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed decoding"];
	
	commandID = [[coder decodeObjectForKey:@"omcCommandID"] retain];

	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];

    if( ![coder allowsKeyedCoding] )
		[NSException raise:NSInvalidArgumentException format:@"Unexpected coder not supporting keyed encoding"];

	if(commandID != NULL)
		[coder encodeObject:commandID forKey:@"omcCommandID"];
}

@end
