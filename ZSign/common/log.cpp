#include "log.h"
#include "../Utils.hpp"

int ZLog::g_nLogLevel = ZLog::E_INFO;

void ZLog::_Print(const char* szLog, int nColor)
{
	if (g_nLogLevel <= E_NONE) {
		return;
	}

#ifdef _WIN32

	string strLog = szLog;
	HANDLE hConsole = ::GetStdHandle(STD_OUTPUT_HANDLE);
	if (nColor > 0) {
		::SetConsoleTextAttribute(hConsole, nColor);
	}
	::WriteFile(hConsole, strLog.data(), (DWORD)strLog.size(), NULL, NULL);
	if (nColor > 0) {
		::SetConsoleTextAttribute(hConsole, 7);
	}

#else

	const char* szColor = NULL;
	switch (nColor) {
		case 6:
			szColor = "\033[33m";
			break;
		case 10:
			szColor = "\033[32m";
			break;
		case 12: 
			szColor = "\033[31m";
			break;
		default:
			break;
	}

	if (NULL != szColor) {
		write(STDOUT_FILENO, szColor, strlen(szColor));
	}
	write(STDOUT_FILENO, szLog, strlen(szLog));
	if (NULL != szColor) {
		write(STDOUT_FILENO, "\033[0m", 4);
	}
    writeToLogFile(szLog);
	
#endif
}

void ZLog::Print(int nLevel, const char* szLog)
{
	if (g_nLogLevel >= nLevel) {
		_Print(szLog);
	}
}

void ZLog::PrintV(int nLevel, const char* szFormat, ...)
{
	if (g_nLogLevel >= nLevel) {
		FORMAT_V(szFormat, szLog);
		_Print(szLog);
	}
}

bool ZLog::Error(const char* szLog)
{
	_Print(szLog, 12);
	return false;
}

bool ZLog::ErrorV(const char* szFormat, ...)
{
	FORMAT_V(szFormat, szLog);
	_Print(szLog, 12);
	return false;
}

bool ZLog::Success(const char* szLog)
{
	_Print(szLog, 10);
	return true;
}

bool ZLog::SuccessV(const char* szFormat, ...)
{
	FORMAT_V(szFormat, szLog);
	_Print(szLog, 10);
	return true;
}

bool ZLog::PrintResult(bool bSuccess, const char* szLog)
{
	return bSuccess ? Success(szLog) : Error(szLog);
}

bool ZLog::PrintResultV(bool bSuccess, const char* szFormat, ...)
{
	FORMAT_V(szFormat, szLog);
	return bSuccess ? Success(szLog) : Error(szLog);
}

bool ZLog::Warn(const char* szLog)
{
	_Print(szLog, 6);
	return false;
}

bool ZLog::WarnV(const char* szFormat, ...)
{
	FORMAT_V(szFormat, szLog);
	_Print(szLog, 6);
	return false;
}

void ZLog::Print(const char* szLog)
{
	if (g_nLogLevel >= E_INFO) {
		_Print(szLog);
	}
}

void ZLog::PrintV(const char* szFormat, ...)
{
	if (g_nLogLevel >= E_INFO) {
		FORMAT_V(szFormat, szLog);
		_Print(szLog);
	}
}

void ZLog::Debug(const char* szLog)
{
	if (g_nLogLevel >= E_DEBUG) {
		_Print(szLog);
	}
}

void ZLog::DebugV(const char* szFormat, ...)
{
	if (g_nLogLevel >= E_DEBUG) {
		FORMAT_V(szFormat, szLog);
		_Print(szLog);
	}
}

vector<string> ZLog::logs;

void ZLog::writeToLogFile(const std::string& message) {
//    const char* documentsPath = getDocumentsDirectory();
//    std::string logFilePath = std::string(documentsPath) + "/logs.txt";
//
//    std::ofstream logFile(logFilePath, std::ios_base::app);
//    if (logFile.is_open()) {
//        logFile << message;
//        logFile.close();
//    } else {
//        std::cerr << "Failed to open log file: " << logFilePath << std::endl;
//    }

    logs.push_back(message);
}
