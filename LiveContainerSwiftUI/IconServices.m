//
//  IconServices.m
//  LiveContainer
//
//  Created by s s on 2026/1/15.
//

@import UIKit;
@import ObjectiveC;
@import UniformTypeIdentifiers;
#include <dlfcn.h>
#import "LCUtils.h"

#define PrivClass(name) ((Class)objc_lookUpClass(#name))

@interface IFColor : NSObject
- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (instancetype)initWithCGColor:(CGColorRef)color;
@end

@interface IFBundle : NSObject
- (instancetype)initWithURL:(NSURL*)url;
- (NSDictionary*)iconDictionary;
@end

@interface IFImage : NSObject
- (CGImageRef)CGImage;
@end

@interface ISImageDescriptor : NSObject
@property (nonatomic, assign, readwrite) NSInteger appearance;
@property (nonatomic, assign, readwrite) NSInteger appearanceVariant NS_AVAILABLE_IOS(18_0);
@property (nonatomic, assign, readwrite) NSUInteger specialIconOptions NS_AVAILABLE_IOS(18_0);
@property (nonatomic, assign, readwrite) BOOL drawBorder;
@property (nonatomic, assign, readwrite) BOOL shouldApplyMask;
@property (atomic, assign, readwrite) BOOL ignoreCache;
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, strong, readwrite) IFColor *tintColor;
@property (nonatomic, assign, readwrite) NSUInteger variantOptions;
+ (instancetype)imageDescriptorNamed:(NSString *)name;
@end

@interface ISIcon : NSObject
- (CGImageRef)CGImageForImageDescriptor:(ISImageDescriptor *)imageDescriptor;
@end

@interface ISConcreteIcon : ISIcon
@end

@interface ISBundleIcon : ISIcon

@property (readonly) NSString *tag;
@property (readonly) NSString *tagClass;
@property (readonly) NSString *type;
@property (readonly) NSURL *url;

+ (bool)supportsSecureCoding;

- (double)_aspectRatio;
- (id)_makeAppResourceProvider;
- (id)_makeDocumentResourceProvider;
- (id)description;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithBundleURL:(id)arg1;
- (id)initWithBundleURL:(id)arg1 fileExtension:(id)arg2;
- (id)initWithBundleURL:(id)arg1 type:(id)arg2;
- (id)initWithBundleURL:(id)arg1 type:(id)arg2 tag:(id)arg3 tagClass:(id)arg4;
- (id)initWithCoder:(id)arg1;
- (id)makeResourceProvider;
- (id)tag;
- (id)tagClass;
- (id)type;
- (id)url;

@end

@interface ISGenerationRequest : NSObject
@property (retain) ISConcreteIcon *icon;
@property (retain) ISImageDescriptor *imageDescriptor;
@property unsigned long long lsDatabaseSequenceNumber;
@property (retain) NSUUID *lsDatabaseUUID;

+ (bool)supportsSecureCoding;

- (id)_decorationRecipeKeyFromType:(id)arg1;
- (void)encodeWithCoder:(id)arg1;
- (id)generateImage;
- (id)generateImageReturningRecordIdentifiers:(id*)arg1;
- (id)icon;
- (id)imageDescriptor;
- (id)init;
- (id)initWithCoder:(id)arg1;
- (unsigned long long)lsDatabaseSequenceNumber;
- (id)lsDatabaseUUID;
- (void)setIcon:(ISConcreteIcon*)arg1;
- (void)setImageDescriptor:(ISImageDescriptor*)arg1;
- (void)setLsDatabaseSequenceNumber:(unsigned long long)arg1;
- (void)setLsDatabaseUUID:(NSUUID*)arg1;

@end

@interface ISRecordResourceProvider : NSObject
-(id)initWithRecord:(id)arg1 options:(unsigned long long)arg2 ;
-(void)resolveResources;
-(id)suggestedRecipe;
-(void)setSuggestedRecipe:(id)suggestedRecipe;
-(void)setResourceType:(NSUInteger)type;
-(void)setIconShape:(NSUInteger)type; // below ios 17
@end

@interface ISBundleResourceProvider : NSObject
- (id)initWithBundle:(id)arg1 options:(unsigned long long)arg2;
@end

@interface ISiOSAppRecipe : NSObject
- (instancetype)init;
@end


