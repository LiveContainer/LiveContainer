#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <os/lock.h>
#define PrivClass(name) ((Class)objc_lookUpClass(#name))

const char **_CFGetProgname(void);
const char **_CFGetProcessPath(void);
int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
int csops_audittoken(pid_t pid, unsigned int ops, void * useraddr, size_t usersize, audit_token_t * token);
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
+ (NSString*)lcLaunchURL;
@end

@interface NSDictionary(lc)
- (BOOL)writeBinToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile;
@end
