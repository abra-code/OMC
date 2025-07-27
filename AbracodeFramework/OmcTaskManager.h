/*
 *  OmcTaskManager.h
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 11/18/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#include "CFObj.h"
#include "MessagePortListener.h"
#include "AObserver.h"
#include "OMCDeferredProgress.h"
#include "OMCRuntimeUUIDs.h"
#include <mach/host_info.h>

class OmcExecutor;
class OmcTask;

host_basic_info * GetHostBasicInfo();

class OmcTaskManager
{
public:
	virtual			~OmcTaskManager() { } //just to satisfy GCC

	//retains OmcExecutor, retains CFStringRefs
	virtual void	AddTask(OmcExecutor *inNewExecutor, CFStringRef inCommand, CFStringRef inInputPipe, CFStringRef inObjName) = 0;

    virtual void    Start() { RunNext(); }//first run, call after adding some tasks
	virtual void	ShowEndNotification() = 0;	
	virtual CFStringRef GetUniqueID() = 0;
	virtual AObserverBase *	GetObserver() = 0;

protected:
	virtual void	RunNext() = 0;    
};

class OnMyCommandCM;
class CommandDescription;

class OmcHostTaskManager : public OmcTaskManager
{
public:
					OmcHostTaskManager(OnMyCommandCM *inPlugin, const CommandDescription &currCommand,
										CFStringRef inCommandName, CFBundleRef inBundle, CFIndex inMaxTaskCount);
	virtual			~OmcHostTaskManager();

	virtual void	AddTask(OmcExecutor *inNewExecutor, CFStringRef inCommand, CFStringRef inInputPipe, CFStringRef inObjName);

    virtual void    Start();//first run, call after adding some tasks
	virtual void	ShowEndNotification();
	virtual CFStringRef GetUniqueID();

	CFDataRef		ReceivePortMessage( SInt32 msgid, CFDataRef inData );//remote message

	virtual AObserverBase *	GetObserver()//task manager as observer
					{
						return (AObserver<OmcHostTaskManager> *)mTaskObserver;
					}

	void			AddObserver(AObserverBase *inObserver)//task manager as notifier
					{
						mNotifier->AddObserver( inObserver );
					}

	void			ReceiveNotification(void *ioData);//local message

	static CFStringRef CreateLastLineString(const UInt8 *inBuff, size_t inSize);
	static CFStringRef CreateLastLineString(CFStringRef inString);

protected:
	virtual void	RunNext();
	void			NoteTaskEnded(CFIndex inDyingExecutorIndex, bool wasSynchronous);
	void			CancelAllTasks();

private:
	void			Finalize();

protected:
	ARefCountedObj<OnMyCommandCM> mPlugin; //the plugin is retained and released when we finish
	const CommandDescription &	mCurrCommand;
	OMCRuntimeUUIDs	    		mCurrCommandUUIDs;
	CFObj<CFStringRef>			mCommandName;
	CFObj<CFDictionaryRef>		mEndNotificationParams;
	CFObj<CFDictionaryRef>		mProgressParams;
	CFObj<CFBundleRef>			mBundle;
	CFObj<CFBundleRef>			mExternBundle;
	CFObj<CFMutableArrayRef>	mPendingTasks;//array of OmcTask *
	CFObj<CFMutableArrayRef>	mRunningTasks; //array of OmcTask *
	CFIndex						mMaxTaskCount;
	CFIndex						mTaskCount;
	CFIndex						mFinishedTasks;
	CFObj<CFStringRef>			mUniqueID;
	ARefCountedObj< AObserver<OmcHostTaskManager> > mTaskObserver;
	ARefCountedObj< ANotifier > mNotifier;//the task manager is also a notifier and forwards all messages to its observers
	MessagePortListener<OmcHostTaskManager> mListener;
	OMCDeferredProgressRef		 mProgress;
	CFObj<CFStringRef>			mLastOutputText;
	CFObj<CFStringRef>			mLastStatusLine;
	bool						mUserCanceled;
};
