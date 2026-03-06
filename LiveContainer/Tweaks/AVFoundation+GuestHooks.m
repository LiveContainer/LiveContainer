//
//  AVFoundation+GuestHooks.m
//  LiveContainer
//
//  Comprehensive camera spoofing with hierarchical hooks
//

#import "AVFoundation+GuestHooks.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <MobileCoreServices/MobileCoreServices.h> 
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import "Tweaks.h"
// #import "../utils.h" // duplicate swizzle

// pragma MARK: - Global State

// Defensive macros
#define SAFE_CALL(obj, selector, ...) \
    ({ \
        typeof(obj) _obj = (obj); \
        (_obj && [_obj respondsToSelector:@selector(selector)]) ? [_obj selector __VA_ARGS__] : nil; \
    })

#define SAFE_RETAIN(obj) \
    ({ \
        typeof(obj) _obj = (obj); \
        _obj ? CFRetain(_obj) : NULL; \
        _obj; \
    })

#define SAFE_RELEASE(obj) \
    do { \
        if (obj) { \
            CFRelease(obj); \
            obj = NULL; \
        } \
    } while(0)

// Core configuration
static BOOL spoofCameraEnabled = NO;
static NSString *spoofCameraVideoPath = @"";
static BOOL spoofCameraLoop = YES;
static BOOL spoofCameraUseVideoAudio = YES;
static NSString *spoofCameraMode = @"standard"; // NEW: Camera mode variable

// Resolution and fallback management
static CGSize targetResolution = {1080, 1920};
static BOOL resolutionDetected = NO;
static CVPixelBufferRef lastGoodSpoofedPixelBuffer = NULL;
static CMVideoFormatDescriptionRef lastGoodSpoofedFormatDesc = NULL;
static OSType lastRequestedFormat = 0;

// Image spoofing resources
static CVPixelBufferRef staticImageSpoofBuffer = NULL;
static AVCaptureDevicePosition g_currentCameraPosition = AVCaptureDevicePositionBack;

// Video spoofing resources
static AVPlayer *videoSpoofPlayer = nil;
static AVPlayerItemVideoOutput *videoSpoofPlayerOutput = nil;
static AVPlayerItemVideoOutput *yuvOutput1 = nil;  // For 420v format
static AVPlayerItemVideoOutput *yuvOutput2 = nil;  // For 420f format
static dispatch_queue_t videoProcessingQueue = NULL;
static BOOL isVideoSetupSuccessfully = NO;
static id playerDidPlayToEndTimeObserver = nil;
static dispatch_queue_t audioSpoofingQueue = NULL;
static AVAssetReader *audioSpoofingReader = nil;
static AVAssetReaderTrackOutput *audioSpoofingOutput = nil;
static NSString *audioSpoofingSourcePath = nil;
static CMTime audioSpoofingLoopOffset = {0, 0, 0, 0};
static CMTime audioSpoofingTrackDuration = {0, 0, 0, 0};
static CMSampleBufferRef g_lastGoodAudioSampleBuffer = NULL;
static NSUInteger audioSpoofingFailureCount = 0;
static CMSampleBufferRef synchronizerVideoSampleBufferRing[8] = {NULL};
static CMSampleBufferRef synchronizerAudioSampleBufferRing[16] = {NULL};
static NSUInteger synchronizerVideoSampleBufferRingIndex = 0;
static NSUInteger synchronizerAudioSampleBufferRingIndex = 0;

// Photo data cache
static CVPixelBufferRef g_cachedPhotoPixelBuffer = NULL;
static CGImageRef g_cachedPhotoCGImage = NULL;
static NSData *g_cachedPhotoJPEGData = nil;
static AVCaptureVideoOrientation g_currentPhotoOrientation = AVCaptureVideoOrientationPortrait;
static CGAffineTransform g_currentVideoTransform;
static dispatch_block_t g_pendingDeferredPhotoCaptureBlock = nil;
static CFAbsoluteTime g_lastRecordingStartTime = 0;
static BOOL g_captureGestureArbitrationEnabled = NO;
static const CFTimeInterval kPhotoDeferralSeconds = 0.30;
static const CFTimeInterval kPhotoSuppressionAfterRecordStartSeconds = 0.60;

// pragma MARK: - Helper Interface

@interface NSUserDefaults(LiveContainerPrivate)
+ (NSDictionary*)guestAppInfo;
@end

// pragma MARK: - Forward Declarations

// Core functions
static void setupImageSpoofingResources(void);
static void setupVideoSpoofingResources(void);
static void setupAudioSpoofingResources(void);
static CMSampleBufferRef createSpoofedSampleBuffer(void);
static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer);
static void cleanupPhotoCache(void);
static void cleanupAudioSpoofingResources(void);
static CMSampleBufferRef copyNextSpoofedAudioSampleBuffer(void);
static void cleanupSynchronizerSampleBufferCache(void);
static void createStaticImageFromUIImage(UIImage *sourceImage);
static CVPixelBufferRef rotatePixelBufferToPortrait(CVPixelBufferRef sourceBuffer);
static void installPrivateCapturePipelineHooks(void);
static void LCCancelPendingDeferredPhotoCapture(void);
static void LCMarkRecordingStarted(void);

@class GetFrameKVOObserver;

@interface GetFrameKVOObserver : NSObject
@end

@interface GetFrame : NSObject
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve;
+ (CVPixelBufferRef)getCurrentFramePixelBuffer:(OSType)requestedFormat;
+ (void)setCurrentVideoPath:(NSString *)path;
+ (void)setupPlayerWithPath:(NSString *)path;
+ (UIWindow *)getKeyWindow;
+ (void)createVideoFromImage:(UIImage *)sourceImage;
+ (CVPixelBufferRef)createPixelBufferFromImage:(UIImage *)image size:(CGSize)size;
+ (CVPixelBufferRef)createVariedPixelBufferFromOriginal:(CVPixelBufferRef)originalBuffer variation:(float)amount;
@end

@interface AVCapturePhotoOutput (LiveContainerSpoofSelectors)
- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@interface AVCaptureVideoDataOutput (LiveContainerSpoofSelectors)
- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate
                             queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@interface AVCaptureAudioDataOutput (LiveContainerSpoofSelectors)
- (void)lc_setAudioSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate
                                  queue:(dispatch_queue_t)sampleBufferCallbackQueue;
@end

@interface AVCaptureDataOutputSynchronizer (LiveContainerSpoofSelectors)
- (void)lc_setDelegate:(id<AVCaptureDataOutputSynchronizerDelegate>)delegate
                 queue:(dispatch_queue_t)delegateCallbackQueue;
@end

// Level 1 hooks (Core Video)
static CVReturn (*original_CVPixelBufferCreate)(CFAllocatorRef, size_t, size_t, OSType, CFDictionaryRef, CVPixelBufferRef *);
CVReturn hook_CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);

// ADD THESE FORWARD DECLARATIONS FOR GetFrame STATIC VARIABLES:
static NSString *currentVideoPath;
static AVPlayer *frameExtractionPlayer;
static AVPlayerItemVideoOutput *bgraOutput;
static AVPlayerItemVideoOutput *yuv420vOutput; 
static AVPlayerItemVideoOutput *yuv420fOutput;
static GetFrameKVOObserver *_kvoObserver = nil;
static BOOL playerIsReady = NO;
static BOOL isValidPixelFormat(OSType format);

// Level 2 hooks (Device Level)
// Device enumeration hooks declared in @implementation

// Level 3 hooks (Device Input Level)
// Device input hooks declared in @implementation

// Level 4 hooks (Session Level)
// Session hooks declared in @implementation

// Level 5 hooks (Output Level)
// Output hooks declared in @implementation

// Level 6 hooks (Photo Accessor Level)
static CVPixelBufferRef (*original_AVCapturePhoto_pixelBuffer)(id, SEL);
static CVPixelBufferRef (*original_AVCapturePhoto_previewPixelBuffer)(id, SEL);
static CGImageRef (*original_AVCapturePhoto_CGImageRepresentation)(id, SEL);
static CGImageRef (*original_AVCapturePhoto_previewCGImageRepresentation)(id, SEL);
static NSData *(*original_AVCapturePhoto_fileDataRepresentation)(id, SEL);
static NSData *(*original_AVCapturePhoto_fileDataRepresentationWithCustomizer)(id, SEL, id);
static CVPixelBufferRef (*original_AVCaptureDeferredPhotoProxy_pixelBuffer)(id, SEL);
static CVPixelBufferRef (*original_AVCaptureDeferredPhotoProxy_previewPixelBuffer)(id, SEL);
static CGImageRef (*original_AVCaptureDeferredPhotoProxy_CGImageRepresentation)(id, SEL);
static CGImageRef (*original_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation)(id, SEL);
static NSData *(*original_AVCaptureDeferredPhotoProxy_fileDataRepresentation)(id, SEL);
static NSData *(*original_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer)(id, SEL, id);
static NSData *(*original_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer)(id, SEL, CMSampleBufferRef, CMSampleBufferRef);
static CMSampleBufferRef (*original_AVCaptureSynchronizedSampleBufferData_sampleBuffer)(id, SEL);
CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd);
CVPixelBufferRef hook_AVCapturePhoto_previewPixelBuffer(id self, SEL _cmd);
CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd);
CGImageRef hook_AVCapturePhoto_previewCGImageRepresentation(id self, SEL _cmd);
NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd);
NSData *hook_AVCapturePhoto_fileDataRepresentationWithCustomizer(id self, SEL _cmd, id customizer);
CVPixelBufferRef hook_AVCaptureDeferredPhotoProxy_pixelBuffer(id self, SEL _cmd);
CVPixelBufferRef hook_AVCaptureDeferredPhotoProxy_previewPixelBuffer(id self, SEL _cmd);
CGImageRef hook_AVCaptureDeferredPhotoProxy_CGImageRepresentation(id self, SEL _cmd);
CGImageRef hook_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation(id self, SEL _cmd);
NSData *hook_AVCaptureDeferredPhotoProxy_fileDataRepresentation(id self, SEL _cmd);
NSData *hook_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer(id self, SEL _cmd, id customizer);
NSData *hook_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer(id self, SEL _cmd, CMSampleBufferRef jpegSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer);
CMSampleBufferRef hook_AVCaptureSynchronizedSampleBufferData_sampleBuffer(id self, SEL _cmd);

// pragma MARK: - Core Utilities

// Pixel buffer utilities
static CIContext *sharedCIContext = nil;

static void LCCancelPendingDeferredPhotoCapture(void) {
    @synchronized([AVCapturePhotoOutput class]) {
        if (g_pendingDeferredPhotoCaptureBlock) {
            dispatch_block_cancel(g_pendingDeferredPhotoCaptureBlock);
            g_pendingDeferredPhotoCaptureBlock = nil;
        }
    }
}

static void LCMarkRecordingStarted(void) {
    @synchronized([AVCapturePhotoOutput class]) {
        g_lastRecordingStartTime = CFAbsoluteTimeGetCurrent();
        if (g_pendingDeferredPhotoCaptureBlock) {
            dispatch_block_cancel(g_pendingDeferredPhotoCaptureBlock);
            g_pendingDeferredPhotoCaptureBlock = nil;
        }
    }

    if (spoofCameraEnabled && spoofCameraUseVideoAudio) {
        // Rebuild reader at recording start so audio follows the same scrub point as video.
        setupAudioSpoofingResources();
    }
}

static CMTime LCAudioSampleDuration(CMSampleBufferRef sampleBuffer) {
    if (!sampleBuffer) {
        return kCMTimeInvalid;
    }
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    if (CMTIME_IS_VALID(duration) &&
        CMTIME_COMPARE_INLINE(duration, >, kCMTimeZero) &&
        !CMTIME_IS_INDEFINITE(duration)) {
        return duration;
    }

    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    if (numSamples <= 0) {
        return kCMTimeInvalid;
    }

    CMAudioFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!formatDesc) {
        return kCMTimeInvalid;
    }

    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    if (!asbd || asbd->mSampleRate <= 0.0) {
        return kCMTimeInvalid;
    }

    Float64 seconds = (Float64)numSamples / asbd->mSampleRate;
    return CMTimeMakeWithSeconds(seconds, 48000);
}

static CMSampleBufferRef createRetimedAudioSampleBuffer(CMSampleBufferRef sampleBuffer, CMTime offset) {
    if (!sampleBuffer) {
        return NULL;
    }
    if (!CMTIME_IS_VALID(offset) || CMTIME_COMPARE_INLINE(offset, ==, kCMTimeZero)) {
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    CMItemCount timingCount = 0;
    OSStatus timingStatus = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, NULL, &timingCount);
    if (timingStatus != noErr || timingCount <= 0) {
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    CMSampleTimingInfo *timings = calloc((size_t)timingCount, sizeof(CMSampleTimingInfo));
    if (!timings) {
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    CMItemCount actualTimingCount = 0;
    timingStatus = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, timingCount, timings, &actualTimingCount);
    if (timingStatus != noErr || actualTimingCount <= 0) {
        free(timings);
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    for (CMItemCount i = 0; i < actualTimingCount; i++) {
        if (CMTIME_IS_VALID(timings[i].presentationTimeStamp)) {
            timings[i].presentationTimeStamp = CMTimeAdd(timings[i].presentationTimeStamp, offset);
        }
        if (CMTIME_IS_VALID(timings[i].decodeTimeStamp) && !CMTIME_IS_INDEFINITE(timings[i].decodeTimeStamp)) {
            timings[i].decodeTimeStamp = CMTimeAdd(timings[i].decodeTimeStamp, offset);
        }
    }

    CMSampleBufferRef retimedSampleBuffer = NULL;
    OSStatus copyStatus = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
                                                                 sampleBuffer,
                                                                 actualTimingCount,
                                                                 timings,
                                                                 &retimedSampleBuffer);
    free(timings);
    if (copyStatus == noErr && retimedSampleBuffer) {
        return retimedSampleBuffer;
    }

    CFRetain(sampleBuffer);
    return sampleBuffer;
}

static CMSampleBufferRef createAudioSampleBufferAlignedToReference(CMSampleBufferRef sampleBuffer,
                                                                   CMSampleBufferRef referenceSampleBuffer) {
    if (!sampleBuffer) {
        return NULL;
    }
    if (!referenceSampleBuffer) {
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    CMTime sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime targetPTS = CMSampleBufferGetPresentationTimeStamp(referenceSampleBuffer);
    if (!CMTIME_IS_VALID(sourcePTS) || CMTIME_IS_INDEFINITE(sourcePTS) ||
        !CMTIME_IS_VALID(targetPTS) || CMTIME_IS_INDEFINITE(targetPTS)) {
        CFRetain(sampleBuffer);
        return sampleBuffer;
    }

    CMTime offset = CMTimeSubtract(targetPTS, sourcePTS);
    return createRetimedAudioSampleBuffer(sampleBuffer, offset);
}

static CMTime LCNormalizedLoopTime(CMTime time, CMTime duration) {
    if (!CMTIME_IS_VALID(time) || CMTIME_IS_INDEFINITE(time) ||
        !CMTIME_IS_VALID(duration) || CMTIME_IS_INDEFINITE(duration) ||
        CMTIME_COMPARE_INLINE(duration, <=, kCMTimeZero)) {
        return kCMTimeInvalid;
    }

    Float64 durationSeconds = CMTimeGetSeconds(duration);
    Float64 timeSeconds = CMTimeGetSeconds(time);
    if (!isfinite(durationSeconds) || durationSeconds <= 0.0 || !isfinite(timeSeconds)) {
        return kCMTimeInvalid;
    }

    Float64 normalizedSeconds = fmod(timeSeconds, durationSeconds);
    if (normalizedSeconds < 0.0) {
        normalizedSeconds += durationSeconds;
    }
    return CMTimeMakeWithSeconds(normalizedSeconds, duration.timescale > 0 ? duration.timescale : 600);
}

static BOOL setupAudioSpoofingReaderLocked(BOOL continueLoopTimeline) {
    if (!spoofCameraEnabled || spoofCameraVideoPath.length == 0) {
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        return NO;
    }

    NSString *sourcePath = [spoofCameraVideoPath copy];
    BOOL sourcePathChanged = ![audioSpoofingSourcePath isEqualToString:sourcePath];
    CMTime nextLoopOffset = kCMTimeZero;
    if (!sourcePathChanged && continueLoopTimeline && CMTIME_IS_VALID(audioSpoofingTrackDuration) &&
        CMTIME_COMPARE_INLINE(audioSpoofingTrackDuration, >, kCMTimeZero)) {
        if (CMTIME_IS_VALID(audioSpoofingLoopOffset)) {
            nextLoopOffset = CMTimeAdd(audioSpoofingLoopOffset, audioSpoofingTrackDuration);
        } else {
            nextLoopOffset = audioSpoofingTrackDuration;
        }
    }

    if (audioSpoofingReader) {
        [audioSpoofingReader cancelReading];
    }
    audioSpoofingReader = nil;
    audioSpoofingOutput = nil;
    audioSpoofingTrackDuration = kCMTimeInvalid;
    audioSpoofingFailureCount = 0;
    audioSpoofingSourcePath = sourcePath;
    if (sourcePathChanged || !continueLoopTimeline) {
        audioSpoofingLoopOffset = kCMTimeZero;
    } else {
        audioSpoofingLoopOffset = nextLoopOffset;
    }

    NSURL *sourceURL = [NSURL fileURLWithPath:sourcePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        NSLog(@"[LC] 🔇 No audio track found in spoof source");
        return NO;
    }

    AVAssetTrack *audioTrack = audioTracks.firstObject;
    CMTime trackDuration = audioTrack.timeRange.duration;
    if (!CMTIME_IS_VALID(trackDuration) || CMTIME_COMPARE_INLINE(trackDuration, <=, kCMTimeZero)) {
        trackDuration = asset.duration;
    }
    if (CMTIME_IS_VALID(trackDuration) && CMTIME_COMPARE_INLINE(trackDuration, >, kCMTimeZero)) {
        audioSpoofingTrackDuration = trackDuration;
    }

    NSError *readerError = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
    if (!reader) {
        NSLog(@"[LC] 🔇 Failed to create audio reader: %@", readerError);
        return NO;
    }

    if (!continueLoopTimeline && frameExtractionPlayer && frameExtractionPlayer.currentItem) {
        CMTime playbackDuration = frameExtractionPlayer.currentItem.duration;
        if (!CMTIME_IS_VALID(playbackDuration) || CMTIME_COMPARE_INLINE(playbackDuration, <=, kCMTimeZero)) {
            playbackDuration = asset.duration;
        }
        CMTime normalizedPlaybackTime = LCNormalizedLoopTime(frameExtractionPlayer.currentTime, playbackDuration);
        CMTime seekableDuration = CMTIME_IS_VALID(asset.duration) ? asset.duration : trackDuration;
        if (CMTIME_IS_VALID(normalizedPlaybackTime) &&
            CMTIME_IS_VALID(seekableDuration) &&
            CMTIME_COMPARE_INLINE(normalizedPlaybackTime, >, kCMTimeZero) &&
            CMTIME_COMPARE_INLINE(seekableDuration, >, normalizedPlaybackTime)) {
            CMTime remainingDuration = CMTimeSubtract(seekableDuration, normalizedPlaybackTime);
            if (CMTIME_IS_VALID(remainingDuration) && CMTIME_COMPARE_INLINE(remainingDuration, >, kCMTimeZero)) {
                reader.timeRange = CMTimeRangeMake(normalizedPlaybackTime, remainingDuration);
                NSLog(@"[LC] 🔊 Audio reader synced to video time %.3fs", CMTimeGetSeconds(normalizedPlaybackTime));
            }
        }
    }

    NSDictionary *outputSettings = @{
        AVFormatIDKey : @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey : @16,
        AVLinearPCMIsFloatKey : @NO,
        AVLinearPCMIsBigEndianKey : @NO,
        AVLinearPCMIsNonInterleaved : @NO
    };
    AVAssetReaderTrackOutput *trackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack
                                                                               outputSettings:outputSettings];
    trackOutput.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:trackOutput]) {
        NSLog(@"[LC] 🔇 Cannot add audio reader output");
        return NO;
    }

    [reader addOutput:trackOutput];
    if (![reader startReading]) {
        NSLog(@"[LC] 🔇 Failed to start audio reader: %@", reader.error);
        return NO;
    }

    audioSpoofingReader = reader;
    audioSpoofingOutput = trackOutput;
    NSLog(@"[LC] 🔊 Audio spoof reader ready (loop offset %.3fs)", CMTimeGetSeconds(audioSpoofingLoopOffset));
    return YES;
}

static void setupAudioSpoofingResources(void) {
    if (!audioSpoofingQueue) {
        audioSpoofingQueue = dispatch_queue_create("com.livecontainer.audiospoofing", DISPATCH_QUEUE_SERIAL);
    }

    if (!spoofCameraEnabled || !spoofCameraUseVideoAudio || spoofCameraVideoPath.length == 0) {
        cleanupAudioSpoofingResources();
        return;
    }

    dispatch_sync(audioSpoofingQueue, ^{
        (void)setupAudioSpoofingReaderLocked(NO);
    });
}

static void cleanupAudioSpoofingResources(void) {
    if (!audioSpoofingQueue) {
        if (g_lastGoodAudioSampleBuffer) {
            CFRelease(g_lastGoodAudioSampleBuffer);
            g_lastGoodAudioSampleBuffer = NULL;
        }
        audioSpoofingReader = nil;
        audioSpoofingOutput = nil;
        audioSpoofingSourcePath = nil;
        audioSpoofingLoopOffset = kCMTimeZero;
        audioSpoofingTrackDuration = kCMTimeInvalid;
        audioSpoofingFailureCount = 0;
        cleanupSynchronizerSampleBufferCache();
        return;
    }

    dispatch_sync(audioSpoofingQueue, ^{
        if (audioSpoofingReader) {
            [audioSpoofingReader cancelReading];
        }
        audioSpoofingReader = nil;
        audioSpoofingOutput = nil;
        audioSpoofingSourcePath = nil;
        audioSpoofingLoopOffset = kCMTimeZero;
        audioSpoofingTrackDuration = kCMTimeInvalid;
        audioSpoofingFailureCount = 0;
        if (g_lastGoodAudioSampleBuffer) {
            CFRelease(g_lastGoodAudioSampleBuffer);
            g_lastGoodAudioSampleBuffer = NULL;
        }
    });
    cleanupSynchronizerSampleBufferCache();
}

static CMSampleBufferRef copyNextSpoofedAudioSampleBuffer(void) {
    if (!spoofCameraEnabled || !spoofCameraUseVideoAudio || spoofCameraVideoPath.length == 0) {
        return NULL;
    }
    if (!audioSpoofingQueue) {
        audioSpoofingQueue = dispatch_queue_create("com.livecontainer.audiospoofing", DISPATCH_QUEUE_SERIAL);
    }

    __block CMSampleBufferRef result = NULL;
    dispatch_sync(audioSpoofingQueue, ^{
        BOOL sourceChanged = ![audioSpoofingSourcePath isEqualToString:spoofCameraVideoPath];
        BOOL readerMissing = (audioSpoofingReader == nil || audioSpoofingOutput == nil);
        BOOL readerFailed = (audioSpoofingReader.status == AVAssetReaderStatusFailed);
        if (sourceChanged || readerMissing || readerFailed) {
            if (!setupAudioSpoofingReaderLocked(NO)) {
                if (g_lastGoodAudioSampleBuffer) {
                    result = g_lastGoodAudioSampleBuffer;
                    CFRetain(result);
                }
                return;
            }
        }

        CMSampleBufferRef sourceSampleBuffer = [audioSpoofingOutput copyNextSampleBuffer];
        if (!sourceSampleBuffer && spoofCameraLoop) {
            if (setupAudioSpoofingReaderLocked(YES)) {
                sourceSampleBuffer = [audioSpoofingOutput copyNextSampleBuffer];
            }
        }

        if (!sourceSampleBuffer) {
            audioSpoofingFailureCount++;
            if (g_lastGoodAudioSampleBuffer && audioSpoofingFailureCount < 16) {
                result = g_lastGoodAudioSampleBuffer;
                CFRetain(result);
            }
            return;
        }

        audioSpoofingFailureCount = 0;
        CMSampleBufferRef retimed = createRetimedAudioSampleBuffer(sourceSampleBuffer, audioSpoofingLoopOffset);
        CFRelease(sourceSampleBuffer);
        if (!retimed) {
            if (g_lastGoodAudioSampleBuffer) {
                result = g_lastGoodAudioSampleBuffer;
                CFRetain(result);
            }
            return;
        }

        if (!CMTIME_IS_VALID(audioSpoofingTrackDuration) ||
            CMTIME_COMPARE_INLINE(audioSpoofingTrackDuration, <=, kCMTimeZero)) {
            CMTime sampleDuration = LCAudioSampleDuration(retimed);
            if (CMTIME_IS_VALID(sampleDuration) && CMTIME_COMPARE_INLINE(sampleDuration, >, kCMTimeZero)) {
                audioSpoofingTrackDuration = sampleDuration;
            }
        }

        if (g_lastGoodAudioSampleBuffer) {
            CFRelease(g_lastGoodAudioSampleBuffer);
        }
        g_lastGoodAudioSampleBuffer = retimed;
        CFRetain(g_lastGoodAudioSampleBuffer);
        result = retimed;
    });

    return result;
}

static CMSampleBufferRef cacheSynchronizerSampleBufferAdopting(CMSampleBufferRef sampleBuffer, BOOL isAudio) {
    if (!sampleBuffer) {
        return NULL;
    }

    @synchronized([AVCaptureSession class]) {
        CMSampleBufferRef *ring = isAudio ? synchronizerAudioSampleBufferRing : synchronizerVideoSampleBufferRing;
        NSUInteger ringSize = isAudio ? (sizeof(synchronizerAudioSampleBufferRing) / sizeof(CMSampleBufferRef))
                                      : (sizeof(synchronizerVideoSampleBufferRing) / sizeof(CMSampleBufferRef));
        NSUInteger *index = isAudio ? &synchronizerAudioSampleBufferRingIndex : &synchronizerVideoSampleBufferRingIndex;

        if (ring[*index]) {
            CFRelease(ring[*index]);
            ring[*index] = NULL;
        }
        ring[*index] = sampleBuffer;
        *index = (*index + 1) % ringSize;
    }

    return sampleBuffer;
}

