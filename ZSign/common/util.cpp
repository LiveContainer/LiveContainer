#include "util.h"

#ifdef _WIN32
#define PRId64						"lld"
#elif __APPLE__
#define PRId64						"lld"
#else
#define PRId64						"ld"
#endif

string ZUtil::FormatSize(int64_t size, int64_t base)
{
	double fsize = 0;
	char ret[64] = { 0 };
	if (size > base * base * base * base) {
		fsize = (size * 1.0) / (base * base * base * base);
		snprintf(ret, sizeof(ret), "%.2f TB", fsize);
	} else if (size > base * base * base) {
		fsize = (size * 1.0) / (base * base * base);
		snprintf(ret, sizeof(ret), "%.2f GB", fsize);
	} else if (size > base * base) {
		fsize = (size * 1.0) / (base * base);
		snprintf(ret, sizeof(ret), "%.2f MB", fsize);
	} else if (size > base) {
		fsize = (size * 1.0) / (base);
		snprintf(ret, sizeof(ret), "%.2f KB", fsize);
	} else {
		snprintf(ret, sizeof(ret), "%" PRId64 " B", size);
	}
	return ret;
}

time_t ZUtil::GetUnixStamp()
{
	time_t ustime = 0;
	time(&ustime);
	return ustime;
}

uint64_t ZUtil::GetMicroSecond()
{
#ifdef _WIN32
	LARGE_INTEGER frequency, counter;
	QueryPerformanceFrequency(&frequency);
	QueryPerformanceCounter(&counter);
	return (counter.QuadPart * 1000000) / frequency.QuadPart;
#else
	struct timeval tv = { 0 };
	gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000000 + tv.tv_usec;
#endif
}

bool  ZUtil::SystemExecV(const char* szCmd, ...)
{
	FORMAT_V(szCmd, szRealCmd);

	if (strlen(szRealCmd) <= 0) {
		return false;
	}

//	int status = system(szRealCmd);
    int status = 0;
	if (0 != status) {
		ZLog::ErrorV("SystemExec: \"%s\", error!\n", szRealCmd);
		return false;
	}
	return true;
}

uint16_t ZUtil::Swap(uint16_t value)
{
	return ((value >> 8) & 0x00ff) | ((value << 8) & 0xff00);
}

uint32_t ZUtil::Swap(uint32_t value)
{
	value = ((value >> 8) & 0x00ff00ff) | ((value << 8) & 0xff00ff00);
	value = ((value >> 16) & 0x0000ffff) | ((value << 16) & 0xffff0000);
	return value;
}

uint64_t ZUtil::Swap(uint64_t value)
{
	value = (value & 0x00000000ffffffffULL) << 32 | (value & 0xffffffff00000000ULL) >> 32;
	value = (value & 0x0000ffff0000ffffULL) << 16 | (value & 0xffff0000ffff0000ULL) >> 16;
	value = (value & 0x00ff00ff00ff00ffULL) << 8 | (value & 0xff00ff00ff00ff00ULL) >> 8;
	return value;
}

uint32_t ZUtil::ByteAlign(uint32_t uValue, uint32_t uAlign)
{
	return (uValue + (uAlign - uValue % uAlign));
}

const char* ZUtil::StringFormatV(string& strFormat, const char* szFormatArgs, ...)
{
	FORMAT_V(szFormatArgs, szFormat);
	strFormat = szFormat;
	return strFormat.c_str();
}

string& ZUtil::StringReplace(string& context, const string& from, const string& to)
{
	size_t lookHere = 0;
	size_t foundHere;
	while ((foundHere = context.find(from, lookHere)) != string::npos) {
		context.replace(foundHere, from.size(), to);
		lookHere = foundHere + to.size();
	}
	return context;
}

void ZUtil::StringSplit(const string& src, const string& split, vector<string>& dest)
{
	size_t oldPos = 0;
	size_t newPos = src.find(split, oldPos);
	while (newPos != string::npos) {
		dest.push_back(src.substr(oldPos, newPos - oldPos));
		oldPos = newPos + split.size();
		newPos = src.find(split, oldPos);
	}
	if (oldPos < src.size()) {
		dest.push_back(src.substr(oldPos));
	}
}

string& ZUtil::StringTrim(string& str)
{
	if (!str.empty()) {
		str.erase(0, str.find_first_not_of(' '));
		str.erase(str.find_last_not_of(' ') + 1);
		str.erase(0, str.find_first_not_of('\t'));
		str.erase(str.find_last_not_of('\t') + 1);
		str.erase(0, str.find_first_not_of('\r'));
		str.erase(str.find_last_not_of('\r') + 1);
		str.erase(0, str.find_first_not_of('\n'));
		str.erase(str.find_last_not_of('\n') + 1);
	}
	return str;
}

const char* ZUtil::GetBaseName(const char* path)
{
#ifdef _WIN32
	return ::PathFindFileNameA(path);
#else
	return ::basename((char*)path);
#endif
}

int ZUtil::builtin_clzll(uint64_t x)
{
	//__builtin_clzll(x);

	if (x == 0) {
		return 64;
	}

	int count = 0;
	if (x <= 0x00000000FFFFFFFF) { 
		count += 32; 
		x <<= 32;
	}
	if (x <= 0x0000FFFFFFFFFFFF) { 
		count += 16; 
		x <<= 16;
	}
	if (x <= 0x00FFFFFFFFFFFFFF) { 
		count += 8;  
		x <<= 8;
	}
	if (x <= 0x0FFFFFFFFFFFFFFF) { 
		count += 4;  
		x <<= 4;
	}
	if (x <= 0x3FFFFFFFFFFFFFFF) { 
		count += 2;  
		x <<= 2;
	}
	if (x <= 0x7FFFFFFFFFFFFFFF) { 
		count += 1;
	}

	return count;
}
