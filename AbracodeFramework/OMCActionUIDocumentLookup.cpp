//
//  OMCActionUIDocumentLookup.cpp
//  Abracode
//
//  See OMCActionUIDocumentLookup.h. Moved from OMCActionUIWindowController.mm's resolveJSONURL:
//  as part of moving the ActionUI window's logic to portable C++; it did the same with NSBundle.
//

#include "OMCActionUIDocumentLookup.h"
#include "CFObj.h"

static CFURLRef
CopyBundleDocumentURL(CFBundleRef inBundle, CFStringRef inBaseName) noexcept
{
	if(inBundle == nullptr)
		return nullptr;
	CFObj<CFURLRef> resourceURL( ::CFBundleCopyResourceURL(inBundle, inBaseName, CFSTR("json"), nullptr) );
	if(resourceURL == nullptr)
		return nullptr;
	return ::CFURLCopyAbsoluteURL(resourceURL);
}

CFURLRef
OMCCopyActionUIDocumentURL(CFStringRef inNameOrPath, CFBundleRef inExternBundle, CFBundleRef inFrameworkBundle) noexcept
{
	if( (inNameOrPath == nullptr) || (::CFStringGetLength(inNameOrPath) == 0) )
		return nullptr;

	if( ::CFStringHasPrefix(inNameOrPath, CFSTR("/")) )
		return ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, inNameOrPath, kCFURLPOSIXPathStyle, false);

	// A last component of just ".json" keeps its name, as NSString's stringByDeletingPathExtension
	// did: stripped to nothing, CFBundleCopyResourceURL would return any .json resource
	CFObj<CFStringRef> baseName(inNameOrPath, kCFObjRetain);
	CFIndex length = ::CFStringGetLength(inNameOrPath);
	if( ::CFStringHasSuffix(inNameOrPath, CFSTR(".json")) && (length > 5) &&
		(::CFStringGetCharacterAtIndex(inNameOrPath, length - 6) != '/') )
	{
		baseName.Adopt( ::CFStringCreateWithSubstring(kCFAllocatorDefault, inNameOrPath, CFRangeMake(0, length - 5)) );
	}

	CFObj<CFURLRef> documentURL( CopyBundleDocumentURL(inExternBundle, baseName) );
	if(documentURL == nullptr)
		documentURL.Adopt( CopyBundleDocumentURL(::CFBundleGetMainBundle(), baseName) );
	if(documentURL == nullptr)
		documentURL.Adopt( CopyBundleDocumentURL(inFrameworkBundle, baseName) );
	return documentURL.Detach();
}
