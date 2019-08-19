/*
 *  OmcExecutor.h
 *  OnMyCommandCM
 *
 *  Created by Tomasz Kukielka on Thu Aug 21 2003.
 *  Copyright (c) 2003 Abracode, Inc. All rights reserved.
 *
 */

#include <Carbon/Carbon.h>
#include "DebugSettings.h"
#include "CFObj.h"
#include "ANotifier.h"
#include "AObserver.h"
#include "ARefCounted.h"
#include "ACFDict.h"
#include "omc_popen.h"
#include <vector>
#include <string>

char ** CreateEnvironmentList(CFDictionaryRef inEnviron);

class OmcTaskManager;
class OutputWindowHandler;
class CommandDescription;

class OmcExecutor : public ARefCounted
{
public:
						OmcExecutor(CFBundleRef inBundleRef)
							: mNotifier( new ANotifier() ),
							mCancelObserver( new AObserver<OmcExecutor>(this) ),
							mBundleRef(inBundleRef, kCFObjRetain),
							/*mIsFinishing(false),*/ mTaskIndex(0)
						{
#if _DEBUG_
							if( (CFBundleRef)mBundleRef != NULL)
							{
								CFIndex retainCount = ::CFGetRetainCount( (CFBundleRef)mBundleRef );
								DEBUG_CSTR("OmcExecutor::OmcExecutor. CFBundleRef retain count after retaining it is %d\n", (int)retainCount );
							}
							else
							{
								DEBUG_CSTR("OmcExecutor::OmcExecutor. Passed NULL CFBundleRef!\n");
							}
#endif
						}

	virtual				~OmcExecutor(void)
						{
							TRACE_CSTR( "OmcExecutor::~OmcExecutor\n");
							
							if( mCancelObserver != NULL )
								mCancelObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

#if _DEBUG_
							if( (CFBundleRef)mBundleRef != NULL)
							{
								CFIndex retainCount = ::CFGetRetainCount( (CFBundleRef)mBundleRef );
								DEBUG_CSTR("OmcExecutor::~OmcExecutor. CFBundleRef retain count before release is %d\n", (int)retainCount );
							}
							else
							{
								DEBUG_CSTR("OmcExecutor::~OmcExecutor. CFBundleRef is NULL!\n");
							}
#endif
						}

	
	virtual bool		ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe );
	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);
	virtual void		Cancel() { Finish(false, false, noErr); }
	virtual void		ProcessOutputData(const void *inData, size_t inSize);
	virtual void		ProcessOutputString(CFStringRef inString);
	
	virtual bool		UsesOutputWindow() const { return false; }
	
	void				AddObserver(AObserverBase *inObserver)
						{
							mNotifier->AddObserver( inObserver );
						}

	void				ReportToManager(OmcTaskManager *inTaskManager, CFIndex inTaskIndex);
	CFIndex				GetTaskIndex() const { return mTaskIndex; }
	virtual pid_t		GetChildProcessID() const { return getpid(); }

	void				ReceiveNotification(void *ioData);//for cancel message

protected:
	virtual void		SetInputString( CFStringRef /*inInputPipe*/ ) { }
	virtual bool		Execute( const char *inCommand, OSStatus &outError ) = 0; //return true if task finished

protected:

	ARefCountedObj< ANotifier > mNotifier;
	ARefCountedObj< AObserver<OmcExecutor> > mCancelObserver;
	CFObj<CFStringRef>	mTaskManagerID;
	CFObj<CFBundleRef>	mBundleRef;
//	Boolean				mIsFinishing;
	CFIndex				mTaskIndex;//task manager assigns task index to us for its own purposes
};


class POpenExecutor
	: public OmcExecutor
{
public:
						
						POpenExecutor(const CommandDescription &inCommandDesc, CFBundleRef inBundle, CFDictionaryRef inEnviron);
	virtual				~POpenExecutor();

	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);
	virtual pid_t		GetChildProcessID() const { return mChildProcessInfo.pid; }
	
	void				CloseWriting();
	void				WriteInputStringChunk();


