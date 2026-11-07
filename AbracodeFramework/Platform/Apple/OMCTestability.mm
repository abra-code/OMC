//
//  OMCTestability.mm
//  Abracode
//
//  macOS implementation of Platform/OMCTestability.h: the decision is read from the running
//  applet's own code signature. See the header for the rule and why it is the rule.
//
//  The process's code object is the applet's main executable, not this framework, which is what
//  matters: the applet's signature decides what the kernel lets another process do to it.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "OMCTestability.h"
#include "OMCTestabilityApple.h"
#include "CFObj.h"
#include "ACFType.h"
#include <dispatch/dispatch.h>

namespace
{

// Distributed builds: anything Apple signs itself, and any certificate Apple issues except a
// development one. The development leaves are Mac Developer (1.2.840.113635.100.6.1.12) and iPhone
// Developer (1.2.840.113635.100.6.1.2); an Apple Development certificate carries both. Everything
// else under Apple's anchor is a distribution kind: Developer ID Application (1.13), the Mac App
// Store's own signing (1.9), TestFlight's, Apple Distribution, and any kind Apple adds later, so
// the list to keep is the short one that does not grow. A build signed this way never gets the
// surface, whatever its flags say. A certificate that does not chain to Apple (self-signed, for
// local use) is not matched.
const CFStringRef kDistributionRequirement = CFSTR("anchor apple or (anchor apple generic and !(certificate leaf[field.1.2.840.113635.100.6.1.12] or certificate leaf[field.1.2.840.113635.100.6.1.2]))");

// The static flags that stop DYLD_INSERT_LIBRARIES or an unsigned library from loading.
const uint32_t kInjectionBlockingFlags = kSecCodeSignatureRuntime | kSecCodeSignatureLibraryValidation | kSecCodeSignatureRestrict;

CFStringRef const kGetTaskAllowEntitlement = CFSTR("com.apple.security.get-task-allow");

// Whether a certificate-signed static code satisfies the distribution requirement. The checks it
// skips (resources, executable pages, network) are about whether the code is intact, which the caller
// has established already; what is asked here is only who signed it. Fails closed: any error other
// than "not satisfied" is reported as false in outReadable.
bool
IsDistributionSigned(SecStaticCodeRef inStaticCode, bool &outReadable)
{
	outReadable = false;
	CFObj<SecRequirementRef> requirement;
	OSStatus status = ::SecRequirementCreateWithString(kDistributionRequirement, kSecCSDefaultFlags, &requirement);
	if((status != errSecSuccess) || (requirement == nullptr))
		return false;

	const SecCSFlags flags = kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable | kSecCSNoNetworkAccess;
	status = ::SecStaticCodeCheckValidity(inStaticCode, flags, requirement);
	if(status == errSecSuccess)
	{
		outReadable = true;
		return true;
	}

	if(status == errSecCSReqFailed)
		outReadable = true;
	return false;
}

// The facts the decision needs, read from a signing-information dictionary, and the decision.
OMCTestSurfaceStatus
StatusFromSigningInformation(CFDictionaryRef inInfo, bool inIsValid, SecStaticCodeRef inStaticCode)
{
	if(!inIsValid || (inInfo == nullptr))
		return kOMCTestSurface_NoValidSignature;

	CFNumberRef flagsNumber = ACFType<CFNumberRef>::DynamicCast(::CFDictionaryGetValue(inInfo, kSecCodeInfoFlags));
	uint32_t flags = 0;
	if((flagsNumber == nullptr) || !::CFNumberGetValue(flagsNumber, kCFNumberSInt32Type, &flags))
		return kOMCTestSurface_NoValidSignature;

	bool isDistributionSigned = false;
	if((flags & kSecCodeSignatureAdhoc) == 0)
	{
		bool readable = false;
		isDistributionSigned = IsDistributionSigned(inStaticCode, readable);
		if(!readable)
			return kOMCTestSurface_NoValidSignature;
	}

	bool hasGetTaskAllow = false;
	CFDictionaryRef entitlements = ACFType<CFDictionaryRef>::DynamicCast(::CFDictionaryGetValue(inInfo, kSecCodeInfoEntitlementsDict));
	if(entitlements != nullptr)
	{
		CFBooleanRef value = ACFType<CFBooleanRef>::DynamicCast(::CFDictionaryGetValue(entitlements, kGetTaskAllowEntitlement));
		hasGetTaskAllow = (value != nullptr) && ::CFBooleanGetValue(value);
	}

	return OMCDecideTestSurfaceStatus(true, isDistributionSigned, hasGetTaskAllow, flags);
}

OMCTestSurfaceStatus
ComputeStatusForSelf()
{
	CFObj<SecCodeRef> code;
	OSStatus status = ::SecCodeCopySelf(kSecCSDefaultFlags, &code);
	if((status != errSecSuccess) || (code == nullptr))
		return kOMCTestSurface_NoValidSignature;

	// Dynamic validity is the kernel's own view of the running code (its CS_VALID flag), read
	// without hashing the bundle: a large applet with an embedded Python would otherwise spend
	// seconds here.
	CFObj<CFDictionaryRef> info;
	const SecCSFlags infoFlags = kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSDynamicInformation;
	status = ::SecCodeCopySigningInformation((SecStaticCodeRef)(SecCodeRef)code, infoFlags, &info);
	if((status != errSecSuccess) || (info == nullptr))
		return kOMCTestSurface_NoValidSignature;

	bool isValid = false;
	CFNumberRef statusNumber = ACFType<CFNumberRef>::DynamicCast(::CFDictionaryGetValue(info, kSecCodeInfoStatus));
	uint32_t codeStatus = 0;
	if((statusNumber != nullptr) && ::CFNumberGetValue(statusNumber, kCFNumberSInt32Type, &codeStatus))
		isValid = ((codeStatus & kSecCodeStatusValid) != 0);

	CFObj<SecStaticCodeRef> staticCode;
	status = ::SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &staticCode);
	if((status != errSecSuccess) || (staticCode == nullptr))
		return kOMCTestSurface_NoValidSignature;

