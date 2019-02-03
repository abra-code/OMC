/*
 *  ABase64.h
 *  b64
 *
 *  Created by Tomasz Kukielka on 12/7/05.
 *  Copyright 2005 Abracode. All rights reserved.
 *
 */

#pragma once 

#ifdef __cplusplus
extern "C" {
#endif

unsigned long CalculateEncodedBufferSize(unsigned long inRawDataLen);
unsigned long CalculateDecodedBufferMaxSize(unsigned long inEncodedLen);

unsigned long EncodeBase64(const unsigned char *inData, unsigned long inByteCount, unsigned char *outBuff, unsigned long inBuffLen);
unsigned long DecodeBase64(const unsigned char *inStrBuff, unsigned long inByteCount, unsigned char *outData, unsigned long inBuffLen);

#ifdef __cplusplus
}
#endif
