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
    StAEDesc() noexcept
    {
        Init();
    }

    StAEDesc(const AEDesc &inDesc) noexcept
    {//just take ownership, do not copy
        this->descriptorType = inDesc.descriptorType;
        this->dataHandle = inDesc.dataHandle;
    }
    
    StAEDesc(DescType inType, const void *inDataPtr, Size inSize) noexcept
    {
        ::AECreateDesc(inType, inDataPtr, inSize, this);
    }
    
    ~StAEDesc() noexcept
    {
        if(dataHandle != nullptr )
        {
            ::AEDisposeDesc( this );
        }
    }

    void Init() noexcept
    {
        AEInitializeDescInline(this);
    }

    DescType GetDescriptorType() const noexcept { return this->descriptorType; }
    AEDataStorage GetDataStorage() const noexcept { return this->dataHandle; }

    OSErr GetData(void *ioData, Size inDataSize) const noexcept
    {
        return ::AEGetDescData(this, ioData, inDataSize);
    }

    bool IsNULL() const noexcept { return (this->descriptorType == typeNull); }

    AEDesc Detach() noexcept
    {
        AEDesc outDesc = *this;
        Init();
        return outDesc;
    }

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

    operator AEDesc* () noexcept
    {
        return this;
    }

    operator const AEDesc* () const noexcept
    {
        return this;
    }

private:
    StAEDesc(const StAEDesc&);
    StAEDesc& operator=(const StAEDesc&);
};
