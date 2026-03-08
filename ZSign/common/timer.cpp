#include "timer.h"

ZTimer::ZTimer()
{
	Reset();
}

uint64_t ZTimer::Reset()
{
	m_uBeginTime = ZUtil::GetMicroSecond();
	return m_uBeginTime;
}

uint64_t ZTimer::Print(const char* szFormatArgs, ...)
{
	FORMAT_V(szFormatArgs, szFormat);
	uint64_t uElapse = ZUtil::GetMicroSecond() - m_uBeginTime;
	ZLog::PrintV("%s (%.03fs, %lluus)\n", szFormat, uElapse / 1000000.0, uElapse);
	return Reset();
}

uint64_t ZTimer::PrintResult(bool bSuccess, const char* szFormatArgs, ...)
{
	FORMAT_V(szFormatArgs, szFormat);
	uint64_t uElapse = ZUtil::GetMicroSecond() - m_uBeginTime;
	ZLog::PrintResultV(bSuccess, "%s (%.03fs, %lluus)\n", szFormat, uElapse / 1000000.0, uElapse);
	return Reset();
}