protected:
	virtual void		SetInputString( CFStringRef inInputPipe );
	virtual bool		Execute( const char *inCommand, OSStatus &outError );

protected:

	CFObj<CFArrayRef>		mCustomShell;
	CFObj<CFDictionaryRef>	mEnvironmentVariables;

	ChildProcessInfo		mChildProcessInfo;
	CFSocketRef				mReadSocket;
	CFSocketRef				mWriteSocket;
	CFRunLoopSourceRef		mReadSource;
	CFRunLoopSourceRef		mWriteSource;

	std::string		        mInputString;
	ByteCount				mWrittenInputBytesCount;
};

class POpenWithOutputExecutor
	: public POpenExecutor
{
public:
						POpenWithOutputExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
												CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
												CFDictionaryRef inEnviron);
	virtual				~POpenWithOutputExecutor();

	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);

	virtual bool		UsesOutputWindow() const { return true; }

protected:
	virtual bool		Execute( const char *inCommand, OSStatus &outError );

protected:
	CFObj<CFDictionaryRef>		mSettingsDict;
	CFObj<CFArrayRef>			mCommandName;
	CFObj<CFStringRef>			mDynamicCommandName;
	CFObj<CFBundleRef>			mExternBundleRef;
	CFObj<CFStringRef>			mLocalizationTableName;	
};

class SystemExecutor
	: public OmcExecutor
{
public:
						SystemExecutor(CFBundleRef inBundle)
							: OmcExecutor(inBundle)
						{
						}

	virtual				~SystemExecutor()
						{
						}

protected:
	virtual bool		Execute( const char *inCommand, OSStatus &outError );

};

class AppleScriptExecutor
	: public OmcExecutor
{
public:
						AppleScriptExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
											CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
											Boolean useOutputWindow);
	virtual				~AppleScriptExecutor();

	virtual bool		ExecuteCFString( CFStringRef inCommand, CFStringRef inInputPipe );

//	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);

	virtual bool		UsesOutputWindow() const { return mUseOutput; }
	static OSErr		OSAActiveProc(SRefCon refCon);

protected:
	ComponentInstance		mOSAComponent;
	OSAActiveUPP			mActiveUPP;
	CFObj<CFDictionaryRef>	mSettingsDict;
	CFObj<CFArrayRef>		mCommandName;
	CFObj<CFStringRef>		mDynamicCommandName;
	CFObj<CFBundleRef>		mExternBundleRef;
	CFObj<CFStringRef>		mLocalizationTableName;
	bool					mUseOutput;

private:
	virtual bool		Execute( const char *, OSStatus &outError ) { outError = noErr; return true; }//unused

};



class ShellScriptExecutor
	: public POpenExecutor
{
public:
						ShellScriptExecutor(const CommandDescription &inCommandDesc, CFBundleRef inBundle, CFDictionaryRef inEnviron)
							: POpenExecutor(inCommandDesc, inBundle, inEnviron)
						{
						}
						
	virtual				~ShellScriptExecutor()
						{
						}

	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);

protected:
	virtual bool		Execute( const char *inCommand, OSStatus &outError );

protected:
	std::string mTempScriptPath;
};

class ShellScriptWithOutputExecutor
	: public ShellScriptExecutor
{
public:
						ShellScriptWithOutputExecutor(const CommandDescription &inCommandDesc, CFStringRef inDynamicName,
														CFBundleRef inBundleRef, CFBundleRef inExternBundleRef,
														CFDictionaryRef inEnviron);
	virtual				~ShellScriptWithOutputExecutor();

	virtual void		Finish(bool wasSynchronous, bool sendNotification, OSStatus inError);

	virtual bool		UsesOutputWindow() const { return true; }

protected:
	virtual bool		Execute( const char *inCommand, OSStatus &outError );

protected:
	CFObj<CFDictionaryRef>		mSettingsDict;
	CFObj<CFArrayRef>			mCommandName;
	CFObj<CFStringRef>			mDynamicCommandName;
	CFObj<CFBundleRef>			mExternBundleRef;
	CFObj<CFStringRef>			mLocalizationTableName;
};
