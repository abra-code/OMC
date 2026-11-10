/*
 *  OmcTaskManager.h
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 11/18/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 */

#include "CFObj.h"
#include "AObserver.h"
#include "OMCDeferredProgress.h"

class OmcExecutor;
class OmcTask;
class CommandRuntimeData;

// The number of CPUs available now (logical cores, as host_info's avail_cpus gave), or 0 when unknown
long GetAvailableCPUCount();

class OmcTaskManager : public ARefCounted
{
public:
	virtual			~OmcTaskManager() { } //just to satisfy GCC

	// retains OmcExecutor, retains CFStringRefs
	virtual void	AddTask(OmcExecutor *inNewExecutor,
                            CommandRuntimeData *runtimeData,
                            CFStringRef inCommand,
                            CFStringRef inInputPipe,
                            CFStringRef inObjName) = 0;

    virtual void    Start() { RunNext(); } // first run, call after adding some tasks
	virtual void	ShowEndNotification() = 0;	
	virtual AObserverBase *	GetObserver() = 0;

protected:
	virtual void	RunNext() = 0;    
};

class OnMyCommand;
class CommandDescription;

class OmcHostTaskManager : public OmcTaskManager
{
public:
					OmcHostTaskManager(OnMyCommand *inPlugin, const CommandDescription &currCommand,
										CFStringRef inCommandName, CFBundleRef inBundle, CFIndex inMaxTaskCount);
	virtual			~OmcHostTaskManager();

	virtual void	AddTask(OmcExecutor *inNewExecutor,
                            CommandRuntimeData *runtimeData,
                            CFStringRef inCommand,
                            CFStringRef inInputPipe,
                            CFStringRef inObjName);

	virtual void	ShowEndNotification();

	virtual AObserverBase *	GetObserver()//task manager as observer
					{
						return (AObserver<OmcHostTaskManager> *)mTaskObserver;
					}

	// True for the client's command and the NEXT_COMMAND_ID commands it leads to: its end counts
	// toward the end the client waits for, and the plugin tells the client "all tasks finished" when
	// the last such task manager ends (OnMyCommand::ClientTaskManagerEnded). The task manager itself
	// sends no kOmcAllTasksFinished; each task's kOmcTaskFinished and the output go to every observer.
	void			SetDoesClientWork(bool inDoes) { mDoesClientWork = inDoes; }

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
	ARefCountedObj<OnMyCommand> mPlugin; //the plugin is retained and released when we finish
	const CommandDescription &	mCurrCommand;
	CFObj<CFStringRef>			mCommandName;
	CFObj<CFDictionaryRef>		mEndNotificationParams;
	CFObj<CFDictionaryRef>		mProgressParams;
	CFObj<CFBundleRef>			mBundle;
	CFObj<CFBundleRef>			mExternBundle;
	CFObj<CFMutableArrayRef>	mPendingTasks;//array of OmcTask *
	CFObj<CFMutableArrayRef>	mRunningTasks; //array of OmcTask *
    CFIndex						mMaxTaskCount {0};
    CFIndex						mTaskCount {0};
    CFIndex						mFinishedTasks {0};
	ARefCountedObj< AObserver<OmcHostTaskManager> > mTaskObserver;
	ARefCountedObj< ANotifier > mNotifier;//the task manager is also a notifier and forwards all messages to its observers
    OMCDeferredProgressRef		mProgress {nullptr};
	CFObj<CFStringRef>			mLastOutputText;
	CFObj<CFStringRef>			mLastStatusLine;
    bool						mUserCanceled {false};
    bool                        mHasFinalized {false};
    bool                        mDoesClientWork {false};
};
