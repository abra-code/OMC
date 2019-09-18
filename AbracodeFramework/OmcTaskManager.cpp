/*
 *  OmcTaskManager.cpp
 *  OMCApplet
 *
 *  Created by Tomasz Kukielka on 11/18/06.
 *  Copyright 2006 Abracode. All rights reserved.
 *
 *	Task manager keeps track of running tasks and allows only a specified number of them to run concurrently.
 *  Task manager does not own the extcutors and does not delete them
 *	this is by design to avoid recurrency when messages are posted - the task manager is also the observer for notification posted by the executor
 *
 */

#include "OmcTaskManager.h"
#include "OmcExecutor.h"
#include "OmcTaskNotification.h"
#include "ACFDict.h"
//#include "NibDialog.h"
//#include "NibDialogControl.h"
#include "ARefCounted.h"
#include "DefaultExternBundle.h"

#include "OnMyCommand.h"
#include "OMCDialog.h"

#include <mach/host_info.h>
#include <mach/mach_host.h>

void KeyPressSimulationCallBack(CFRunLoopTimerRef timer, void* context);

class OmcTask : public ARefCounted
{
public:
	//retains OmcExecutor
	OmcTask(OmcExecutor *inNewExec, CFStringRef inCommand, CFStringRef inInputPipe, CFStringRef inObjName)
		: mExec(inNewExec, kARefCountRetain), mCommand(inCommand, kCFObjRetain), mInputPipe(inInputPipe, kCFObjRetain),
		mObjName(inObjName, kCFObjRetain)
	{
	}

	virtual ~OmcTask()
	{
		TRACE_CSTR( "OmcTask::~OmcTask\n" );
	}

	//returns true if task finished synchronously
	bool Run()
	{
		return mExec->ExecuteCFString(mCommand, mInputPipe);
//		mCommand.Release(); //we no longer need it. do not release the command now because the task might have finished and we may be deleted already
	}

	bool UsesOutputWindow()
	{
		return mExec->UsesOutputWindow();
	}

	ARefCountedObj< OmcExecutor > mExec;
	CFObj<CFStringRef>		mCommand;
	CFObj<CFStringRef>		mInputPipe;
	CFObj<CFStringRef>		mObjName;
};


OmcHostTaskManager::OmcHostTaskManager(OnMyCommandCM *inPlugin, const CommandDescription &currCommand,
										CFStringRef inCommandName, CFBundleRef inBundle, CFIndex inMaxTaskCount)
	: mPlugin(inPlugin, kARefCountRetain), mCurrCommand(currCommand), mCurrCommandState(new CommandState()),
	mCommandName(inCommandName, kCFObjRetain), mEndNotificationParams(currCommand.endNotification, kCFObjRetain),
	mProgressParams(currCommand.progress, kCFObjRetain), mBundle(inBundle, kCFObjRetain),
	mMaxTaskCount(inMaxTaskCount), mTaskCount(0), mFinishedTasks(0),
	mTaskObserver( new AObserver<OmcHostTaskManager>(this) ), mNotifier( new ANotifier() ),
	mProgress(NULL),
	mUserCanceled(false)
{
    //do not init command state here. parsing of the command happens later
    //so defer the init of mCurrCommandState until Run

	mExternBundle.Adopt(inPlugin->GetCurrentCommandExternBundle(), kCFObjRetain);

	mPendingTasks.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, 0, ARefCounted::GetCFArrayCallbacks()) );
	if( mMaxTaskCount <= 0 )
		mMaxTaskCount = 1024;

	mRunningTasks.Adopt( ::CFArrayCreateMutable(kCFAllocatorDefault, mMaxTaskCount, ARefCounted::GetCFArrayCallbacks()) );
}

OmcHostTaskManager::~OmcHostTaskManager()
{
	TRACE_CSTR( "OmcHostTaskManager::~OmcHostTaskManager\n");

#if _DEBUG_

//make sure that when we are dying, the lists of tasks are empty
	CFIndex pendingCount = ::CFArrayGetCount( mPendingTasks );
	CFIndex runningCount = ::CFArrayGetCount( mRunningTasks );
	if( (pendingCount != 0) || (runningCount != 0) )
	{
		DEBUG_CSTR( "OmcHostTaskManager::~OmcHostTaskManager. Task list not empty. pendingCount = %d, runningCount = %d\n", (int)pendingCount, (int)runningCount );
	}

#endif //_DEBUG_

	Finalize();
	if(mTaskObserver != NULL)
		mTaskObserver->SetOwner(NULL);//observer may outlive us so it is very important to tell that we died

	delete mCurrCommandState;
}

