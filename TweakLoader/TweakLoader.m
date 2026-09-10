#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#import "../LiveContainer/utils.h"

static NSString *loadTweakAtURL(NSURL *url) {
    NSString *tweakPath = url.path;
    NSString *tweak = tweakPath.lastPathComponent;
    if (![tweakPath hasSuffix:@".dylib"] && ![tweakPath hasSuffix:@".framework"]) {
        return nil;
    }
    if ([tweakPath hasSuffix:@".framework"]) {
        NSURL* infoPlistURL = [url URLByAppendingPathComponent:@"Info.plist"];
        NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfURL:infoPlistURL];
        NSString* binary = infoDict[@"CFBundleExecutable"];
        if(!binary || ![binary isKindOfClass:NSString.class]) {
            return [NSString stringWithFormat:@"Unable to load %@: Unable to read Info.Plist", tweak];
        }
        tweakPath = [[url URLByAppendingPathComponent:binary] path];
    }
    
    void *handle = dlopen(tweakPath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    const char *error = dlerror();
    if (handle) {
        NSLog(@"Loaded tweak %@", tweak);
        return nil;
    } else if (error) {
        NSLog(@"Error: %s", error);
        return @(error);
    } else {
        NSLog(@"Error: dlopen(%@): Unknown error because dlerror() returns NULL", tweak);
        return [NSString stringWithFormat:@"dlopen(%@): unknown error, handle is NULL", tweakPath];
    }
}

static void loadTweaksRecursively(NSURL *folderURL, NSMutableArray *errors) {
    NSArray<NSURL *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folderURL includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:nil];
    for (NSURL *fileURL in items) {
        NSString *name = fileURL.lastPathComponent;
        if ([name hasSuffix:@".disabled"]) {
            NSLog(@"Skipping disabled tweak %@", name);
            continue;
        }
        NSNumber *isDirectory = nil;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        // a .framework is a directory but loads as a single tweak
        if (isDirectory.boolValue && ![name hasSuffix:@".framework"]) {
            loadTweaksRecursively(fileURL, errors);
        } else {
            NSString *error = loadTweakAtURL(fileURL);
            if (error) {
                [errors addObject:error];
            }
        }
    }
}

static void showDlerrAlert(NSString *error) {
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Failed to load tweaks" message:error preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:okAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        UIPasteboard.generalPasteboard.string = error;
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = 1000;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

 __attribute__((constructor))
static void TweakLoaderConstructor() {
    const char *tweakFolderC = getenv("LC_GLOBAL_TWEAKS_FOLDER");
    NSString *globalTweakFolder = @(tweakFolderC);
    unsetenv("LC_GLOBAL_TWEAKS_FOLDER");
    
    if([NSUserDefaults.guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {
        // don't load any tweak since tweakloader is loaded after all initializers
        NSLog(@"Skip loading tweaks");
        return;
    }
    
    NSMutableArray *errors = [NSMutableArray new];
    
    NSArray<NSURL *> *globalTweaks = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:globalTweakFolder]
    includingPropertiesForKeys:@[] options:0 error:nil];
    NSString *tweakFolderName = NSUserDefaults.guestAppInfo[@"LCTweakFolder"];
    
    if([globalTweaks count] <= 1 && tweakFolderName.length == 0) {
        // nothing to load
        return;
    }

    // Load CydiaSubstrate
    const char *lcMainBundlePath;
    if(NSUserDefaults.isLiveProcess) {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.fileSystemRepresentation;
    } else {
        lcMainBundlePath = NSUserDefaults.lcMainBundle.bundlePath.fileSystemRepresentation;
    }
    char substratePath[PATH_MAX];
    snprintf(substratePath, sizeof(substratePath), "%s/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", lcMainBundlePath);
    dlopen(substratePath, RTLD_LAZY | RTLD_GLOBAL);
    const char *substrateError = dlerror();
    if (substrateError) {
        [errors addObject:@(substrateError)];
    }

    // Load global tweaks
    NSLog(@"Loading tweaks from the global folder");

    for (NSURL *fileURL in globalTweaks) {
        NSString *name = fileURL.lastPathComponent;
        if ([name isEqualToString:@"TweakLoader.dylib"]) {
            // skip loading myself
            continue;
        }
        if ([name hasSuffix:@".disabled"]) {
            NSLog(@"Skipping disabled global tweak %@", name);
            continue;
        }
        NSString *error = loadTweakAtURL(fileURL);
        if (error) {
            [errors addObject:error];
        }
    }

    // Load selected tweak folder, recursively
    if (tweakFolderName.length > 0) {
        NSLog(@"Loading tweaks from the selected folder");
        NSString *tweakFolder = [globalTweakFolder stringByAppendingPathComponent:tweakFolderName];
        loadTweaksRecursively([NSURL fileURLWithPath:tweakFolder], errors);
    }

    if (errors.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *error = [errors componentsJoinedByString:@"\n"];
            showDlerrAlert(error);
        });
    }
}