static void cleanupSynchronizerSampleBufferCache(void) {
    @synchronized([AVCaptureSession class]) {
        for (NSUInteger i = 0; i < sizeof(synchronizerVideoSampleBufferRing) / sizeof(CMSampleBufferRef); i++) {
            if (synchronizerVideoSampleBufferRing[i]) {
                CFRelease(synchronizerVideoSampleBufferRing[i]);
                synchronizerVideoSampleBufferRing[i] = NULL;
            }
        }
        for (NSUInteger i = 0; i < sizeof(synchronizerAudioSampleBufferRing) / sizeof(CMSampleBufferRef); i++) {
            if (synchronizerAudioSampleBufferRing[i]) {
                CFRelease(synchronizerAudioSampleBufferRing[i]);
                synchronizerAudioSampleBufferRing[i] = NULL;
            }
        }
        synchronizerVideoSampleBufferRingIndex = 0;
        synchronizerAudioSampleBufferRingIndex = 0;
    }
}

// Replace the createScaledPixelBuffer function with this improved version:
static CVPixelBufferRef createScaledPixelBuffer(CVPixelBufferRef sourceBuffer, CGSize scaleToSize) {
    if (!sourceBuffer) return NULL;

    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    OSType sourceFormat = CVPixelBufferGetPixelFormatType(sourceBuffer);

    // CRITICAL FIX: Complete the target format assignment
    OSType targetFormat = kCVPixelFormatType_32BGRA; // Default
    if (lastRequestedFormat != 0 && isValidPixelFormat(lastRequestedFormat)) {
        targetFormat = lastRequestedFormat;
    }

    // If source already matches target size and format, return as-is
    if (sourceWidth == (size_t)scaleToSize.width && 
        sourceHeight == (size_t)scaleToSize.height && 
        sourceFormat == targetFormat) {
        CVPixelBufferRetain(sourceBuffer);
        return sourceBuffer;
    }

    CVPixelBufferRef scaledPixelBuffer = NULL;
    NSDictionary *pixelAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    // IMPROVEMENT: Create buffer in the requested format, not always BGRA
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)scaleToSize.width,
                                          (size_t)scaleToSize.height,
                                          targetFormat, // Use requested format!
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &scaledPixelBuffer);
    if (status != kCVReturnSuccess || !scaledPixelBuffer) {
        NSLog(@"[LC] Error creating scaled pixel buffer with format %c%c%c%c: %d", 
              (targetFormat >> 24) & 0xFF, (targetFormat >> 16) & 0xFF, 
              (targetFormat >> 8) & 0xFF, targetFormat & 0xFF, status);
        return NULL;
    }

    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
        if (!sharedCIContext) {
            NSLog(@"[LC] CRITICAL: Failed to create shared CIContext");
            CVPixelBufferRelease(scaledPixelBuffer);
            return NULL; 
        }
    }
    
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    CGFloat scaleX = scaleToSize.width / sourceWidth;
    CGFloat scaleY = scaleToSize.height / sourceHeight;
    ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
    
    CGRect extent = ciImage.extent;
    if (extent.origin.x != 0 || extent.origin.y != 0) {
        ciImage = [ciImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    }

    // CRITICAL: Render to the target format buffer
    [sharedCIContext render:ciImage toCVPixelBuffer:scaledPixelBuffer];
    return scaledPixelBuffer;
}

static void updateLastGoodSpoofedFrame(CVPixelBufferRef newPixelBuffer, CMVideoFormatDescriptionRef newFormatDesc) {
    if (lastGoodSpoofedPixelBuffer) {
        CVPixelBufferRelease(lastGoodSpoofedPixelBuffer);
        lastGoodSpoofedPixelBuffer = NULL;
    }
    if (lastGoodSpoofedFormatDesc) {
        CFRelease(lastGoodSpoofedFormatDesc);
        lastGoodSpoofedFormatDesc = NULL;
    }

    if (newPixelBuffer) {
        lastGoodSpoofedPixelBuffer = newPixelBuffer;
        CVPixelBufferRetain(lastGoodSpoofedPixelBuffer);
    }
    if (newFormatDesc) {
        lastGoodSpoofedFormatDesc = newFormatDesc;
        CFRetain(lastGoodSpoofedFormatDesc);
    }
}

// pragma MARK: - Frame Generation Logic

static BOOL isValidPixelFormat(OSType format) {
    switch (format) {
        case kCVPixelFormatType_32BGRA:
            return YES;
        case 875704422: // '420v' - YUV 4:2:0 video range
            return YES;
        case 875704438: // '420f' - YUV 4:2:0 full range  
            return YES;
        // NOTE: Don't use the constants as they have the same values as the literals above
        // case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: // Same as 875704438
        // case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:  // Same as 875704422
        default:
            NSLog(@"[LC] ⚠️ Unknown pixel format: %c%c%c%c (%u)", 
                  (format >> 24) & 0xFF, (format >> 16) & 0xFF, 
                  (format >> 8) & 0xFF, format & 0xFF, (unsigned int)format);
            return NO;
    }
}

// New helper function for format conversion
static CVPixelBufferRef createPixelBufferInFormat(CVPixelBufferRef sourceBuffer, OSType targetFormat, CGSize targetSize) {
    if (!sourceBuffer) return NULL;

    CVPixelBufferRef targetBuffer = NULL;
    NSDictionary *pixelAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    // Create target buffer in the exact requested format
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)targetSize.width,
                                          (size_t)targetSize.height,
                                          targetFormat,
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &targetBuffer);
    
    if (status != kCVReturnSuccess || !targetBuffer) {
        NSLog(@"[LC] ❌ Failed to create target buffer in format %c%c%c%c: %d", 
              (targetFormat >> 24) & 0xFF, (targetFormat >> 16) & 0xFF, 
              (targetFormat >> 8) & 0xFF, targetFormat & 0xFF, status);
        return NULL;
    }

    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
        if (!sharedCIContext) {
            NSLog(@"[LC] ❌ Failed to create CIContext");
            CVPixelBufferRelease(targetBuffer);
            return NULL; 
        }
    }
    
    // Convert using Core Image
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    
    // Scale if needed
    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    if (sourceWidth != (size_t)targetSize.width || sourceHeight != (size_t)targetSize.height) {
        CGFloat scaleX = targetSize.width / sourceWidth;
        CGFloat scaleY = targetSize.height / sourceHeight;
        sourceImage = [sourceImage imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
    }
    
    // Ensure proper bounds
    CGRect extent = sourceImage.extent;
    if (extent.origin.x != 0 || extent.origin.y != 0) {
        sourceImage = [sourceImage imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    }

    // Render to target buffer (Core Image handles format conversion automatically)
    [sharedCIContext render:sourceImage toCVPixelBuffer:targetBuffer];
    
    return targetBuffer;
}

// Add this function right after the createPixelBufferInFormat function
// static CVPixelBufferRef rotatePixelBufferToPortrait(CVPixelBufferRef sourceBuffer) {
//     if (!sourceBuffer) return NULL;
    
//     size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
//     size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    
//     NSLog(@"[LC] 🔄 fd: Input buffer %zux%zu", sourceWidth, sourceHeight);
    
//     // CRITICAL FIX: Don't automatically assume rotation is needed
//     // Let's check what the target resolution expects
//     BOOL targetIsPortrait = (targetResolution.height > targetResolution.width);
//     BOOL sourceIsPortrait = (sourceHeight > sourceWidth);
    
//     NSLog(@"[LC] 🔄 fd: Target expects portrait: %@, Source is portrait: %@", 
//           targetIsPortrait ? @"YES" : @"NO", sourceIsPortrait ? @"YES" : @"NO");
    
//     // CRITICAL: Only rotate if source and target orientations don't match
//     BOOL needsRotation = (targetIsPortrait != sourceIsPortrait);
    
//     if (!needsRotation) {
//         NSLog(@"[LC] 🔄 fd: No rotation needed - orientations match");
//         CVPixelBufferRetain(sourceBuffer);
//         return sourceBuffer;
//     }
    
//     NSLog(@"[LC] 🔄 fd: Rotating %zux%zu to match target orientation", sourceWidth, sourceHeight);
    
//     // Create rotated buffer (swap dimensions)
//     CVPixelBufferRef rotatedBuffer = NULL;
//     NSDictionary *attributes = @{
//         (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
//         (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
//         (NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{}
//     };
    
//     CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
//                                          sourceHeight, // Swap width/height for rotation
//                                          sourceWidth,
//                                          CVPixelBufferGetPixelFormatType(sourceBuffer),
//                                          (__bridge CFDictionaryRef)attributes,
//                                          &rotatedBuffer);
    
//     if (status != kCVReturnSuccess) {
//         NSLog(@"[LC] ❌ fd: Failed to create rotated buffer: %d", status);
//         return NULL;
//     }
    
//     // CRITICAL: Hardware-level rotation using Core Image
//     if (!sharedCIContext) {
//         sharedCIContext = [CIContext contextWithOptions:nil];
//     }
    
//     CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    
//     // CRITICAL FIX: Determine correct rotation direction
//     CGAffineTransform rotationTransform;
//     CGAffineTransform translationTransform;
    
//     if (sourceIsPortrait && !targetIsPortrait) {
//         // Source is portrait, target is landscape: rotate +90° (clockwise)
//         rotationTransform = CGAffineTransformMakeRotation(M_PI_2);
//         translationTransform = CGAffineTransformMakeTranslation(sourceHeight, 0);
//         NSLog(@"[LC] 🔄 fd: Portrait to landscape (+90°)");
//     } else {
//         // Source is landscape, target is portrait: rotate -90° (counterclockwise)
//         rotationTransform = CGAffineTransformMakeRotation(-M_PI_2);
//         translationTransform = CGAffineTransformMakeTranslation(0, sourceWidth);
//         NSLog(@"[LC] 🔄 fd: Landscape to portrait (-90°)");
//     }
    
//     // Combine transforms
//     CGAffineTransform combinedTransform = CGAffineTransformConcat(rotationTransform, translationTransform);
//     CIImage *rotatedCIImage = [sourceImage imageByApplyingTransform:combinedTransform];
    
//     // Render to the rotated buffer
//     [sharedCIContext render:rotatedCIImage toCVPixelBuffer:rotatedBuffer];
    
//     NSLog(@"[LC] ✅ fd: Buffer rotated from %zux%zu to %zux%zu", 
//           sourceWidth, sourceHeight, CVPixelBufferGetWidth(rotatedBuffer), CVPixelBufferGetHeight(rotatedBuffer));
    
//     return rotatedBuffer;
// }
static CVPixelBufferRef rotatePixelBufferToPortrait(CVPixelBufferRef sourceBuffer) {
    if (!sourceBuffer) return NULL;
    
    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);
    
    NSLog(@"[LC] 🔄 fd: Input buffer %zux%zu", sourceWidth, sourceHeight);
    
    // CRITICAL FIX: Don't automatically assume rotation is needed
    // Let's check what the target resolution expects
    BOOL targetIsPortrait = (targetResolution.height > targetResolution.width);
    BOOL sourceIsPortrait = (sourceHeight > sourceWidth);
    
    NSLog(@"[LC] 🔄 fd: Target expects portrait: %@, Source is portrait: %@", 
          targetIsPortrait ? @"YES" : @"NO", sourceIsPortrait ? @"YES" : @"NO");
    
    // CRITICAL: Only rotate if source and target orientations don't match
    BOOL needsRotation = (targetIsPortrait != sourceIsPortrait);
    
    if (!needsRotation) {
        NSLog(@"[LC] 🔄 fd: No rotation needed - orientations match");
        CVPixelBufferRetain(sourceBuffer);
        return sourceBuffer;
    }
    
    NSLog(@"[LC] 🔄 fd: Rotating %zux%zu to match target orientation", sourceWidth, sourceHeight);
    
    // Create rotated buffer (swap dimensions)
    CVPixelBufferRef rotatedBuffer = NULL;
    NSDictionary *attributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         sourceHeight, // Swap width/height for rotation
                                         sourceWidth,
                                         CVPixelBufferGetPixelFormatType(sourceBuffer),
                                         (__bridge CFDictionaryRef)attributes,
                                         &rotatedBuffer);
    
    if (status != kCVReturnSuccess) {
        NSLog(@"[LC] ❌ fd: Failed to create rotated buffer: %d", status);
        return NULL;
    }
    
    // CRITICAL: Hardware-level rotation using Core Image
    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
    }
    
    CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];
    
    // CRITICAL FIX: Determine correct rotation direction
    CGAffineTransform rotationTransform;
    CGAffineTransform translationTransform;
    
    if (sourceIsPortrait && !targetIsPortrait) {
        // Source is portrait, target is landscape: rotate +90° (clockwise)
        rotationTransform = CGAffineTransformMakeRotation(M_PI_2);
        translationTransform = CGAffineTransformMakeTranslation(sourceHeight, 0);
        NSLog(@"[LC] 🔄 fd: Portrait to landscape (+90°)");
    } else {
        // Source is landscape, target is portrait: rotate -90° (counterclockwise)
        rotationTransform = CGAffineTransformMakeRotation(-M_PI_2);
        translationTransform = CGAffineTransformMakeTranslation(0, sourceWidth);
        NSLog(@"[LC] 🔄 fd: Landscape to portrait (-90°)");
    }
    
    // Combine transforms
    CGAffineTransform combinedTransform = CGAffineTransformConcat(rotationTransform, translationTransform);
    CIImage *rotatedCIImage = [sourceImage imageByApplyingTransform:combinedTransform];
    
    // Render to the rotated buffer
    [sharedCIContext render:rotatedCIImage toCVPixelBuffer:rotatedBuffer];
    
    NSLog(@"[LC] ✅ fd: Buffer rotated from %zux%zu to %zux%zu", 
          sourceWidth, sourceHeight, CVPixelBufferGetWidth(rotatedBuffer), CVPixelBufferGetHeight(rotatedBuffer));
    
    return rotatedBuffer;
}

static CVPixelBufferRef correctPhotoRotation(CVPixelBufferRef sourceBuffer) {
    if (!sourceBuffer) {
        NSLog(@"[LC] 📷 correctPhotoRotation: sourceBuffer is NULL");
        return NULL;
    }

    size_t sourceWidth = CVPixelBufferGetWidth(sourceBuffer);
    size_t sourceHeight = CVPixelBufferGetHeight(sourceBuffer);

    BOOL isFrontCamera = (g_currentCameraPosition == AVCaptureDevicePositionFront);
    
    NSLog(@"[LC] 📷 correctPhotoRotation: Input %zux%zu, Camera: %s", 
          sourceWidth, sourceHeight, isFrontCamera ? "FRONT" : "BACK");

    CVPixelBufferRef rotatedBuffer = NULL;
    NSDictionary *attributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    // Output buffer will have dimensions sourceHeight (new width) x sourceWidth (new height)
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         sourceHeight, // New width
                                         sourceWidth,  // New height
                                         CVPixelBufferGetPixelFormatType(sourceBuffer),
                                         (__bridge CFDictionaryRef)attributes,
                                         &rotatedBuffer);

    if (status != kCVReturnSuccess || !rotatedBuffer) {
        NSLog(@"[LC] 📷❌ correctPhotoRotation: Failed to create rotated CVPixelBuffer. Status: %d", status);
        return NULL;
    }

    if (!sharedCIContext) {
        sharedCIContext = [CIContext contextWithOptions:nil];
        if (!sharedCIContext) {
            NSLog(@"[LC] 📷❌ correctPhotoRotation: Failed to create shared CIContext.");
            CVPixelBufferRelease(rotatedBuffer);
            return NULL;
        }
    }

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:sourceBuffer];

    // CRITICAL: Different transforms for front vs back camera
    CGAffineTransform finalTransform;
    
    if (isFrontCamera) {
        // Front camera: Rotate +90°, mirror horizontally, then rotate 180° to fix upside down
        
        // Step 1: Rotate +90°
        CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(M_PI_2); // +90 degrees
        CGAffineTransform translateAfterRotation = CGAffineTransformMakeTranslation(sourceHeight, 0);
        
        // Step 2: Mirror horizontally (flip left-right)
        CGAffineTransform mirrorTransform = CGAffineTransformMakeScale(-1, 1);
        CGAffineTransform translateAfterMirror = CGAffineTransformMakeTranslation(sourceHeight, 0);
        
        // Step 3: Rotate 180° to fix upside down
        CGAffineTransform uprightTransform = CGAffineTransformMakeRotation(M_PI); // 180 degrees
        CGAffineTransform translateAfterUpright = CGAffineTransformMakeTranslation(sourceHeight, sourceWidth);
        
        // Combine all transforms: rotate → translate → mirror → translate → upright → translate
        finalTransform = CGAffineTransformConcat(rotationTransform, translateAfterRotation);
        finalTransform = CGAffineTransformConcat(finalTransform, mirrorTransform);
        finalTransform = CGAffineTransformConcat(finalTransform, translateAfterMirror);
        finalTransform = CGAffineTransformConcat(finalTransform, uprightTransform);
        finalTransform = CGAffineTransformConcat(finalTransform, translateAfterUpright);
        
        NSLog(@"[LC] 📷 correctPhotoRotation: FRONT camera - applying +90deg rotation + horizontal mirror + 180deg upright");
    } else {
        // Back camera: Just rotate +90° (no mirroring needed)
        CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(M_PI_2); // +90 degrees
        CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(sourceHeight, 0);
        finalTransform = CGAffineTransformConcat(rotationTransform, translateTransform);
        
        NSLog(@"[LC] 📷 correctPhotoRotation: BACK camera - applying +90deg rotation only");
    }
    
    CIImage *transformedCIImage = [ciImage imageByApplyingTransform:finalTransform];

    // Render the transformed CIImage to the new CVPixelBuffer
    [sharedCIContext render:transformedCIImage toCVPixelBuffer:rotatedBuffer];

    NSLog(@"[LC] 📷✅ correctPhotoRotation: %s camera processed. Original: %zux%zu, New: %zux%zu",
          isFrontCamera ? "FRONT (rotated+mirrored+upright)" : "BACK (rotated)",
          sourceWidth, sourceHeight,
          CVPixelBufferGetWidth(rotatedBuffer), CVPixelBufferGetHeight(rotatedBuffer));
          
    return rotatedBuffer;
}

// Replace crash-resistant version:
static CMSampleBufferRef createSpoofedSampleBuffer(void) {
    @try {
        if (!spoofCameraEnabled) {
            return NULL;
        }

        CVPixelBufferRef sourcePixelBuffer = NULL;

        // Prefer video frame extraction when video spoofing is configured.
        if (currentVideoPath && currentVideoPath.length > 0) {
            sourcePixelBuffer = [GetFrame getCurrentFramePixelBuffer:lastRequestedFormat];
        }
        
        // Static image fallback
        if (!sourcePixelBuffer && staticImageSpoofBuffer) {
            sourcePixelBuffer = CVPixelBufferRetain(staticImageSpoofBuffer);
        }
        
        if (!sourcePixelBuffer) {
            // Emergency fallback: reuse previously generated spoofed frame.
            if (lastGoodSpoofedPixelBuffer) {
                CMVideoFormatDescriptionRef formatDesc = NULL;
                if (lastGoodSpoofedFormatDesc) {
                    formatDesc = (CMVideoFormatDescriptionRef)CFRetain(lastGoodSpoofedFormatDesc);
                } else {
                    OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, &formatDesc);
                    if (formatStatus != noErr || !formatDesc) {
                        return NULL;
                    }
                }

                CMSampleTimingInfo timingInfo = {
                    .duration = CMTimeMake(1, 30),
                    .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC),
                    .decodeTimeStamp = kCMTimeInvalid
                };
                
                CMSampleBufferRef emergencySampleBuffer = NULL;
                OSStatus emergencyStatus = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, formatDesc, &timingInfo, &emergencySampleBuffer);
                if (formatDesc) {
                    CFRelease(formatDesc);
                }
                if (emergencyStatus == noErr && emergencySampleBuffer) {
                    return emergencySampleBuffer;
                }
            }
            return NULL;
        }

        // Single conversion pass for both scale and pixel format.
        CVPixelBufferRef finalPixelBuffer = createScaledPixelBuffer(sourcePixelBuffer, targetResolution);
        CVPixelBufferRelease(sourcePixelBuffer);

        if (!finalPixelBuffer) {
            return NULL;
        }
        
        CMVideoFormatDescriptionRef formatDesc = NULL;
        OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, finalPixelBuffer, &formatDesc);
        
        if (formatStatus != noErr || !formatDesc) {
            CVPixelBufferRelease(finalPixelBuffer);
            return NULL;
        }

        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC),
            .decodeTimeStamp = kCMTimeInvalid
        };

        CMSampleBufferRef sampleBuffer = NULL;
        OSStatus bufferStatus = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, finalPixelBuffer, formatDesc, &timingInfo, &sampleBuffer);

        // Cleanup
        CFRelease(formatDesc);
        
        if (bufferStatus != noErr || !sampleBuffer) {
            CVPixelBufferRelease(finalPixelBuffer);
            return NULL;
        }
        
        if (sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
            updateLastGoodSpoofedFrame(finalPixelBuffer, CMSampleBufferGetFormatDescription(sampleBuffer));
            CVPixelBufferRelease(finalPixelBuffer);
            return sampleBuffer;
        } else {
            CVPixelBufferRelease(finalPixelBuffer);
            if (sampleBuffer) CFRelease(sampleBuffer);
            return NULL;
        }
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception in createSpoofedSampleBuffer: %@", exception);
        return NULL;
    }
}

// pragma MARK: - Resource Setup

static void setupImageSpoofingResources(void) {
    NSLog(@"[LC] 🖼️ Setting up image spoofing resources: %.0fx%.0f", targetResolution.width, targetResolution.height);

    CVPixelBufferRef previousStaticBuffer = NULL;
    if (staticImageSpoofBuffer) {
        previousStaticBuffer = CVPixelBufferRetain(staticImageSpoofBuffer);
        CVPixelBufferRelease(staticImageSpoofBuffer);
        staticImageSpoofBuffer = NULL;
    }

    UIImage *sourceImage = nil;
    
    // CRITICAL FIX: Try to load user's selected image first
    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    NSString *imagePath = guestAppInfo[@"spoofCameraImagePath"];
    
    if (imagePath && imagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        NSLog(@"[LC] 🖼️ Loading user image from: %@", imagePath.lastPathComponent);
        sourceImage = [UIImage imageWithContentsOfFile:imagePath];
        
        if (sourceImage) {
            NSLog(@"[LC] ✅ User image loaded: %.0fx%.0f", sourceImage.size.width, sourceImage.size.height);
            
            // CRITICAL FIX: Create BOTH static image AND video
            // First create the static image as immediate fallback
            createStaticImageFromUIImage(sourceImage); // FIXED: Remove [self ...]
            
            // THEN create video asynchronously
            NSLog(@"[LC] 🎬 Starting video creation from image...");
            [GetFrame createVideoFromImage:sourceImage];
            
            // DON'T return early - continue to ensure we have static fallback
        } else {
            NSLog(@"[LC] ⚠️ Failed to load user image, falling back to default");
        }
    } else {
        NSLog(@"[LC] 🖼️ No user image specified, using fallback pipeline");
    }

    // If no user image (or static conversion failed), keep previous fallback if available.
    if (!sourceImage || !staticImageSpoofBuffer) {
        if (previousStaticBuffer) {
            staticImageSpoofBuffer = previousStaticBuffer;
            previousStaticBuffer = NULL;
            NSLog(@"[LC] 🔄 Reusing previous static image buffer as fallback");
            return;
        }

        // Check if we have lastGoodSpoofedPixelBuffer
        if (lastGoodSpoofedPixelBuffer) {
            NSLog(@"[LC] 🔄 No user image - using lastGoodSpoofedPixelBuffer as fallback");
            staticImageSpoofBuffer = CVPixelBufferRetain(lastGoodSpoofedPixelBuffer);
            if (previousStaticBuffer) {
                CVPixelBufferRelease(previousStaticBuffer);
                previousStaticBuffer = NULL;
            }
            return;
        }
        
        // LAST RESORT: Create a simple BLACK buffer (no text, no gradient)
        NSLog(@"[LC] ⚠️ No fallback available - creating black buffer (no text)");
        
        NSDictionary *pixelBufferAttributes = @{
            (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
            (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };

        CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, 
                                         (size_t)targetResolution.width, (size_t)targetResolution.height, 
                                         kCVPixelFormatType_32BGRA,
                                         (__bridge CFDictionaryRef)pixelBufferAttributes, &staticImageSpoofBuffer);
        
        if (cvRet == kCVReturnSuccess && staticImageSpoofBuffer) {
            CVPixelBufferLockBaseAddress(staticImageSpoofBuffer, 0);
            void *pxdata = CVPixelBufferGetBaseAddress(staticImageSpoofBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(staticImageSpoofBuffer);
            
            // Fill with black (no text, no gradient) - like CaptureJailed pattern
            memset(pxdata, 0, bytesPerRow * (size_t)targetResolution.height);
            
            CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);
            
            NSLog(@"[LC] ✅ Black fallback buffer created (no visible text)");
            
            CMVideoFormatDescriptionRef tempFormatDesc = NULL;
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &tempFormatDesc);
            updateLastGoodSpoofedFrame(staticImageSpoofBuffer, tempFormatDesc);
            if (tempFormatDesc) CFRelease(tempFormatDesc);
        }
        if (previousStaticBuffer) {
            CVPixelBufferRelease(previousStaticBuffer);
            previousStaticBuffer = NULL;
        }
        return;
    }

    if (previousStaticBuffer) {
        CVPixelBufferRelease(previousStaticBuffer);
        previousStaticBuffer = NULL;
    }
}

