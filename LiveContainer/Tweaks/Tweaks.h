//
//  Tweaks.h
//  LiveContainer
//
//  Created by s s on 2025/2/7.
//

void swizzle(Class class, SEL originalAction, SEL swizzledAction);
bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction);

void NUDGuestHooksInit(void);
void SecItemGuestHooksInit(void);
void DyldHooksInit(bool hideLiveContainer, bool hookDlopen, uint32_t spoofSDKVersion);
void NSFMGuestHooksInit(void);
void initDead10ccFix(void);
// Device spoofing
void DeviceSpoofingGuestHooksInit(void);

@interface NSBundle(LiveContainer)
- (instancetype)initWithPathForMainBundle:(NSString *)path;
@end


extern uint32_t appMainImageIndex;
extern void* appExecutableHandle;
extern bool tweakLoaderLoaded;
void* getGuestAppHeader(void);
void* getDSCAddr(void);
void* getCachedSymbol(NSString* symbolName, struct mach_header_64* header);
void saveCachedSymbol(NSString* symbolName, struct mach_header_64* header, uint64_t offset);
void* dlopen_nolock(const char *path, int mode);

static void hook_do_nothing(void) {}
