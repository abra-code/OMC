//**************************************************************************************
// Filename:	StAEDesc.h
//				Part of Contextual Menu Workshop by Abracode Inc.
//				http://free.abracode.com/cmworkshop/
// Copyright � 2002-2004 Abracode, Inc.  All rights reserved.
//
// Description:	very primitive. use PowerPlant's StAEDescriptor if you prefer
//				but note that this one does not throw
//
//
//**************************************************************************************
// Revision History:
// Friday, January 25, 2002 - Original
//**************************************************************************************

#pragma once
#import <Carbon/Carbon.h>

//no virtual methods so the memory layout is identical to AEDesc

class StAEDesc : public AEDesc
{
public:
							StAEDesc()
							{
								Init();
							}

							StAEDesc(const AEDesc &inDesc)
							{//just take ownership, do not copy
								//*this = inDesc;
								descriptorType = inDesc.descriptorType;
								dataHandle = inDesc.dataHandle;
							}
							
							StAEDesc(DescType inType, const void *inDataPtr, Size inSize)
							{
								::AECreateDesc(inType, inDataPtr, inSize, this);
							}
							
							~StAEDesc()
							{
								if(dataHandle != NULL )
								{
									::AEDisposeDesc( this );
								}
							}

		void				Init()
							{
								AEInitializeDescInline(this);
							}

		DescType			GetDescriptorType() const { return descriptorType; }
		AEDataStorage		GetDataStorage() const { return dataHandle; }

		OSErr				GetData(void *ioData, Size inDataSize) const
							{
								return ::AEGetDescData(this, ioData, inDataSize);
							}

		bool				IsNULL() { return (descriptorType == typeNull); }
		void				Detach() { Init(); }

/*
		operator			AEDesc& ()
							{
								return *this;
							}

		operator			const AEDesc& () const
							{
								return *this;
							}
*/
		
		operator			AEDesc* ()
							{
								return this;
							}

		operator			const AEDesc* () const
							{
								return this;
							}
				
private:
							StAEDesc(const StAEDesc&);
		StAEDesc&			operator=(const StAEDesc&);
};
