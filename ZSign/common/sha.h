#pragma once

#include "common.h"

class ZSHA
{
public:

	static bool SHA1(uint8_t* data, size_t size, string& strOutput);
	static bool SHA1(const string& strData, string& strOutput);
	static bool SHA256(uint8_t* data, size_t size, string& strOutput);
	static bool SHA256(const string& strData, string& strOutput);
	static bool SHA(const string& strData, string& strSHA1, string& strSHA256);
	static bool SHA1Text(const string& strData, string& strOutput);
	static bool SHAFile(const char* szFile, string& strSHA1, string& strSHA256);
	static bool SHABase64(const string& strData, string& strSHA1Base64, string& strSHA256Base64);
	static bool SHABase64File(const char* szFile, string& strSHA1Base64, string& strSHA256Base64);
	static void Print(const char* prefix, const uint8_t* hash, uint32_t size, const char* suffix = "\n");
	static void Print(const char* prefix, const string& strSHASum, const char* suffix = "\n");
	static void PrintData1(const char* prefix, const string& strData, const char* suffix = "\n");
	static void PrintData1(const char* prefix, uint8_t* data, size_t size, const char* suffix = "\n");
	static void PrintData256(const char* prefix, const string& strData, const char* suffix = "\n");
	static void PrintData256(const char* prefix, uint8_t* data, size_t size, const char* suffix = "\n");
};
