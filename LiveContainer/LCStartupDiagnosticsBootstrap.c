#include "LCStartupDiagnostics.h"

#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

enum { LCMaximumFrames = 64, LCMaximumImages = 2048, LCMaximumDumps = 8 };
static const uint64_t LCSecond = 1000000000ull;
static int logFD = -1;
static uint64_t launchTime;
static thread_t mainThread;
static atomic_bool stopped;
static atomic_bool heartbeatPending;
static atomic_uint_fast64_t lastHeartbeat;
static atomic_uint_fast64_t uiAppearedTime;
static atomic_uint_fast64_t writtenBytes;

typedef struct {
    atomic_bool ready;
    uintptr_t start;
    uintptr_t end;
    uuid_t uuid;
    char name[256];
} LCStartupImage;
static LCStartupImage images[LCMaximumImages];
static atomic_uint imageCount;

static uint64_t now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * LCSecond + ts.tv_nsec;
}

static void logMessage(const char *message) {
    if (logFD < 0 || atomic_load(&stopped)) return;
    uint64_t tid = 0;
    pthread_threadid_np(NULL, &tid);
    char line[2048];
    int length = snprintf(line, sizeof(line), "[+%.3fs tid=%llu] %s\n",
                          (now() - launchTime) / (double)LCSecond,
                          (unsigned long long)tid, message);
    if (length < 0) return;
    size_t count = (size_t)length < sizeof(line) ? (size_t)length : sizeof(line) - 1;
    line[count - 1] = '\n';
    // Bound diagnostic disk usage, including unexpectedly large thread lists.
    if (atomic_fetch_add(&writtenBytes, count) > 8 * 1024 * 1024) return;
    // No stdio buffering or queue: an abort/SIGKILL keeps completed writes.
    for (size_t offset = 0; offset < count;) {
        ssize_t result = write(logFD, line + offset, count - offset);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) break;
        offset += (size_t)result;
    }
}

static void logFormat(const char *format, ...) {
    char message[1800];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    logMessage(message);
}

static uint64_t begin(const char *label) {
    if (logFD < 0 || atomic_load(&stopped)) return 0;
    uint64_t token = now();
    logFormat("BEGIN span=%llu %s", (unsigned long long)token, label);
    return token;
}

static void end(uint64_t token) {
    if (token) logFormat("END span=%llu duration=%.3fms",
                         (unsigned long long)token, (now() - token) / 1000000.0);
}

static void stop(const char *reason) {
    logFormat("STOP %s", reason);
    atomic_store(&stopped, true);
    // Keep the descriptor valid for any in-flight writer. It is CLOEXEC and
    // the OS closes it at process exit; never race close() with write().
}

static void uiAppeared(void) {
    uint64_t expected = 0;
    uint64_t timestamp = now();
    if (atomic_compare_exchange_strong(&uiAppearedTime, &expected, timestamp)) {
        logMessage("Root view onAppear; monitoring another 10 seconds (not proof of first frame)");
    }
}

// Called under dyld's lock. Only copy fixed-size metadata; no logging,
// allocation, symbol lookup or dispatch here. The sampler never takes that lock.
static void imageAdded(const struct mach_header *header, intptr_t slide) {
    if (atomic_load(&stopped) || header->magic != MH_MAGIC_64) return;
    unsigned index = atomic_fetch_add(&imageCount, 1);
    if (index >= LCMaximumImages) return;
    LCStartupImage *image = &images[index];
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const char *cursor = (const char *)(header64 + 1);
    const char *limit = cursor + header64->sizeofcmds;
    strlcpy(image->name, "<executable>", sizeof(image->name));
    for (uint32_t i = 0; i < header64->ncmds && cursor + sizeof(struct load_command) <= limit; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(limit - cursor)) break;
        if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) {
                image->start = (uintptr_t)(segment->vmaddr + slide);
                image->end = image->start + segment->vmsize;
            }
        } else if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            memcpy(image->uuid, ((const struct uuid_command *)command)->uuid, sizeof(uuid_t));
        } else if (command->cmd == LC_ID_DYLIB && command->cmdsize >= sizeof(struct dylib_command)) {
            uint32_t offset = ((const struct dylib_command *)command)->dylib.name.offset;
            if (offset < command->cmdsize) {
                size_t length = strnlen(cursor + offset, command->cmdsize - offset);
                if (length >= sizeof(image->name)) length = sizeof(image->name) - 1;
                memcpy(image->name, cursor + offset, length);
                image->name[length] = 0;
            }
        }
        cursor += command->cmdsize;
    }
    atomic_store_explicit(&image->ready, true, memory_order_release);
}

