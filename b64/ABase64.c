/*
 *  ABase64.c
 *
 *  Created by Tomasz Kukielka on 12/7/05.
 *  Copyright 2005 Abracode. All rights reserved.
 *
 */

#include "ABase64.h"

static const unsigned char base64AllChars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

typedef struct Base64CharType
{
	char			index;//0-63 is valid index
	unsigned char	isWhitespace;
} Base64CharType;

static const Base64CharType base64LookupTable[256] = 
{
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 1 },// 9 = '\t'
	{ -1, 1 },// 10 = '\n'
	{ -1, 0 }, { -1, 0 },
	{ -1, 1 }, //13 = '\r'
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 1 },//32 = ' '
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ 62, 0 },//43 = '+'
	{ -1, 0 }, { -1, 0 }, { -1, 0 },
	{ 63, 0 },//47 = '/'
	{ 52, 0 },//48 = '0'
	{ 53, 0 },
	{ 54, 0 },
	{ 55, 0 },
	{ 56, 0 },
	{ 57, 0 },
	{ 58, 0 },
	{ 59, 0 },
	{ 60, 0 },
	{ 61, 0 },//57 = '9'
	{ -1, 0 }, { -1, 0 }, { -1, 0 },
	{ -1, 0 },//61 = '=' - special terminating char
	{ -1, 0 }, { -1, 0 }, { -1, 0 },
	{ 0, 0 },//65 = 'A'
	{ 1, 0 },//B
	{ 2, 0 },//C
	{ 3, 0 },//D
	{ 4, 0 },//E
	{ 5, 0 },//F
	{ 6, 0 },//G
	{ 7, 0 },
	{ 8, 0 },
	{ 9, 0 },
	{ 10, 0 },
	{ 11, 0 },
	{ 12, 0 },
	{ 13, 0 },
	{ 14, 0 },
	{ 15, 0 },
	{ 16, 0 },
	{ 17, 0 },
	{ 18, 0 },
	{ 19, 0 },
	{ 20, 0 },
	{ 21, 0 },
	{ 22, 0 },
	{ 23, 0 },
	{ 24, 0 },
	{ 25, 0 },//90 = 'Z'
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
	{ 26, 0 }, //97 = 'a'
	{ 27, 0 },
	{ 28, 0 },
	{ 29, 0 },
	{ 30, 0 },
	{ 31, 0 },
	{ 32, 0 },
	{ 33, 0 },
	{ 34, 0 },
	{ 35, 0 },
	{ 36, 0 },
	{ 37, 0 },
	{ 38, 0 },
	{ 39, 0 },
	{ 40, 0 },
	{ 41, 0 },
	{ 42, 0 },
	{ 43, 0 },
	{ 44, 0 },
	{ 45, 0 },
	{ 46, 0 },
	{ 47, 0 },
	{ 48, 0 },
	{ 49, 0 },
	{ 50, 0 },
	{ 51, 0 },//122 = 'z'
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },//127
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, 
	{ -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }	
};

//each triplet is changed into 4 bytes
//zero termination byte not included in this calculation
unsigned long
CalculateEncodedBufferSize(unsigned long inRawDataLen)
{
	unsigned long round3Count = inRawDataLen/3;
	unsigned long theRest = (inRawDataLen % 3);
	if(theRest != 0)
		round3Count++;
	return 4*round3Count;
}

unsigned long
CalculateDecodedBufferMaxSize(unsigned long inEncodedLen)
{
	unsigned long round4Count = inEncodedLen/4;
	unsigned long theRest = (inEncodedLen % 4);
	if(theRest != 0)
		round4Count++;
	return 3*round4Count;
}


//outBuff must be preallocated and must hold 4/3 of input buff length
//returns the number of characters written to the outBuff without the null terminating byte
unsigned long
EncodeBase64(const unsigned char *inData, unsigned long inByteCount, unsigned char *outBuff, unsigned long inBuffLen)
{
	long i = 0;
	unsigned long outIndx = 0;
	unsigned char tmp1, tmp2, tmp3;

	if( CalculateEncodedBufferSize(inByteCount) > inBuffLen )
		return 0;

	unsigned long round3Count = inByteCount/3;
	round3Count *= 3;

	while(i < round3Count)
	{
		tmp1 = inData[i++];
		outBuff[outIndx++] = base64AllChars[(tmp1 >> 2) & 0x3F];
		tmp2 = inData[i++];
		outBuff[outIndx++] = base64AllChars[((tmp1 << 4) | (tmp2 >> 4)) & 0x3F];
		tmp3 = inData[i++];
		outBuff[outIndx++] = base64AllChars[((tmp2 << 2) | (tmp3 >> 6)) & 0x3F];
		outBuff[outIndx++] = base64AllChars[tmp3 & 0x3F];
	}

	unsigned long theRest = (inByteCount % 3);

	if(theRest == 1)
	{
		tmp1 = inData[i++];
		outBuff[outIndx++] = base64AllChars[(tmp1 >> 2) & 0x3F];
		tmp2 = 0;
		outBuff[outIndx++] = base64AllChars[((tmp1 << 4) | (tmp2 >> 4)) & 0x3F];
		outBuff[outIndx++] = '=';
		outBuff[outIndx++] = '=';
	}
	else if(theRest == 2)
	{
		tmp1 = inData[i++];
		outBuff[outIndx++] = base64AllChars[(tmp1 >> 2) & 0x3F];
		tmp2 = inData[i++];
		outBuff[outIndx++] = base64AllChars[((tmp1 << 4) | (tmp2 >> 4)) & 0x3F];
		tmp3 = 0;
		outBuff[outIndx++] = base64AllChars[((tmp2 << 2) | (tmp3 >> 6)) & 0x3F];		
		outBuff[outIndx++] = '=';
	}
	return outIndx;
}

unsigned long
DecodeBase64(const unsigned char *inStrBuff, unsigned long inByteCount, unsigned char *outData, unsigned long inBuffLen)
{
	unsigned long i = 0;
	unsigned long j = 0;
	unsigned long indx = 0;
	unsigned long outIndx = 0;
	unsigned char inChar;
	unsigned char quad[4];

	if( CalculateDecodedBufferMaxSize(inByteCount) > inBuffLen )
		return 0;

	while( indx < inByteCount )
	{
		inChar = inStrBuff[indx++];
		if( base64LookupTable[inChar].index >= 0 )
		{
			quad[i++] = base64LookupTable[inChar].index;
		}
		else if( base64LookupTable[inChar].isWhitespace )
		{
			;//skip
		}
		else
		{
			break;//invalid char or '='
		}
		
		if( i == 4 )
		{
			outData[outIndx++] = (quad[0] << 2) + ((quad[1] & 0x30) >> 4);
			outData[outIndx++] = ((quad[1] & 0x0F) << 4) + ((quad[2] & 0x3C) >> 2);
			outData[outIndx++] = ((quad[2] & 0x03) << 6) + (quad[3] & 0x3F);
			i = 0;
		}
	}

	//i cannot be equal 1 in well formed base64 stream
	//i = 4 is handled above (and reset to 0), so the only remaning possiblities are 2 and 3
 	if(i >= 2)
	{
		for (j = i; j < 4; j++)
			quad[j] = 0;
		
		outData[outIndx++] = (quad[0] << 2) + ((quad[1] & 0x30) >> 4);
		if( i == 3 )
			outData[outIndx++] = ((quad[1] & 0xf) << 4) + ((quad[2] & 0x3c) >> 2);
	}

	return outIndx;
}

