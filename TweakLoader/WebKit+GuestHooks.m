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
//   Clear _mediaCapabilityGrantsEnabled before any WKWebView is
//   bound to a WebContent process. That sends WebKit down the
//   pre-17.4 code path, which always registers the presenting
//   PID and takes the MediaPlayback assertion — the path that
//   has been working in extensions all along.
//
//   We hook three points so the fix takes effect even if a
//   WKWebView is created very early (before this constructor
//   runs) or if a WKWebViewConfiguration is built without going
//   through WKWebView init:
//     1. WKWebViewConfiguration init   (catches early configs)
//     2. WKWebView initWithFrame:configuration: (covers the
//        common path and any config not built via plain init)
//     3. On load, walk live windows and patch any existing
//        WKWebView's preferences (recovers if the constructor
//        ran after Firefox already created its first WKWebView)
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

static void disableMediaCapabilityGrantsOnPrefs(WKPreferences *prefs) {
    if ([prefs respondsToSelector:@selector(_setMediaCapabilityGrantsEnabled:)]) {
        [prefs _setMediaCapabilityGrantsEnabled:NO];
    }
}

@interface WKWebView (LCMediaCapabilityFix)
- (instancetype)hook_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration;
@end

@implementation WKWebView (LCMediaCapabilityFix)

- (instancetype)hook_initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (configuration) {
        disableMediaCapabilityGrantsOnPrefs(configuration.preferences);
    }
    return [self hook_initWithFrame:frame configuration:configuration];
}

@end

@interface WKWebViewConfiguration (LCMediaCapabilityFix)
- (instancetype)hook_init;
@end

@implementation WKWebViewConfiguration (LCMediaCapabilityFix)

- (instancetype)hook_init {
    WKWebViewConfiguration *cfg = [self hook_init];
    if (cfg) {
        disableMediaCapabilityGrantsOnPrefs(cfg.preferences);
    }
    return cfg;
}

@end

static void patchWebViewsInView(UIView *view) {
    if ([view isKindOfClass:[WKWebView class]]) {
        disableMediaCapabilityGrantsOnPrefs(((WKWebView *)view).configuration.preferences);
    }
    for (UIView *sub in view.subviews) {
        patchWebViewsInView(sub);
    }
}

static void patchExistingWebViews(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            patchWebViewsInView(window);
        }
    }
}

__attribute__((constructor))
static void WebKitGuestHooksInit(void) {
    if (!NSUserDefaults.lcGuestAppId) return;
    if (@available(iOS 17.4, *)) {
        swizzle(WKWebViewConfiguration.class,
                @selector(init),
                @selector(hook_init));
        swizzle(WKWebView.class,
                @selector(initWithFrame:configuration:),
                @selector(hook_initWithFrame:configuration:));

        // If our constructor ran after the host already created its
        // first WKWebView (e.g. during state restoration), patch live
        // ones now so they pick up the corrected preference before
        // their next media load.
        dispatch_async(dispatch_get_main_queue(), ^{
            patchExistingWebViews();
        });
    }
}
