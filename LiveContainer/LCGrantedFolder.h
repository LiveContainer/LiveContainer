#import <Foundation/Foundation.h>

/// A real Files bookmark lease, not a fabricated filesystem permission.
static inline NSString *LCPrepareGrantedFolder(NSString *home, NSData *bookmark, NSURL * __strong *lease) {
    if (bookmark && ![bookmark isKindOfClass:NSData.class]) return @"Invalid shared folder bookmark. Select the folder again.";
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *base = [home stringByAppendingPathComponent:@"Documents/LiveContainer Access"];
    NSString *marker = [base stringByAppendingPathComponent:@".lcos-access"];
    NSString *mount = [base stringByAppendingPathComponent:@"Shared"];
    NSString *resolvedHome = [home stringByResolvingSymlinksInPath];
    if (![[base stringByResolvingSymlinksInPath] hasPrefix:[resolvedHome stringByAppendingString:@"/"]]) {
        return bookmark ? @"The shared folder mount points outside this guest's container; it was not changed." : nil;
    }
    NSData *signature = [@"LiveContainer-Granted-Folder-v1" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL managed = [[NSData dataWithContentsOfFile:marker] isEqualToData:signature];
    if (!bookmark.length) {
        if (managed && [[fm attributesOfItemAtPath:mount error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink]) {
            [fm removeItemAtPath:mount error:nil];
        }
        return nil;
    }
    BOOL stale = NO;
    NSError *error = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    if (!url || stale) return @"The shared folder permission expired. Select the folder again in this app's LiveContainer settings.";
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *(^fail)(NSString *) = ^NSString *(NSString *reason) {
        if (scoped) [url stopAccessingSecurityScopedResource];
        return reason ?: @"Shared folder access could not be prepared.";
    };
    NSString *target = url.URLByResolvingSymlinksInPath.path;
    if ([target isEqualToString:resolvedHome] || [target hasPrefix:[resolvedHome stringByAppendingString:@"/"]] ||
        [resolvedHome hasPrefix:[target stringByAppendingString:@"/"]] || [target isEqualToString:@"/"]) {
        return fail(@"Choose a folder outside this guest's data container to avoid recursive folder links.");
    }
    BOOL directory = NO;
    if (![fm fileExistsAtPath:target isDirectory:&directory] || !directory || ![fm isReadableFileAtPath:target]) {
        return fail(@"The granted folder is unavailable. Reconnect its file provider or select it again.");
    }
    NSDictionary *baseAttributes = [fm attributesOfItemAtPath:base error:nil];
    if (baseAttributes && (!managed || ![baseAttributes[NSFileType] isEqual:NSFileTypeDirectory])) {
        return fail(@"Documents/LiveContainer Access already contains unmanaged data; it was not changed.");
    }
    if (![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![signature writeToFile:marker options:NSDataWritingAtomic error:&error]) return fail(error.localizedDescription);
    NSDictionary *attributes = [fm attributesOfItemAtPath:mount error:nil];
    if (attributes && ![attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) {
        return fail(@"The shared folder link was replaced by a file or directory; it was not changed.");
    }
    if (attributes && ![fm removeItemAtPath:mount error:&error]) return fail(error.localizedDescription);
    if (![fm createSymbolicLinkAtPath:mount withDestinationPath:target error:&error]) return fail(error.localizedDescription);
    if (lease) *lease = scoped ? url : nil;
    return nil;
}
