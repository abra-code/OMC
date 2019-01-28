/*
 *  OmcTaskNotification.h
 *  OnMyCommandCM
 *
 *  Created by Tomasz Kukielka on Fri Dec 1 2006.
 *  Copyright (c) 2006 Abracode, Inc. All rights reserved.
 *
 *	Defines protocol used by Omc task notifications
 *
 */


typedef enum OmcTaskMessageID
{
	kOmcTaskNone,
	kOmcTaskFinished, //tasks notifies its observers that it ended, data is NULL
	kOmcTaskProgress, //task notifies its observes about progress and may provide data for observer to process 
	kOmcTaskCancel, //cancel message can be sent to task or to task manager
	kOmcAllTasksFinished //sent by task manager only. data is NULL
} OmcTaskMessageID;

typedef enum OmcTaskDataType
{
	kOMCDataTypeNone = 0,
	kOmcDataTypePointer,
	kOmcDataTypeCFString,
	kOmcDataTypeCFData,
	kOmcDataTypeCFIndex,
	kOmcDataTypeBoolean
} OmcTaskDataType;

typedef struct OmcTaskData
{
	OmcTaskMessageID	messageID;
	CFIndex				taskID;
	pid_t				childProcessID;
	OSStatus			error;
	OmcTaskDataType		dataType;
	size_t				dataSize;
	union
	{
		const void *	ptr;
		CFTypeRef		cfObj;
		CFIndex			index;
		Boolean			test;
	} data;
} OmcTaskData;

CFDataRef OMCTaskCreatePackedData( const OmcTaskData &iStruct );
bool OMCTaskUnpackData( CFDataRef inData, OmcTaskData &outStruct );
