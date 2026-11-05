/*
	OMCViewSetupProtocol.h
*/

#import <Cocoa/Cocoa.h>

@protocol OMCViewSetupProtocol

@required
- (void)setupWithEnvironmentVariables:(NSDictionary *)envVars;

@end