@interface LSApplicationRecordFake : NSObject
@property NSBundle* bundle;
@end

@interface UIImageAsset(private)
+(instancetype)_dynamicAssetNamed:(NSString*)arg1 generator:(UIImage* (^)(UIImageAsset *asset, UIImageConfiguration *config, UIImage *image))arg2 ;
@end

@interface UIImageConfiguration(private)
+(instancetype)_unspecifiedConfiguration;
@end


@implementation LSApplicationRecordFake
- (instancetype)initWithBundle:(NSBundle *)bundle {
    self.bundle = bundle;
    return self;
}
- (BOOL)_is_canProvideIconResources {
    return YES;
}
- (NSDictionary *)iconDictionary {
    IFBundle* ifBundle = [[PrivClass(IFBundle) alloc] initWithURL:self.bundle.bundleURL];
    return [ifBundle iconDictionary];
}
- (NSURL *)iconResourceBundleURL {
    return self.bundle.bundleURL;
}
- (NSData *)persistentIdentifier {
    return [NSData data];
}
- (NSUInteger) _IS_platformToIFPlatform {
    return 4;
}
- (id)appClipMetadata {
    return nil;
}

-(BOOL)isKindOfClass:(Class)aClass {
    const char* className = class_getName(aClass);
    if(strcmp(className, "LSBundleRecord") == 0) {
        return true;
    } else if (strcmp(className, "LSApplicationRecord") == 0) {
        return true;
    } else {
        return [super isKindOfClass:aClass];
    }
}

-(id)initWithURL:(id)arg1 allowPlaceholder:(BOOL)arg2 error:(id*)arg3 {
    return nil;
}

- (int)developerType {
    return 0;
}

@end


NSMutableSet<ISBundleIcon*>* iconsNeedToGenerateOriginalIcon;
@interface ISBundleIconFake : NSObject
@end

@implementation ISBundleIconFake

- (id)makeResourceProvider {
    NSURL* url = [(ISBundleIcon*)self url];
    NSBundle* bundle = [[NSBundle alloc] initWithURL:url];
    
    if([iconsNeedToGenerateOriginalIcon containsObject:(ISBundleIcon *)self]) {
//        return [[PrivClass(ISBundleResourceProvider) alloc] initWithBundle:bundle options:0];
        return [self makeResourceProviderOrignal];
    }
    
    // to make IconServices generate an app icon, we need ISRecordResourceProvider instead of ISBundleResourceProvider, but it requires a LSApplicationRecord, so we create a fake LSApplicationRecordFake with necessary methods to make it initialize correctly
    LSApplicationRecordFake* record = [[LSApplicationRecordFake alloc] initWithBundle:bundle];
    ISRecordResourceProvider* provider = [[PrivClass(ISRecordResourceProvider) alloc] initWithRecord:record options:0];
    
    if(@available(iOS 17.0, *)) {
        // set suggestedRecipe so -[ISRecipeFactory _recipe] skips all checks and directly use ISiOSAppRecipe
        [provider setSuggestedRecipe:[[PrivClass(ISiOSAppRecipe) alloc] init]];
        [provider setResourceType:1];
    } else {
        // force IconShape to 7 so a ISiOSAppRecipe will eventually generate in -[ISGenerationRequest generateImageReturningRecordIdentifiers:]
        // 0x1a04c116c(x26, &sel_setShape:, 0x1a04c116c(x0_37, &sel_iconShape))
        // shape - 1 > 5 -> ISiOSAppRecipe
        [provider setIconShape:7];
    }
    return provider;
}

- (id)makeResourceProviderOrignal {
    return nil;
}

@end

@interface IFBundleFake : NSObject
@end

@implementation IFBundleFake
- (NSUInteger)platform {
    return 4;
}
@end

BOOL saveCGImage(CGImageRef image, NSURL *url) {
    // 1. Define the file type (PNG is lossless)
    // For older systems, use kUTTypePNG
    CFStringRef type = (__bridge CFStringRef)(UTTypePNG.identifier);

    // 2. Create the image destination
    // We specify the URL, the file type, and a count of 1 image
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
    
    if (!destination) {
        NSLog(@"Failed to create image destination");
        return NO;
    }

    // 3. Add the image to the destination
    // The third parameter is for options (like metadata or compression settings)
    CGImageDestinationAddImage(destination, image, NULL);

    // 4. Finalize the writing process
    BOOL success = CGImageDestinationFinalize(destination);
    
    // 5. Release the destination (Core Foundation objects require manual release)
    CFRelease(destination);
    
    return success;
}