static uintptr_t stripCodePointer(uintptr_t pointer) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip((void *)pointer, ptrauth_key_return_address);
#elif defined(__arm64__)
    // arm64 builds may sample arm64e system frames. XPACLRI strips code PAC
    // using the hardware's address width, and is a NOP on non-PAC hardware.
    register uintptr_t lr __asm__("x30") = pointer;
    __asm__("hint #7" : "+r"(lr));
    return lr;
#else
    return pointer;
#endif
}

typedef struct {
    uintptr_t frames[LCMaximumFrames];
    unsigned count;
    kern_return_t stateResult;
    kern_return_t resumeResult;
    const char *termination;
} LCStartupStack;

static LCStartupStack sampleThread(thread_t thread) {
    LCStartupStack stack = { .termination = "end of frame chain" };
    stack.stateResult = thread_suspend(thread);
    if (stack.stateResult != KERN_SUCCESS) {
        stack.termination = "thread_suspend failed";
        return stack;
    }
    // While suspended, do not allocate, log, symbolize or acquire user locks.
    // A target thread may own malloc/dyld/stdio locks. Always resume it.
    uintptr_t fp = 0;
#if defined(__arm64__)
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    stack.stateResult = thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
    if (stack.stateResult == KERN_SUCCESS) {
        stack.frames[stack.count++] = stripCodePointer(arm_thread_state64_get_pc(state));
        stack.frames[stack.count++] = stripCodePointer(arm_thread_state64_get_lr(state));
        fp = arm_thread_state64_get_fp(state);
    }
#elif defined(__x86_64__)
    x86_thread_state64_t state;
    mach_msg_type_number_t count = x86_THREAD_STATE64_COUNT;
    stack.stateResult = thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&state, &count);
    if (stack.stateResult == KERN_SUCCESS) {
        stack.frames[stack.count++] = state.__rip;
        fp = state.__rbp;
    }
#else
    stack.stateResult = KERN_NOT_SUPPORTED;
#endif
    while (fp && stack.count < LCMaximumFrames && stack.stateResult == KERN_SUCCESS) {
        struct { uintptr_t previous; uintptr_t returnAddress; } frame;
        vm_size_t readSize = 0;
        if (fp % sizeof(uintptr_t) ||
            vm_read_overwrite(mach_task_self(), (vm_address_t)fp, sizeof(frame), (vm_address_t)&frame, &readSize) != KERN_SUCCESS ||
            readSize != sizeof(frame)) {
            stack.termination = "unreadable frame pointer";
            break;
        }
        uintptr_t address = stripCodePointer(frame.returnAddress);
        if (address) stack.frames[stack.count++] = address;
        if (frame.previous <= fp || frame.previous - fp > 1024 * 1024) {
            stack.termination = "end or invalid frame chain";
            break;
        }
        fp = frame.previous;
    }
    if (stack.count == LCMaximumFrames) stack.termination = "frame limit";
    stack.resumeResult = thread_resume(thread);
    return stack;
}

static void logFrame(unsigned index, uintptr_t address) {
    unsigned count = atomic_load(&imageCount);
    if (count > LCMaximumImages) count = LCMaximumImages;
    for (unsigned i = 0; i < count; i++) {
        LCStartupImage *image = &images[i];
        if (atomic_load_explicit(&image->ready, memory_order_acquire) &&
            address >= image->start && address < image->end) {
            const char *name = strrchr(image->name, '/');
            logFormat("  frame #%u: 0x%llx %s + 0x%llx", index, (unsigned long long)address,
                      name ? name + 1 : image->name, (unsigned long long)(address - image->start));
            return;
        }
    }
    logFormat("  frame #%u: 0x%llx <unmapped>", index, (unsigned long long)address);
}

