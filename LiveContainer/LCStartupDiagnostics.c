#include "LCStartupDiagnostics.h"

static const LCStartupDiagnosticsAPI *startupAPI;

void LCStartupDiagnosticsAttach(const LCStartupDiagnosticsAPI *api) {
    startupAPI = api;
}

void LCStartupLog(const char *message) {
    if (startupAPI) startupAPI->log(message);
}

uint64_t LCStartupBegin(const char *label) {
    return startupAPI ? startupAPI->begin(label) : 0;
}

void LCStartupEnd(uint64_t token) {
    if (startupAPI) startupAPI->end(token);
}

void LCStartupUIAppeared(void) {
    if (startupAPI) startupAPI->uiAppeared();
}

void LCStartupStop(const char *reason) {
    if (startupAPI) startupAPI->stop(reason);
}
