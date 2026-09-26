#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "LCStartupDiagnostics.h"

void* lcShared = 0;

int LiveContainerMainC(int argc, char *argv[], char *envp[]) {
    const char *home = getenv("HOME");

    int (*lcMain)(int argc, char *argv[], char *envp[]) = 0;
    
    if (!home) {
        abort();
    }
    const LCStartupDiagnosticsAPI *diagnostics = LCStartupDiagnosticsStart(home);
    diagnostics->log("Entered LiveContainerMainC");
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/Library/preloadLibraries.txt", home);
    FILE *file = fopen(path, "r");
    if (!file) {
        goto loadlc;
    }
    char line[PATH_MAX];
    while (fgets(line, sizeof(line), file)) {
        // Remove trailing newline if present
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
        }
        uint64_t preloadSpan = diagnostics->begin("dlopen preloaded library");
        dlopen(line, RTLD_LAZY|RTLD_GLOBAL);
        diagnostics->end(preloadSpan);
    }
    
    fclose(file);
    remove(path);
    
loadlc:
    ;
    uint64_t sharedSpan = diagnostics->begin("dlopen LiveContainerShared");
    lcShared = dlopen("@executable_path/Frameworks/LiveContainerShared.framework/LiveContainerShared", RTLD_LAZY|RTLD_GLOBAL);
    diagnostics->end(sharedSpan);
    if (!lcShared) {
        const char *error = dlerror();
        diagnostics->log(error ? error : "LiveContainerShared failed to load");
        return 1;
    }
    void (*attachDiagnostics)(const LCStartupDiagnosticsAPI *) = dlsym(lcShared, "LCStartupDiagnosticsAttach");
    if (attachDiagnostics) attachDiagnostics(diagnostics);
    lcMain = dlsym(lcShared, "LiveContainerMain");
    if (!lcMain) {
        diagnostics->log("LiveContainerMain symbol not found");
        return 1;
    }
    diagnostics->log("Calling LiveContainerMain");
    __attribute__((musttail)) return lcMain(argc, argv, envp);
}

#ifdef DEBUG
int main(int argc, char *argv[], char *envp[]) {

    if(lcShared == NULL) {
        __attribute__((musttail)) return LiveContainerMainC(argc, argv, envp);
    }
    int (*callAppMain)(int argc, char *argv[], char *envp[]) = dlsym(lcShared, "callAppMain");
    __attribute__((musttail)) return callAppMain(argc, argv, envp);

}
#endif