static void dumpThreads(unsigned dumpNumber, double stalledSeconds, const char *reason) {
    logFormat("THREAD BACKTRACE ALL sample=%u reason=%s main-heartbeat-stalled=%.3fs (best-effort frame-pointer stacks, not LLDB)",
              dumpNumber, reason, stalledSeconds);
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t threadCount = 0;
    kern_return_t result = task_threads(mach_task_self(), &threads, &threadCount);
    if (result != KERN_SUCCESS) {
        logFormat("task_threads failed: %d", result);
        return;
    }
    thread_t sampler = mach_thread_self();
    for (unsigned i = 0; i < threadCount; i++) {
        if (threads[i] == sampler) {
            logFormat("thread #%u port=%u: diagnostic sampler (not suspended)", i, threads[i]);
        } else {
            thread_identifier_info_data_t identifier = {0};
            mach_msg_type_number_t count = THREAD_IDENTIFIER_INFO_COUNT;
            thread_info(threads[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&identifier, &count);
            LCStartupStack stack = sampleThread(threads[i]);
            logFormat("thread #%u tid=%llu port=%u%s state=%d resume=%d %s", i,
                      (unsigned long long)identifier.thread_id, threads[i],
                      threads[i] == mainThread ? " MAIN" : "",
                      stack.stateResult, stack.resumeResult, stack.termination);
            for (unsigned j = 0; j < stack.count; j++) logFrame(j, stack.frames[j]);
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    mach_port_deallocate(mach_task_self(), sampler);
    vm_deallocate(mach_task_self(), (vm_address_t)threads, threadCount * sizeof(thread_t));
    logMessage("Binary images (load address, UUID, install name; use matching dSYMs for symbolication):");
    unsigned count = atomic_load(&imageCount);
    if (count > LCMaximumImages) {
        logMessage("Image table truncated at 2048 entries");
        count = LCMaximumImages;
    }
    for (unsigned i = 0; i < count; i++) {
        LCStartupImage *image = &images[i];
        if (!atomic_load_explicit(&image->ready, memory_order_acquire)) continue;
        char uuid[37];
        uuid_unparse(image->uuid, uuid);
        logFormat("  0x%llx-0x%llx %s %s", (unsigned long long)image->start,
                  (unsigned long long)image->end, uuid, image->name);
    }
    logMessage("END THREAD BACKTRACE ALL");
}

static void heartbeat(void *context) {
    (void)context;
    atomic_store(&lastHeartbeat, now());
    atomic_store(&heartbeatPending, false);
}

static void *monitor(void *context) {
    (void)context;
    pthread_setname_np("LC startup diagnostics");
    unsigned dumps = 0;
    uint64_t lastDump = 0;
    while (!atomic_load(&stopped)) {
        bool expected = false;
        if (atomic_compare_exchange_strong(&heartbeatPending, &expected, true)) {
            dispatch_async_f(dispatch_get_main_queue(), NULL, heartbeat);
        }
        uint64_t timestamp = now();
        uint64_t lastResponse = atomic_load(&lastHeartbeat);
        uint64_t stalled = timestamp > lastResponse ? timestamp - lastResponse : 0;
        uint64_t appeared = atomic_load(&uiAppearedTime);
        bool waitingForRoot = !appeared && timestamp - launchTime >= 8 * LCSecond;
        if ((stalled >= 3 * LCSecond || waitingForRoot) && dumps < LCMaximumDumps &&
            (!lastDump || timestamp - lastDump >= 10 * LCSecond)) {
            dumpThreads(++dumps, stalled / (double)LCSecond,
                        stalled >= 3 * LCSecond ? "main queue unresponsive" : "root view not appeared");
            lastDump = now();
        }
        if (appeared && timestamp >= appeared && timestamp - appeared >= 10 * LCSecond && stalled < LCSecond) {
            stop("Root appeared and main queue responsive after 10-second grace period");
        } else if (timestamp - launchTime >= 180 * LCSecond) {
            stop("Startup monitor reached 180-second limit; no successful completion recorded");
        }
        // Flush from the sampler, never fsync every main-thread checkpoint.
        fsync(logFD);
        struct timespec delay = { .tv_nsec = 500000000 };
        nanosleep(&delay, NULL);
    }
    fsync(logFD);
    mach_port_deallocate(mach_task_self(), mainThread);
    return NULL;
}

const LCStartupDiagnosticsAPI *LCStartupDiagnosticsStart(const char *home) {
    static const LCStartupDiagnosticsAPI api = { logMessage, begin, end, uiAppeared, stop };
    if (!home || logFD >= 0) return &api;
    launchTime = now();
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/Documents", home);
    mkdir(path, 0700);
    time_t wallTime = time(NULL);
    struct tm date;
    localtime_r(&wallTime, &date);
    char timestamp[40];
    strftime(timestamp, sizeof(timestamp), "%Y%m%d-%H%M%S%z", &date);
    snprintf(path, sizeof(path), "%s/Documents/LCStartup-%s-%d.log", home, timestamp, getpid());
    logFD = open(path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0600);
    if (logFD < 0) {
        perror("LC startup diagnostics: cannot create log in Documents");
        return &api;
    }
    mainThread = mach_thread_self();
    atomic_store(&lastHeartbeat, launchTime);
    logFormat("START LC startup diagnostics v1 date=%s pid=%d main-port=%u", timestamp, getpid(), mainThread);
    struct utsname system;
    if (uname(&system) == 0) logFormat("System: %s %s %s %s", system.sysname, system.release, system.machine, system.version);
    logMessage("Each launch has its own file. BEGIN without END identifies interrupted work. Raw stacks can be incomplete without frame pointers.");
    pthread_t worker;
    int result = pthread_create(&worker, NULL, monitor, NULL);
    if (result == 0) {
        pthread_detach(worker);
    } else {
        logFormat("Cannot start diagnostic sampler: %d", result);
        mach_port_deallocate(mach_task_self(), mainThread);
    }
    uint64_t token = begin("Register binary image metadata");
    _dyld_register_func_for_add_image(imageAdded);
    end(token);
    return &api;
}