void
OmcHostTaskManager::Finalize()
{
	OmcTaskData notificationData;
	memset( &notificationData, 0, sizeof(notificationData) );
	notificationData.messageID = kOmcAllTasksFinished;
	notificationData.taskID = 0;
	notificationData.childProcessID = 0;
	notificationData.error = noErr;
	notificationData.dataType = kOMCDataTypeNone;
	notificationData.dataSize = 0;
	notificationData.data.ptr = NULL;

	mNotifier->NotifyObservers( &notificationData );

	if(mProgress != NULL)
	{
		OMCDeferredProgressRelease(mProgress);
		mProgress = NULL;
	}
	
	// In case of error, we don't do any extra post-execution tasks
	// and do not execute the next command
	if( mPlugin->GetError() != noErr )
		return;

	mPlugin->RefreshObjectsInFinder();

	if(mCurrCommand.simulatePaste)
	{			
		TRACE_CSTR( "OnMyCommandCM::Finalize: simulate paste\n" );
		CFRunLoopTimerRef myTimer = CFRunLoopTimerCreate(
										kCFAllocatorDefault,
										CFAbsoluteTimeGetCurrent() + 0.05,
										0,		// interval
										0,		// flags
										0,		// order
										KeyPressSimulationCallBack,
										NULL);

		if(myTimer != NULL)
		{
			TRACE_CSTR( "OnMyCommandCM:Finalize: adding timer for paste simulation\n" );
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), myTimer, kCFRunLoopCommonModes);
		}
		else
		{
			usleep(50000);//0.05s for compatibility with "Shortcuts"
			KeyPressSimulationCallBack(NULL, NULL);
		}
	}
	
//any command following this one?
	CFObj<CFStringRef> nextCommandID( CopyNextCommandID(mCurrCommand, mCurrCommandState) );
	if(nextCommandID != NULL)
	{
		assert(mCurrCommandState != NULL);
		OMCDialog *currDialog = NULL;
		if(mCurrCommandState->dialogGUID != NULL)
			currDialog = OMCDialog::FindDialogByGUID(mCurrCommandState->dialogGUID);
		OSStatus err = mPlugin->ExecuteSubcommand(mCurrCommand.name, nextCommandID, currDialog, NULL);
		#pragma unused(err)
	}
}

//retains OmcExecutor object, retain CFStringRefs
void
OmcHostTaskManager::AddTask(OmcExecutor *inNewExecutor, CFStringRef inCommand, CFStringRef inInputPipe, CFStringRef inObjName)
{
	if(inNewExecutor != NULL)
	{
		ARefCountedObj< OmcTask > newTask( new OmcTask(inNewExecutor, inCommand, inInputPipe, inObjName) );
		::CFArrayAppendValue(mPendingTasks, (OmcTask *)newTask );//retains newTask
		inNewExecutor->ReportToManager(this, mTaskCount);
		mTaskCount++;
	}
}

//kick start all tasks
void
OmcHostTaskManager::Start()
{
    //now the command have been parsed so we can copy the state params before execution
	assert(mCurrCommandState != nullptr);
	assert(mCurrCommand.currState != nullptr);
	mCurrCommandState->commandGUID.Adopt(mCurrCommand.currState->commandGUID, kCFObjRetain);
	mCurrCommandState->commandGUIDUsedByCommand = mCurrCommand.currState->commandGUIDUsedByCommand;

	// if current command has a dialog associated with it
	// remember its ID but do not save the pointer because when we need it later the dialog may be deleted already
	//we will use the dialog ID to look it up on the list of existing dialogs
	mCurrCommandState->dialogGUID.Adopt(mCurrCommand.currState->dialogGUID, kCFObjRetain);
    
    RunNext();
}

