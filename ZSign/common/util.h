#pragma once

#include "common.h"

class ZUtil
{
public:
	static const char* 	StringFormatV(string& strFormat, const char* szFormatArgs, ...);
	static string& 		StringReplace(string& context, const string& from, const string& to);
	static void 		StringSplit(const string& src, const string& split, vector<string>& dest);
	static string&		StringTrim(string& str);
	static string 		FormatSize(int64_t size, int64_t base = 1024);
	static time_t		GetUnixStamp();
	static uint64_t 	GetMicroSecond();
	static bool			SystemExecV(const char* szCmd, ...);
	static uint32_t		ByteAlign(uint32_t uValue, uint32_t uAlign);
	static const char*	GetBaseName(const char* path);
	static int			builtin_clzll(uint64_t x);
	static uint16_t		Swap(uint16_t value);
	static uint32_t		Swap(uint32_t value);
	static uint64_t		Swap(uint64_t value);
};

#define LE(x) ZUtil::Swap(x)
#define BE(x) ZUtil::Swap(x)
