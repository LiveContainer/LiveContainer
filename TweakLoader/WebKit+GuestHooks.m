@import WebKit;
#import "utils.h"

// ============================================================
// WebKit media playback fix for extension-hosted guest apps.
//
// Fixes: video in WKWebView stalls after the first decoded frame
// when a guest app runs in multitasking mode on iOS 17.4 or later.
//
// Root cause:
//   Starting in iOS 17.4, WKPreferences added a new embedder-level
//   preference `MediaCapabilityGrantsEnabled` which defaults to YES
//   on real device WebKit builds (Source/WTF/Scripts/Preferences/
//   UnifiedWebPreferences.yaml, condition ENABLE(EXTENSION_CAPABILITIES)).
//
//   When enabled, WebKit assumes that BrowserEngineKit media
//   capability grants will manage media lifecycle, and takes
//   shortcut branches that SILENTLY SKIP:
//     - registering the presenting application PID with
//       mediaservicesd (GPUConnectionToWebProcess::
//       providePresentingApplicationPID, RemoteAudioSessionProxyManager)
//     - taking the MediaPlayback process assertion for the
//       playing page (WebProcessProxy::updateAudibleMediaAssertion)
//
//   LiveContainer hosts guest apps via NSExtension. In that
//   context, BrowserEngineKit capability grants do not propagate
//   the way the non-extension path assumes, so neither the
//   presenting-PID registration nor the MediaPlayback assertion
//   ever happens. WebKit's GPU process decodes the initial
//   pre-roll frame, then the playback clock is never advanced
//   and the pipeline stalls silently (no errors, video element
//   reports paused=false readyState=4 but currentTime=0).
//
// Fix:
//   On every new WKWebView, clear _mediaCapabilityGrantsEnabled
//   before init. That sends WebKit down the pre-17.4 code path,
//   which always registers the presenting PID and takes the
//   MediaPlayback assertion — the path that has been working
//   in extensions all along.
//
// References:
//   Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
//     _mediaCapabilityGrantsEnabled property, ios(17.4)+
//   Source/WebKit/GPUProcess/media/RemoteAudioSessionProxyManager.cpp
//     lines 183-186 and 273-276 (silent-skip blocks)
//   Source/WebKit/UIProcess/WebProcessProxy.cpp
//     lines 1936-1963 (skipped MediaPlayback assertion)
//   Source/WebKit/GPUProcess/GPUConnectionToWebProcess.cpp
//     lines 716-727 (silent-skip providePresentingApplicationPID)
// ============================================================

@interface WKPreferences (LCMediaCapabilityFix)
- (void)_setMediaCapabilityGrantsEnabled:(BOOL)enabled;
@end

@interface WKWebView (LCMediaCapabilityFix)
- (instancetype)hook_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration;
@end

@implementation WKWebView (LCMediaCapabilityFix)

- (instancetype)hook_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (configuration) {
        WKPreferences *prefs = configuration.preferences;
        if ([prefs respondsToSelector:@selector(_setMediaCapabilityGrantsEnabled:)]) {
            // Disable the iOS 17.4+ capability-grant shortcut so WebKit
            // takes the pre-17.4 path that actually registers the
            // presenting app PID and takes the MediaPlayback assertion.
            [prefs _setMediaCapabilityGrantsEnabled:NO];
        }
    }
    return [self hook_initWithFrame:frame configuration:configuration];
}

@end

__attribute__((constructor))
static void WebKitGuestHooksInit(void) {
    if (!NSUserDefaults.lcGuestAppId) return;
    if (@available(iOS 17.4, *)) {
        swizzle(WKWebView.class,
                @selector(initWithFrame:configuration:),
                @selector(hook_initWithFrame:configuration:));
    }
}