	OMCTestSurfaceStatus result = StatusFromSigningInformation(info, isValid, staticCode);

	// Everything above was read from the file on disk, which can be replaced after launch: an ad hoc
	// copy renamed over a running hardened or Developer ID applet would otherwise answer for it. The
	// dynamic check compares the running code's directory hash with the one on disk
	// (errSecCSStaticCodeChanged) and validates only the code directory and its special slots, not
	// the bundle's resources, so it stays cheap. It comes last so it covers every read above.
	status = ::SecCodeCheckValidity(code, kSecCSDefaultFlags, nullptr);
	if(status != errSecSuccess)
		return kOMCTestSurface_NoValidSignature;

	return result;
}

} // namespace

OMCTestSurfaceStatus
OMCDecideTestSurfaceStatus(bool inIsValid, bool inIsDistributionSigned, bool inHasGetTaskAllow, uint32_t inStaticFlags)
{
	if(!inIsValid)
		return kOMCTestSurface_NoValidSignature;

	if(inIsDistributionSigned)
		return kOMCTestSurface_DistributionSigned;

	if(inHasGetTaskAllow)
		return kOMCTestSurface_Allowed;

	if((inStaticFlags & kInjectionBlockingFlags) != 0)
		return kOMCTestSurface_Hardened;

	return kOMCTestSurface_Allowed;
}

OMCTestSurfaceStatus
OMCGetTestSurfaceStatusForCodeAtPath(const char *inPath)
{
	if((inPath == nullptr) || (inPath[0] == 0))
		return kOMCTestSurface_NoValidSignature;

	CFObj<CFURLRef> url( ::CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)inPath, (CFIndex)strlen(inPath), false) );
	if(url == nullptr)
		return kOMCTestSurface_NoValidSignature;

	CFObj<SecStaticCodeRef> staticCode;
	OSStatus status = ::SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &staticCode);
	if((status != errSecSuccess) || (staticCode == nullptr))
		return kOMCTestSurface_NoValidSignature;

	// Not running, so there is no kernel view to ask: validate the code itself instead.
	status = ::SecStaticCodeCheckValidity(staticCode, kSecCSDefaultFlags | kSecCSNoNetworkAccess, nullptr);
	bool isValid = (status == errSecSuccess);

	CFObj<CFDictionaryRef> info;
	const SecCSFlags infoFlags = kSecCSSigningInformation | kSecCSRequirementInformation;
	status = ::SecCodeCopySigningInformation(staticCode, infoFlags, &info);
	if((status != errSecSuccess) || (info == nullptr))
		return kOMCTestSurface_NoValidSignature;

	return StatusFromSigningInformation(info, isValid, staticCode);
}

OMCTestSurfaceStatus
OMCGetTestSurfaceStatus(void)
{
	static OMCTestSurfaceStatus sStatus = kOMCTestSurface_NoValidSignature;
	static dispatch_once_t sOnce;
	dispatch_once(&sOnce, ^{
		sStatus = ComputeStatusForSelf();
	});
	return sStatus;
}

const char *
OMCGetTestSurfaceStatusDescription(OMCTestSurfaceStatus inStatus)
{
	switch(inStatus)
	{
		case kOMCTestSurface_Allowed:
			return "allowed: the applet is signed for local use";
		case kOMCTestSurface_NoValidSignature:
			return "refused: the applet has no valid code signature, or it could not be read";
		case kOMCTestSurface_DistributionSigned:
			return "refused: the applet is signed for distribution (Developer ID, App Store, TestFlight or another Apple certificate that is not a development one)";
		case kOMCTestSurface_Hardened:
			return "refused: the applet is signed with the hardened runtime, library validation or restrict, and without com.apple.security.get-task-allow";
		case kOMCTestSurface_NotInThisBuild:
			return "refused: this build of OMC leaves the test surface out";
	}
	return "refused: unknown status";
}