static void createStaticImageFromUIImage(UIImage *sourceImage) {
    if (!sourceImage) {
        NSLog(@"[LC] ❌ No source image for static buffer creation");
        return; 
    }
    
    // CRITICAL: Force image to be in proper orientation before processing
    UIImage *normalizedImage = sourceImage;
    
    // If image has orientation metadata that would cause rotation, fix it
    if (sourceImage.imageOrientation != UIImageOrientationUp) {
        NSLog(@"[LC] 🔄 Normalizing image orientation from %ld to Up", (long)sourceImage.imageOrientation);
        
        UIGraphicsBeginImageContextWithOptions(sourceImage.size, NO, sourceImage.scale);
        [sourceImage drawInRect:CGRectMake(0, 0, sourceImage.size.width, sourceImage.size.height)];
        normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    // Convert to CVPixelBuffer using normalized image
    CGImageRef cgImage = normalizedImage.CGImage;
    if (!cgImage) {
        NSLog(@"[LC] ❌ CGImage is NULL");
        return;
    }

    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, 
                                     (size_t)targetResolution.width, (size_t)targetResolution.height, 
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)pixelBufferAttributes, &staticImageSpoofBuffer);
    if (cvRet != kCVReturnSuccess || !staticImageSpoofBuffer) {
        NSLog(@"[LC] ❌ Failed to create CVPixelBuffer for static image: %d", cvRet);
        return;
    }

    CVPixelBufferLockBaseAddress(staticImageSpoofBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(staticImageSpoofBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, 
                                                 (size_t)targetResolution.width, (size_t)targetResolution.height, 
                                                 8, CVPixelBufferGetBytesPerRow(staticImageSpoofBuffer),
                                                 rgbColorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (context) {
        // Fill with black background
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, targetResolution.width, targetResolution.height));
        
        // CRITICAL: Use aspect fill with PORTRAIT orientation (no rotation transforms)
        CGFloat imageWidth = CGImageGetWidth(cgImage);
        CGFloat imageHeight = CGImageGetHeight(cgImage);
        CGFloat imageAspect = imageWidth / imageHeight;
        CGFloat targetAspect = targetResolution.width / targetResolution.height;
        
        CGRect drawRect;
        if (imageAspect > targetAspect) {
            // Image is wider - fit height and crop sides
            CGFloat scaledWidth = targetResolution.height * imageAspect;
            drawRect = CGRectMake(-(scaledWidth - targetResolution.width) / 2, 0, scaledWidth, targetResolution.height);
        } else {
            // Image is taller - fit width and crop top/bottom  
            CGFloat scaledHeight = targetResolution.width / imageAspect;
            drawRect = CGRectMake(0, -(scaledHeight - targetResolution.height) / 2, targetResolution.width, scaledHeight);
        }
        
        // CRITICAL: Draw with NO rotation transforms (image is already normalized)
        CGContextDrawImage(context, drawRect, cgImage);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(staticImageSpoofBuffer, 0);

    if (staticImageSpoofBuffer) {
        NSLog(@"[LC] ✅ Static image buffer created successfully (normalized orientation)");
        CMVideoFormatDescriptionRef tempFormatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, staticImageSpoofBuffer, &tempFormatDesc);
        updateLastGoodSpoofedFrame(staticImageSpoofBuffer, tempFormatDesc);
        if (tempFormatDesc) CFRelease(tempFormatDesc);
    }
}

static void setupVideoSpoofingResources(void) {
    NSLog(@"[LC] 🎬 Setting up video spoofing: %@", spoofCameraVideoPath);
    if (!spoofCameraVideoPath || spoofCameraVideoPath.length == 0) {
        isVideoSetupSuccessfully = NO;
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:spoofCameraVideoPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
        NSLog(@"[LC] Video file not found: %@", spoofCameraVideoPath);
        isVideoSetupSuccessfully = NO;
        return;
    }

    // IMPROVEMENT: Clean up ALL outputs first
    if (videoSpoofPlayer && videoSpoofPlayer.currentItem) {
        if (videoSpoofPlayerOutput) {
            [videoSpoofPlayer.currentItem removeOutput:videoSpoofPlayerOutput];
            videoSpoofPlayerOutput = nil;
        }
        if (yuvOutput1) {
            [videoSpoofPlayer.currentItem removeOutput:yuvOutput1];
            yuvOutput1 = nil;
        }
        if (yuvOutput2) {
            [videoSpoofPlayer.currentItem removeOutput:yuvOutput2];
            yuvOutput2 = nil;
        }
    }
    
    // Create multiple format outputs for better compatibility (cj pattern)
    NSDictionary *bgraAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420vAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704422), // '420v'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420fAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704438), // '420f'
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        NSError *error = nil;
        AVKeyValueStatus status = [asset statusOfValueForKey:@"tracks" error:&error];

        if (status != AVKeyValueStatusLoaded) {
            NSLog(@"[LC] Failed to load video tracks: %@", error);
            isVideoSetupSuccessfully = NO;
            return;
        }

        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) {
            NSLog(@"[LC] No video tracks found");
            isVideoSetupSuccessfully = NO;
            return;
        }

        // Clean up existing player
        if (videoSpoofPlayer) {
            [videoSpoofPlayer pause];
            if (playerDidPlayToEndTimeObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
                playerDidPlayToEndTimeObserver = nil;
            }
            videoSpoofPlayer = nil;
        }

        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
        videoSpoofPlayer = [AVPlayer playerWithPlayerItem:playerItem];
        videoSpoofPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        videoSpoofPlayer.muted = YES;

        // CREATE ALL THREE OUTPUTS (like cj)
        videoSpoofPlayerOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:bgraAttributes];
        yuvOutput1 = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420vAttributes];
        yuvOutput2 = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420fAttributes];
        
        dispatch_async(videoProcessingQueue, ^{
            while (playerItem.status != AVPlayerItemStatusReadyToPlay) {
                [NSThread sleepForTimeInterval:0.05];
                if (playerItem.status == AVPlayerItemStatusFailed) {
                     NSLog(@"[LC] Player item failed: %@", playerItem.error);
                     isVideoSetupSuccessfully = NO;
                     return;
                }
            }
            
            // ADD ALL THREE OUTPUTS TO PLAYER ITEM
            if (![playerItem.outputs containsObject:videoSpoofPlayerOutput]) {
                [playerItem addOutput:videoSpoofPlayerOutput];
                NSLog(@"[LC] ✅ Added BGRA output");
            }
            if (![playerItem.outputs containsObject:yuvOutput1]) {
                [playerItem addOutput:yuvOutput1];
                NSLog(@"[LC] ✅ Added 420v output");
            }
            if (![playerItem.outputs containsObject:yuvOutput2]) {
                [playerItem addOutput:yuvOutput2];
                NSLog(@"[LC] ✅ Added 420f output");
            }
            
            if (spoofCameraLoop) {
                if (playerDidPlayToEndTimeObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:playerDidPlayToEndTimeObserver];
                }
                playerDidPlayToEndTimeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                  object:playerItem
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
                    [videoSpoofPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                        if (finished) [videoSpoofPlayer play];
                    }];
                }];
            }
            
            [videoSpoofPlayer play];
            isVideoSetupSuccessfully = YES;
            NSLog(@"[LC] ✅ Video spoofing ready with 3 format outputs");
            
            // CRITICAL: Pre-cache photo data immediately when video is ready
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                NSLog(@"[LC] 📷 Emergency: Creating photo cache from video setup");
                cachePhotoDataFromSampleBuffer(NULL);
                NSLog(@"[LC] 📷 Emergency: Photo cache ready");
            });
        });
    }];
}



//pragma MARK: - Centralized Frame Manager (cj Pattern)

// @interface GetFrame : NSObject
// + (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve;
// + (CVPixelBufferRef)getCurrentFramePixelBuffer:(OSType)requestedFormat;
// + (void)setCurrentVideoPath:(NSString *)path;
// + (UIWindow *)getKeyWindow;
// @end

@implementation GetFrame

// Static variables
// static NSString *currentVideoPath = nil;
// static AVPlayer *frameExtractionPlayer = nil;
// static AVPlayerItemVideoOutput *bgraOutput = nil;
// static AVPlayerItemVideoOutput *yuv420vOutput = nil;
// static AVPlayerItemVideoOutput *yuv420fOutput = nil;
// static GetFrameKVOObserver *_kvoObserver = nil;
// static BOOL playerIsReady = NO;

// Add a simple frame cache at the top of GetFrame implementation
static CVPixelBufferRef g_lastGoodFrame = NULL;
static Float64 g_sourceFrameRate = 30.0;
static CMTime g_frameRequestCursor = {0, 0, 0, 0};
static CFTimeInterval g_lastFrameRequestHostTime = 0;
static NSUInteger g_consecutiveFrameFallbackCount = 0;
static BOOL g_forceSingleOutputMode = NO;
static BOOL g_isLooping = NO;
static CVPixelBufferRef g_loopTransitionFrame = NULL;

// Fix the GetFrame getCurrentFrame method to better handle sample buffer creation:
+ (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve {
    if (!spoofCameraEnabled) {
        return originalFrame;
    }
    
    if (!frameExtractionPlayer || !frameExtractionPlayer.currentItem) {
        NSLog(@"[LC] [GetFrame] No player available, returning NULL");
        return NULL;
    }
    
    // CRITICAL: Check if player is actually ready
    if (frameExtractionPlayer.currentItem.status != AVPlayerItemStatusReadyToPlay || !playerIsReady) {
        NSLog(@"[LC] [GetFrame] Player not ready (status: %ld, flag: %d), returning NULL", 
              (long)frameExtractionPlayer.currentItem.status, playerIsReady);
        return NULL;
    }
    
    CMTime currentTime = [frameExtractionPlayer.currentItem currentTime];
    CMTime duration = [frameExtractionPlayer.currentItem duration];
    
    // CRITICAL: Better time validation for 720x1280 videos
    if (!CMTIME_IS_VALID(currentTime) || CMTimeGetSeconds(currentTime) < 0.01) {
        NSLog(@"[LC] [GetFrame] Invalid time, seeking to start");
        currentTime = CMTimeMake(1, 30); // Start at frame 1
        [frameExtractionPlayer seekToTime:currentTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        [NSThread sleepForTimeInterval:0.1]; // Give time to seek
    }
    
    // Detect format from original frame
    OSType requestedFormat = kCVPixelFormatType_32BGRA;
    if (originalFrame) {
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(originalFrame);
        if (formatDesc) {
            requestedFormat = CMFormatDescriptionGetMediaSubType(formatDesc);
        }
    }
    
    NSLog(@"[LC] [GetFrame] Processing format: %c%c%c%c at time %.3f/%.3f", 
          (requestedFormat >> 24) & 0xFF, (requestedFormat >> 16) & 0xFF, 
          (requestedFormat >> 8) & 0xFF, requestedFormat & 0xFF,
          CMTimeGetSeconds(currentTime), CMTimeGetSeconds(duration));
    
    CVPixelBufferRef pixelBuffer = [self getCurrentFramePixelBuffer:requestedFormat];
    if (!pixelBuffer) {
        NSLog(@"[LC] [GetFrame] Failed to get pixel buffer for requested format %@", fourCCToString(requestedFormat));
        return NULL;
    }
    
    // Log actual extracted frame info
    size_t actualWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t actualHeight = CVPixelBufferGetHeight(pixelBuffer);
    OSType actualFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    
    NSLog(@"[LC] [GetFrame] ✅ Frame extracted: %zux%zu format=%c%c%c%c", 
          actualWidth, actualHeight,
          (actualFormat >> 24) & 0xFF, (actualFormat >> 16) & 0xFF, 
          (actualFormat >> 8) & 0xFF, actualFormat & 0xFF);
    
    // Scale if needed (this should work better now)
    CVPixelBufferRef scaledBuffer = createScaledPixelBuffer(pixelBuffer, targetResolution);
    CVPixelBufferRelease(pixelBuffer);
    
    if (!scaledBuffer) {
        NSLog(@"[LC] [GetFrame] Failed to scale %zux%zu to %.0fx%.0f", 
              actualWidth, actualHeight, targetResolution.width, targetResolution.height);
        return NULL;
    }
    
    // Create sample buffer with proper timing
    CMSampleBufferRef newSampleBuffer = NULL;
    CMVideoFormatDescriptionRef videoFormatDesc = NULL;
    
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, scaledBuffer, &videoFormatDesc);
    if (status != noErr || !videoFormatDesc) {
        NSLog(@"[LC] [GetFrame] Failed to create format description: %d", status);
        CVPixelBufferRelease(scaledBuffer);
        return NULL;
    }
    
    CMSampleTimingInfo timingInfo;
    if (originalFrame) {
        CMItemCount timingCount = 0;
        CMSampleBufferGetSampleTimingInfoArray(originalFrame, 0, NULL, &timingCount);
        if (timingCount > 0) {
            CMSampleBufferGetSampleTimingInfoArray(originalFrame, 1, &timingInfo, &timingCount);
        } else {
            timingInfo = (CMSampleTimingInfo){
                .duration = CMTimeMake(1, 30),
                .presentationTimeStamp = currentTime,
                .decodeTimeStamp = kCMTimeInvalid
            };
        }
    } else {
        timingInfo = (CMSampleTimingInfo){
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC),
            .decodeTimeStamp = kCMTimeInvalid
        };
    }
    
    status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, scaledBuffer, videoFormatDesc, &timingInfo, &newSampleBuffer);
    
    CFRelease(videoFormatDesc);
    CVPixelBufferRelease(scaledBuffer);
    
    if (status != noErr || !newSampleBuffer) {
        NSLog(@"[LC] [GetFrame] Failed to create sample buffer: %d", status);
        return NULL;
    }
    
    // IMPROVEMENT: Validate sample buffer before returning (TTtest pattern)
    if (!CMSampleBufferIsValid(newSampleBuffer)) {
        NSLog(@"[LC] [GetFrame] ❌ Sample buffer validation failed");
        CFRelease(newSampleBuffer);
        return NULL;
    }
    
    NSLog(@"[LC] [GetFrame] ✅ Sample buffer created and validated successfully");
    return newSampleBuffer;
}

// Add helper function for debugging
static NSString* fourCCToString(OSType fourCC) {
    char bytes[5] = {0};
    bytes[0] = (fourCC >> 24) & 0xFF;
    bytes[1] = (fourCC >> 16) & 0xFF;
    bytes[2] = (fourCC >> 8) & 0xFF;
    bytes[3] = fourCC & 0xFF;
    return [NSString stringWithCString:bytes encoding:NSASCIIStringEncoding] ?: [NSString stringWithFormat:@"%u", (unsigned int)fourCC];
}

static CMTime LCFrameStepTime(void) {
    Float64 fps = (g_sourceFrameRate > 1.0) ? g_sourceFrameRate : 30.0;
    return CMTimeMakeWithSeconds(1.0 / fps, 600);
}

static CMTime LCWrapTimeIntoDuration(CMTime time, CMTime duration) {
    if (!CMTIME_IS_VALID(time) || CMTIME_IS_INDEFINITE(time)) {
        return kCMTimeZero;
    }
    if (!CMTIME_IS_VALID(duration) || CMTIME_IS_INDEFINITE(duration) || CMTimeCompare(duration, kCMTimeZero) <= 0) {
        return time;
    }

    Float64 timeSeconds = CMTimeGetSeconds(time);
    Float64 durationSeconds = CMTimeGetSeconds(duration);
    if (!isfinite(timeSeconds) || !isfinite(durationSeconds) || durationSeconds <= 0) {
        return time;
    }

    while (timeSeconds >= durationSeconds) {
        timeSeconds -= durationSeconds;
    }
    while (timeSeconds < 0) {
        timeSeconds += durationSeconds;
    }
    return CMTimeMakeWithSeconds(timeSeconds, 600);
}

static CMTime LCNextFrameRequestTime(void) {
    if (!frameExtractionPlayer || !frameExtractionPlayer.currentItem) {
        return kCMTimeZero;
    }

    CMTime itemTime = frameExtractionPlayer.currentItem.currentTime;
    CFTimeInterval hostTime = CACurrentMediaTime();
    CMTime step = LCFrameStepTime();

    if (!CMTIME_IS_VALID(g_frameRequestCursor) || CMTIME_IS_INDEFINITE(g_frameRequestCursor)) {
        g_frameRequestCursor = (CMTIME_IS_VALID(itemTime) && !CMTIME_IS_INDEFINITE(itemTime)) ? itemTime : kCMTimeZero;
        g_lastFrameRequestHostTime = hostTime;
        return g_frameRequestCursor;
    }

    Float64 delta = (g_lastFrameRequestHostTime > 0) ? (hostTime - g_lastFrameRequestHostTime) : 0;
    g_lastFrameRequestHostTime = hostTime;
    if (!isfinite(delta) || delta < 0) {
        delta = 0;
    }
    if (delta > 0.2) {
        delta = 0.2;
    }

    if (delta > 0) {
        g_frameRequestCursor = CMTimeAdd(g_frameRequestCursor, CMTimeMakeWithSeconds(delta, 600));
    } else {
        g_frameRequestCursor = CMTimeAdd(g_frameRequestCursor, step);
    }

    g_frameRequestCursor = LCWrapTimeIntoDuration(g_frameRequestCursor, frameExtractionPlayer.currentItem.duration);
    return g_frameRequestCursor;
}

+ (CVPixelBufferRef)getCurrentFramePixelBuffer:(OSType)requestedFormat {
    if (!spoofCameraEnabled || !frameExtractionPlayer || !frameExtractionPlayer.currentItem || !playerIsReady) {
        return NULL;
    }

    // Force playback progression in extraction-only scenarios (not attached to visible layer).
    if (frameExtractionPlayer.rate == 0.0f) {
        if ([frameExtractionPlayer respondsToSelector:@selector(playImmediatelyAtRate:)]) {
            [frameExtractionPlayer playImmediatelyAtRate:1.0f];
        } else {
            [frameExtractionPlayer play];
        }
    }

    // During loop transition, return a stable cached frame.
    if (g_isLooping && g_loopTransitionFrame) {
        CVPixelBufferRetain(g_loopTransitionFrame);
        return g_loopTransitionFrame;
    }

    AVPlayerItemVideoOutput *selectedOutput = NULL;
    switch (requestedFormat) {
        case 875704422: // '420v'
            if (yuv420vOutput) selectedOutput = yuv420vOutput;
            break;
        case 875704438: // '420f'  
            if (yuv420fOutput) selectedOutput = yuv420fOutput;
            else if (yuv420vOutput) selectedOutput = yuv420vOutput;
            break;
    }
    
    if (!selectedOutput && bgraOutput) {
        selectedOutput = bgraOutput;
    }
    
    if (!selectedOutput) {
        if (g_loopTransitionFrame) {
            CVPixelBufferRetain(g_loopTransitionFrame);
            return g_loopTransitionFrame;
        }
        if (g_lastGoodFrame) {
            CVPixelBufferRetain(g_lastGoodFrame);
            return g_lastGoodFrame;
        }
        return NULL;
    }

    CMTime steppedTime = LCNextFrameRequestTime();
    CMTime hostMappedTime = [selectedOutput itemTimeForHostTime:CACurrentMediaTime()];
    CMTime itemTime = frameExtractionPlayer.currentItem.currentTime;
    CMTime candidateTimes[] = { steppedTime, hostMappedTime, itemTime };

    AVPlayerItemVideoOutput *candidateOutputs[] = { selectedOutput, bgraOutput, yuv420vOutput, yuv420fOutput };
    CVPixelBufferRef pixelBuffer = NULL;
    CMTime resolvedOutputTime = kCMTimeInvalid;

    for (NSUInteger t = 0; t < sizeof(candidateTimes) / sizeof(candidateTimes[0]) && !pixelBuffer; t++) {
        CMTime probeTime = candidateTimes[t];
        if (!CMTIME_IS_VALID(probeTime) || CMTIME_IS_INDEFINITE(probeTime)) {
            continue;
        }

        for (NSUInteger i = 0; i < sizeof(candidateOutputs) / sizeof(candidateOutputs[0]); i++) {
            AVPlayerItemVideoOutput *candidate = candidateOutputs[i];
            if (!candidate) continue;

            BOOL duplicate = NO;
            for (NSUInteger j = 0; j < i; j++) {
                if (candidateOutputs[j] == candidate) {
                    duplicate = YES;
                    break;
                }
            }
            if (duplicate) continue;

            CMTime itemTimeForDisplay = kCMTimeInvalid;
            pixelBuffer = [candidate copyPixelBufferForItemTime:probeTime itemTimeForDisplay:&itemTimeForDisplay];
            if (pixelBuffer) {
                resolvedOutputTime = CMTIME_IS_VALID(itemTimeForDisplay) ? itemTimeForDisplay : probeTime;
                break;
            }
        }
    }

    if (pixelBuffer) {
        g_consecutiveFrameFallbackCount = 0;
        if (CMTIME_IS_VALID(resolvedOutputTime) && !CMTIME_IS_INDEFINITE(resolvedOutputTime)) {
            g_frameRequestCursor = LCWrapTimeIntoDuration(resolvedOutputTime, frameExtractionPlayer.currentItem.duration);
        }

        // Cache a stable fallback for brief extraction gaps.
        if (g_lastGoodFrame) {
            CVPixelBufferRelease(g_lastGoodFrame);
        }
        g_lastGoodFrame = pixelBuffer;
        CVPixelBufferRetain(g_lastGoodFrame);
        return pixelBuffer;
    }

    g_consecutiveFrameFallbackCount++;
    if (g_consecutiveFrameFallbackCount >= 10) {
        CMTime step = LCFrameStepTime();
        CMTime nudgeTime = CMTIME_IS_VALID(itemTime) ? CMTimeAdd(itemTime, step) : step;
        nudgeTime = LCWrapTimeIntoDuration(nudgeTime, frameExtractionPlayer.currentItem.duration);
        g_frameRequestCursor = nudgeTime;

        [frameExtractionPlayer seekToTime:nudgeTime
                          toleranceBefore:step
                           toleranceAfter:step
                        completionHandler:^(BOOL finished) {}];
        [frameExtractionPlayer play];
        g_consecutiveFrameFallbackCount = 0;
        NSLog(@"[LC] [GetFrame] ⚠️ Frame extraction stalled; nudged player to %.3f", CMTimeGetSeconds(nudgeTime));
    }

    // Prioritize loop transition frame, then the last good frame.
    if (g_loopTransitionFrame) {
        CVPixelBufferRetain(g_loopTransitionFrame);
        return g_loopTransitionFrame;
    }
    if (g_lastGoodFrame) {
        CVPixelBufferRetain(g_lastGoodFrame);
        return g_lastGoodFrame;
    }
    return NULL;
}

// IMPROVEMENT: Track video file modification date for hot-reload detection (inspired by VCAM pattern)
static NSDate *g_lastVideoModificationDate = nil;

// Check if video file has been modified since last load
+ (BOOL)hasVideoFileChanged:(NSString *)path {
    if (!path || path.length == 0) return NO;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return NO;
    
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    NSDate *modDate = attrs[NSFileModificationDate];
    
    if (!modDate) return NO;
    
    // Check for .new marker file (VCAM-style hot reload signal)
    NSString *markerPath = [path stringByAppendingString:@".new"];
    BOOL hasMarker = [fm fileExistsAtPath:markerPath];
    if (hasMarker) {
        // Remove marker and force reload
        [fm removeItemAtPath:markerPath error:nil];
        NSLog(@"[LC] [GetFrame] 🔄 Hot reload marker detected, forcing video reload");
        return YES;
    }
    
    if (!g_lastVideoModificationDate) {
        g_lastVideoModificationDate = modDate;
        return NO; // First load
    }
    
    BOOL changed = ![modDate isEqualToDate:g_lastVideoModificationDate];
    if (changed) {
        NSLog(@"[LC] [GetFrame] 🔄 Video file modified: old=%@ new=%@", g_lastVideoModificationDate, modDate);
        g_lastVideoModificationDate = modDate;
    }
    return changed;
}

+ (void)setCurrentVideoPath:(NSString *)path {
    // Check if path changed OR if file was modified (hot-reload support)
    BOOL pathChanged = ![path isEqualToString:currentVideoPath];
    BOOL fileChanged = [self hasVideoFileChanged:path];
    
    if (!pathChanged && !fileChanged) {
        return; // No changes
    }
    
    if (fileChanged && !pathChanged) {
        NSLog(@"[LC] [GetFrame] 🔄 Video file changed, reloading player");
    }
    
    currentVideoPath = path;
    [self setupPlayerWithPath:path];
}

+ (void)cleanupPlayer {
    // Remove any existing observers
    if (frameExtractionPlayer && _kvoObserver) {
        @try {
            [frameExtractionPlayer.currentItem removeObserver:_kvoObserver forKeyPath:@"status"];
        } @catch (NSException *exception) {
            NSLog(@"[LC] [GetFrame] Exception removing observer during cleanup: %@", exception);
        }
    }
    
    // Clear observer reference
    _kvoObserver = nil;
    
    if (frameExtractionPlayer) {
        [[NSNotificationCenter defaultCenter] removeObserver:[GetFrame class] 
                                                        name:AVPlayerItemDidPlayToEndTimeNotification 
                                                      object:frameExtractionPlayer.currentItem];
        
        [frameExtractionPlayer pause];
        
        // Remove old outputs safely
        if (frameExtractionPlayer.currentItem) {
            if (bgraOutput) [frameExtractionPlayer.currentItem removeOutput:bgraOutput];
            if (yuv420vOutput) [frameExtractionPlayer.currentItem removeOutput:yuv420vOutput];
            if (yuv420fOutput) [frameExtractionPlayer.currentItem removeOutput:yuv420fOutput];
        }
        
        frameExtractionPlayer = nil;
    }
    
    // Clean up frame cache
    if (g_lastGoodFrame) {
        CVPixelBufferRelease(g_lastGoodFrame);
        g_lastGoodFrame = NULL;
    }

    // Clean up loop transition frame
    if (g_loopTransitionFrame) {
        CVPixelBufferRelease(g_loopTransitionFrame);
        g_loopTransitionFrame = NULL;
    }
    g_isLooping = NO;

    bgraOutput = nil;
    yuv420vOutput = nil;
    yuv420fOutput = nil;
    playerIsReady = NO;
    g_frameRequestCursor = kCMTimeInvalid;
    g_lastFrameRequestHostTime = 0;
    g_consecutiveFrameFallbackCount = 0;
    g_sourceFrameRate = 30.0;
    g_forceSingleOutputMode = NO;
}

// CRITICAL FIX: Add looping handler
+ (void)playerItemDidReachEnd:(NSNotification *)notification {
    NSLog(@"[LC] [GetFrame] 🔄 Video reached end, restarting for loop");
    
    // CRITICAL: Set looping flag to use cached frame during transition
    g_isLooping = YES;
    
    // Cache the last good frame for seamless transition
    if (g_lastGoodFrame && !g_loopTransitionFrame) {
        g_loopTransitionFrame = g_lastGoodFrame;
        CVPixelBufferRetain(g_loopTransitionFrame);
        NSLog(@"[LC] [GetFrame] 🔄 Cached loop transition frame");
    }
    
    if (frameExtractionPlayer && frameExtractionPlayer.currentItem) {
        // Seek back to beginning
        [frameExtractionPlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            if (finished) {
                NSLog(@"[LC] [GetFrame] ✅ Video looped successfully");
                [frameExtractionPlayer play];
                
                // Give a brief moment for frames to become available
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    g_isLooping = NO;
                    // Release transition frame after loop completes
                    if (g_loopTransitionFrame) {
                        CVPixelBufferRelease(g_loopTransitionFrame);
                        g_loopTransitionFrame = NULL;
                    }
                    NSLog(@"[LC] [GetFrame] ✅ Loop transition complete");
                });
            } else {
                NSLog(@"[LC] [GetFrame] ❌ Video loop seek failed");
                g_isLooping = NO;
            }
        }];
    }
}

