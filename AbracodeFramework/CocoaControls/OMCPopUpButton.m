/*
	OMCPopUpButton.m
*/

#import "OMCPopUpButton.h"
#import "OMCMenuItem.h"

@implementation OMCPopUpButton

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
	NSArray<NSMenuItem *> *itemArray = [self itemArray];
	if( (itemArray == NULL) || (title == NULL) )
		return;

	for(NSMenuItem *menuItem in itemArray)
	{
		if( [menuItem respondsToSelector:@selector(mappedValue)] )
		{
			NSString *mappedValue = [menuItem performSelector:@selector(mappedValue)];
			if( (mappedValue != NULL) && [mappedValue isEqualToString:title] )
			{
				[self selectItem:menuItem];
				return;
			}
		}
	}
	
	return [super selectItemWithTitle:title];
}

@end