void
OmcHostTaskManager::RunNext()
{
	CFIndex pendingCount = ::CFArrayGetCount( mPendingTasks );
	CFIndex runningCount = ::CFArrayGetCount( mRunningTasks );
	if( (pendingCount == 0) && (runningCount == 0) )
	{
		if(!mUserCanceled)
			ShowEndNotification();
		delete this;
		return;
	}

	bool finishedSynchronously = false;

	if( (pendingCount  > 0) && (runningCount < mMaxTaskCount) )
	{
		if( (mProgressParams != NULL) && (mProgress == NULL) )
		{//lazy progress creation
			
			CFBundleRef localizationBundle = NULL;
			if(mCurrCommand.localizationTableName != NULL)//client wants to be localized
			{
				localizationBundle = mExternBundle;
				if(localizationBundle == NULL)
					localizationBundle = CFBundleGetMainBundle();
			}

			mProgress = OMCDeferredProgressCreate(mProgressParams, mCommandName, mTaskCount, mCurrCommand.localizationTableName, localizationBundle);
			mProgressParams.Release();
		}
		
		CFIndex emptySlotCount = mMaxTaskCount - runningCount;
		if(pendingCount > emptySlotCount)
			pendingCount = emptySlotCount;

		for(CFIndex i = 0; i < pendingCount; i++)
		{//move first pending task from pending list to the end of running list
			OmcTask *oneTask = (OmcTask *)::CFArrayGetValueAtIndex( mPendingTasks, 0 );
			if(oneTask != NULL)
				::CFArrayAppendValue(mRunningTasks, oneTask);//will retain oneTask
			::CFArrayRemoveValueAtIndex( mPendingTasks, 0 );
			//now run the task
			finishedSynchronously |= oneTask->Run();
			if(mUserCanceled)
				break;
		}
	}
	
	if(finishedSynchronously) //at least one task finished synchronously: go and run more pending tasks
		RunNext();
}

void
OmcHostTaskManager::NoteTaskEnded(CFIndex inDyingExecutorIndex, bool wasSynchronous)
{
	CFIndex itemCount = ::CFArrayGetCount( mRunningTasks );
	for(CFIndex i = 0; i < itemCount; i++)
	{
		OmcTask *oneTask = (OmcTask *)::CFArrayGetValueAtIndex( mRunningTasks, i );
		if( (oneTask != NULL) && (oneTask->mExec != NULL) &&
			(oneTask->mExec->GetTaskIndex() == inDyingExecutorIndex) )
		{
			::CFArrayRemoveValueAtIndex( mRunningTasks, i );//releases task
			mFinishedTasks++;
			if(mProgress != NULL)
				mUserCanceled = OMCDeferredProgressAdvanceProgress(mProgress, inDyingExecutorIndex, 0, NULL, true);
			break;
		}
	}

	if(mUserCanceled)
	{
		CancelAllTasks();
		delete this;
	}
	else if( !wasSynchronous )
	{
	//if the execution was synchronous, we are still in "Run" command above.
	//we let the task finish and clean up before running again
		RunNext();//run pending tasks in empty slots. may delete self
	}
}

void
OmcHostTaskManager::CancelAllTasks()
{
#if DEBUG
	//make sure we never re-enter here
	static bool sDuringCancel = false;
	
	if(sDuringCancel)
	{
		DEBUG_CSTR("Re-entering OmcHostTaskManager::CancelAllTasks() - BAD things will happen\n");
	}

	sDuringCancel = true;

#endif

	CFIndex pendingCount = ::CFArrayGetCount( mPendingTasks );
	CFIndex runningCount = ::CFArrayGetCount( mRunningTasks );
	if( (pendingCount == 0) && (runningCount == 0) )
	{
#if DEBUG
		sDuringCancel = false;//exiting now
#endif
		return;
	}

	mPlugin->SetError( userCanceledErr );

	if(pendingCount > 0 )
		::CFArrayRemoveAllValues( mPendingTasks );//individual tasks will be released

	if(runningCount == 0)
	{
#if DEBUG
		sDuringCancel = false;//exiting now
#endif
		return;
	}

//copy running tasks to local array 
	CFObj<CFArrayRef> runningTasks( ::CFArrayCreateCopy(kCFAllocatorDefault, mRunningTasks) );

//remove all running tasks from original array to prevent re-entry to this function
	::CFArrayRemoveAllValues( mRunningTasks );

//cancel all tasks in the copied array
	CFIndex itemCount = ::CFArrayGetCount( runningTasks );
	for(CFIndex i = (itemCount-1); i >= 0 ; i--)
	{
		OmcTask *oneTask = (OmcTask *)::CFArrayGetValueAtIndex( runningTasks, i );
		if( oneTask != NULL )
		{
			ARefCountedObj<OmcTask> canceledTask(oneTask, kARefCountRetain);//temp retain
			if(oneTask->mExec != NULL)
				oneTask->mExec->Cancel();
		}
	}

#if DEBUG
	sDuringCancel = false;//exiting now
#endif
}

