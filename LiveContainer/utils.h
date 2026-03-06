#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <os/lock.h>
#define PrivClass(name) ((Class)objc_lookUpClass(#name))

void swizzle(Class class, SEL originalAction, SEL swizzledAction);
void swizzleClassMethod(Class class, SEL originalAction, SEL swizzledAction);
// Cross-class swizzling (adds method from class2 to class, then swizzles)
void swizzle2(Class class, SEL originalAction, Class class2, SEL swizzledAction);

const char **_CFGetProgname(void);
const char **_CFGetProcessPath(void);
int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
int csops_audittoken(pid_t pid, unsigned int ops, void * useraddr, size_t usersize, audit_token_t * token);
#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_VALID
#define CS_VALID 0x00000001
#endif
#ifndef CS_ADHOC
#define CS_ADHOC 0x00000002
#endif
#ifndef CS_GET_TASK_ALLOW
#define CS_GET_TASK_ALLOW 0x00000004
#endif
#ifndef CS_INSTALLER
#define CS_INSTALLER 0x00000008
#endif
#ifndef CS_HARD
#define CS_HARD 0x00000100
#endif
#ifndef CS_KILL
#define CS_KILL 0x00000200
#endif
#ifndef CS_RESTRICT
#define CS_RESTRICT 0x00000800
#endif
#ifndef CS_ENFORCEMENT
#define CS_ENFORCEMENT 0x00001000
#endif
#ifndef CS_REQUIRE_LV
#define CS_REQUIRE_LV 0x00002000
#endif
#ifndef CS_PLATFORM_BINARY
#define CS_PLATFORM_BINARY 0x04000000
#endif
#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
void os_unfair_recursive_lock_lock_with_options(void* lock, uint32_t options);
void os_unfair_recursive_lock_unlock(void* lock);
bool os_unfair_recursive_lock_trylock(void* lock);
bool os_unfair_recursive_lock_tryunlock4objc(void* lock);

struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void);
void *getDyldBase(void);
void init_bypassDyldLibValidation(void);
kern_return_t builtin_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot);
void *jitless_hook_dlopen(const char *path, int mode);

uint64_t aarch64_get_tbnz_jump_address(uint32_t instruction, uint64_t pc);
uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc);
bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm);
uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc);
uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc);

@interface NSUserDefaults(LiveContainer)
+ (instancetype)lcUserDefaults;
+ (instancetype)lcSharedDefaults;
+ (NSString *)lcAppGroupPath;
+ (NSString *)lcAppUrlScheme;
+ (NSBundle *)lcMainBundle;
+ (NSDictionary *)guestAppInfo;
+ (NSDictionary *)guestContainerInfo;
+ (bool)isLiveProcess;
+ (bool)isSharedApp;
+ (NSString*)lcGuestAppId;
+ (bool)isSideStore;
+ (bool)sideStoreExist;
@end

@interface NSDictionary(lc)
- (BOOL)writeBinToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile;
@end
