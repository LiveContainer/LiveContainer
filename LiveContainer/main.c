#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>

void* lcShared = 0;

int LiveContainerMainC(int argc, char *argv[]) {
    const char *home = getenv("HOME");
    char sharedPath[PATH_MAX];
    snprintf(sharedPath, sizeof(sharedPath), "%s/Documents/LCShared", home);

    // Check if folder exists
    struct stat st;
    if (stat(sharedPath, &st) != 0) {
    // Folder does not exist, create it
    if (mkdir(sharedPath, 0755) != 0) {
        perror("Failed to create LCShared folder");
    }
    } else if (!S_ISDIR(st.st_mode)) {
    // Path exists but is not a folder
    fprintf(stderr, "%s exists but is not a directory\n", sharedPath);
    }

    setenv("LC_SHARED_FOLDER", sharedPath, 1);

    int (*lcMain)(int argc, char *argv[]) = 0;
    
    if (!home) {
        abort();
    }
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
        dlopen(line, RTLD_LAZY|RTLD_GLOBAL);
    }
    
    fclose(file);
    remove(path);
    
loadlc:
    lcShared = dlopen("@executable_path/Frameworks/LiveContainerShared.framework/LiveContainerShared", RTLD_LAZY|RTLD_GLOBAL);
    lcMain = dlsym(lcShared, "LiveContainerMain");
    __attribute__((musttail)) return lcMain(argc, argv);
}

#ifdef DEBUG
int main(int argc, char *argv[]) {

    if(lcShared == NULL) {
        __attribute__((musttail)) return LiveContainerMainC(argc, argv);
    }
    int (*callAppMain)(int argc, char *argv[]) = dlsym(lcShared, "callAppMain");
    __attribute__((musttail)) return callAppMain(argc, argv);

}
#endif