void
OmcHostTaskManager::ShowEndNotification()
{
	if(mEndNotificationParams == NULL)
		return;

	CFBundleRef localizationBundle = NULL;
	if(mCurrCommand.localizationTableName != NULL)//client wants to be localized
	{
		localizationBundle = mExternBundle;
		if(localizationBundle == NULL)
			localizationBundle = CFBundleGetMainBundle();
	}

	ACFDict params(mEndNotificationParams);
	CFStringRef titleStr = mCommandName;
	params.GetValue( CFSTR("TITLE"), titleStr );

	CFObj<CFStringRef> localizedTitle;
	if(mCurrCommand.localizationTableName != NULL)
	{
		titleStr = ::CFCopyLocalizedStringFromTableInBundle( titleStr, mCurrCommand.localizationTableName, localizationBundle, "");
		localizedTitle.Adopt(titleStr);
	}
	
	CFObj<CFStringRef> localizedMessage;
	CFStringRef messageStr = mLastStatusLine;
	if( params.GetValue( CFSTR("MESSAGE"), messageStr ) )
	{//localize only when comming from command plist
		if(mCurrCommand.localizationTableName != NULL)
		{
			messageStr = ::CFCopyLocalizedStringFromTableInBundle( messageStr, mCurrCommand.localizationTableName, localizationBundle, "");
			localizedMessage.Adopt(messageStr);
		}
	}

	CFObj<CFURLRef> iconURL;
	CFStringRef iconName = CFSTR("app.icns");

//extern bundle actually should be checked first
/*we have the dynamic command name here but we need the original name for default bundle
	if(iconURL == NULL)
	{//still not found, check default external bundle url
		CFObj<CFBundleRef> defaultExternBundleRef( CreateDefaultExternBundleRef(mCommandName) );
		if(defaultExternBundleRef != NULL)
			iconURL.Adopt( CFBundleCopyResourceURL(defaultExternBundleRef, iconName, NULL, NULL) );
	}
*/
	
	iconURL.Adopt( CFBundleCopyResourceURL(CFBundleGetMainBundle(), iconName, nullptr, nullptr) );//main bundle first from host app

	if( (iconURL == nullptr) && (mBundle != nullptr) )//fall back to Abracode framework icon
		iconURL.Adopt( ::CFBundleCopyResourceURL(mBundle, iconName, nullptr, nullptr) );

//it checks for timeout after 30 seconds so it is quite useless for shorter timeouts

	double autoTimeout = 0.0;//no timeout
//	params.GetValue( CFSTR("AUTO_CLOSE_TIMEOUT"), autoTimeout );

	/*SInt32 success = */(void)::CFUserNotificationDisplayNotice(
						   autoTimeout,
						   kCFUserNotificationNoteAlertLevel, //kCFUserNotificationPlainAlertLevel, //CFOptionFlags flags,
						   iconURL,
						   NULL, //CFURLRef soundURL,
						   NULL, //CFURLRef localizationURL,
						   titleStr,
						   messageStr, //CFStringRef alertMessage,
						   CFSTR("OK") ); //CFSTR("Roger") CFStringRef defaultButtonTitle
}

