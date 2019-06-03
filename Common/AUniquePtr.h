//**************************************************************************************
// Filename:	AUniquePtr.h
//
// Description: equivalent of std::unique_ptr with a couple to tweaks
//**************************************************************************************

#pragma once
#include <memory>

template <class T>
class AUniquePtr : public std::unique_ptr<T>
{
public:
    AUniquePtr() noexcept
        : std::unique_ptr<T>(nullptr)
    {}

    AUniquePtr(T* inObj) noexcept
        : std::unique_ptr<T>(inObj)
    {}

    AUniquePtr(AUniquePtr& inOrig) noexcept
        : std::unique_ptr<T>(inOrig.detach())
    {
    }

    //std::unique_ptr does not have automatic extraction of underlying pointer
    //I can't live without it
    operator T*() const noexcept
    {
        return this->get();
    }
    
    T* detach() noexcept
    {
        return this->release(); //release is a very bad misnomer becuase the term is reserved in many ref-counted APIs
    }
};
