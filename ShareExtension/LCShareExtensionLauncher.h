#import <Foundation/Foundation.h>

@interface LCShareExtensionLauncher : NSObject
+ (BOOL)openURLFromShareExtension:(NSURL *)url;
+ (BOOL)openURLFromShareExtensionWithOptions:(NSDictionary *)options;
+ (BOOL)canOpenURLFromShareExtension:(NSURL *)url;
@end