+ (void)completePlayerSetup:(AVURLAsset *)asset {
    NSError *error = nil;
    AVKeyValueStatus tracksStatus = [asset statusOfValueForKey:@"tracks" error:&error];
    
    if (tracksStatus != AVKeyValueStatusLoaded) {
        NSLog(@"[LC] [GetFrame] ❌ Failed to load tracks: %@", error);
        return;
    }
    
    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        NSLog(@"[LC] [GetFrame] ❌ No video tracks found in asset");
        return;
    }
    
    // CRITICAL: Analyze video properties for performance optimization
    AVAssetTrack *videoTrack = videoTracks.firstObject;
    CGSize naturalSize = videoTrack.naturalSize;
    float nominalFrameRate = videoTrack.nominalFrameRate;
    CMTimeRange timeRange = videoTrack.timeRange;
    Float64 duration = CMTimeGetSeconds(timeRange.duration);
    g_sourceFrameRate = nominalFrameRate > 1.0 ? nominalFrameRate : 30.0;
    
    // CRITICAL: Get bitrate information
    Float64 estimatedDataRate = videoTrack.estimatedDataRate;
    NSLog(@"[LC] [GetFrame] 🎬 VIDEO ANALYSIS:");
    NSLog(@"[LC] [GetFrame] Size: %.0fx%.0f", naturalSize.width, naturalSize.height);
    NSLog(@"[LC] [GetFrame] Duration: %.3fs", duration);
    NSLog(@"[LC] [GetFrame] Bitrate: %.0f bps (%.2f Mbps)", estimatedDataRate, estimatedDataRate / 1000000.0);
    NSLog(@"[LC] [GetFrame] Frame rate: %.2f fps", nominalFrameRate);
    
    // DETECT HIGH BITRATE VIDEO (like your 2.73 Mbps 720x1280)
    BOOL isHighBitrateVideo = estimatedDataRate > 2000000; // 2+ Mbps
    if (isHighBitrateVideo) {
        NSLog(@"[LC] [GetFrame] 🚨 HIGH BITRATE video detected - enabling optimizations");
    }
    // Handle portrait videos
    if (naturalSize.height > naturalSize.width) {
        NSLog(@"[LC] [GetFrame] ✅ Portrait video detected: %.0fx%.0f", naturalSize.width, naturalSize.height);
        if (targetResolution.width > targetResolution.height) {
            targetResolution = CGSizeMake(targetResolution.height, targetResolution.width);
            NSLog(@"[LC] [GetFrame] 🔄 Adjusted target to portrait: %.0fx%.0f", 
                  targetResolution.width, targetResolution.height);
        }
    }
    
    // Create player and item
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    frameExtractionPlayer = [AVPlayer playerWithPlayerItem:item];
    frameExtractionPlayer.muted = YES;
    
    // CRITICAL: Configure for high bitrate videos
    if (isHighBitrateVideo) {
        NSLog(@"[LC] [GetFrame] 🎯 Configuring for high bitrate video");
        
        // Enable better buffering for high bitrate content
        if ([item respondsToSelector:@selector(setPreferredForwardBufferDuration:)]) {
            item.preferredForwardBufferDuration = 2.0; // 2 second buffer for high bitrate
        }
        
        // More aggressive seeking settings
        frameExtractionPlayer.actionAtItemEnd = AVPlayerActionAtItemEndPause; // Prevent auto-loop issues
        
        // Configure automatic rate management
        if ([frameExtractionPlayer respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
            frameExtractionPlayer.automaticallyWaitsToMinimizeStalling = YES;
        }
    } else {
        // Standard configuration for lower bitrate videos
        frameExtractionPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        if ([item respondsToSelector:@selector(setPreferredForwardBufferDuration:)]) {
            item.preferredForwardBufferDuration = 1.0; // Standard buffer
        }
    }
    
    // Set up looping notification
    [[NSNotificationCenter defaultCenter] addObserver:[GetFrame class]
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    
    // Prefer source resolution unless we can downscale to a smaller known target.
    BOOL canDownscaleToTarget =
        targetResolution.width > 0 &&
        targetResolution.height > 0 &&
        targetResolution.width < naturalSize.width &&
        targetResolution.height < naturalSize.height;
    CGSize outputSize = canDownscaleToTarget ? targetResolution : naturalSize;

    // Universal stability guard: cap decode output when extraction load is likely to starve outputs.
    CGFloat requestedOutputPixelCount = outputSize.width * outputSize.height;
    BOOL shouldCapDecodeOutput =
        requestedOutputPixelCount > (1280.0 * 720.0) &&
        (isHighBitrateVideo || g_sourceFrameRate > 30.0 || requestedOutputPixelCount >= (1920.0 * 1080.0));
    if (shouldCapDecodeOutput) {
        CGFloat maxEdge = 1280.0;
        CGFloat longEdge = MAX(outputSize.width, outputSize.height);
        CGFloat scale = (longEdge > maxEdge) ? (maxEdge / longEdge) : 1.0;
        CGSize capped = CGSizeMake(floor(outputSize.width * scale), floor(outputSize.height * scale));
        if (((int)capped.width) % 2 != 0) capped.width -= 1.0;
        if (((int)capped.height) % 2 != 0) capped.height -= 1.0;
        if (capped.width < 2.0) capped.width = 2.0;
        if (capped.height < 2.0) capped.height = 2.0;
        outputSize = capped;
        NSLog(@"[LC] [GetFrame] 🎯 Decode cap enabled for extraction stability: %.0fx%.0f", outputSize.width, outputSize.height);
    }

    // Above-720p extraction is significantly less stable with 3 outputs in hook-only contexts.
    g_forceSingleOutputMode = requestedOutputPixelCount > (1280.0 * 720.0) ||
                              (outputSize.width * outputSize.height) > (1280.0 * 720.0);
    NSLog(@"[LC] [GetFrame] Using output size: %.0fx%.0f (downscaled: %@)",
          outputSize.width, outputSize.height, canDownscaleToTarget ? @"YES" : @"NO");
    
    NSDictionary *bgraAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferWidthKey : @((int)outputSize.width),
        (NSString*)kCVPixelBufferHeightKey : @((int)outputSize.height),
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };
    
    NSDictionary *yuv420vAttributes = nil;
    NSDictionary *yuv420fAttributes = nil;
    if (!g_forceSingleOutputMode) {
        yuv420vAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704422), // '420v'
            (NSString*)kCVPixelBufferWidthKey : @((int)outputSize.width),
            (NSString*)kCVPixelBufferHeightKey : @((int)outputSize.height),
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
        yuv420fAttributes = @{
            (NSString*)kCVPixelBufferPixelFormatTypeKey : @(875704438), // '420f'
            (NSString*)kCVPixelBufferWidthKey : @((int)outputSize.width),
            (NSString*)kCVPixelBufferHeightKey : @((int)outputSize.height),
            (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
        };
    }

    bgraOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:bgraAttributes];
    yuv420vOutput = yuv420vAttributes ? [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420vAttributes] : nil;
    yuv420fOutput = yuv420fAttributes ? [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:yuv420fAttributes] : nil;
    
    // CRITICAL: Configure outputs for high bitrate videos
    if (isHighBitrateVideo) {
        // More conservative settings for high bitrate
        bgraOutput.suppressesPlayerRendering = YES;
        if (yuv420vOutput) yuv420vOutput.suppressesPlayerRendering = YES;
        if (yuv420fOutput) yuv420fOutput.suppressesPlayerRendering = YES;
    }
    
    // Add outputs
    [item addOutput:bgraOutput];
    if (yuv420vOutput) [item addOutput:yuv420vOutput];
    if (yuv420fOutput) [item addOutput:yuv420fOutput];
    
    NSLog(@"[LC] [GetFrame] ✅ Outputs added (high bitrate optimized: %@, single-output mode: %@)",
          isHighBitrateVideo ? @"YES" : @"NO",
          g_forceSingleOutputMode ? @"YES" : @"NO");
    
    // Wait for player to be ready
    if (!_kvoObserver) {
        _kvoObserver = [[GetFrameKVOObserver alloc] init];
    }
    [item addObserver:_kvoObserver forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    
    // CRITICAL: For high bitrate videos, wait longer before starting playback
    if (isHighBitrateVideo) {
        NSLog(@"[LC] [GetFrame] 🎯 High bitrate: delaying playback for buffer preparation");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (frameExtractionPlayer.status == AVPlayerStatusReadyToPlay) {
                [frameExtractionPlayer play];
                NSLog(@"[LC] [GetFrame] ✅ High bitrate playback started");
            } else {
                NSLog(@"[LC] [GetFrame] ⚠️ Player not ready yet, starting anyway");
                [frameExtractionPlayer play];
            }
        });
    } else {
        [frameExtractionPlayer play];
    }
    
    NSLog(@"[LC] [GetFrame] 🎬 Player setup complete for %.0fx%.0f video (bitrate: %.2f Mbps)", 
          naturalSize.width, naturalSize.height, estimatedDataRate / 1000000.0);
}

+ (void)setupPlayerWithPath:(NSString *)path {
    NSLog(@"[LC] [GetFrame] 🎬 Setting up player with path: %@", path);
    
    // Reset ready flag
    playerIsReady = NO;
    
    // Clean up existing player and observers
    [self cleanupPlayer];
    
    if (!path || path.length == 0) {
        NSLog(@"[LC] [GetFrame] ❌ No video path provided");
        return;
    }
    
    // Verify file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"[LC] [GetFrame] ❌ Video file does not exist at path: %@", path);
        return;
    }
    
    NSURL *videoURL = [NSURL fileURLWithPath:path];
    NSLog(@"[LC] [GetFrame] 📁 Video URL: %@", videoURL);
    
    // Create asset and load tracks asynchronously
    AVURLAsset *asset = [AVURLAsset assetWithURL:videoURL];
    
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self completePlayerSetup:asset];
        });
    }];
}

+ (UIWindow *)getKeyWindow {
    // Use modern UIWindowScene API
    if (@available(iOS 15.0, *)) {
        NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
            }
        }
        return nil;
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [[UIApplication sharedApplication] keyWindow];
        #pragma clang diagnostic pop
    }
}

// old
// + (UIWindow *)getKeyWindow {
//     // Use modern UIWindowScene API for iOS 15+, fallback for older versions
//     if (@available(iOS 15.0, *)) {
//         NSSet<UIScene *> *connectedScenes = [UIApplication sharedApplication].connectedScenes;
//         for (UIScene *scene in connectedScenes) {
//             if ([scene isKindOfClass:[UIWindowScene class]]) {
//                 UIWindowScene *windowScene = (UIWindowScene *)scene;
//                 for (UIWindow *window in windowScene.windows) {
//                     if (window.isKeyWindow) {
//                         return window;
//                     }
//                 }
//             }
//         }
        
//         // Fallback to first window if no key window found
//         for (UIScene *scene in connectedScenes) {
//             if ([scene isKindOfClass:[UIWindowScene class]]) {
//                 UIWindowScene *windowScene = (UIWindowScene *)scene;
//                 if (windowScene.windows.count > 0) {
//                     return windowScene.windows.firstObject;
//                 }
//             }
//         }
//         return nil;
//     } else {
//         // iOS 14 and earlier
//         #pragma clang diagnostic push
//         #pragma clang diagnostic ignored "-Wdeprecated-declarations"
//         NSArray *windows = [[UIApplication sharedApplication] windows];
//         for (UIWindow *window in windows) {
//             if (window.isKeyWindow) {
//                 return window;
//             }
//         }
//         return windows.firstObject;
//         #pragma clang diagnostic pop
//     }
// }


// old
// + (CMSampleBufferRef)getCurrentFrame:(CMSampleBufferRef)originalFrame preserveOrientation:(BOOL)preserve {
//     if (!spoofCameraEnabled) {
//         return originalFrame; // Pass through when disabled
//     }
    
//     // Get spoofed frame
//     CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
//     if (!spoofedFrame) {
//         return originalFrame; // Fallback to original
//     }
    
//     if (preserve) {
//         // Return spoofed frame with ORIGINAL orientation context
//         // This is key for photo capture where orientation must be preserved
//         return spoofedFrame;
//     } else {
//         // Return spoofed frame with orientation processing
//         // This might be for preview layers where transform is expected
//         return spoofedFrame;
//     }
// }

+ (void)createVideoFromImage:(UIImage *)sourceImage {
    NSLog(@"[LC] 🎬 Creating video from image: %.0fx%.0f", sourceImage.size.width, sourceImage.size.height);
    
    // Create temporary video file
    NSString *tempDir = NSTemporaryDirectory();
    NSString *tempVideoPath = [tempDir stringByAppendingPathComponent:@"lc_image_video.mp4"];
    
    // Remove existing temp file
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempVideoPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempVideoPath error:nil];
    }
    
    NSURL *outputURL = [NSURL fileURLWithPath:tempVideoPath];
    
    // Create video writer
    NSError *error = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outputURL fileType:AVFileTypeMPEG4 error:&error];
    if (!writer) {
        NSLog(@"[LC] ❌ Failed to create video writer: %@", error);
        return;
    }
    
    // Determine video size (maintain aspect ratio but fit within target resolution)
    CGSize imageSize = sourceImage.size;
    CGSize videoSize = targetResolution;
    
    // Calculate scale to fit
    CGFloat scaleX = targetResolution.width / imageSize.width;
    CGFloat scaleY = targetResolution.height / imageSize.height;
    CGFloat scale = MIN(scaleX, scaleY);
    
    videoSize = CGSizeMake(floor(imageSize.width * scale), floor(imageSize.height * scale));
    
    // Ensure even dimensions (required for H.264)
    if ((int)videoSize.width % 2 != 0) videoSize.width -= 1;
    if ((int)videoSize.height % 2 != 0) videoSize.height -= 1;
    
    NSLog(@"[LC] 🎬 Video size: %.0fx%.0f (scaled from %.0fx%.0f)", videoSize.width, videoSize.height, imageSize.width, imageSize.height);
    
    // Video settings
    NSDictionary *videoSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @((int)videoSize.width),
        AVVideoHeightKey: @((int)videoSize.height),
        AVVideoCompressionPropertiesKey: @{
            AVVideoAverageBitRateKey: @(1000000), // 1 Mbps - reasonable for looping
            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
        }
    };
    
    AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    writerInput.expectsMediaDataInRealTime = NO;
    
    // Pixel buffer adaptor
    NSDictionary *pixelBufferAttributes = @{
        (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString*)kCVPixelBufferWidthKey: @((int)videoSize.width),
        (NSString*)kCVPixelBufferHeightKey: @((int)videoSize.height)
    };
    
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor 
                                                     assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput 
                                                     sourcePixelBufferAttributes:pixelBufferAttributes];
    
    if (![writer canAddInput:writerInput]) {
        NSLog(@"[LC] ❌ Cannot add video input to writer");
        return;
    }
    
    [writer addInput:writerInput];
    
    // Start writing
    if (![writer startWriting]) {
        NSLog(@"[LC] ❌ Failed to start writing: %@", writer.error);
        return;
    }
    
    [writer startSessionAtSourceTime:kCMTimeZero];
    
    // Create video in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // Create pixel buffer from image
        CVPixelBufferRef pixelBuffer = [self createPixelBufferFromImage:sourceImage size:videoSize];
        if (!pixelBuffer) {
            NSLog(@"[LC] ❌ Failed to create pixel buffer from image");
            return;
        }
        
        // Video parameters
        int frameRate = 30;
        float videoDuration = 2.0; // 2 seconds
        int totalFrames = (int)(videoDuration * frameRate);
        
        NSLog(@"[LC] 🎬 Creating %d frames at %d fps for %.1fs video", totalFrames, frameRate, videoDuration);
        
        // Write frames
        CMTime frameDuration = CMTimeMake(1, frameRate);
        CMTime currentTime = kCMTimeZero;
        
        for (int i = 0; i < totalFrames; i++) {
            while (!writerInput.readyForMoreMediaData) {
                usleep(10000); // Wait 10ms
            }
            
            // Add slight variations to each frame to make it feel more "alive"
            CVPixelBufferRef frameBuffer = pixelBuffer;
            
            // Every 10th frame, add a tiny brightness variation (subtle animation)
            if (i % 10 == 0 && i > 0) {
                frameBuffer = [self createVariedPixelBufferFromOriginal:pixelBuffer variation:(i % 100) / 100.0];
            } else {
                CVPixelBufferRetain(frameBuffer);
            }
            
            BOOL success = [adaptor appendPixelBuffer:frameBuffer withPresentationTime:currentTime];
            CVPixelBufferRelease(frameBuffer);
            
            if (!success) {
                NSLog(@"[LC] ❌ Failed to append frame %d: %@", i, writer.error);
                break;
            }
            
            currentTime = CMTimeAdd(currentTime, frameDuration);
            
            if (i % 30 == 0) { // Log every second
                NSLog(@"[LC] 🎬 Progress: %d/%d frames", i, totalFrames);
            }
        }
        
        CVPixelBufferRelease(pixelBuffer);
        
        // Finish writing
        [writerInput markAsFinished];
        [writer finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (writer.status == AVAssetWriterStatusCompleted) {
                    NSLog(@"[LC] ✅ Video created successfully at: %@", tempVideoPath);
                    
                    // CRITICAL: Update the global video path variables
                    spoofCameraVideoPath = tempVideoPath;
                    currentVideoPath = tempVideoPath;
                    
                    // Initialize the GetFrame video system
                    [GetFrame setCurrentVideoPath:tempVideoPath];
                    
                    // Also set up the main video spoofing system
                    setupVideoSpoofingResources();
                    
                    NSLog(@"[LC] 🎬 Image-to-video conversion complete - video system activated");
                    
                    // IMPORTANT: Clear the static image buffer to force video usage
                    if (staticImageSpoofBuffer) {
                        NSLog(@"[LC] 🔄 Switching from static image to video mode");
                        CVPixelBufferRelease(staticImageSpoofBuffer);
                        staticImageSpoofBuffer = NULL;
                    }
                    
                } else {
                    NSLog(@"[LC] ❌ Video creation failed: %@", writer.error);
                    NSLog(@"[LC] 🔄 Keeping static image mode as fallback");
                }
            });
        }];
    });
}

// Helper method to create pixel buffer from UIImage
// Fix the createPixelBufferFromImage method around line 1699:

+ (CVPixelBufferRef)createPixelBufferFromImage:(UIImage *)image size:(CGSize)size {
    NSDictionary *options = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         (size_t)size.width,
                                         (size_t)size.height,
                                         kCVPixelFormatType_32BGRA,
                                         (__bridge CFDictionaryRef)options,
                                         &pixelBuffer);
    
    if (status != kCVReturnSuccess) {
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data,
                                                size.width,
                                                size.height,
                                                8,
                                                CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                colorSpace,
                                                kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    
    if (context) {
        // Fill with black background first
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
        
        // FIXED: Always ensure target size is portrait
        CGSize adjustedSize = size;
        if (size.width > size.height) {
            // If target is landscape, swap to portrait
            adjustedSize = CGSizeMake(size.height, size.width);
            NSLog(@"[LC] 🔄 fd: Adjusted target from %0.fx%.0f to %.0fx%.0f (portrait)", 
                  size.width, size.height, adjustedSize.width, adjustedSize.height);
        }
        
        // Get the CGImage and calculate aspect fill for PORTRAIT target
        CGImageRef cgImage = image.CGImage;
        CGFloat imageAspect = CGImageGetWidth(cgImage) / (CGFloat)CGImageGetHeight(cgImage);
        CGFloat targetAspect = adjustedSize.width / adjustedSize.height;
        
        CGRect imageRect;
        if (imageAspect > targetAspect) {
            // Image is wider - fit height and crop sides
            CGFloat scaledWidth = adjustedSize.height * imageAspect;
            imageRect = CGRectMake(-(scaledWidth - adjustedSize.width) / 2, 0, scaledWidth, adjustedSize.height);
        } else {
            // Image is taller - fit width and crop top/bottom
            CGFloat scaledHeight = adjustedSize.width / imageAspect;
            imageRect = CGRectMake(0, -(scaledHeight - adjustedSize.height) / 2, adjustedSize.width, scaledHeight);
        }
        
        // Draw with NO transforms - rely on hardware rotation later if needed
        CGContextDrawImage(context, imageRect, cgImage);
        
        CGContextRelease(context);
    }
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // FIXED: Return the created pixelBuffer directly since rotation is disabled
    return pixelBuffer;
}

// Helper method to create subtle variations for animation
+ (CVPixelBufferRef)createVariedPixelBufferFromOriginal:(CVPixelBufferRef)originalBuffer variation:(float)amount {
    if (!originalBuffer) return NULL;
    
    size_t width = CVPixelBufferGetWidth(originalBuffer);
    size_t height = CVPixelBufferGetHeight(originalBuffer);
    
    CVPixelBufferRef newBuffer = NULL;
    NSDictionary *options = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         (__bridge CFDictionaryRef)options, &newBuffer);
    
    if (status != kCVReturnSuccess) {
        return NULL;
    }
    
    // Copy original buffer
    CVPixelBufferLockBaseAddress(originalBuffer, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(newBuffer, 0);
    
    void *originalData = CVPixelBufferGetBaseAddress(originalBuffer);
    void *newData = CVPixelBufferGetBaseAddress(newBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(originalBuffer);
    
    // Copy and apply subtle brightness variation
    for (size_t row = 0; row < height; row++) {
        uint8_t *originalRow = (uint8_t *)originalData + row * bytesPerRow;
        uint8_t *newRow = (uint8_t *)newData + row * bytesPerRow;
        
        for (size_t col = 0; col < width * 4; col += 4) {
            // BGRA format
            float brightnessFactor = 1.0 + (amount * 0.02); // Very subtle ±2% variation
            
            newRow[col] = MIN(255, originalRow[col] * brightnessFactor);     // B
            newRow[col + 1] = MIN(255, originalRow[col + 1] * brightnessFactor); // G  
            newRow[col + 2] = MIN(255, originalRow[col + 2] * brightnessFactor); // R
            newRow[col + 3] = originalRow[col + 3]; // A
        }
    }
    
    CVPixelBufferUnlockBaseAddress(newBuffer, 0);
    CVPixelBufferUnlockBaseAddress(originalBuffer, kCVPixelBufferLock_ReadOnly);
    
    return newBuffer;
}

@end


// pragma MARK: - KVO Observer for Player Item Status

@implementation GetFrameKVOObserver

- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context {
    if ([keyPath isEqualToString:@"status"] && [object isKindOfClass:[AVPlayerItem class]]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        
        switch (item.status) {
            case AVPlayerItemStatusReadyToPlay:
                NSLog(@"[LC] [GetFrame] ✅ Player ready - enabling frame extraction");
                playerIsReady = YES;
                // Seek to beginning to ensure frames are available
                [frameExtractionPlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                break;
                
            case AVPlayerItemStatusFailed:
                NSLog(@"[LC] [GetFrame] ❌ Player failed: %@", item.error);
                playerIsReady = NO;
                break;
                
            case AVPlayerItemStatusUnknown:
                NSLog(@"[LC] [GetFrame] ⏳ Player status unknown");
                playerIsReady = NO;
                break;
        }
        
        // Remove observer after first status change
        @try {
            [item removeObserver:_kvoObserver forKeyPath:@"status"];
            _kvoObserver = nil; // Clear the reference
        } @catch (NSException *exception) {
            NSLog(@"[LC] [GetFrame] Exception removing observer: %@", exception);
        }
    }
}

@end

// pragma MARK: - Photo Data Management


static dispatch_queue_t photoCacheQueue = NULL;

static void initializePhotoCacheQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        photoCacheQueue = dispatch_queue_create("com.livecontainer.photocache", DISPATCH_QUEUE_SERIAL);
    });
}

// Debug logging:

// In our photo caching function, we need to NOT apply any rotation
// static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
//     @try {
//         NSLog(@"[LC] 📷 fd: Caching photo data with hardware rotation");
        
//         // Get spoofed frame 
//         CVPixelBufferRef spoofedPixelBuffer = [GetFrame getCurrentFramePixelBuffer:kCVPixelFormatType_32BGRA];
//         if (!spoofedPixelBuffer) {
//             NSLog(@"[LC] 📷 ❌ No spoofed pixel buffer available");
//             return;
//         }
        
//         // Clean up existing cache
//         cleanupPhotoCache();
        
//         // CRITICAL: Apply fd's hardware rotation BEFORE creating CGImage
//         CVPixelBufferRef portraitBuffer = rotatePixelBufferToPortrait(spoofedPixelBuffer);
//         CVPixelBufferRelease(spoofedPixelBuffer);
        
//         if (!portraitBuffer) {
//             NSLog(@"[LC] 📷 ❌ Failed to rotate buffer to portrait");
//             return;
//         }
        
//         // Store the properly oriented pixel buffer
//         g_cachedPhotoPixelBuffer = portraitBuffer;
//         CVPixelBufferRetain(g_cachedPhotoPixelBuffer);
        
//         // Create CGImage from the ALREADY ROTATED pixel buffer
//         size_t width = CVPixelBufferGetWidth(portraitBuffer);
//         size_t height = CVPixelBufferGetHeight(portraitBuffer);
        
//         CVPixelBufferLockBaseAddress(portraitBuffer, kCVPixelBufferLock_ReadOnly);
//         void *baseAddress = CVPixelBufferGetBaseAddress(portraitBuffer);
//         size_t bytesPerRow = CVPixelBufferGetBytesPerRow(portraitBuffer);
        
//         NSData *pixelData = [NSData dataWithBytes:baseAddress length:bytesPerRow * height];
//         CVPixelBufferUnlockBaseAddress(portraitBuffer, kCVPixelBufferLock_ReadOnly);
        
//         CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//         CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
        
//         CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixelData);
//         g_cachedPhotoCGImage = CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace, bitmapInfo, dataProvider, NULL, false, kCGRenderingIntentDefault);
        
//         CGDataProviderRelease(dataProvider);
//         CGColorSpaceRelease(colorSpace);
        
//         // CRITICAL: Create JPEG with orientation = 1 (since pixels are already correctly oriented)
//         if (g_cachedPhotoCGImage) {
//             // Create UIImage with Up orientation (pixels are already correct)
//             UIImage *uiImage = [UIImage imageWithCGImage:g_cachedPhotoCGImage 
//                                                    scale:1.0 
//                                              orientation:UIImageOrientationUp];
            
//             // Create base JPEG data 
//             NSData *jpegData = UIImageJPEGRepresentation(uiImage, 1.0);
            
