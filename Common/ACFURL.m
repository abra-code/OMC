#include "ACFURL.h"
#import <Foundation/Foundation.h>

bool DeleteFile(CFURLRef fileURL)
{
    @autoreleasepool
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        return (bool)[fileManager removeItemAtURL:(NSURL*)fileURL error:NULL];
    }
}