CFDataRef
OmcHostTaskManager::ReceivePortMessage( SInt32 msgid, CFDataRef inData )
{
	if(inData != NULL)
	{
		OmcTaskData remoteData;
		if( OMCTaskUnpackData( inData, remoteData ) )
		{
			CFObj<CFTypeRef> cfObjDisposer;
			if( (remoteData.dataType == kOmcDataTypeCFString) || (remoteData.dataType == kOmcDataTypeCFData) )
				cfObjDisposer.Adopt( remoteData.data.cfObj, kCFObjDontRetain );
			
			ReceiveNotification( (void *)&remoteData );
		}
	}

	return NULL;
}

//static
CFStringRef
OmcHostTaskManager::CreateLastLineString(const UInt8 *inBuff, size_t inSize)
{
	if( (inBuff == NULL) || (inSize <= 0) )
		return NULL;

	long i = (inSize-1);
	long lastCharIndex = (inSize-1);
	//trim from the end and skip all line breaks
	while( lastCharIndex >= 0  )
	{
		if( (inBuff[lastCharIndex] != '\n') && (inBuff[lastCharIndex] != '\r') )
			break;
		lastCharIndex--;
	}

	if(lastCharIndex < 0)
		return NULL;

	i = lastCharIndex;

	while(i >= 0)
	{
		if( (inBuff[i] == '\n') || (inBuff[i] == '\r') )
			break;
		i--;
	}
	
	long firstCharIndex = i+1;
	if(firstCharIndex > lastCharIndex)
		return NULL;

	const UInt8 *startPtr = &(inBuff[firstCharIndex]);
	return ::CFStringCreateWithBytes(kCFAllocatorDefault, startPtr, lastCharIndex-firstCharIndex+1, kCFStringEncodingUTF8, true);
}

//static
CFStringRef
OmcHostTaskManager::CreateLastLineString(CFStringRef inString)
{
	if(inString == NULL)
		return NULL;

	CFIndex theSize = ::CFStringGetLength(inString);
	if(theSize == 0)
		return NULL;

	CFStringInlineBuffer inlineBuff;
	CFStringInitInlineBuffer( inString, &inlineBuff, CFRangeMake(0, theSize) );
	
	CFIndex i = (theSize-1);
	CFIndex lastCharIndex = (theSize-1);
	//trim from the end and skip all line breaks
	
	UniChar oneChar = 0;

	while( lastCharIndex >= 0 )
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, lastCharIndex );
		if( (oneChar != (UniChar)'\n') && (oneChar != (UniChar)'\r') )//find first non-line break
			break;
		lastCharIndex--;
	}

	if(lastCharIndex < 0)
		return NULL;

	i = lastCharIndex;

	while(i >= 0)
	{
		oneChar = CFStringGetCharacterFromInlineBuffer( &inlineBuff, i);
		if( (oneChar == (UniChar)'\n') || (oneChar == (UniChar)'\r') )
			break;
		i--;
	}
	
	long firstCharIndex = i+1;
	if(firstCharIndex > lastCharIndex)
		return NULL;

	return ::CFStringCreateWithSubstring( kCFAllocatorDefault, inString, CFRangeMake(firstCharIndex, lastCharIndex-firstCharIndex+1) );
}