//             if (jpegData) {
//                 // Create iPhone metadata with FIXED orientation = 1
//                 CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)jpegData, NULL);
//                 if (imageSource) {
//                     NSMutableData *newJpegData = [NSMutableData data];
//                     CFStringRef jpegType;
//                     if (@available(iOS 14.0, *)) {
//                         jpegType = (__bridge CFStringRef)UTTypeJPEG.identifier;
//                     } else {
//                         #pragma clang diagnostic push
//                         #pragma clang diagnostic ignored "-Wdeprecated-declarations"
//                         jpegType = kUTTypeJPEG;
//                         #pragma clang diagnostic pop
//                     }
                    
//                     CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)newJpegData, jpegType, 1, NULL);
                    
//                     if (destination) {
//                         // Get current date for realistic timestamps
//                         NSDateFormatter *exifDateFormatter = [[NSDateFormatter alloc] init];
//                         [exifDateFormatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
//                         [exifDateFormatter setTimeZone:[NSTimeZone systemTimeZone]];
//                         NSString *currentDateTime = [exifDateFormatter stringFromDate:[NSDate date]];
                        
//                         // Get device model for realistic camera info
//                         NSString *deviceModel = [[UIDevice currentDevice] model];
//                         NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
                        
//                         // Create comprehensive camera metadata like real iPhone photos
//                         NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
//                         NSMutableDictionary *tiffDict = [NSMutableDictionary dictionary];
//                         NSMutableDictionary *exifDict = [NSMutableDictionary dictionary];
                        
//                         // CRITICAL: Orientation = 1 because pixels are already correctly oriented
//                         tiffDict[(NSString*)kCGImagePropertyTIFFOrientation] = @1; // Up/Normal - pixels are correct
//                         tiffDict[(NSString*)kCGImagePropertyTIFFMake] = @"Apple";
//                         tiffDict[(NSString*)kCGImagePropertyTIFFModel] = deviceModel;
//                         tiffDict[(NSString*)kCGImagePropertyTIFFSoftware] = [NSString stringWithFormat:@"iOS %@", systemVersion];
//                         tiffDict[(NSString*)kCGImagePropertyTIFFDateTime] = currentDateTime;
//                         tiffDict[(NSString*)kCGImagePropertyTIFFXResolution] = @72;
//                         tiffDict[(NSString*)kCGImagePropertyTIFFYResolution] = @72;
//                         tiffDict[(NSString*)kCGImagePropertyTIFFResolutionUnit] = @2;
                        
//                         // EXIF metadata (camera-specific info)
//                         exifDict[(NSString*)kCGImagePropertyExifPixelXDimension] = @(width);
//                         exifDict[(NSString*)kCGImagePropertyExifPixelYDimension] = @(height);
//                         exifDict[(NSString*)kCGImagePropertyExifColorSpace] = @1; // sRGB
//                         exifDict[(NSString*)kCGImagePropertyExifDateTimeOriginal] = currentDateTime;
//                         exifDict[(NSString*)kCGImagePropertyExifDateTimeDigitized] = currentDateTime;
                        
//                         // Realistic camera settings
//                         exifDict[(NSString*)kCGImagePropertyExifFNumber] = @1.8;
//                         exifDict[(NSString*)kCGImagePropertyExifExposureTime] = @(1.0/60.0);
//                         exifDict[(NSString*)kCGImagePropertyExifISOSpeedRatings] = @[@100];
//                         exifDict[(NSString*)kCGImagePropertyExifFocalLength] = @4.25;
//                         exifDict[(NSString*)kCGImagePropertyExifExposureMode] = @0;
//                         exifDict[(NSString*)kCGImagePropertyExifWhiteBalance] = @0;
//                         exifDict[(NSString*)kCGImagePropertyExifFlash] = @16;
//                         exifDict[(NSString*)kCGImagePropertyExifMeteringMode] = @5;
//                         exifDict[(NSString*)kCGImagePropertyExifSensingMethod] = @2;
//                         exifDict[(NSString*)kCGImagePropertyExifSceneCaptureType] = @0;
                        
//                         // iPhone-specific EXIF data
//                         if ([deviceModel containsString:@"iPhone"]) {
//                             exifDict[(NSString*)kCGImagePropertyExifLensMake] = @"Apple";
//                             exifDict[(NSString*)kCGImagePropertyExifLensModel] = [NSString stringWithFormat:@"%@ back camera 4.25mm f/1.8", deviceModel];
//                             exifDict[(NSString*)kCGImagePropertyExifSubsecTimeOriginal] = @"000";
//                             exifDict[(NSString*)kCGImagePropertyExifSubsecTimeDigitized] = @"000";
//                         }
                        
//                         metadata[(NSString*)kCGImagePropertyTIFFDictionary] = tiffDict;
//                         metadata[(NSString*)kCGImagePropertyExifDictionary] = exifDict;
                        
//                         // Add the image with proper metadata
//                         CGImageDestinationAddImage(destination, g_cachedPhotoCGImage, (__bridge CFDictionaryRef)metadata);
                        
//                         if (CGImageDestinationFinalize(destination)) {
//                             g_cachedPhotoJPEGData = [newJpegData copy];
//                             NSLog(@"[LC] 📷 ✅ fd: Photo cache with hardware rotation created (%zuB)", g_cachedPhotoJPEGData.length);
//                         } else {
//                             g_cachedPhotoJPEGData = jpegData; // Fallback
//                             NSLog(@"[LC] 📷 ⚠️ Using fallback JPEG");
//                         }
                        
//                         CFRelease(destination);
//                     } else {
//                         g_cachedPhotoJPEGData = jpegData; // Fallback
//                     }
                    
//                     CFRelease(imageSource);
//                 } else {
//                     g_cachedPhotoJPEGData = jpegData; // Fallback
//                 }
//             } else {
//                 NSLog(@"[LC] 📷 ❌ Failed to create JPEG data");
//             }
            
//             NSLog(@"[LC] 📷 ✅ fd: Photo cache updated with hardware rotation - CGIMG:%p, JPEG:%zuB", 
//                   g_cachedPhotoCGImage, g_cachedPhotoJPEGData.length);
//         } else {
//             NSLog(@"[LC] 📷 ❌ Failed to create CGImage from rotated pixel buffer");
//         }
        
//         // Release the rotated buffer
//         CVPixelBufferRelease(portraitBuffer);
        
//     } @catch (NSException *exception) {
//         NSLog(@"[LC] 📷 ❌ fd photo caching exception: %@", exception);
//     }
// }

static void cachePhotoDataFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
    @try {
        NSLog(@"[LC] 📷 FIXED: Caching photo data WITHOUT rotation");
        
        // Get spoofed frame 
        CVPixelBufferRef originalSpoofedPixelBuffer = [GetFrame getCurrentFramePixelBuffer:kCVPixelFormatType_32BGRA];
        if (!originalSpoofedPixelBuffer) {
            NSLog(@"[LC] 📷 ❌ No original spoofed pixel buffer available for photo cache.");
            return;
        }
        
        // Clean up existing cache
        cleanupPhotoCache();

        // Apply fixed -90 degree rotation to correct the consistent rotation issue
        CVPixelBufferRef correctedPixelBuffer = correctPhotoRotation(originalSpoofedPixelBuffer);
        CVPixelBufferRelease(originalSpoofedPixelBuffer); // Release original buffer from GetFrame

        if (!correctedPixelBuffer) {
            NSLog(@"[LC] 📷 ❌ Failed to apply rotation correction to photo buffer. Using uncorrected buffer as fallback (if any).");
            // As a fallback, consider if we should attempt to use originalSpoofedPixelBuffer or just fail.
            // For now, if correction fails, we can't proceed to cache because g_cachedPhotoPixelBuffer would be NULL.
            return;
        }
        
        // Store the corrected (and rotated) pixel buffer
        g_cachedPhotoPixelBuffer = correctedPixelBuffer; 
        // No need to CVPixelBufferRetain here, as correctPhotoRotation returns a new, retained buffer.
        // We are taking ownership of the buffer returned by correctPhotoRotation.
        
        // Create CGImage from the *corrected* pixel buffer
        size_t width = CVPixelBufferGetWidth(g_cachedPhotoPixelBuffer); // Width of the corrected buffer
        size_t height = CVPixelBufferGetHeight(g_cachedPhotoPixelBuffer); // Height of the corrected buffer
        
        NSLog(@"[LC] 📷 Creating CGImage from CORRECTED %zux%zu buffer", width, height);
        
        CVPixelBufferLockBaseAddress(g_cachedPhotoPixelBuffer, kCVPixelBufferLock_ReadOnly);
        void *baseAddress = CVPixelBufferGetBaseAddress(g_cachedPhotoPixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(g_cachedPhotoPixelBuffer);
        
        NSData *pixelData = [NSData dataWithBytes:baseAddress length:bytesPerRow * height];
        CVPixelBufferUnlockBaseAddress(g_cachedPhotoPixelBuffer, kCVPixelBufferLock_ReadOnly);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
        
        CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixelData);
        g_cachedPhotoCGImage = CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace, bitmapInfo, dataProvider, NULL, false, kCGRenderingIntentDefault);
        
        CGDataProviderRelease(dataProvider);
        CGColorSpaceRelease(colorSpace);
        
        // Create JPEG with the orientation that matches the pixel data
        if (g_cachedPhotoCGImage) {
            // Create UIImage with Up orientation
            UIImage *uiImage = [UIImage imageWithCGImage:g_cachedPhotoCGImage 
                                                   scale:1.0 
                                             orientation:UIImageOrientationUp];
            
            // Create JPEG with realistic metadata
            NSData *jpegData = UIImageJPEGRepresentation(uiImage, 1.0);
            
            if (jpegData) {
                // Create metadata with orientation = 1 (normal/up)
                CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)jpegData, NULL);
                if (imageSource) {
                    NSMutableData *newJpegData = [NSMutableData data];
                    CFStringRef jpegType;
                    if (@available(iOS 14.0, *)) {
                        jpegType = (__bridge CFStringRef)UTTypeJPEG.identifier;
                    } else {
                        #pragma clang diagnostic push
                        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        jpegType = kUTTypeJPEG;
                        #pragma clang diagnostic pop
                    }
                    
                    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)newJpegData, jpegType, 1, NULL);
                    
                    if (destination) {
                        // Create basic metadata
                        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
                        NSMutableDictionary *tiffDict = [NSMutableDictionary dictionary];
                        NSMutableDictionary *exifDict = [NSMutableDictionary dictionary];
                        
                        // CRITICAL: Test different orientation values
                        // Try orientation = 1 first (normal/up)
                        tiffDict[(NSString*)kCGImagePropertyTIFFOrientation] = @1;
                        
                        // Basic metadata
                        tiffDict[(NSString*)kCGImagePropertyTIFFMake] = @"Apple";
                        tiffDict[(NSString*)kCGImagePropertyTIFFModel] = [[UIDevice currentDevice] model];
                        
                        exifDict[(NSString*)kCGImagePropertyExifPixelXDimension] = @(width);
                        exifDict[(NSString*)kCGImagePropertyExifPixelYDimension] = @(height);
                        exifDict[(NSString*)kCGImagePropertyExifColorSpace] = @1;
                        
                        metadata[(NSString*)kCGImagePropertyTIFFDictionary] = tiffDict;
                        metadata[(NSString*)kCGImagePropertyExifDictionary] = exifDict;
                        
                        CGImageDestinationAddImage(destination, g_cachedPhotoCGImage, (__bridge CFDictionaryRef)metadata);
                        
                        if (CGImageDestinationFinalize(destination)) {
                            g_cachedPhotoJPEGData = [newJpegData copy];
                            NSLog(@"[LC] 📷 ✅ FIXED: Photo cache created WITHOUT rotation (%zuB)", g_cachedPhotoJPEGData.length);
                        } else {
                            g_cachedPhotoJPEGData = jpegData;
                            NSLog(@"[LC] 📷 ⚠️ Using fallback JPEG");
                        }
                        
                        CFRelease(destination);
                    } else {
                        g_cachedPhotoJPEGData = jpegData;
                    }
                    
                    CFRelease(imageSource);
                } else {
                    g_cachedPhotoJPEGData = jpegData;
                }
            }
            
            NSLog(@"[LC] 📷 ✅ FIXED: Photo cache updated WITHOUT rotation - size: %zux%zu", width, height);
            NSLog(@"[LC] 📷 ✅ FIXED: Cache status - PixelBuffer:%p, CGImage:%p, JPEG:%zuB", 
                  g_cachedPhotoPixelBuffer, g_cachedPhotoCGImage, g_cachedPhotoJPEGData.length);
        }
        
        // g_cachedPhotoPixelBuffer (which is correctedPixelBuffer) will be released in cleanupPhotoCache.
        // No need to release spoofedPixelBuffer here as it was already released after passing to correctPhotoRotation.
        // No need to release originalSpoofedPixelBuffer explicitly here, it was released.
        // No need to release correctedPixelBuffer here, as it's now g_cachedPhotoPixelBuffer and managed by the cache.

    } @catch (NSException *exception) {
        NSLog(@"[LC] 📷 ❌ Photo caching exception with rotation: %@", exception);
    }
}

static void cleanupPhotoCache(void) {
    if (!photoCacheQueue) return;
    
    dispatch_async(photoCacheQueue, ^{
        if (g_cachedPhotoPixelBuffer) {
            CVPixelBufferRelease(g_cachedPhotoPixelBuffer);
            g_cachedPhotoPixelBuffer = NULL;
        }
        if (g_cachedPhotoCGImage) {
            CGImageRelease(g_cachedPhotoCGImage);
            g_cachedPhotoCGImage = NULL;
        }
        g_cachedPhotoJPEGData = nil;
        NSLog(@"[LC] 🧹 Photo cache cleaned up safely");
    });
}

// pragma MARK: - Delegate Wrapper

static void configurePhotoOutputForSpoofing(AVCapturePhotoOutput *photoOutput, NSString *reason) {
    if (!spoofCameraEnabled || !photoOutput) {
        return;
    }

    if (@available(iOS 17.0, *)) {
        @try {
            if ([photoOutput isAutoDeferredPhotoDeliverySupported]) {
                BOOL wasEnabled = photoOutput.isAutoDeferredPhotoDeliveryEnabled;
                if (wasEnabled) {
                    photoOutput.autoDeferredPhotoDeliveryEnabled = NO;
                    NSLog(@"[LC] 📷 %@: Disabled autoDeferredPhotoDeliveryEnabled", reason);
                } else {
                    NSLog(@"[LC] 📷 %@: autoDeferredPhotoDeliveryEnabled already OFF", reason);
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[LC] ❌ %@: Failed to configure deferred photo delivery: %@", reason, exception);
        }
    }
}

static void primePhotoCacheIfNeeded(void) {
    if (!spoofCameraEnabled) {
        return;
    }
    if (g_cachedPhotoPixelBuffer && g_cachedPhotoCGImage && g_cachedPhotoJPEGData.length > 0) {
        return;
    }

    CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
    if (!spoofedFrame) {
        return;
    }
    cachePhotoDataFromSampleBuffer(spoofedFrame);
    CFRelease(spoofedFrame);
}

static int photoCacheWarmupAttemptsForMode(NSString *mode) {
    if ([mode isEqualToString:@"aggressive"]) {
        return 5;
    }
    if ([mode isEqualToString:@"compatibility"]) {
        return 3;
    }
    return 1;
}

static void warmPhotoCacheAsyncForMode(NSString *mode) {
    NSString *effectiveMode = mode ?: @"standard";
    int attempts = photoCacheWarmupAttemptsForMode(effectiveMode);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        for (int i = 0; i < attempts; i++) {
            CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
            if (spoofedFrame) {
                cachePhotoDataFromSampleBuffer(spoofedFrame);
                CFRelease(spoofedFrame);
            }
            if (i < attempts - 1) {
                usleep(5000); // 5ms delay between attempts for enhanced modes.
            }
        }
        if (attempts > 1) {
            NSLog(@"[LC] 📷 Enhanced mode (%@): %d cache attempts completed", effectiveMode, attempts);
        } else {
            NSLog(@"[LC] 📷 Standard mode: Photo cache updated");
        }
    });
}

@interface LCSpoofPhotoCaptureDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) id<AVCapturePhotoCaptureDelegate> originalDelegate;
@property (nonatomic, weak) AVCapturePhotoOutput *photoOutput;
- (instancetype)initWithDelegate:(id<AVCapturePhotoCaptureDelegate>)delegate photoOutput:(AVCapturePhotoOutput *)output;
@end

@implementation LCSpoofPhotoCaptureDelegate

- (instancetype)initWithDelegate:(id<AVCapturePhotoCaptureDelegate>)delegate photoOutput:(AVCapturePhotoOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _photoOutput = output;
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhoto:(AVCapturePhoto *)photo
                error:(NSError *)error {
    NSLog(@"[LC] 📷 L5 delegate: didFinishProcessingPhoto (error=%@)", error ? @"YES" : @"NO");
    if (spoofCameraEnabled && !error) {
        primePhotoCacheIfNeeded();
    }
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate captureOutput:output didFinishProcessingPhoto:photo error:error];
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer
     resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
      bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
                error:(NSError *)error {
    NSLog(@"[LC] 📷 L5 delegate: didFinishProcessingPhotoSampleBuffer (error=%@)", error ? @"YES" : @"NO");
    CMSampleBufferRef spoofedFrame = NULL;
    CMSampleBufferRef forwardedPhotoSampleBuffer = photoSampleBuffer;

    if (spoofCameraEnabled && !error) {
        primePhotoCacheIfNeeded();
        if (photoSampleBuffer && CMSampleBufferGetImageBuffer(photoSampleBuffer)) {
            spoofedFrame = createSpoofedSampleBuffer();
            if (spoofedFrame) {
                forwardedPhotoSampleBuffer = spoofedFrame;
            }
        }
    }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.originalDelegate captureOutput:output
          didFinishProcessingPhotoSampleBuffer:forwardedPhotoSampleBuffer
                  previewPhotoSampleBuffer:previewPhotoSampleBuffer
                          resolvedSettings:resolvedSettings
                           bracketSettings:bracketSettings
                                     error:error];
        #pragma clang diagnostic pop
    }

    if (spoofedFrame) {
        CFRelease(spoofedFrame);
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingRawPhotoSampleBuffer:(CMSampleBufferRef)rawSampleBuffer
previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer
     resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
      bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
                error:(NSError *)error {
    NSLog(@"[LC] 📷 L5 delegate: didFinishProcessingRawPhotoSampleBuffer (error=%@)", error ? @"YES" : @"NO");
    CMSampleBufferRef spoofedFrame = NULL;
    CMSampleBufferRef forwardedRawSampleBuffer = rawSampleBuffer;

    if (spoofCameraEnabled && !error) {
        primePhotoCacheIfNeeded();
        if (rawSampleBuffer && CMSampleBufferGetImageBuffer(rawSampleBuffer)) {
            spoofedFrame = createSpoofedSampleBuffer();
            if (spoofedFrame) {
                forwardedRawSampleBuffer = spoofedFrame;
            }
        }
    }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.originalDelegate captureOutput:output
          didFinishProcessingRawPhotoSampleBuffer:forwardedRawSampleBuffer
                  previewPhotoSampleBuffer:previewPhotoSampleBuffer
                          resolvedSettings:resolvedSettings
                           bracketSettings:bracketSettings
                                     error:error];
        #pragma clang diagnostic pop
    }

    if (spoofedFrame) {
        CFRelease(spoofedFrame);
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishCapturingDeferredPhotoProxy:(id)deferredPhotoProxy
                error:(NSError *)error {
    NSLog(@"[LC] 📷 L5 delegate: didFinishCapturingDeferredPhotoProxy (error=%@)", error ? @"YES" : @"NO");
    if (spoofCameraEnabled && !error) {
        primePhotoCacheIfNeeded();
    }
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        if (@available(iOS 17.0, *)) {
            [self.originalDelegate captureOutput:output didFinishCapturingDeferredPhotoProxy:deferredPhotoProxy error:error];
        }
    }
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
                error:(NSError *)error {
    NSLog(@"[LC] 📷 L5 delegate: didFinishCaptureForResolvedSettings (error=%@)", error ? @"YES" : @"NO");
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate captureOutput:output didFinishCaptureForResolvedSettings:resolvedSettings error:error];
    }
    if (output == self.photoOutput) {
        objc_setAssociatedObject(output, @selector(lc_capturePhotoWithSettings:delegate:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end

@interface SimpleSpoofDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;
@property (nonatomic, assign) AVCaptureOutput *originalOutput;
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output;
@end

@implementation SimpleSpoofDelegate
- (instancetype)initWithDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate output:(AVCaptureOutput *)output {
    if (self = [super init]) {
        _originalDelegate = delegate;
        _originalOutput = output;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    static int frameCounter = 0;
    frameCounter++;
    
    if (frameCounter % 30 == 0) { // Log every 30 frames to avoid spam
        NSLog(@"[LC] 📹 SimpleSpoofDelegate: Frame %d - spoofing: %@, output: %@", 
              frameCounter, spoofCameraEnabled ? @"ON" : @"OFF", NSStringFromClass([output class]));
    }
    
    @try {
        // DEFENSIVE: Track format from REAL frames with null checks
        if (sampleBuffer) {
            CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
            if (formatDesc) {
                OSType mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
                if (mediaSubType != lastRequestedFormat) {
                    lastRequestedFormat = mediaSubType;
                }
            }

            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
            if (imageBuffer) {
                size_t width = CVPixelBufferGetWidth(imageBuffer);
                size_t height = CVPixelBufferGetHeight(imageBuffer);
                if (width > 0 && height > 0) {
                    if (!resolutionDetected ||
                        (size_t)targetResolution.width != width ||
                        (size_t)targetResolution.height != height) {
                        targetResolution = CGSizeMake((CGFloat)width, (CGFloat)height);
                    }
                    resolutionDetected = YES;
                }
            }
        }
        
        if (spoofCameraEnabled) {
            if (frameCounter % 30 == 0) {
                NSLog(@"[LC] 🎬 SimpleSpoofDelegate: Creating spoofed frame %d", frameCounter);
            }
            
            CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
            if (spoofedFrame) {
                if (frameCounter % 30 == 0) {
                    NSLog(@"[LC] ✅ SimpleSpoofDelegate: Spoofed frame %d created successfully", frameCounter);
                }
                
                if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                    [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:spoofedFrame fromConnection:connection];
                    if (frameCounter % 30 == 0) {
                        NSLog(@"[LC] ✅ SimpleSpoofDelegate: Spoofed frame %d delivered", frameCounter);
                    }
                } else {
                    NSLog(@"[LC] ❌ SimpleSpoofDelegate: No valid delegate for frame %d", frameCounter);
                }
                CFRelease(spoofedFrame);
            } else {
                NSLog(@"[LC] ❌ SimpleSpoofDelegate: Failed to create spoofed frame %d - trying lastGoodSpoofedPixelBuffer", frameCounter);
                // FALLBACK: Use lastGoodSpoofedPixelBuffer instead of real camera (NEVER show real camera)
                CMSampleBufferRef fallbackFrame = nil;
                if (lastGoodSpoofedPixelBuffer) {
                    CMVideoFormatDescriptionRef videoInfo = NULL;
                    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, &videoInfo);
                    if (videoInfo) {
                        CMSampleTimingInfo timing = {0};
                        timing.duration = CMTimeMake(1, 30);
                        timing.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
                        timing.decodeTimeStamp = kCMTimeInvalid;
                        
                        OSStatus status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, true, NULL, NULL, videoInfo, &timing, &fallbackFrame);
                        CFRelease(videoInfo);
                        
                        if (status == noErr && fallbackFrame) {
                            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:fallbackFrame fromConnection:connection];
                                NSLog(@"[LC] ⚠️ SimpleSpoofDelegate: Used lastGoodSpoofedPixelBuffer for frame %d", frameCounter);
                            }
                            CFRelease(fallbackFrame);
                        }
                    }
                }
                // If fallback also fails, drop the frame entirely (never show real camera)
                if (!fallbackFrame) {
                    NSLog(@"[LC] ⚠️ SimpleSpoofDelegate: Dropped frame %d - no fallback available (protecting real camera)", frameCounter);
                }
            }
        } else {
            if (frameCounter % 30 == 0) {
                NSLog(@"[LC] 📹 SimpleSpoofDelegate: Spoofing disabled - passing through frame %d", frameCounter);
            }
            if (self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:sampleBuffer fromConnection:connection];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ SimpleSpoofDelegate: Exception in frame %d: %@", frameCounter, exception);
        // On exception, try to use lastGoodSpoofedPixelBuffer (NEVER show real camera)
        @try {
            if (lastGoodSpoofedPixelBuffer && self.originalDelegate && [self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                CMVideoFormatDescriptionRef videoInfo = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, &videoInfo);
                if (videoInfo) {
                    CMSampleTimingInfo timing = {0};
                    timing.duration = CMTimeMake(1, 30);
                    timing.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
                    timing.decodeTimeStamp = kCMTimeInvalid;
                    
                    CMSampleBufferRef fallbackFrame = nil;
                    OSStatus status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, lastGoodSpoofedPixelBuffer, true, NULL, NULL, videoInfo, &timing, &fallbackFrame);
                    CFRelease(videoInfo);
                    
                    if (status == noErr && fallbackFrame) {
                        [self.originalDelegate captureOutput:self.originalOutput didOutputSampleBuffer:fallbackFrame fromConnection:connection];
                        CFRelease(fallbackFrame);
                        NSLog(@"[LC] ⚠️ SimpleSpoofDelegate: Exception recovery - used lastGoodSpoofedPixelBuffer for frame %d", frameCounter);
                    } else {
                        NSLog(@"[LC] ⚠️ SimpleSpoofDelegate: Exception recovery failed - dropped frame %d", frameCounter);
                    }
                }
            } else {
                NSLog(@"[LC] ⚠️ SimpleSpoofDelegate: Exception recovery - no lastGoodSpoofedPixelBuffer, dropped frame %d", frameCounter);
            }
        } @catch (NSException *innerException) {
            NSLog(@"[LC] ❌❌ SimpleSpoofDelegate: Double exception in frame %d - dropped frame: %@", frameCounter, innerException);
        }
    }
}
@end

// pragma MARK: - LEVEL 1: Core Video Hooks (Lowest Level)