CGImageRef loadCGImageFromURL(NSURL *url) {
    // 1. Create an image source from the URL
    // Passing NULL for options; you can pass a dictionary to hint at the file type
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    
    if (!source) {
        NSLog(@"Failed to create image source at: %@", url);
        return NULL;
    }

    // 2. Create the CGImage from the source at index 0
    // (Index 0 is the standard for single-image files like PNG/JPG)
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    
    // 3. Cleanup the source
    // Even though we created the image, we must release the source reference
    CFRelease(source);
    
    if (!image) {
        NSLog(@"Failed to create image from source");
        return NULL;
    }

    // Note: The caller is responsible for calling CFRelease(image) when finished!
    return image;
}

@implementation UIImage(LiveContainer)
+ (instancetype)generateIconForBundleURL:(NSURL*)url style:(GeneratedIconStyle)style hasBorder:(BOOL)hasBorder {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iconsNeedToGenerateOriginalIcon = [NSMutableSet new];
        
        void* handle = dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_LAZY|RTLD_GLOBAL);
        assert(handle);

        Class isBundleClass = PrivClass(ISBundleIcon);
        Method originalGetProviderMethod = class_getInstanceMethod(isBundleClass, @selector(makeResourceProvider));
        class_addMethod(isBundleClass, @selector(makeResourceProviderOrignal), method_getImplementation(originalGetProviderMethod), method_getTypeEncoding(originalGetProviderMethod));
        method_exchangeImplementations(originalGetProviderMethod, class_getInstanceMethod(ISBundleIconFake.class, @selector(makeResourceProvider)));

        // stop IFBundle from trying to connect to lsd database
        method_exchangeImplementations(class_getInstanceMethod(PrivClass(IFBundle), @selector(platform)), class_getInstanceMethod(IFBundleFake.class, @selector(platform)));
        // stop LSBundleIcon from trying to connect to lsd database
        method_exchangeImplementations(class_getInstanceMethod(PrivClass(LSApplicationRecord), @selector(initWithURL:allowPlaceholder:error:)), class_getInstanceMethod(LSApplicationRecordFake.class, @selector(initWithURL:allowPlaceholder:error:)));
    });
    
    if(@available(iOS 18.0, *)) {
        
    } else {
        style = 0;
    }
    
    ISBundleIcon* icon = [[PrivClass(ISBundleIcon) alloc] initWithBundleURL:url];
    ISImageDescriptor *descriptor = [PrivClass(ISImageDescriptor) imageDescriptorNamed:@"com.apple.IconServices.ImageDescriptor.HomeScreen"];
    
    ISGenerationRequest* request = [[PrivClass(ISGenerationRequest) alloc] init];
    [request setIcon:(ISConcreteIcon*)icon];
    [request setImageDescriptor:descriptor];
    

    descriptor.ignoreCache = YES;
    descriptor.scale = UIScreen.mainScreen.scale;
    descriptor.variantOptions = 0;

    if (@available(iOS 16.0, *)) {
        // 0 = light mode, 1 = dark mode
        if(style == 1) {
            descriptor.appearance = 1;
        } else {
            descriptor.appearance = 0;
        }
    }
    if (@available(iOS 18.0, *)) {
        if(@available(iOS 18.2, *)) {
            // 0 = normal, 2 = tinted mode, 3 = liquid glass (gray scale)
            descriptor.appearanceVariant = 0;
        }
        descriptor.specialIconOptions = 2;
    }
    
    descriptor.drawBorder = hasBorder;
    descriptor.shouldApplyMask = hasBorder;
    
    if(style == Original) {
        [iconsNeedToGenerateOriginalIcon addObject:icon];
    }
    
    IFImage* ifImage = [request generateImageReturningRecordIdentifiers:nil];
    CGImageRef imageRef = [ifImage CGImage];
    
    if(style == Original) {
        [iconsNeedToGenerateOriginalIcon removeObject:icon];
    }

    return [UIImage imageWithCGImage:imageRef];
}

@end