void
OmcHostTaskManager::ReceiveNotification(void *ioData)
{
	if(ioData == NULL)
		return;
	
	//forward notification to my observers too
	mNotifier->NotifyObservers( ioData );
	
	OmcTaskData *taskData = (OmcTaskData *)ioData;

	switch(taskData->messageID)
	{
		case kOmcTaskFinished:
		{
			mPlugin->SetError( taskData->error );
			if( taskData->dataType == kOmcDataTypeBoolean )
				NoteTaskEnded(taskData->taskID, taskData->data.test);//may delete self. do not access "this" after that call
		}
		break;

		case kOmcTaskProgress:
		{
			switch(taskData->dataType)
			{
				case kOmcDataTypePointer:
				{
					if(taskData->data.ptr != NULL) //do not clear last status if we don't have anything explicilty new
					{
						mLastOutputText.Adopt( ::CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)taskData->data.ptr, taskData->dataSize, kCFStringEncodingUTF8, true), kCFObjDontRetain );
						mLastStatusLine.Adopt( CreateLastLineString((const UInt8 *)taskData->data.ptr, taskData->dataSize), kCFObjDontRetain );
					}
				}
				break;

				case kOmcDataTypeCFData:
				{
					if(taskData->data.cfObj != NULL) //do not clear last status if we don't have anything explicilty new
					{
						const UInt8 *rawData = ::CFDataGetBytePtr( (CFDataRef)taskData->data.cfObj );
						CFIndex theLen = ::CFDataGetLength( (CFDataRef)taskData->data.cfObj );
						mLastOutputText.Adopt( ::CFStringCreateWithBytes(kCFAllocatorDefault, rawData, theLen, kCFStringEncodingUTF8, true), kCFObjDontRetain );
						mLastStatusLine.Adopt( CreateLastLineString(rawData, theLen), kCFObjDontRetain );
					}
				}
				break;

				case kOmcDataTypeCFString:
				{
					if(taskData->data.cfObj != NULL) //do not clear last status if we don't have anything explicilty new
					{
						mLastOutputText.Adopt( (CFStringRef)taskData->data.cfObj, kCFObjRetain );						
						mLastStatusLine.Adopt( CreateLastLineString( (CFStringRef)taskData->data.cfObj ), kCFObjDontRetain );
					}
				}
				break;
					
				default:
					//should we expect other enums here?
					//assert(false);
				break;
			}
			
			if(mProgress != NULL)
			{
				mUserCanceled = OMCDeferredProgressAdvanceProgress(mProgress, taskData->taskID, taskData->childProcessID, mLastOutputText, false);
			}			

			if(mUserCanceled)
			{
				CancelAllTasks();
				delete this;
			}
		}
		break;

		case kOmcTaskCancel:
		{
			mUserCanceled = true;
			CancelAllTasks();
			delete this;
		}
		break;
			
		default:
		break;
	}
	// do not put any code here because this may have been deleted
}

//caller should NOT release the result string

CFStringRef
OmcHostTaskManager::GetUniqueID()
{
	if(mUniqueID != NULL)
		return mUniqueID;

	CFObj<CFUUIDRef>  myUUID( ::CFUUIDCreate(kCFAllocatorDefault) );
	if(myUUID != NULL)
		mUniqueID.Adopt( ::CFUUIDCreateString(kCFAllocatorDefault, myUUID) );

	return mUniqueID;
}


#pragma mark -

//pack structure data so it can travel with message to another process
CFDataRef OMCTaskCreatePackedData( const OmcTaskData &inStruct )
{
    ACFMutableDict dataDict;

	dataDict.SetValue( CFSTR("messageID"), (CFIndex)inStruct.messageID );
	dataDict.SetValue( CFSTR("taskID"), inStruct.taskID );
	dataDict.SetValue( CFSTR("childProcessID"), (CFIndex)inStruct.childProcessID );
	dataDict.SetValue( CFSTR("error"), (CFIndex)inStruct.error );

	CFIndex dataType = (CFIndex)inStruct.dataType;
	if(inStruct.dataType == kOmcDataTypePointer)
	{
		dataType = (CFIndex)kOmcDataTypeCFData;
	}

	dataDict.SetValue( CFSTR("dataType"), (CFIndex)dataType );
	dataDict.SetValue( CFSTR("dataSize"), (CFIndex)inStruct.dataSize );

	switch(inStruct.dataType)
	{
		case kOmcDataTypeCFString:
		case kOmcDataTypeCFData:
			dataDict.SetValue(CFSTR("data"), inStruct.data.cfObj);
		break;
		
		case kOmcDataTypeCFIndex:
			dataDict.SetValue(CFSTR("data"), inStruct.data.index);
		break;
		
		case kOmcDataTypeBoolean:
			dataDict.SetValue(CFSTR("data"), inStruct.data.test);
		break;

		case kOmcDataTypePointer:
		{
			//we change raw data pointer into CFData
			CFObj<CFDataRef> myData( ::CFDataCreate(kCFAllocatorDefault,
													(const UInt8 *)inStruct.data.ptr,
													(CFIndex)inStruct.dataSize ) );
			dataDict.SetValue(CFSTR("data"), (CFTypeRef)(CFDataRef)myData );
		}
		break;

		default:
		//unknown data type to pack
		break;
	}
	
    return CFPropertyListCreateData(kCFAllocatorDefault, (CFMutableDictionaryRef)dataDict, kCFPropertyListBinaryFormat_v1_0, 0, nullptr);
}

