#pragma once

#include "common.h"

class ZTimer
{
public:
	ZTimer();

public:
	uint64_t Reset();
	uint64_t Print(const char* szFormatArgs, ...);
	uint64_t PrintResult(bool bSuccess, const char* szFormatArgs, ...);

private:
	uint64_t m_uBeginTime;
};