CVReturn hook_CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut) {
    NSLog(@"[LC] 🔧 L1: CVPixelBufferCreate called - %zux%zu, format: %c%c%c%c", 
          width, height,
          (pixelFormatType >> 24) & 0xFF, (pixelFormatType >> 16) & 0xFF, 
          (pixelFormatType >> 8) & 0xFF, pixelFormatType & 0xFF);
    
    if (spoofCameraEnabled && width > 0 && height > 0) {
        NSLog(@"[LC] 🔧 L1: Intercepting CVPixelBuffer creation: %zux%zu", width, height);
        
        CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
        if (spoofedFrame) {
            CVImageBufferRef spoofedBuffer = CMSampleBufferGetImageBuffer(spoofedFrame);
            if (spoofedBuffer) {
                *pixelBufferOut = CVPixelBufferRetain(spoofedBuffer);
                CFRelease(spoofedFrame);
                NSLog(@"[LC] ✅ L1: Returned spoofed pixel buffer");
                return kCVReturnSuccess;
            }
            CFRelease(spoofedFrame);
        }
        NSLog(@"[LC] ❌ L1: Failed to create spoofed buffer, using original");
    } else {
        NSLog(@"[LC] 🔧 L1: Passing through original CVPixelBufferCreate");
    }
    
    CVReturn result = original_CVPixelBufferCreate(allocator, width, height, pixelFormatType, pixelBufferAttributes, pixelBufferOut);
    NSLog(@"[LC] 🔧 L1: Original CVPixelBufferCreate result: %d", result);
    return result;
}

// pragma MARK: - PRIVATE PIPELINE HOOKS (BTATM-style fallback)

static IMP original_BWGraph_start = NULL;
static IMP original_BWGraph_stop = NULL;
static IMP original_FigVideoCaptureConnectionConfiguration_setOutputFormat = NULL;
static IMP original_FigVideoCaptureConnectionConfiguration_setOutputWidth = NULL;
static IMP original_FigVideoCaptureConnectionConfiguration_setOutputHeight = NULL;
static IMP original_BWNodeOutput_emitSampleBuffer = NULL;
static IMP original_BWMetadataSourceNode_appendMetadataSampleBuffer = NULL;
static IMP original_BWPixelTransferNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWUBNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWStillImageScalerNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWPhotoEncoderNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWMetadataDetectorGatingNode_renderSampleBuffer_forInput = NULL;
static IMP original_BWVideoOrientationMetadataNode_renderSampleBuffer_forInput = NULL;

static BOOL shouldReplacePrivateRenderStages(void) {
    if (!spoofCameraEnabled) {
        return NO;
    }
    return [spoofCameraMode isEqualToString:@"aggressive"] || [spoofCameraMode isEqualToString:@"compatibility"];
}

static void updateCaptureHintsFromSampleBuffer(CMSampleBufferRef sampleBuffer) {
    if (!sampleBuffer) {
        return;
    }

    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDesc) {
        OSType mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
        if (isValidPixelFormat(mediaSubType)) {
            lastRequestedFormat = mediaSubType;
        }
    }

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) {
        return;
    }

    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    if (width == 0 || height == 0) {
        return;
    }

    if (!resolutionDetected ||
        (size_t)targetResolution.width != width ||
        (size_t)targetResolution.height != height) {
        targetResolution = CGSizeMake((CGFloat)width, (CGFloat)height);
    }
    resolutionDetected = YES;
}

static CMSampleBufferRef createPrivatePipelineSpoofedSampleBuffer(CMSampleBufferRef originalSampleBuffer) {
    if (!spoofCameraEnabled || !originalSampleBuffer) {
        return NULL;
    }

    // Only replace true image sample buffers.
    if (!CMSampleBufferGetImageBuffer(originalSampleBuffer)) {
        return NULL;
    }

    @try {
        CMSampleBufferRef spoofedFrame = [GetFrame getCurrentFrame:originalSampleBuffer preserveOrientation:YES];
        if (spoofedFrame) {
            return spoofedFrame;
        }
        return createSpoofedSampleBuffer();
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Private pipeline frame creation failed: %@", exception);
        return NULL;
    }
}

static BOOL installPrivateInstanceHook(NSString *className, NSString *selectorName, IMP replacement, IMP *originalOut) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        return NO;
    }

    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        return NO;
    }

    IMP current = method_getImplementation(method);
    if (current == replacement) {
        return YES;
    }

    const char *typeEncoding = method_getTypeEncoding(method);
    BOOL addedClassOverride = class_addMethod(cls, selector, replacement, typeEncoding);
    if (!addedClassOverride) {
        method_setImplementation(method, replacement);
    }

    if (originalOut) {
        *originalOut = current;
    }
    NSLog(@"[LC] ✅ Private camera hook installed: %@ %@", className, selectorName);
    return YES;
}

static uintptr_t lc_BWGraph_start(id self, SEL _cmd, id arg) {
    if (spoofCameraEnabled) {
        cleanupPhotoCache();
    }
    if (!original_BWGraph_start) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, id))original_BWGraph_start)(self, _cmd, arg);
}

static uintptr_t lc_BWGraph_stop(id self, SEL _cmd, id arg) {
    if (spoofCameraEnabled) {
        cleanupPhotoCache();
    }
    if (!original_BWGraph_stop) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, id))original_BWGraph_stop)(self, _cmd, arg);
}

static uintptr_t lc_FigVideoCaptureConnectionConfiguration_setOutputFormat(id self, SEL _cmd, OSType outputFormat) {
    if (isValidPixelFormat(outputFormat)) {
        lastRequestedFormat = outputFormat;
    }
    if (!original_FigVideoCaptureConnectionConfiguration_setOutputFormat) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, OSType))original_FigVideoCaptureConnectionConfiguration_setOutputFormat)(self, _cmd, outputFormat);
}

static uintptr_t lc_FigVideoCaptureConnectionConfiguration_setOutputWidth(id self, SEL _cmd, int outputWidth) {
    if (outputWidth > 0) {
        CGFloat height = targetResolution.height > 0 ? targetResolution.height : 1920.0;
        targetResolution = CGSizeMake((CGFloat)outputWidth, height);
        resolutionDetected = YES;
    }
    if (!original_FigVideoCaptureConnectionConfiguration_setOutputWidth) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, int))original_FigVideoCaptureConnectionConfiguration_setOutputWidth)(self, _cmd, outputWidth);
}

static uintptr_t lc_FigVideoCaptureConnectionConfiguration_setOutputHeight(id self, SEL _cmd, int outputHeight) {
    if (outputHeight > 0) {
        CGFloat width = targetResolution.width > 0 ? targetResolution.width : 1080.0;
        targetResolution = CGSizeMake(width, (CGFloat)outputHeight);
        resolutionDetected = YES;
    }
    if (!original_FigVideoCaptureConnectionConfiguration_setOutputHeight) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, int))original_FigVideoCaptureConnectionConfiguration_setOutputHeight)(self, _cmd, outputHeight);
}

static uintptr_t lc_BWNodeOutput_emitSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sampleBuffer) {
    updateCaptureHintsFromSampleBuffer(sampleBuffer);

    CMSampleBufferRef spoofedFrame = createPrivatePipelineSpoofedSampleBuffer(sampleBuffer);
    CMSampleBufferRef forwardedFrame = spoofedFrame ? spoofedFrame : sampleBuffer;

    uintptr_t result = 0;
    if (original_BWNodeOutput_emitSampleBuffer) {
        result = ((uintptr_t (*)(id, SEL, CMSampleBufferRef))original_BWNodeOutput_emitSampleBuffer)(self, _cmd, forwardedFrame);
    }

    if (spoofedFrame) {
        CFRelease(spoofedFrame);
    }
    return result;
}

static uintptr_t lc_BWMetadataSourceNode_appendMetadataSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sampleBuffer) {
    updateCaptureHintsFromSampleBuffer(sampleBuffer);
    if (!original_BWMetadataSourceNode_appendMetadataSampleBuffer) {
        return 0;
    }
    return ((uintptr_t (*)(id, SEL, CMSampleBufferRef))original_BWMetadataSourceNode_appendMetadataSampleBuffer)(self, _cmd, sampleBuffer);
}

#define DEFINE_PRIVATE_RENDER_HOOK(hook_name, original_imp) \
static uintptr_t hook_name(id self, SEL _cmd, CMSampleBufferRef sampleBuffer, id input) { \
    updateCaptureHintsFromSampleBuffer(sampleBuffer); \
    CMSampleBufferRef spoofedFrame = NULL; \
    if (shouldReplacePrivateRenderStages()) { \
        spoofedFrame = createPrivatePipelineSpoofedSampleBuffer(sampleBuffer); \
    } \
    CMSampleBufferRef forwardedFrame = spoofedFrame ? spoofedFrame : sampleBuffer; \
    uintptr_t result = 0; \
    if (original_imp) { \
        result = ((uintptr_t (*)(id, SEL, CMSampleBufferRef, id))original_imp)(self, _cmd, forwardedFrame, input); \
    } \
    if (spoofedFrame) { \
        CFRelease(spoofedFrame); \
    } \
    return result; \
}

DEFINE_PRIVATE_RENDER_HOOK(lc_BWPixelTransferNode_renderSampleBuffer_forInput, original_BWPixelTransferNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWNode_renderSampleBuffer_forInput, original_BWNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWUBNode_renderSampleBuffer_forInput, original_BWUBNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWStillImageScalerNode_renderSampleBuffer_forInput, original_BWStillImageScalerNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWPhotoEncoderNode_renderSampleBuffer_forInput, original_BWPhotoEncoderNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWMetadataDetectorGatingNode_renderSampleBuffer_forInput, original_BWMetadataDetectorGatingNode_renderSampleBuffer_forInput)
DEFINE_PRIVATE_RENDER_HOOK(lc_BWVideoOrientationMetadataNode_renderSampleBuffer_forInput, original_BWVideoOrientationMetadataNode_renderSampleBuffer_forInput)

#undef DEFINE_PRIVATE_RENDER_HOOK

static void installPrivateCapturePipelineHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Match BTATM strategy: load private camera frameworks before trying class hooks.
        (void)dlopen("/System/Library/PrivateFrameworks/CMCaptureCore.framework/CMCaptureCore", RTLD_LAZY);
        (void)dlopen("/System/Library/PrivateFrameworks/CMCapture.framework/CMCapture", RTLD_LAZY);

        NSUInteger installedCount = 0;

        installedCount += installPrivateInstanceHook(@"BWGraph", @"start:", (IMP)lc_BWGraph_start, &original_BWGraph_start) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWGraph", @"stop:", (IMP)lc_BWGraph_stop, &original_BWGraph_stop) ? 1 : 0;

        installedCount += installPrivateInstanceHook(@"FigVideoCaptureConnectionConfiguration",
                                                     @"setOutputFormat:",
                                                     (IMP)lc_FigVideoCaptureConnectionConfiguration_setOutputFormat,
                                                     &original_FigVideoCaptureConnectionConfiguration_setOutputFormat) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"FigVideoCaptureConnectionConfiguration",
                                                     @"setOutputWidth:",
                                                     (IMP)lc_FigVideoCaptureConnectionConfiguration_setOutputWidth,
                                                     &original_FigVideoCaptureConnectionConfiguration_setOutputWidth) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"FigVideoCaptureConnectionConfiguration",
                                                     @"setOutputHeight:",
                                                     (IMP)lc_FigVideoCaptureConnectionConfiguration_setOutputHeight,
                                                     &original_FigVideoCaptureConnectionConfiguration_setOutputHeight) ? 1 : 0;

        installedCount += installPrivateInstanceHook(@"BWNodeOutput",
                                                     @"emitSampleBuffer:",
                                                     (IMP)lc_BWNodeOutput_emitSampleBuffer,
                                                     &original_BWNodeOutput_emitSampleBuffer) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWMetadataSourceNode",
                                                     @"appendMetadataSampleBuffer:",
                                                     (IMP)lc_BWMetadataSourceNode_appendMetadataSampleBuffer,
                                                     &original_BWMetadataSourceNode_appendMetadataSampleBuffer) ? 1 : 0;

        installedCount += installPrivateInstanceHook(@"BWPixelTransferNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWPixelTransferNode_renderSampleBuffer_forInput,
                                                     &original_BWPixelTransferNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWNode_renderSampleBuffer_forInput,
                                                     &original_BWNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWUBNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWUBNode_renderSampleBuffer_forInput,
                                                     &original_BWUBNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWStillImageScalerNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWStillImageScalerNode_renderSampleBuffer_forInput,
                                                     &original_BWStillImageScalerNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWPhotoEncoderNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWPhotoEncoderNode_renderSampleBuffer_forInput,
                                                     &original_BWPhotoEncoderNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWMetadataDetectorGatingNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWMetadataDetectorGatingNode_renderSampleBuffer_forInput,
                                                     &original_BWMetadataDetectorGatingNode_renderSampleBuffer_forInput) ? 1 : 0;
        installedCount += installPrivateInstanceHook(@"BWVideoOrientationMetadataNode",
                                                     @"renderSampleBuffer:forInput:",
                                                     (IMP)lc_BWVideoOrientationMetadataNode_renderSampleBuffer_forInput,
                                                     &original_BWVideoOrientationMetadataNode_renderSampleBuffer_forInput) ? 1 : 0;

        if (installedCount > 0) {
            NSLog(@"[LC] ✅ Private camera pipeline hooks active (%lu)", (unsigned long)installedCount);
        } else {
            NSLog(@"[LC] ℹ️ Private camera pipeline classes unavailable in this process");
        }
    });
}

// pragma MARK: - LEVEL 2: Device Level Hooks

@implementation AVCaptureDevice(LiveContainerSpoof)

+ (NSArray<AVCaptureDevice *> *)lc_devicesWithMediaType:(AVMediaType)mediaType {
    NSLog(@"[LC] 🎥 L2: devicesWithMediaType called - mediaType: %@", mediaType);
    
    NSArray *originalDevices = [self lc_devicesWithMediaType:mediaType];
    
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L2: Video device enumeration - %lu devices found", (unsigned long)originalDevices.count);
        for (AVCaptureDevice *device in originalDevices) {
            NSLog(@"[LC] 🎥 L2: Device: %@ (pos: %ld)", device.localizedName, (long)device.position);
        }
    } else {
        NSLog(@"[LC] 🎥 L2: Non-video device enumeration: %@ - %lu devices", mediaType, (unsigned long)originalDevices.count);
    }
    
    return originalDevices;
}

+ (AVCaptureDevice *)lc_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    NSLog(@"[LC] 🎥 L2: defaultDeviceWithMediaType called - mediaType: %@", mediaType);
    
    AVCaptureDevice *originalDevice = [self lc_defaultDeviceWithMediaType:mediaType];
    
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L2: Default video device: %@ (pos: %ld)", 
              originalDevice.localizedName, (long)originalDevice.position);
    } else {
        NSLog(@"[LC] 🎥 L2: Default non-video device: %@ for type: %@", 
              originalDevice.localizedName, mediaType);
    }
    
    return originalDevice;
}

@end

// pragma MARK: - LEVEL 3: Device Input Level Hooks

@implementation AVCaptureDeviceInput(LiveContainerSpoof)

+ (instancetype)lc_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    NSLog(@"[LC] 🎥 L3: deviceInputWithDevice called - device: %@", device.localizedName);
    
    if (device && [device hasMediaType:AVMediaTypeVideo]) {
        NSLog(@"[LC] 🎥 L3: Creating video device input: %@ (pos: %ld)", 
              device.localizedName, (long)device.position);
        
        AVCaptureDeviceInput *originalInput = [self lc_deviceInputWithDevice:device error:outError];
        if (originalInput) {
            NSLog(@"[LC] ✅ L3: Video device input created successfully");
            if (spoofCameraEnabled) {
                objc_setAssociatedObject(originalInput, @selector(lc_deviceInputWithDevice:error:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                NSLog(@"[LC] 🏷️ L3: Marked input for spoofing");
            }
        } else {
            NSLog(@"[LC] ❌ L3: Failed to create video device input - error: %@", outError ? *outError : nil);
        }
        return originalInput;
    } else if (device) {
        NSLog(@"[LC] 🎥 L3: Creating non-video device input: %@ (type: %@)", 
              device.localizedName, [device hasMediaType:AVMediaTypeAudio] ? @"Audio" : @"Unknown");
    } else {
        NSLog(@"[LC] ❌ L3: deviceInputWithDevice called with nil device");
    }
    
    AVCaptureDeviceInput *result = [self lc_deviceInputWithDevice:device error:outError];
    NSLog(@"[LC] 🎥 L3: deviceInputWithDevice completed - success: %@", result ? @"YES" : @"NO");
    return result;
}

@end

// pragma MARK: - LEVEL 4: Session Level Hooks

@implementation AVCaptureSession(LiveContainerSpoof)

- (void)lc_addInput:(AVCaptureInput *)input {
    if (spoofCameraEnabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        
        // CRITICAL: Track camera position for photo orientation
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            g_currentCameraPosition = deviceInput.device.position;
            NSLog(@"[LC] 🎥 L4: Camera position updated: %s", 
                  (g_currentCameraPosition == AVCaptureDevicePositionFront) ? "FRONT" : "BACK");
        }
        
        NSLog(@"[LC] 🎥 L4: Intercepting session input: %@ (pos: %ld)", 
              deviceInput.device.localizedName, (long)deviceInput.device.position);
        
        objc_setAssociatedObject(self, @selector(lc_addInput:), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self lc_addInput:input];
}

- (void)lc_addOutput:(AVCaptureOutput *)output {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📹 L4: Intercepting session output: %@", NSStringFromClass([output class]));
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            NSLog(@"[LC] Video data output detected");
        } else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            NSLog(@"[LC] Photo output detected");
            configurePhotoOutputForSpoofing((AVCapturePhotoOutput *)output, @"L4 addOutput");
        } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
            NSLog(@"[LC] Movie file output detected");
        }
    }
    [self lc_addOutput:output];
}

- (void)lc_setSessionPreset:(AVCaptureSessionPreset)sessionPreset {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 📐 L4: Session preset change: %@", sessionPreset);
        // Track format preferences from preset
        if ([sessionPreset isEqualToString:AVCaptureSessionPresetPhoto]) {
            lastRequestedFormat = kCVPixelFormatType_32BGRA;
        } else if ([sessionPreset isEqualToString:AVCaptureSessionPresetHigh]) {
            lastRequestedFormat = 875704422; // '420v'
        }
    }
    [self lc_setSessionPreset:sessionPreset];
}

- (void)lc_startRunning {
    NSLog(@"[LC] 🎥 L4: Session startRunning called - spoofing: %@", spoofCameraEnabled ? @"ON" : @"OFF");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎥 L4: Session starting - checking for camera inputs");
        NSLog(@"[LC] 🔍 DEBUG L4: Session inputs count: %lu", (unsigned long)self.inputs.count);
        NSLog(@"[LC] 🔍 DEBUG L4: Session outputs count: %lu", (unsigned long)self.outputs.count);
        
        BOOL hasCameraInput = NO;
        BOOL hasVideoDataOutput = NO;
        BOOL hasAudioDataOutput = NO;
        BOOL hasPhotoOutput = NO;
        BOOL hasMovieFileOutput = NO;
        
        for (AVCaptureInput *input in self.inputs) {
            NSLog(@"[LC] 🔍 DEBUG L4: Input: %@", NSStringFromClass([input class]));
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                NSLog(@"[LC] 🔍 DEBUG L4: Device input: %@ (hasVideo: %@)", 
                      deviceInput.device.localizedName, [deviceInput.device hasMediaType:AVMediaTypeVideo] ? @"YES" : @"NO");
                if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                    hasCameraInput = YES;
                }
            }
        }
        
        for (AVCaptureOutput *output in self.outputs) {
            NSLog(@"[LC] 🔍 DEBUG L4: Output: %@", NSStringFromClass([output class]));
            if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                hasVideoDataOutput = YES;
                
                AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                id delegate = videoOutput.sampleBufferDelegate;
                NSLog(@"[LC] 🔍 DEBUG L4: VideoDataOutput delegate: %@", NSStringFromClass([delegate class]));
                
                // Check if our wrapper is in place
                SimpleSpoofDelegate *wrapper = objc_getAssociatedObject(videoOutput, @selector(lc_setSampleBufferDelegate:queue:));
                if (wrapper) {
                    NSLog(@"[LC] ✅ L4: Our SimpleSpoofDelegate wrapper is in place: %@", wrapper);
                } else {
                    NSLog(@"[LC] ❌ L4: No SimpleSpoofDelegate wrapper found!");
                }
            } else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
                hasAudioDataOutput = YES;
                AVCaptureAudioDataOutput *audioOutput = (AVCaptureAudioDataOutput *)output;
                id delegate = audioOutput.sampleBufferDelegate;
                NSLog(@"[LC] 🔍 DEBUG L4: AudioDataOutput delegate: %@", NSStringFromClass([delegate class]));
            } else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
                hasPhotoOutput = YES;
                configurePhotoOutputForSpoofing((AVCapturePhotoOutput *)output, @"L4 startRunning");
            } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
                hasMovieFileOutput = YES;
            }
        }
        
        NSLog(@"[LC] 🔍 DEBUG L4: Camera input: %@, VideoData output: %@, AudioData output: %@, Photo output: %@, Movie output: %@",
              hasCameraInput ? @"YES" : @"NO",
              hasVideoDataOutput ? @"YES" : @"NO",
              hasAudioDataOutput ? @"YES" : @"NO",
              hasPhotoOutput ? @"YES" : @"NO",
              hasMovieFileOutput ? @"YES" : @"NO");
        
        if (hasCameraInput) {
            NSLog(@"[LC] 🎥 L4: Camera session detected - spoofing will be active");
            g_captureGestureArbitrationEnabled = hasPhotoOutput && hasMovieFileOutput;
            if (!g_captureGestureArbitrationEnabled) {
                LCCancelPendingDeferredPhotoCapture();
            }
            NSLog(@"[LC] 📷 L4: Capture arbitration (photo vs record) %@", g_captureGestureArbitrationEnabled ? @"ENABLED" : @"DISABLED");
            
            // CRITICAL: ALWAYS pre-cache photo data for ALL camera sessions
            NSLog(@"[LC] 📷 L4: FORCE caching spoofed photo data");
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                cachePhotoDataFromSampleBuffer(NULL);
                NSLog(@"[LC] 📷 L4: Photo cache creation completed");
            });
            
            if (hasPhotoOutput) {
                NSLog(@"[LC] 📷 L4: Photo output detected - additional caching");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    cachePhotoDataFromSampleBuffer(NULL);
                    NSLog(@"[LC] 📷 L4: Additional photo cache completed");
                });
            }
            
            if (!hasVideoDataOutput) {
                NSLog(@"[LC] ⚠️ L4: Camera session has no video data output - this might be why we see original camera");
            }
        } else {
            NSLog(@"[LC] 🔍 DEBUG L4: No camera input detected");
            g_captureGestureArbitrationEnabled = NO;
            LCCancelPendingDeferredPhotoCapture();
        }
    }
    
    NSLog(@"[LC] 🎥 L4: Calling original startRunning");
    [self lc_startRunning];
    NSLog(@"[LC] 🎥 L4: startRunning completed");
}

- (void)lc_stopRunning {
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎥 L4: Session stopping - cleaning up spoofed resources");
        
        // Clean up photo cache when session stops.
        cleanupPhotoCache();
        cleanupAudioSpoofingResources();
        g_captureGestureArbitrationEnabled = NO;
        LCCancelPendingDeferredPhotoCapture();
        
        // Clean up any preview layer associations
        objc_setAssociatedObject(self, @selector(lc_addInput:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self lc_stopRunning];
}

@end

// pragma MARK: - LEVEL 5: Output Level Hooks

@interface SimpleSpoofAudioDelegate : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id<AVCaptureAudioDataOutputSampleBufferDelegate> originalDelegate;
- (instancetype)initWithDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)delegate;
@end

@implementation SimpleSpoofAudioDelegate

- (instancetype)initWithDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)delegate {
    if (self = [super init]) {
        _originalDelegate = delegate;
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    static NSUInteger audioFrameCounter = 0;
    audioFrameCounter++;

    CMSampleBufferRef spoofedAudioSampleBuffer = NULL;
    CMSampleBufferRef forwardedSampleBuffer = sampleBuffer;
    if (spoofCameraEnabled && spoofCameraUseVideoAudio) {
        spoofedAudioSampleBuffer = copyNextSpoofedAudioSampleBuffer();
        if (spoofedAudioSampleBuffer) {
            CMSampleBufferRef alignedAudioSampleBuffer = createAudioSampleBufferAlignedToReference(spoofedAudioSampleBuffer,
                                                                                                   sampleBuffer);
            if (alignedAudioSampleBuffer) {
                CFRelease(spoofedAudioSampleBuffer);
                spoofedAudioSampleBuffer = alignedAudioSampleBuffer;
                forwardedSampleBuffer = spoofedAudioSampleBuffer;
            } else {
                forwardedSampleBuffer = sampleBuffer;
            }
        }
    }

    if (audioFrameCounter % 120 == 0) {
        NSLog(@"[LC] 🔊 Audio delegate frame %lu forwarded (%s)",
              (unsigned long)audioFrameCounter,
              (spoofedAudioSampleBuffer ? "SPOOFED" : "ORIGINAL"));
    }

    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate captureOutput:output
                      didOutputSampleBuffer:forwardedSampleBuffer
                             fromConnection:connection];
    }

    if (spoofedAudioSampleBuffer) {
        CFRelease(spoofedAudioSampleBuffer);
    }
}

@end

@implementation AVCaptureVideoDataOutput(LiveContainerSpoof)