//caller responsible for releasing CF objects allocated for this struct
bool OMCTaskUnpackData( CFDataRef inData, OmcTaskData &outStruct )
{
	memset( &outStruct, 0, sizeof(OmcTaskData) );

	if(inData == NULL)
		return false;

    CFObj<CFPropertyListRef> thePlist(CFPropertyListCreateWithData(kCFAllocatorDefault, inData, kCFPropertyListImmutable, nullptr, nullptr));
	if(thePlist == NULL)
		return false;

	CFDictionaryRef plistDict = ACFType<CFDictionaryRef>::DynamicCast(thePlist);
	if(plistDict == NULL)
	{//not a CFDictionary?
		::CFRelease(thePlist);
		return false;
	}

	ACFDict dataDict(plistDict);

	CFIndex val = 0;
	dataDict.GetValue(CFSTR("messageID"), val);
	outStruct.messageID = (OmcTaskMessageID)val;

	outStruct.taskID = 0;
	dataDict.GetValue(CFSTR("taskID"), outStruct.taskID);

	val = 0;
	dataDict.GetValue( CFSTR("childProcessID"), val );
	outStruct.childProcessID = val;
	
	val = 0;
	dataDict.GetValue(CFSTR("error"), val);
	outStruct.error = (OSStatus)val;

	val = 0;
	dataDict.GetValue(CFSTR("dataType"), val);
	outStruct.dataType = (OmcTaskDataType)val;

	val = 0;
	dataDict.GetValue(CFSTR("dataSize"), val);
	outStruct.dataSize = (size_t)val;
	
	switch(outStruct.dataType)
	{
		case kOmcDataTypeCFString:
		case kOmcDataTypeCFData:
			dataDict.CopyValue(CFSTR("data"), outStruct.data.cfObj);
		break;
		
		case kOmcDataTypeCFIndex:
			dataDict.GetValue(CFSTR("data"), outStruct.data.index);
		break;
		
		case kOmcDataTypeBoolean:
			dataDict.GetValue(CFSTR("data"), outStruct.data.test);
		break;

		case kOmcDataTypePointer:
		default:
		//invalid data type requested
			return false;
		break;
	}
	return true;
}

#pragma mark -

host_basic_info *
GetHostBasicInfo()
{
	static bool sInfoValid = false;
	static host_basic_info sHostBasicInfo;

	if(sInfoValid)
		return &sHostBasicInfo;

	unsigned int i = HOST_BASIC_INFO_COUNT;
	if( host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)(&sHostBasicInfo), &i) != KERN_SUCCESS )
		return NULL;

	sInfoValid = true;
	return &sHostBasicInfo;
}



//it is a one-shot timer which is supposed to self-invalidate but also needs to be released
//so we invalidate here and release as well

void
KeyPressSimulationCallBack(CFRunLoopTimerRef timer, void* context)
{
#pragma unused (context)

    //synchronize pasteboard before simulating cmd+v
    {
        CFObj<PasteboardRef> thePasteboard;
        OSStatus err = PasteboardCreate( kPasteboardClipboard, &thePasteboard );
        if( (err == noErr) && (thePasteboard != nullptr) )
        {
            PasteboardSyncFlags syncFlags = PasteboardSynchronize( thePasteboard );
    #if _DEBUG_
            printf("OMC: PasteboardSyncFlags = 0x%.8X\n", (unsigned int)syncFlags);
    #endif
        }
    }

    CFObj<CGEventRef> cmdDown = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)55, true);
    CGEventPost(kCGHIDEventTap, cmdDown);
    
    CFObj<CGEventRef> vDown = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)9, true); // 'v' down
    CGEventPost(kCGHIDEventTap, vDown);

    CFObj<CGEventRef> vUp = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)9, false); // 'v' up
    CGEventPost(kCGHIDEventTap, vUp);

    CFObj<CGEventRef> cmdUp = CGEventCreateKeyboardEvent(nullptr, (CGKeyCode)55, false);
    CGEventPost(kCGHIDEventTap, cmdUp);

	if(timer != nullptr)
	{
		CFRunLoopTimerInvalidate(timer);
		CFRelease(timer);
	}
}

