//**************************************************************************************
// Filename:	CMUtilsAEFile.cp
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
//
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	static utilities for Contextual Menu Plugins
//
//
//**************************************************************************************

#include "CMUtils.h"
#include "StAEDesc.h"
#include <vector>

CFURLRef CopyURLFromFileURLAEDesc(const AEDesc &inDesc)
{
    Size byteCount = ::AEGetDescDataSize( &inDesc );
    std::vector<char> newBuffer(byteCount);
    if( ::AEGetDescData(&inDesc, newBuffer.data(), byteCount) != noErr)
        return nullptr;
    CFURLRef outURL = CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)newBuffer.data(), newBuffer.size(), kCFStringEncodingUTF8, nullptr);
    return outURL;
}

CFURLRef
CMUtils::CopyURL(const AEDesc &inDesc)
{
    if( (inDesc.descriptorType == typeFileURL) && (inDesc.dataHandle != nullptr) )
    {//no need to coerce
        TRACE_CSTR("\tCMUtils::CopyURL without coercing...\n" );
        return CopyURLFromFileURLAEDesc(inDesc);
    }
    else if( (inDesc.descriptorType != typeNull) && (inDesc.dataHandle != nullptr) )
    {
        StAEDesc coercedRef;
        OSErr err = ::AECoerceDesc( &inDesc, typeFileURL, coercedRef );
        if(err == noErr)
        {
            TRACE_CSTR("\tCMUtils::CopyURL with coercing...\n" );
            return CopyURLFromFileURLAEDesc(coercedRef);
        }
    }
    return nullptr;
}