- (void)lc_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] 🔍 DEBUG L5: setSampleBufferDelegate called - delegate: %@, spoofing: %@", 
          NSStringFromClass([sampleBufferDelegate class]), spoofCameraEnabled ? @"ON" : @"OFF");
    
    if (spoofCameraEnabled && sampleBufferDelegate) {
        NSLog(@"[LC] 📹 L5: Creating SimpleSpoofDelegate wrapper for: %@", NSStringFromClass([sampleBufferDelegate class]));
        
        // IMPROVEMENT: Detect preferred format from output settings
        NSDictionary *videoSettings = self.videoSettings;
        if (videoSettings) {
            NSNumber *formatNum = videoSettings[(NSString*)kCVPixelBufferPixelFormatTypeKey];
            if (formatNum) {
                lastRequestedFormat = [formatNum unsignedIntValue];
                NSLog(@"[LC] 📐 Output requests format: %c%c%c%c", 
                      (lastRequestedFormat >> 24) & 0xFF, (lastRequestedFormat >> 16) & 0xFF, 
                      (lastRequestedFormat >> 8) & 0xFF, lastRequestedFormat & 0xFF);
            }
        }
        
        // Create wrapper and store reference
        SimpleSpoofDelegate *wrapper = [[SimpleSpoofDelegate alloc] initWithDelegate:sampleBufferDelegate output:self];
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        NSLog(@"[LC] ✅ L5: SimpleSpoofDelegate wrapper created: %@", wrapper);
        NSLog(@"[LC] 🔗 L5: Setting wrapper as delegate instead of original");
        
        [self lc_setSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
        
        NSLog(@"[LC] ✅ L5: Video hook installation completed");
    } else {
        NSLog(@"[LC] 📹 L5: Spoofing disabled or no delegate - using original");
        objc_setAssociatedObject(self, @selector(lc_setSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    }
}
@end

@implementation AVCaptureAudioDataOutput(LiveContainerSpoof)

- (void)lc_setAudioSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate
                                  queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[LC] 🔊 L5: setAudioSampleBufferDelegate called - delegate: %@, spoofing: %@",
          NSStringFromClass([sampleBufferDelegate class]),
          spoofCameraEnabled ? @"ON" : @"OFF");

    if (spoofCameraEnabled && spoofCameraUseVideoAudio && sampleBufferDelegate) {
        SimpleSpoofAudioDelegate *wrapper = [[SimpleSpoofAudioDelegate alloc] initWithDelegate:sampleBufferDelegate];
        objc_setAssociatedObject(self, @selector(lc_setAudioSampleBufferDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setAudioSampleBufferDelegate:wrapper queue:sampleBufferCallbackQueue];
        NSLog(@"[LC] ✅ L5: Audio delegate wrapper installed");
    } else {
        objc_setAssociatedObject(self, @selector(lc_setAudioSampleBufferDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setAudioSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
        NSLog(@"[LC] 🔊 L5: Audio spoofing disabled or no delegate - using original");
    }
}

@end

@interface SimpleSpoofSynchronizerDelegate : NSObject <AVCaptureDataOutputSynchronizerDelegate>
@property (nonatomic, strong) id<AVCaptureDataOutputSynchronizerDelegate> originalDelegate;
- (instancetype)initWithDelegate:(id<AVCaptureDataOutputSynchronizerDelegate>)delegate;
@end

@implementation SimpleSpoofSynchronizerDelegate

- (instancetype)initWithDelegate:(id<AVCaptureDataOutputSynchronizerDelegate>)delegate {
    if (self = [super init]) {
        _originalDelegate = delegate;
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    return [self.originalDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (void)dataOutputSynchronizer:(AVCaptureDataOutputSynchronizer *)synchronizer
didOutputSynchronizedDataCollection:(AVCaptureSynchronizedDataCollection *)synchronizedDataCollection {
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate dataOutputSynchronizer:synchronizer didOutputSynchronizedDataCollection:synchronizedDataCollection];
    }
}

@end

@implementation AVCaptureDataOutputSynchronizer(LiveContainerSpoof)

- (void)lc_setDelegate:(id<AVCaptureDataOutputSynchronizerDelegate>)delegate
                 queue:(dispatch_queue_t)delegateCallbackQueue {
    NSLog(@"[LC] 🎯 L5: DataOutputSynchronizer setDelegate called - delegate: %@, spoofing: %@",
          NSStringFromClass([delegate class]),
          spoofCameraEnabled ? @"ON" : @"OFF");

    if (spoofCameraEnabled && delegate) {
        SimpleSpoofSynchronizerDelegate *wrapper = [[SimpleSpoofSynchronizerDelegate alloc] initWithDelegate:delegate];
        objc_setAssociatedObject(self, @selector(lc_setDelegate:queue:), wrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setDelegate:wrapper queue:delegateCallbackQueue];
        NSLog(@"[LC] ✅ L5: DataOutputSynchronizer delegate wrapper installed");
    } else {
        objc_setAssociatedObject(self, @selector(lc_setDelegate:queue:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lc_setDelegate:delegate queue:delegateCallbackQueue];
    }
}

@end

@implementation AVAssetWriter(LiveContainerSpoof)

- (instancetype)lc_initWithURL:(NSURL *)outputURL fileType:(AVFileType)outputFileType error:(NSError **)outError {
    NSLog(@"[LC] 🎬 DIAGNOSTIC: AVAssetWriter init - URL: %@, type: %@", outputURL.lastPathComponent, outputFileType);
    
    if ([outputURL.pathExtension.lowercaseString isEqualToString:@"mp4"] || 
        [outputURL.pathExtension.lowercaseString isEqualToString:@"mov"]) {
        NSLog(@"[LC] 🎯 DIAGNOSTIC: Video file creation detected via AVAssetWriter!");
    }
    
    return [self lc_initWithURL:outputURL fileType:outputFileType error:outError];
}

- (BOOL)lc_startWriting {
    NSLog(@"[LC] 🎬 DIAGNOSTIC: AVAssetWriter startWriting called");
    return [self lc_startWriting];
}

- (BOOL)lc_finishWriting {
    NSLog(@"[LC] 🎬 DIAGNOSTIC: AVAssetWriter finishWriting called");
    return [self lc_finishWriting];
}

@end

@implementation NSFileManager(LiveContainerSpoof)

- (BOOL)lc_createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSFileAttributeKey, id> *)attr {
    if ([path.pathExtension.lowercaseString isEqualToString:@"mp4"] || 
        [path.pathExtension.lowercaseString isEqualToString:@"mov"]) {
        NSLog(@"[LC] 🎬 DIAGNOSTIC: Video file creation at path: %@", path.lastPathComponent);
    }
    
    return [self lc_createFileAtPath:path contents:data attributes:attr];
}

@end

@implementation AVCapturePhotoOutput(LiveContainerSpoof)

- (void)lc_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    id<AVCapturePhotoCaptureDelegate> effectiveDelegate = delegate;

    if (spoofCameraEnabled) {
        configurePhotoOutputForSpoofing(self, @"L5 capturePhoto");
        NSLog(@"[LC] 📷 L5: Photo capture intercepted - Mode: %@", spoofCameraMode);

        if (delegate && ![delegate isKindOfClass:[LCSpoofPhotoCaptureDelegate class]]) {
            LCSpoofPhotoCaptureDelegate *proxy = [[LCSpoofPhotoCaptureDelegate alloc] initWithDelegate:delegate photoOutput:self];
            objc_setAssociatedObject(self, @selector(lc_capturePhotoWithSettings:delegate:), proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            effectiveDelegate = (id<AVCapturePhotoCaptureDelegate>)proxy;
            NSLog(@"[LC] ✅ L5: Photo delegate wrapped for sample-buffer interception: %@", NSStringFromClass([delegate class]));
        }

        NSString *effectiveMode = spoofCameraMode ?: @"standard";
        if (![effectiveMode isEqualToString:@"standard"] &&
            ![effectiveMode isEqualToString:@"aggressive"] &&
            ![effectiveMode isEqualToString:@"compatibility"]) {
            NSLog(@"[LC] ⚠️ Unknown camera mode: %@, using standard", spoofCameraMode);
            effectiveMode = @"standard";
        }
        if (![effectiveMode isEqualToString:@"standard"]) {
            NSLog(@"[LC] 📸 Enhanced caching mode: %@", effectiveMode);
        }
        warmPhotoCacheAsyncForMode(effectiveMode);
        if ([effectiveMode isEqualToString:@"aggressive"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"[LC] 📷 Aggressive mode: Delayed verification complete");
            });
        }
        
        // Verify cache readiness based on mode
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (g_cachedPhotoPixelBuffer && g_cachedPhotoCGImage && g_cachedPhotoJPEGData) {
                NSLog(@"[LC] 📷 Mode %@: Photo cache verified ready", spoofCameraMode);
            } else {
                NSLog(@"[LC] ❌ Mode %@: Photo cache incomplete", spoofCameraMode);
            }
        });

        if (g_captureGestureArbitrationEnabled) {
            __weak AVCapturePhotoOutput *weakSelf = self;
            AVCapturePhotoSettings *capturedSettings = settings;
            id<AVCapturePhotoCaptureDelegate> capturedDelegate = effectiveDelegate;
            __block dispatch_block_t deferredCaptureBlock = nil;
            deferredCaptureBlock = dispatch_block_create(0, ^{
                AVCapturePhotoOutput *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                BOOL shouldSuppress = NO;
                CFAbsoluteTime elapsedSinceRecordStart = -1.0;
                @synchronized([AVCapturePhotoOutput class]) {
                    if (g_pendingDeferredPhotoCaptureBlock != deferredCaptureBlock) {
                        return;
                    }
                    g_pendingDeferredPhotoCaptureBlock = nil;
                    if (g_lastRecordingStartTime > 0) {
                        elapsedSinceRecordStart = CFAbsoluteTimeGetCurrent() - g_lastRecordingStartTime;
                        shouldSuppress = elapsedSinceRecordStart >= 0.0 &&
                                         elapsedSinceRecordStart < kPhotoSuppressionAfterRecordStartSeconds;
                    }
                }

                if (shouldSuppress) {
                    NSLog(@"[LC] 📷 L5: Suppressing deferred photo (record started %.3fs ago)", elapsedSinceRecordStart);
                    objc_setAssociatedObject(strongSelf, @selector(lc_capturePhotoWithSettings:delegate:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    return;
                }

                NSLog(@"[LC] 📷 L5: Executing deferred photo capture");
                [strongSelf lc_capturePhotoWithSettings:capturedSettings delegate:capturedDelegate];
            });

            @synchronized([AVCapturePhotoOutput class]) {
                if (g_pendingDeferredPhotoCaptureBlock) {
                    dispatch_block_cancel(g_pendingDeferredPhotoCaptureBlock);
                }
                g_pendingDeferredPhotoCaptureBlock = deferredCaptureBlock;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPhotoDeferralSeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(),
                           deferredCaptureBlock);
            return;
        }
    }
    
    [self lc_capturePhotoWithSettings:settings delegate:effectiveDelegate];
}

@end

@implementation AVCaptureStillImageOutput(LiveContainerSpoof)

- (void)lc_captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef imageDataSampleBuffer, NSError *error))handler {
    NSLog(@"[LC] 📷 L5: Legacy still image capture intercepted");
    
    if (spoofCameraEnabled && handler) {
        NSLog(@"[LC] 📷 L5: Providing spoofed still image");
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
            if (spoofedFrame) {
                NSLog(@"[LC] ✅ L5: Legacy still image spoofed successfully");
                handler(spoofedFrame, nil);
                CFRelease(spoofedFrame);
            } else {
                NSLog(@"[LC] ❌ L5: Failed to create spoofed still image");
                [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
            }
        });
    } else {
        NSLog(@"[LC] 📷 L5: Legacy still image - spoofing disabled or no handler");
        [self lc_captureStillImageAsynchronouslyFromConnection:connection completionHandler:handler];
    }
}

@end

@implementation AVCaptureMovieFileOutput(LiveContainerSpoof)

// Store original implementation pointer
static IMP original_startRecordingToOutputFileURL_IMP = NULL;
static IMP original_stopRecording_IMP = NULL;

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Store original implementations before swizzling
        Method startMethod = class_getInstanceMethod([AVCaptureMovieFileOutput class], @selector(startRecordingToOutputFileURL:recordingDelegate:));
        original_startRecordingToOutputFileURL_IMP = method_getImplementation(startMethod);
        
        Method stopMethod = class_getInstanceMethod([AVCaptureMovieFileOutput class], @selector(stopRecording));
        original_stopRecording_IMP = method_getImplementation(stopMethod);
    });
}

- (void)lc_startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    NSLog(@"[LC] 🎬 L5: Recording button pressed - URL: %@", outputFileURL.lastPathComponent);
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎬 L5: Spoofing enabled - creating fake recording");
        if (g_captureGestureArbitrationEnabled) {
            LCMarkRecordingStarted();
        }
        
        // CRITICAL: Don't call ANY version of startRecording to avoid real camera
        // Instead, immediately start our spoofing process
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            @try {
                BOOL success = NO;
                NSError *error = nil;
                
                if (spoofCameraVideoPath && [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath]) {
                    NSLog(@"[LC] 🎬 L5: Copying spoof video from: %@", spoofCameraVideoPath.lastPathComponent);
                    
                    // Ensure output directory exists
                    NSString *outputDir = outputFileURL.path.stringByDeletingLastPathComponent;
                    [[NSFileManager defaultManager] createDirectoryAtPath:outputDir 
                                                withIntermediateDirectories:YES 
                                                                 attributes:nil 
                                                                      error:nil];
                    
                    // Remove existing file
                    if ([[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path]) {
                        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
                    }
                    
                    // Copy spoof video
                    success = [[NSFileManager defaultManager] copyItemAtPath:spoofCameraVideoPath 
                                                                      toPath:outputFileURL.path 
                                                                       error:&error];
                    
                    if (success) {
                        NSLog(@"[LC] ✅ L5: Spoof video copied successfully");
                        
                        // Simulate recording delay (makes it feel more realistic)
                        [NSThread sleepForTimeInterval:0.5];
                        
                    } else {
                        NSLog(@"[LC] ❌ L5: Failed to copy spoof video: %@", error);
                    }
                } else {
                    // Create a simple black video if no spoof video available
                    NSLog(@"[LC] 🎬 L5: No spoof video - creating black video placeholder");
                    success = [self createBlackVideoAtURL:outputFileURL];
                }
                
                // CRITICAL: Always notify delegate on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (delegate) {
                        if ([delegate respondsToSelector:@selector(captureOutput:didStartRecordingToOutputFileAtURL:fromConnections:)]) {
                            // Notify recording started
                            [delegate captureOutput:self 
                             didStartRecordingToOutputFileAtURL:outputFileURL 
                                        fromConnections:@[]];
                            NSLog(@"[LC] ✅ L5: Delegate notified - recording started");
                        }
                        
                        if ([delegate respondsToSelector:@selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:)]) {
                            // Notify recording finished
                            [delegate captureOutput:self 
                             didFinishRecordingToOutputFileAtURL:outputFileURL 
                                         fromConnections:@[] 
                                                   error:success ? nil : error];
                            NSLog(@"[LC] ✅ L5: Delegate notified - recording finished: %@", success ? @"SUCCESS" : @"FAILED");
                        }
                    } else {
                        NSLog(@"[LC] ❌ L5: No delegate to notify!");
                    }
                });
                
            } @catch (NSException *exception) {
                NSLog(@"[LC] ❌ L5: Exception during spoofed recording: %@", exception);
                
                // Notify delegate of error
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:)]) {
                        NSError *spoofError = [NSError errorWithDomain:@"LiveContainerSpoof" 
                                                                 code:-1 
                                                             userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
                        [delegate captureOutput:self 
                         didFinishRecordingToOutputFileAtURL:outputFileURL 
                                     fromConnections:@[] 
                                               error:spoofError];
                    }
                });
            }
        });
        
    } else {
        NSLog(@"[LC] 🎬 L5: Spoofing disabled - using original recording");
        
        // FIXED: Call original implementation correctly
        if (original_startRecordingToOutputFileURL_IMP) {
            void (*originalFunc)(id, SEL, NSURL *, id) = (void (*)(id, SEL, NSURL *, id))original_startRecordingToOutputFileURL_IMP;
            originalFunc(self, @selector(startRecordingToOutputFileURL:recordingDelegate:), outputFileURL, delegate);
        } else {
            NSLog(@"[LC] ❌ L5: No original implementation found!");
        }
    }
}

- (void)lc_stopRecording {
    NSLog(@"[LC] 🎬 L5: Stop recording called");
    
    if (spoofCameraEnabled) {
        NSLog(@"[LC] 🎬 L5: Spoofed recording - stop ignored (already finished)");
        // For spoofed recordings, we already finished when we copied the file
        // No action needed
        return;
    }
    
    // FIXED: Call original implementation correctly
    if (original_stopRecording_IMP) {
        void (*originalFunc)(id, SEL) = (void (*)(id, SEL))original_stopRecording_IMP;
        originalFunc(self, @selector(stopRecording));
    } else {
        NSLog(@"[LC] ❌ L5: No original stopRecording implementation found!");
    }
}

// Helper method to create a black video when no spoof video is available
- (BOOL)createBlackVideoAtURL:(NSURL *)outputURL {
    @try {
        NSLog(@"[LC] 🎬 Creating black video placeholder");
        
        NSError *error = nil;
        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outputURL 
                                                           fileType:AVFileTypeMPEG4 
                                                              error:&error];
        if (!writer) {
            NSLog(@"[LC] ❌ Failed to create AVAssetWriter: %@", error);
            return NO;
        }
        
        // Video settings for a simple black video
        NSDictionary *videoSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,  // FIXED: Use non-deprecated constant
            AVVideoWidthKey: @(targetResolution.width),
            AVVideoHeightKey: @(targetResolution.height),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(1000000) // 1 Mbps
            }
        };
        
        AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo 
                                                                            outputSettings:videoSettings];
        videoInput.expectsMediaDataInRealTime = YES;
        
        if ([writer canAddInput:videoInput]) {
            [writer addInput:videoInput];
        } else {
            NSLog(@"[LC] ❌ Cannot add video input to writer");
            return NO;
        }
        
        // Start writing
        if (![writer startWriting]) {
            NSLog(@"[LC] ❌ Failed to start writing: %@", writer.error);
            return NO;
        }
        
        [writer startSessionAtSourceTime:kCMTimeZero];
        
        // Create a few seconds of black video
        CMTime frameDuration = CMTimeMake(1, 30); // 30 fps
        CMTime currentTime = kCMTimeZero;
        
        for (int i = 0; i < 90; i++) { // 3 seconds at 30fps
            if (videoInput.isReadyForMoreMediaData) {
                CVPixelBufferRef blackBuffer = [self createBlackPixelBuffer];
                if (blackBuffer) {
                    CMSampleBufferRef sampleBuffer = [self createSampleBufferFromPixelBuffer:blackBuffer 
                                                                                        time:currentTime 
                                                                                    duration:frameDuration];
                    if (sampleBuffer) {
                        [videoInput appendSampleBuffer:sampleBuffer];
                        CFRelease(sampleBuffer);
                    }
                    CVPixelBufferRelease(blackBuffer);
                }
                currentTime = CMTimeAdd(currentTime, frameDuration);
            }
        }
        
        [videoInput markAsFinished];
        [writer finishWritingWithCompletionHandler:^{
            NSLog(@"[LC] ✅ Black video creation completed");
        }];
        
        return YES;
        
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception creating black video: %@", exception);
        return NO;
    }
}

- (CVPixelBufferRef)createBlackPixelBuffer {
    CVPixelBufferRef pixelBuffer = NULL;
    
    NSDictionary *attributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                         (size_t)targetResolution.width,
                                         (size_t)targetResolution.height,
                                         kCVPixelFormatType_32BGRA,
                                         (__bridge CFDictionaryRef)attributes,
                                         &pixelBuffer);
    
    if (result == kCVReturnSuccess) {
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        
        // Fill with black
        memset(baseAddress, 0, bytesPerRow * height);
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    
    return pixelBuffer;
}

- (CMSampleBufferRef)createSampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer 
                                                   time:(CMTime)time 
                                               duration:(CMTime)duration {
    CMSampleBufferRef sampleBuffer = NULL;
    CMVideoFormatDescriptionRef formatDescription = NULL;
    
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, 
                                                                   pixelBuffer, 
                                                                   &formatDescription);
    if (status != noErr) {
        return NULL;
    }
    
    CMSampleTimingInfo timingInfo = {
        .duration = duration,
        .presentationTimeStamp = time,
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                      pixelBuffer,
                                                      formatDescription,
                                                      &timingInfo,
                                                      &sampleBuffer);
    
    CFRelease(formatDescription);
    
    return sampleBuffer;
}

@end

@implementation AVCaptureVideoPreviewLayer(LiveContainerSpoof)

static const void *SpoofDisplayLayerKey = &SpoofDisplayLayerKey;
static const void *SpoofDisplayTimerKey = &SpoofDisplayTimerKey;

- (void)lc_setSession:(AVCaptureSession *)session {
    NSLog(@"[LC] 📺 L5: PreviewLayer setSession called - session: %p", session);

    // Always call the original method first to maintain proper layer setup
    [self lc_setSession:session];

    if (spoofCameraEnabled && session) {
        // Start spoofing the preview layer with our video content
        [self startRobustSpoofedPreview];
    } else if (!session) {
        // Session is being removed, clean up our spoof
        [self stopRobustSpoofedPreview];
    }
}

// session to NIL (preview bluescreen)
// - (void)lc_setSession:(AVCaptureSession *)session {
//     NSLog(@"[LC] 📺 L5: PreviewLayer setSession called - session: %p", session);

//     // Always call the original method first
//     [self lc_setSession:session];

//     if (spoofCameraEnabled) {
//         if (session) {
//             // A session is being set. This is our cue to start the spoof.
            
//             // 1. Hide the original preview content to prevent the real camera feed from showing.
//             // By setting the session to nil on the original implementation, we disconnect it from the live feed.
//             // This is safer than hiding the layer, which might interfere with app layout logic.
//             // [super setSession:nil];
//             [self lc_setSession:nil];
//             self.backgroundColor = [UIColor blackColor].CGColor; // Show a black background

//             // 2. Start our robust preview feed.
//             [self startRobustSpoofedPreview];

//         } else {
//             // The session is being set to nil (e.g., view is disappearing). Clean up our resources.
//             [self stopRobustSpoofedPreview];
//         }
//     }
// }

- (void)startRobustSpoofedPreview {
    // Clean up any existing spoof first
    [self stopRobustSpoofedPreview];

    // Create our spoof display layer
    AVSampleBufferDisplayLayer *spoofLayer = [[AVSampleBufferDisplayLayer alloc] init];
    spoofLayer.frame = self.bounds;
    spoofLayer.videoGravity = self.videoGravity;
    spoofLayer.backgroundColor = [UIColor clearColor].CGColor;
    
    // Add the spoof layer as a sublayer (don't replace the original session)
    [self addSublayer:spoofLayer];
    
    // Store reference to our spoof layer
    objc_setAssociatedObject(self, SpoofDisplayLayerKey, spoofLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Use a CADisplayLink for smooth frame updates
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderNextSpoofedFrame)];
    displayLink.preferredFramesPerSecond = 30; // Limit to 30fps for better performance
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self, SpoofDisplayTimerKey, displayLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"[LC] ✅📺 Spoof preview layer started with video content");
}

- (void)renderNextSpoofedFrame {
    AVSampleBufferDisplayLayer *spoofLayer = objc_getAssociatedObject(self, SpoofDisplayLayerKey);
    if (!spoofLayer || !spoofLayer.superlayer) {
        [self stopRobustSpoofedPreview];
        return;
    }

    // Update the spoof layer frame to match the preview layer
    if (!CGRectEqualToRect(spoofLayer.frame, self.bounds)) {
        spoofLayer.frame = self.bounds;
        spoofLayer.videoGravity = self.videoGravity;
    }

    // CRITICAL: Always try to get a frame, never show placeholder
    CMSampleBufferRef spoofedBuffer = createSpoofedSampleBuffer();
    
    // FALLBACK: If createSpoofedSampleBuffer failed, use lastGoodSpoofedPixelBuffer
    if (!spoofedBuffer && lastGoodSpoofedPixelBuffer) {
        CMVideoFormatDescriptionRef formatDesc = NULL;
        OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, 
                                                                       lastGoodSpoofedPixelBuffer, 
                                                                       &formatDesc);
        if (status == noErr && formatDesc) {
            CMSampleTimingInfo timingInfo = {
                .duration = CMTimeMake(1, 30),
                .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), NSEC_PER_SEC),
                .decodeTimeStamp = kCMTimeInvalid
            };
            CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, 
                                                     lastGoodSpoofedPixelBuffer, 
                                                     formatDesc, 
                                                     &timingInfo, 
                                                     &spoofedBuffer);
            CFRelease(formatDesc);
        }
    }
    
    if (spoofedBuffer) {
        if (spoofLayer.isReadyForMoreMediaData) {
            [spoofLayer enqueueSampleBuffer:spoofedBuffer];
        }
        CFRelease(spoofedBuffer);
    }
    // CRITICAL: Never show anything if we don't have frames - just skip this frame
    // This prevents the blue gradient/text placeholder from ever appearing
}

- (void)stopRobustSpoofedPreview {
    // Stop the display link
    CADisplayLink *displayLink = objc_getAssociatedObject(self, SpoofDisplayTimerKey);
    if (displayLink) {
        [displayLink invalidate];
        objc_setAssociatedObject(self, SpoofDisplayTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    // Remove the spoof layer
    AVSampleBufferDisplayLayer *spoofLayer = objc_getAssociatedObject(self, SpoofDisplayLayerKey);
    if (spoofLayer) {
        [spoofLayer removeFromSuperlayer];
        [spoofLayer flush];
        objc_setAssociatedObject(self, SpoofDisplayLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    NSLog(@"[LC] 📺 Spoof preview stopped");
}

- (void)startSpoofedPreviewFeed {
    NSLog(@"[LC] 📺 L5: startSpoofedPreviewFeed called");
    
    // Create a sample buffer display layer for spoofed content
    AVSampleBufferDisplayLayer *spoofLayer = [[AVSampleBufferDisplayLayer alloc] init];
    spoofLayer.frame = self.bounds;
    spoofLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self addSublayer:spoofLayer];
    
    NSLog(@"[LC] 📺 L5: Created spoofed display layer - frame: %@", NSStringFromCGRect(spoofLayer.frame));
    
    // Store reference for cleanup
    objc_setAssociatedObject(self, @selector(startSpoofedPreviewFeed), spoofLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Feed spoofed frames to the layer
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"[LC] 📺 L5: Starting spoofed frame feed loop");
        int frameCount = 0;
        while (spoofCameraEnabled && spoofLayer.superlayer) {
            @autoreleasepool {
                CMSampleBufferRef spoofedFrame = createSpoofedSampleBuffer();
                if (spoofedFrame && spoofLayer.isReadyForMoreMediaData) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [spoofLayer enqueueSampleBuffer:spoofedFrame];
                    });
                    CFRelease(spoofedFrame);
                    frameCount++;
                    if (frameCount % 30 == 0) { // Log every 30 frames (1 second at 30fps)
                        NSLog(@"[LC] 📺 L5: Fed %d spoofed frames to preview", frameCount);
                    }
                } else if (!spoofedFrame) {
                    NSLog(@"[LC] ❌ L5: Failed to create spoofed frame for preview");
                }
                [NSThread sleepForTimeInterval:1.0/30.0]; // 30 FPS
            }
        }
        NSLog(@"[LC] 📺 L5: Spoofed frame feed loop ended - total frames: %d", frameCount);
    });
}

