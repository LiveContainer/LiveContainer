#ifndef LCStartupDiagnostics_h
#define LCStartupDiagnostics_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The executable owns diagnostics so it can monitor even the first dlopen.
// LiveContainerShared forwards to it after loading; extensions remain no-ops.
typedef struct {
    void (*log)(const char *message);
    uint64_t (*begin)(const char *label);
    void (*end)(uint64_t token);
    void (*uiAppeared)(void);
    void (*stop)(const char *reason);
} LCStartupDiagnosticsAPI;

const LCStartupDiagnosticsAPI *LCStartupDiagnosticsStart(const char *home);
void LCStartupDiagnosticsAttach(const LCStartupDiagnosticsAPI *api);
void LCStartupLog(const char *message);
uint64_t LCStartupBegin(const char *label);
void LCStartupEnd(uint64_t token);
void LCStartupUIAppeared(void);
void LCStartupStop(const char *reason);

static inline void LCStartupEndScope(uint64_t *token) {
    LCStartupEnd(*token);
}
#define LC_STARTUP_SCOPE(label) \
    __attribute__((cleanup(LCStartupEndScope), unused)) uint64_t lcStartupScope = LCStartupBegin(label)

#ifdef __cplusplus
}
#endif

#endif