- (void)stopSpoofedPreviewFeed {
    NSLog(@"[LC] 📺 L5: stopSpoofedPreviewFeed called");
    
    AVSampleBufferDisplayLayer *spoofLayer = objc_getAssociatedObject(self, @selector(startSpoofedPreviewFeed));
    if (spoofLayer) {
        NSLog(@"[LC] 📺 L5: Removing spoofed display layer");
        [spoofLayer removeFromSuperlayer];
        objc_setAssociatedObject(self, @selector(startSpoofedPreviewFeed), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[LC] ✅ L5: Spoofed display layer removed");
    } else {
        NSLog(@"[LC] 📺 L5: No spoofed display layer to remove");
    }
}
@end

// pragma MARK: - LEVEL 6: Photo Accessor Hooks (Highest Level)

static CVPixelBufferRef spoofedPhotoPixelBufferValue(void) {
    if (!spoofCameraEnabled) {
        return NULL;
    }
    primePhotoCacheIfNeeded();
    if (g_cachedPhotoPixelBuffer) {
        return g_cachedPhotoPixelBuffer;
    }

    CMSampleBufferRef emergencyFrame = createSpoofedSampleBuffer();
    if (!emergencyFrame) {
        return NULL;
    }
    cachePhotoDataFromSampleBuffer(emergencyFrame);
    CFRelease(emergencyFrame);
    return g_cachedPhotoPixelBuffer;
}

static CGImageRef spoofedPhotoCGImageValue(void) {
    if (!spoofCameraEnabled) {
        return NULL;
    }
    primePhotoCacheIfNeeded();
    if (g_cachedPhotoCGImage) {
        return g_cachedPhotoCGImage;
    }

    CMSampleBufferRef emergencyFrame = createSpoofedSampleBuffer();
    if (!emergencyFrame) {
        return NULL;
    }
    cachePhotoDataFromSampleBuffer(emergencyFrame);
    CFRelease(emergencyFrame);
    return g_cachedPhotoCGImage;
}

static NSData *spoofedPhotoJPEGValue(void) {
    if (!spoofCameraEnabled) {
        return nil;
    }
    primePhotoCacheIfNeeded();
    if (g_cachedPhotoJPEGData.length > 0) {
        return g_cachedPhotoJPEGData;
    }

    CMSampleBufferRef emergencyFrame = createSpoofedSampleBuffer();
    if (!emergencyFrame) {
        return nil;
    }
    cachePhotoDataFromSampleBuffer(emergencyFrame);
    CFRelease(emergencyFrame);
    return g_cachedPhotoJPEGData;
}

CVPixelBufferRef hook_AVCapturePhoto_pixelBuffer(id self, SEL _cmd) {
    CVPixelBufferRef spoofedBuffer = spoofedPhotoPixelBufferValue();
    if (spoofedBuffer) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto pixelBuffer -> spoofed");
        return spoofedBuffer;
    }
    if (original_AVCapturePhoto_pixelBuffer) {
        return original_AVCapturePhoto_pixelBuffer(self, _cmd);
    }
    return NULL;
}

CVPixelBufferRef hook_AVCapturePhoto_previewPixelBuffer(id self, SEL _cmd) {
    CVPixelBufferRef spoofedBuffer = spoofedPhotoPixelBufferValue();
    if (spoofedBuffer) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto previewPixelBuffer -> spoofed");
        return spoofedBuffer;
    }
    if (original_AVCapturePhoto_previewPixelBuffer) {
        return original_AVCapturePhoto_previewPixelBuffer(self, _cmd);
    }
    return NULL;
}

CGImageRef hook_AVCapturePhoto_CGImageRepresentation(id self, SEL _cmd) {
    CGImageRef spoofedImage = spoofedPhotoCGImageValue();
    if (spoofedImage) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto CGImageRepresentation -> spoofed");
        return spoofedImage;
    }
    if (original_AVCapturePhoto_CGImageRepresentation) {
        return original_AVCapturePhoto_CGImageRepresentation(self, _cmd);
    }
    return NULL;
}

CGImageRef hook_AVCapturePhoto_previewCGImageRepresentation(id self, SEL _cmd) {
    CGImageRef spoofedImage = spoofedPhotoCGImageValue();
    if (spoofedImage) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto previewCGImageRepresentation -> spoofed");
        return spoofedImage;
    }
    if (original_AVCapturePhoto_previewCGImageRepresentation) {
        return original_AVCapturePhoto_previewCGImageRepresentation(self, _cmd);
    }
    return NULL;
}

// make sure our photo hooks don't apply any additional rotation
NSData *hook_AVCapturePhoto_fileDataRepresentation(id self, SEL _cmd) {
    NSData *spoofedData = spoofedPhotoJPEGValue();
    if (spoofedData.length > 0) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto fileDataRepresentation -> spoofed (%lu bytes)",
              (unsigned long)spoofedData.length);
        return spoofedData;
    }
    if (original_AVCapturePhoto_fileDataRepresentation) {
        return original_AVCapturePhoto_fileDataRepresentation(self, _cmd);
    }
    return nil;
}

NSData *hook_AVCapturePhoto_fileDataRepresentationWithCustomizer(id self, SEL _cmd, id customizer) {
    NSData *spoofedData = spoofedPhotoJPEGValue();
    if (spoofedData.length > 0) {
        NSLog(@"[LC] ✅ L6: AVCapturePhoto fileDataRepresentationWithCustomizer -> spoofed (%lu bytes)",
              (unsigned long)spoofedData.length);
        return spoofedData;
    }
    if (original_AVCapturePhoto_fileDataRepresentationWithCustomizer) {
        return original_AVCapturePhoto_fileDataRepresentationWithCustomizer(self, _cmd, customizer);
    }
    return nil;
}

CVPixelBufferRef hook_AVCaptureDeferredPhotoProxy_pixelBuffer(id self, SEL _cmd) {
    CVPixelBufferRef spoofedBuffer = spoofedPhotoPixelBufferValue();
    if (spoofedBuffer) {
        NSLog(@"[LC] ✅ L6: Deferred proxy pixelBuffer -> spoofed");
        return spoofedBuffer;
    }
    if (original_AVCaptureDeferredPhotoProxy_pixelBuffer) {
        return original_AVCaptureDeferredPhotoProxy_pixelBuffer(self, _cmd);
    }
    return NULL;
}

CVPixelBufferRef hook_AVCaptureDeferredPhotoProxy_previewPixelBuffer(id self, SEL _cmd) {
    CVPixelBufferRef spoofedBuffer = spoofedPhotoPixelBufferValue();
    if (spoofedBuffer) {
        NSLog(@"[LC] ✅ L6: Deferred proxy previewPixelBuffer -> spoofed");
        return spoofedBuffer;
    }
    if (original_AVCaptureDeferredPhotoProxy_previewPixelBuffer) {
        return original_AVCaptureDeferredPhotoProxy_previewPixelBuffer(self, _cmd);
    }
    return NULL;
}

CGImageRef hook_AVCaptureDeferredPhotoProxy_CGImageRepresentation(id self, SEL _cmd) {
    CGImageRef spoofedImage = spoofedPhotoCGImageValue();
    if (spoofedImage) {
        NSLog(@"[LC] ✅ L6: Deferred proxy CGImageRepresentation -> spoofed");
        return spoofedImage;
    }
    if (original_AVCaptureDeferredPhotoProxy_CGImageRepresentation) {
        return original_AVCaptureDeferredPhotoProxy_CGImageRepresentation(self, _cmd);
    }
    return NULL;
}

CGImageRef hook_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation(id self, SEL _cmd) {
    CGImageRef spoofedImage = spoofedPhotoCGImageValue();
    if (spoofedImage) {
        NSLog(@"[LC] ✅ L6: Deferred proxy previewCGImageRepresentation -> spoofed");
        return spoofedImage;
    }
    if (original_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation) {
        return original_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation(self, _cmd);
    }
    return NULL;
}

NSData *hook_AVCaptureDeferredPhotoProxy_fileDataRepresentation(id self, SEL _cmd) {
    NSData *spoofedData = spoofedPhotoJPEGValue();
    if (spoofedData.length > 0) {
        NSLog(@"[LC] ✅ L6: Deferred proxy fileDataRepresentation -> spoofed (%lu bytes)",
              (unsigned long)spoofedData.length);
        return spoofedData;
    }
    if (original_AVCaptureDeferredPhotoProxy_fileDataRepresentation) {
        return original_AVCaptureDeferredPhotoProxy_fileDataRepresentation(self, _cmd);
    }
    return nil;
}

NSData *hook_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer(id self, SEL _cmd, id customizer) {
    NSData *spoofedData = spoofedPhotoJPEGValue();
    if (spoofedData.length > 0) {
        NSLog(@"[LC] ✅ L6: Deferred proxy fileDataRepresentationWithCustomizer -> spoofed (%lu bytes)",
              (unsigned long)spoofedData.length);
        return spoofedData;
    }
    if (original_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer) {
        return original_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer(self, _cmd, customizer);
    }
    return nil;
}

NSData *hook_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer(id self, SEL _cmd, CMSampleBufferRef jpegSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer) {
    NSData *spoofedData = spoofedPhotoJPEGValue();
    if (spoofedData.length > 0) {
        NSLog(@"[LC] ✅ L6: JPEGPhotoDataRepresentation helper -> spoofed (%lu bytes)",
              (unsigned long)spoofedData.length);
        return spoofedData;
    }

    if (original_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer) {
        return original_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer(self, _cmd, jpegSampleBuffer, previewPhotoSampleBuffer);
    }
    return nil;
}

CMSampleBufferRef hook_AVCaptureSynchronizedSampleBufferData_sampleBuffer(id self, SEL _cmd) {
    CMSampleBufferRef originalSampleBuffer = NULL;
    if (original_AVCaptureSynchronizedSampleBufferData_sampleBuffer) {
        originalSampleBuffer = original_AVCaptureSynchronizedSampleBufferData_sampleBuffer(self, _cmd);
    }

    if (!spoofCameraEnabled) {
        return originalSampleBuffer;
    }

    AVCaptureOutput *dataOutput = nil;
    SEL dataOutputSelector = NSSelectorFromString(@"dataOutput");
    if ([self respondsToSelector:dataOutputSelector]) {
        id outputCandidate = ((id (*)(id, SEL))objc_msgSend)(self, dataOutputSelector);
        if ([outputCandidate isKindOfClass:[AVCaptureOutput class]]) {
            dataOutput = (AVCaptureOutput *)outputCandidate;
        }
    }

    if ([dataOutput isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        CMSampleBufferRef spoofedFrame = createPrivatePipelineSpoofedSampleBuffer(originalSampleBuffer);
        if (!spoofedFrame) {
            return originalSampleBuffer;
        }
        return cacheSynchronizerSampleBufferAdopting(spoofedFrame, NO);
    }

    if ([dataOutput isKindOfClass:[AVCaptureAudioDataOutput class]]) {
        if (!spoofCameraUseVideoAudio) {
            return originalSampleBuffer;
        }
        if (spoofCameraVideoPath.length == 0) {
            return originalSampleBuffer;
        }

        CMSampleBufferRef spoofedAudioSampleBuffer = copyNextSpoofedAudioSampleBuffer();
        if (!spoofedAudioSampleBuffer) {
            return originalSampleBuffer;
        }
        CMSampleBufferRef alignedAudioSampleBuffer = createAudioSampleBufferAlignedToReference(spoofedAudioSampleBuffer,
                                                                                               originalSampleBuffer);
        CFRelease(spoofedAudioSampleBuffer);
        if (!alignedAudioSampleBuffer) {
            return originalSampleBuffer;
        }
        return cacheSynchronizerSampleBufferAdopting(alignedAudioSampleBuffer, YES);
    }

    return originalSampleBuffer;
}

// pragma MARK: - Configuration Loading

static void loadSpoofingConfiguration(void) {
    NSLog(@"[LC] Loading camera spoofing configuration...");

    NSDictionary *guestAppInfo = [NSUserDefaults guestAppInfo];
    if (!guestAppInfo) {
        NSLog(@"[LC] ❌ No guestAppInfo found");
        spoofCameraEnabled = NO;
        spoofCameraUseVideoAudio = YES;
        cleanupAudioSpoofingResources();
        return;
    }

    spoofCameraEnabled = [guestAppInfo[@"spoofCamera"] boolValue];
    spoofCameraVideoPath = guestAppInfo[@"spoofCameraVideoPath"] ?: @"";
    spoofCameraLoop = (guestAppInfo[@"spoofCameraLoop"] != nil) ? [guestAppInfo[@"spoofCameraLoop"] boolValue] : YES;
    spoofCameraUseVideoAudio = (guestAppInfo[@"spoofCameraUseVideoAudio"] != nil) ? [guestAppInfo[@"spoofCameraUseVideoAudio"] boolValue] : YES;
    spoofCameraMode = guestAppInfo[@"spoofCameraMode"] ?: @"standard";

    NSString *spoofCameraType = guestAppInfo[@"spoofCameraType"] ?: @"image";
    NSString *spoofCameraImagePath = guestAppInfo[@"spoofCameraImagePath"] ?: @"";

    NSLog(@"[LC] ⚙️ Config: Enabled=%d, Type='%@', VideoPath='%@', ImagePath='%@', Loop=%d, UseVideoAudio=%d, Mode='%@'",
          spoofCameraEnabled,
          spoofCameraType,
          spoofCameraVideoPath,
          spoofCameraImagePath.lastPathComponent ?: @"",
          spoofCameraLoop,
          spoofCameraUseVideoAudio,
          spoofCameraMode);

    if (!spoofCameraEnabled) {
        cleanupAudioSpoofingResources();
        cleanupSynchronizerSampleBufferCache();
    }

    if (spoofCameraEnabled) {
        if (spoofCameraVideoPath.length == 0) {
            NSLog(@"[LC] Image mode (no video path provided)");
        } else {
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:spoofCameraVideoPath];
            NSLog(@"[LC] Video mode - file exists: %d at path: %@", exists, spoofCameraVideoPath);

            if (!exists) {
                NSLog(@"[LC] ❌ Video file not found - falling back to image mode");
                spoofCameraVideoPath = @"";
            }
        }
    }

    if (!spoofCameraEnabled || !spoofCameraUseVideoAudio || spoofCameraVideoPath.length == 0) {
        cleanupAudioSpoofingResources();
    }
}

// pragma MARK: - Hook Installation

static void installLevel2Hooks(void) {
    @try {
        swizzle([AVCaptureDevice class], @selector(devicesWithMediaType:), @selector(lc_devicesWithMediaType:));
        swizzle([AVCaptureDevice class], @selector(defaultDeviceWithMediaType:), @selector(lc_defaultDeviceWithMediaType:));
        NSLog(@"[LC] ✅ Level 2 hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Level 2 hook error: %@", e);
    }
}

static void installLevel3Hooks(void) {
    @try {
        swizzle([AVCaptureDeviceInput class], @selector(deviceInputWithDevice:error:), @selector(lc_deviceInputWithDevice:error:));
        NSLog(@"[LC] ✅ Level 3 hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Level 3 hook error: %@", e);
    }
}

static void installLevel4Hooks(void) {
    @try {
        swizzle([AVCaptureSession class], @selector(addInput:), @selector(lc_addInput:));
        swizzle([AVCaptureSession class], @selector(addOutput:), @selector(lc_addOutput:));
        swizzle([AVCaptureSession class], @selector(startRunning), @selector(lc_startRunning));
        swizzle([AVCaptureSession class], @selector(setSessionPreset:), @selector(lc_setSessionPreset:));
        swizzle([AVCaptureSession class], @selector(stopRunning), @selector(lc_stopRunning));
        NSLog(@"[LC] ✅ Level 4 hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Level 4 hook error: %@", e);
    }
}

static void installLevel5Hooks(void) {
    @try {
        swizzle([AVCaptureVideoDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setSampleBufferDelegate:queue:));
        swizzle([AVCaptureAudioDataOutput class], @selector(setSampleBufferDelegate:queue:), @selector(lc_setAudioSampleBufferDelegate:queue:));
        Class dataOutputSynchronizerClass = NSClassFromString(@"AVCaptureDataOutputSynchronizer");
        if (dataOutputSynchronizerClass && [dataOutputSynchronizerClass instancesRespondToSelector:@selector(setDelegate:queue:)]) {
            swizzle(dataOutputSynchronizerClass, @selector(setDelegate:queue:), @selector(lc_setDelegate:queue:));
            NSLog(@"[LC] ✅ L5: DataOutputSynchronizer delegate hook installed");
        }
        swizzle([AVCapturePhotoOutput class], @selector(capturePhotoWithSettings:delegate:), @selector(lc_capturePhotoWithSettings:delegate:));

        swizzle([AVCaptureMovieFileOutput class], @selector(startRecordingToOutputFileURL:recordingDelegate:), @selector(lc_startRecordingToOutputFileURL:recordingDelegate:));
        swizzle([AVCaptureMovieFileOutput class], @selector(stopRecording), @selector(lc_stopRecording));

        swizzle([AVCaptureVideoPreviewLayer class], @selector(setSession:), @selector(lc_setSession:));

        if (NSClassFromString(@"AVCaptureStillImageOutput")) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            swizzle([AVCaptureStillImageOutput class], @selector(captureStillImageAsynchronouslyFromConnection:completionHandler:), @selector(lc_captureStillImageAsynchronouslyFromConnection:completionHandler:));
            #pragma clang diagnostic pop
            NSLog(@"[LC] ✅ Legacy still image capture hook installed");
        }
        NSLog(@"[LC] ✅ Level 5 hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Level 5 hook error: %@", e);
    }
}

static void installLevel5DiagnosticHooks(void) {
    @try {
        swizzle([AVAssetWriter class], @selector(initWithURL:fileType:error:), @selector(lc_initWithURL:fileType:error:));
        swizzle([AVAssetWriter class], @selector(startWriting), @selector(lc_startWriting));
        swizzle([AVAssetWriter class], @selector(finishWriting), @selector(lc_finishWriting));
        NSLog(@"[LC] ✅ L5: AVAssetWriter diagnostic hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ AVAssetWriter hook error: %@", e);
    }

    @try {
        swizzle([NSFileManager class], @selector(createFileAtPath:contents:attributes:), @selector(lc_createFileAtPath:contents:attributes:));
        NSLog(@"[LC] ✅ L5: File creation diagnostic hooks installed");
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ File creation hook error: %@", e);
    }
}

static void installPrivatePipelineHooks(void) {
    @try {
        installPrivateCapturePipelineHooks();
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Private pipeline hook error: %@", e);
    }
}

static void installDirectMethodHook(Class cls,
                                    SEL selector,
                                    IMP replacement,
                                    IMP *originalOut,
                                    BOOL isClassMethod,
                                    NSString *label) {
    if (!cls || !selector || !replacement || !originalOut) {
        return;
    }

    Method method = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!method) {
        return;
    }

    IMP current = method_getImplementation(method);
    if (current == replacement) {
        NSLog(@"[LC] ✅ L6: %@ hook already installed", label);
        return;
    }

    *originalOut = current;
    method_setImplementation(method, replacement);
    NSLog(@"[LC] ✅ L6: %@ hook installed", label);
}

static void installLevel6Hooks(void) {
    @try {
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(pixelBuffer),
                                (IMP)hook_AVCapturePhoto_pixelBuffer,
                                (IMP *)&original_AVCapturePhoto_pixelBuffer,
                                NO,
                                @"Photo pixelBuffer");
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(previewPixelBuffer),
                                (IMP)hook_AVCapturePhoto_previewPixelBuffer,
                                (IMP *)&original_AVCapturePhoto_previewPixelBuffer,
                                NO,
                                @"Photo previewPixelBuffer");
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(CGImageRepresentation),
                                (IMP)hook_AVCapturePhoto_CGImageRepresentation,
                                (IMP *)&original_AVCapturePhoto_CGImageRepresentation,
                                NO,
                                @"Photo CGImageRepresentation");
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(previewCGImageRepresentation),
                                (IMP)hook_AVCapturePhoto_previewCGImageRepresentation,
                                (IMP *)&original_AVCapturePhoto_previewCGImageRepresentation,
                                NO,
                                @"Photo previewCGImageRepresentation");
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(fileDataRepresentation),
                                (IMP)hook_AVCapturePhoto_fileDataRepresentation,
                                (IMP *)&original_AVCapturePhoto_fileDataRepresentation,
                                NO,
                                @"Photo fileDataRepresentation");
        installDirectMethodHook([AVCapturePhoto class],
                                @selector(fileDataRepresentationWithCustomizer:),
                                (IMP)hook_AVCapturePhoto_fileDataRepresentationWithCustomizer,
                                (IMP *)&original_AVCapturePhoto_fileDataRepresentationWithCustomizer,
                                NO,
                                @"Photo fileDataRepresentationWithCustomizer");

        Class deferredPhotoProxyClass = NSClassFromString(@"AVCaptureDeferredPhotoProxy");
        if (deferredPhotoProxyClass) {
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(pixelBuffer),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_pixelBuffer,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_pixelBuffer,
                                    NO,
                                    @"Deferred photo proxy pixelBuffer");
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(previewPixelBuffer),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_previewPixelBuffer,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_previewPixelBuffer,
                                    NO,
                                    @"Deferred photo proxy previewPixelBuffer");
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(CGImageRepresentation),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_CGImageRepresentation,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_CGImageRepresentation,
                                    NO,
                                    @"Deferred photo proxy CGImageRepresentation");
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(previewCGImageRepresentation),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_previewCGImageRepresentation,
                                    NO,
                                    @"Deferred photo proxy previewCGImageRepresentation");
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(fileDataRepresentation),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_fileDataRepresentation,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_fileDataRepresentation,
                                    NO,
                                    @"Deferred photo proxy fileDataRepresentation");
            installDirectMethodHook(deferredPhotoProxyClass,
                                    @selector(fileDataRepresentationWithCustomizer:),
                                    (IMP)hook_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer,
                                    (IMP *)&original_AVCaptureDeferredPhotoProxy_fileDataRepresentationWithCustomizer,
                                    NO,
                                    @"Deferred photo proxy fileDataRepresentationWithCustomizer");
        }

        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        installDirectMethodHook([AVCapturePhotoOutput class],
                                @selector(JPEGPhotoDataRepresentationForJPEGSampleBuffer:previewPhotoSampleBuffer:),
                                (IMP)hook_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer,
                                (IMP *)&original_AVCapturePhotoOutput_JPEGPhotoDataRepresentationForJPEGSampleBuffer,
                                YES,
                                @"JPEGPhotoDataRepresentation helper");
        #pragma clang diagnostic pop

        Class synchronizedSampleBufferDataClass = NSClassFromString(@"AVCaptureSynchronizedSampleBufferData");
        if (synchronizedSampleBufferDataClass) {
            installDirectMethodHook(synchronizedSampleBufferDataClass,
                                    @selector(sampleBuffer),
                                    (IMP)hook_AVCaptureSynchronizedSampleBufferData_sampleBuffer,
                                    (IMP *)&original_AVCaptureSynchronizedSampleBufferData_sampleBuffer,
                                    NO,
                                    @"Synchronized sampleBuffer");
        }
    } @catch (NSException *e) {
        NSLog(@"[LC] ❌ Level 6 hook error: %@", e);
    }
}

static void installHierarchicalHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            NSLog(@"[LC] Installing hierarchical hooks...");

            // Initialize original MovieFileOutput IMP snapshots before swizzling.
            [AVCaptureMovieFileOutput load];

            installLevel2Hooks();
            installLevel3Hooks();
            installLevel4Hooks();
            installLevel5Hooks();
            installPrivatePipelineHooks();
            installLevel5DiagnosticHooks();
            installLevel6Hooks();

            NSLog(@"[LC] ✅ All hooks installed with error handling");
        } @catch (NSException *exception) {
            NSLog(@"[LC] ❌ CRITICAL: Hook installation failed: %@", exception);
        }
    });
}

// pragma MARK: - Initialization Helpers

static void setupInitialSpoofingResources(void) {
    setupImageSpoofingResources();

    if (!spoofCameraEnabled) {
        cleanupAudioSpoofingResources();
        cleanupSynchronizerSampleBufferCache();
        return;
    }

    if (spoofCameraVideoPath.length > 0) {
        NSLog(@"[LC] 🎬 Setting up video spoofing system");
        [GetFrame setCurrentVideoPath:spoofCameraVideoPath];
        setupVideoSpoofingResources();
        if (spoofCameraUseVideoAudio) {
            setupAudioSpoofingResources();
        } else {
            cleanupAudioSpoofingResources();
        }
    } else {
        NSLog(@"[LC] 🖼️ Image-only mode activated.");
        cleanupAudioSpoofingResources();
    }
}

static void ensureEmergencyFallbackBuffer(void) {
    if (lastGoodSpoofedPixelBuffer) {
        return;
    }

    NSLog(@"[LC] ⚠️ Creating emergency fallback buffer (BLACK, no text)");

    CVPixelBufferRef emergencyPixelBuffer = NULL;
    NSDictionary *pixelAttributes = @{
        (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
        (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{}
    };

    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)targetResolution.width,
                                          (size_t)targetResolution.height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)pixelAttributes,
                                          &emergencyPixelBuffer);
    if (status != kCVReturnSuccess || !emergencyPixelBuffer) {
        return;
    }

    CVPixelBufferLockBaseAddress(emergencyPixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(emergencyPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(emergencyPixelBuffer);
    memset(baseAddress, 0, bytesPerRow * (size_t)targetResolution.height);
    CVPixelBufferUnlockBaseAddress(emergencyPixelBuffer, 0);

    CMVideoFormatDescriptionRef emergencyFormatDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, emergencyPixelBuffer, &emergencyFormatDesc);
    updateLastGoodSpoofedFrame(emergencyPixelBuffer, emergencyFormatDesc);

    if (emergencyFormatDesc) {
        CFRelease(emergencyFormatDesc);
    }
    CVPixelBufferRelease(emergencyPixelBuffer);
    NSLog(@"[LC] ✅ Emergency BLACK buffer created (no text/gradient)");
}

// pragma MARK: - Initialization

void AVFoundationGuestHooksInit(void) {
    @try {
        NSLog(@"[LC] 🚀 Initializing comprehensive AVFoundation hooks...");

        g_currentVideoTransform = CGAffineTransformIdentity;
        loadSpoofingConfiguration();

        if (!videoProcessingQueue) {
            videoProcessingQueue = dispatch_queue_create("com.livecontainer.videoprocessingqueue", DISPATCH_QUEUE_SERIAL);
        }

        setupInitialSpoofingResources();
        ensureEmergencyFallbackBuffer();
        installHierarchicalHooks();

        if (spoofCameraEnabled) {
            NSLog(@"[LC] ✅ Spoofing initialized - LastGoodBuffer: %s",
                  lastGoodSpoofedPixelBuffer ? "VALID" : "NULL");
        }
    } @catch (NSException *exception) {
        NSLog(@"[LC] ❌ Exception during initialization: %@", exception);
    }
}
