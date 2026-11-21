//
//  LCGuestSidecar.m
//  LiveProcess
//  Summary (EN): Guest-process sidecar: loopback HTTP server inside the guest app (tree, activate, taps, text, screenshot, OCR, inspect).
//
//  Runs a loopback HTTP server inside the guest app process and exposes its UI to the LiveContainer host:
//    GET  /guest/info                 bundleId / pid / screen size
//    GET  /guest/ui/tree              accessibility tree (label/identifier/frame/activatable)
//    POST /guest/ui/activate          {index} | {label} | {identifier} | {x,y}
//    POST /guest/ui/taps              {steps:[{label|identifier|index|x,y,delayMs}], detectChange}
//    POST /guest/ui/text              {text}
//    GET  /guest/screenshot?maxWidth=&quality=
//
//  Binds 127.0.0.1 only and requires the bearer token written by the host into
//  <app-group>/LiveContainer/RemoteControl/guest-sidecar-token, shared by both sides.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <signal.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
#import <Vision/Vision.h>

static const int kLCGuestSidecarPort = 8850;

// Forward declarations: the snapshot/OCR helpers reference each other, and the request handler
// below uses them before their definitions.
static UIImage *LCSnapshot(CGFloat maxWidth);
static UIImage *LCResize(UIImage *img, CGFloat maxWidth);
static void LCSnapshotWithWeb(CGFloat maxWidth, void (^done)(UIImage *));
static NSArray<NSDictionary *> *LCRecognizeText(void);
static NSArray<NSDictionary *> *LCRecognizeImage(UIImage *img);
static NSDictionary *LCOCRRun(void);
static NSDictionary *LCOCRRunWithImage(UIImage *img);
static NSData *LCGrayThumb(void);
static NSData *LCGrayThumbOf(UIImage *img);
static NSString *LCImageDigest(UIImage *img);
static void LCCollectTexts(UIView *v, NSMutableArray<NSString *> *out, NSInteger depth);
static void LCCollectLayerTexts(CALayer *layer, NSMutableArray<NSString *> *out, NSInteger depth);

// In app extensions UIKit does not expose accessibilityIdentifier on NSObject, so declare it here.
@interface NSObject (LCGuestA11y)
- (NSString *)accessibilityIdentifier;
@end

// -- small helpers ---------------------------------------------------------

static NSData *LCJSON(id object, int status, NSMutableDictionary *extraHeaders) {
    NSError *err = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:&err];
    if (!body) body = [@"{\"ok\":false,\"error\":\"encode\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *resp = [NSMutableData data];
    NSString *head = [NSString stringWithFormat:
        @"HTTP/1.1 %d %@\r\nContent-Type: application/json; charset=utf-8\r\n"
         "Content-Length: %lu\r\nConnection: close\r\nServer: LC-GuestSidecar/1\r\n",
        status, status == 200 ? @"OK" : @"Error", (unsigned long)body.length];
    [resp appendData:[head dataUsingEncoding:NSUTF8StringEncoding]];
    [extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [resp appendData:[[NSString stringWithFormat:@"%@: %@\r\n", k, v] dataUsingEncoding:NSUTF8StringEncoding]];
    }];
    [resp appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [resp appendData:body];
    return resp;
}

static NSData *LCBinary(NSData *body, NSString *contentType, int status) {
    NSMutableData *resp = [NSMutableData data];
    NSString *head = [NSString stringWithFormat:
        @"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        status, status == 200 ? @"OK" : @"Error", contentType, (unsigned long)body.length];
    [resp appendData:[head dataUsingEncoding:NSUTF8StringEncoding]];
    [resp appendData:body];
    return resp;
}

// UIApplication.sharedApplication is marked unavailable in extensions, so fetch the instance dynamically.
static UIApplication *LCApp(void) {
    static UIApplication *app = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL sel = NSSelectorFromString(@"sharedApplication");
        Class cls = [UIApplication class];
        if ([cls respondsToSelector:sel]) {
            app = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel);
        }
    });
    return app;
}

static NSURL *LCGroupURL(void) {
    NSArray<NSString *> *ids = @[@"group.com.kdt.livecontainer",
                                 @"group.com.SideStore.SideStore",
                                 @"group.com.rileytestut.AltStore"];
    for (NSString *gid in ids) {
        NSURL *u = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:gid];
        if (u) return u;
    }
    return nil;
}

static NSString *LCSidecarTokenPath(void) {
    NSURL *group = LCGroupURL();
    if (!group) return nil;
    return [[[group.path stringByAppendingPathComponent:@"LiveContainer"]
             stringByAppendingPathComponent:@"RemoteControl"]
            stringByAppendingPathComponent:@"guest-sidecar-token"];
}

static NSString *LCReadSidecarToken(void) {
    NSString *path = LCSidecarTokenPath();
    if (!path) return @"";
    NSString *t = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

// -- view traversal (same order as the host process so indexes line up) ------

static BOOL LCHasLabel(NSObject *o) {
    if (o.accessibilityLabel.length) return YES;
    if ([o respondsToSelector:@selector(accessibilityIdentifier)] && [[o accessibilityIdentifier] length]) return YES;
    if ([o.accessibilityValue isKindOfClass:NSString.class] && [o.accessibilityValue length]) return YES;
    if ([o isKindOfClass:UIControl.class]) return YES;
    return (o.accessibilityTraits & (UIAccessibilityTraitButton | UIAccessibilityTraitLink)) != 0;
}

static void LCWalk(id obj, NSMutableArray *out, NSMutableSet *visited, NSUInteger depth) {
    if (out.count >= 800 || depth > 32) return;
    if (![obj isKindOfClass:NSObject.class]) return;
    NSObject *o = (NSObject *)obj;
    NSValue *key = [NSValue valueWithNonretainedObject:o];
    if ([visited containsObject:key]) return;
    [visited addObject:key];

    if (LCHasLabel(o)) [out addObject:o];

    if ([o isKindOfClass:UIView.class]) {
        UIView *v = (UIView *)o;
        if (v.hidden || v.alpha < 0.01) return;
        for (UIView *sub in v.subviews) LCWalk(sub, out, visited, depth + 1);
    }
    if ([[o accessibilityElements] isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)[o accessibilityElements]) LCWalk(child, out, visited, depth + 1);
    }
}

static NSArray<NSObject *> *LCCollect(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *visited = [NSMutableSet set];
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            LCWalk(w, out, visited, 0);
        }
    }
    return out;
}

// Old apps rarely set accessibilityLabel, but their visible text always lives in some
// UILabel / UIButton title / UISegmentedControl segment / UITextField.
// This walks the element subtree and collects that text (depth 6), so interfaces without
// any a11y labels can still be located by text. No-op for SwiftUI (it has a11y labels),
// and no-op for WKWebView / Flutter (their text is not a UIKit control, use OCR there).
// Text inside a CALayer subtree (CATextLayer.string may be an NSString or NSAttributedString).
static void LCCollectLayerTexts(CALayer *layer, NSMutableArray<NSString *> *out, NSInteger depth) {
    if (!layer || depth > 6 || out.count >= 12) return;
    if ([layer isKindOfClass:NSClassFromString(@"CATextLayer")]) {
        id str = [(id)layer valueForKey:@"string"];
        NSString *plain = nil;
        if ([str isKindOfClass:NSString.class]) plain = str;
        else if ([str isKindOfClass:NSAttributedString.class]) plain = [(NSAttributedString *)str string];
        if (plain.length && ![out containsObject:plain]) [out addObject:plain];
    }
    for (CALayer *sub in layer.sublayers) LCCollectLayerTexts(sub, out, depth + 1);
}

static void LCCollectTexts(UIView *v, NSMutableArray<NSString *> *out, NSInteger depth) {
    // Menu items in old apps are often MenuBtn -> container -> UIStackView -> UILabel, deeper
    // than expected, hence depth 6 and at most 12 strings.
    if (!v || depth > 6 || out.count >= 12) return;
    NSString *t = nil;
    // CATextLayer: some custom buttons paint their text into layers (walk the layer subtree, not one level).
    LCCollectLayerTexts(v.layer, out, 0);
    if ([v isKindOfClass:UILabel.class]) {
        UILabel *lb = (UILabel *)v;
        t = lb.text.length ? lb.text : lb.attributedText.string;
    } else if ([v isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)v;
        for (NSNumber *st in @[@(UIControlStateNormal), @(UIControlStateSelected), @(UIControlStateHighlighted)]) {
            UIControlState state = (UIControlState)st.unsignedIntegerValue;
            NSString *title = [b titleForState:state];
            if (!title.length) title = [b attributedTitleForState:state].string;
            if (title.length && ![out containsObject:title]) [out addObject:title];
        }
    } else if ([v isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *seg = (UISegmentedControl *)v;
        for (NSUInteger i = 0; i < seg.numberOfSegments; i++) {
            NSString *title = [seg titleForSegmentAtIndex:i];
            if (title.length && ![out containsObject:title]) [out addObject:title];
        }
    } else if ([v isKindOfClass:UITextField.class]) {
        UITextField *f = (UITextField *)v;
        for (NSString *cand in @[f.text ?: @"", f.placeholder ?: @""]) {
            if (cand.length && ![out containsObject:cand]) [out addObject:cand];
        }
    } else if ([v isKindOfClass:UITextView.class]) {
        t = ((UITextView *)v).text;
    } else if ([v isKindOfClass:UISearchBar.class]) {
        t = ((UISearchBar *)v).placeholder;
    }
    if (t.length && ![out containsObject:t]) [out addObject:t];
    for (UIView *sub in v.subviews) LCCollectTexts(sub, out, depth + 1);
}

// Text of the element plus its subtree, joined into one readable string.
static NSArray<NSString *> *LCTextsOf(NSObject *o) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if ([o isKindOfClass:UIView.class]) LCCollectTexts((UIView *)o, out, 0);
    if (out.count == 0) {
        NSString *l = o.accessibilityLabel;
        if (l.length) [out addObject:l];
    }
    return out;
}

static NSDictionary *LCDescribe(NSObject *o) {
    CGRect frame = CGRectZero;
    if ([o isKindOfClass:UIView.class]) {
        UIView *v = (UIView *)o;
        frame = [v convertRect:v.bounds toView:nil];
    } else {
        frame = [o accessibilityFrame];
    }
    BOOL activatable = [o isKindOfClass:UIControl.class]
        || (o.accessibilityTraits & (UIAccessibilityTraitButton | UIAccessibilityTraitLink | UIAccessibilityTraitTabBar)) != 0;
    NSArray<NSString *> *texts = LCTextsOf(o);
    return @{
        @"label": o.accessibilityLabel ?: @"",
        @"text": [texts componentsJoinedByString: @" | "],
        @"texts": texts,
        @"identifier": ([o respondsToSelector:@selector(accessibilityIdentifier)] ? [o accessibilityIdentifier] : nil) ?: @"",
        @"value": ([o.accessibilityValue isKindOfClass:NSString.class] ? (NSString *)o.accessibilityValue : @""),
        @"class": NSStringFromClass(o.class),
        @"frame": @{@"x": @(frame.origin.x), @"y": @(frame.origin.y),
                    @"w": @(frame.size.width), @"h": @(frame.size.height)},
        @"control": @([o isKindOfClass:UIControl.class]),
        @"activatable": @(activatable)
    };
}

// -- actions ---------------------------------------------------------------

static UIWindow *LCKeyWindow(void) {
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return LCApp().windows.firstObject;
}

static NSDictionary *LCTap(CGFloat x, CGFloat y);
static NSDictionary *LCActivateHit(UIView *hit);

static NSDictionary *LCActivateObject(NSObject *o) {
    if ([o isKindOfClass:UIControl.class]) {
        [(UIControl *)o sendActionsForControlEvents:UIControlEventTouchUpInside];
        return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"sendActions on %@", NSStringFromClass(o.class)]};
    }
    if ([o accessibilityActivate]) {
        return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"accessibilityActivate on %@", NSStringFromClass(o.class)]};
    }
    if ([o isKindOfClass:UIView.class]) {
        UIView *v = (UIView *)o;
        CGPoint c = CGPointMake(v.bounds.size.width / 2, v.bounds.size.height / 2);
        UIView *hit = [v hitTest:c withEvent:nil];
        NSDictionary *r = hit && hit != v ? LCActivateHit(hit) : nil;
        if (r) return r;
    } else {
        CGRect f = [o accessibilityFrame];
        if (f.size.width > 1 && f.size.height > 1) {
            NSDictionary *r = LCTap(f.origin.x + f.size.width / 2, f.origin.y + f.size.height / 2);
            if ([r[@"ok"] boolValue]) return r;
            return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"a11y node cannot be activated and the coordinate tap failed too: %@", r[@"detail"]]};
        }
    }
    return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"%@ cannot be activated", NSStringFromClass(o.class)]};
}

static NSDictionary *LCActivateHit(UIView *hit) {
    UIView *cur = hit;
    while (cur) {
        if ([cur isKindOfClass:UIControl.class]) {
            [(UIControl *)cur sendActionsForControlEvents:UIControlEventTouchUpInside];
            return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"sendActions on %@", NSStringFromClass(cur.class)]};
        }
        if ([cur accessibilityActivate]) {
            return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"accessibilityActivate on %@", NSStringFromClass(cur.class)]};
        }
        cur = cur.superview;
    }
    return nil;
}

static NSDictionary *LCTap(CGFloat x, CGFloat y) {
    CGPoint p = CGPointMake(x, y);
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!CGRectContainsPoint(w.bounds, p)) continue;
            UIView *hit = [w hitTest:p withEvent:nil];
            if (!hit) continue;
            NSDictionary *r = LCActivateHit(hit);
            if (r) return r;
            return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"hit %@ but found no activatable control", NSStringFromClass(hit.class)]};
        }
    }
    return @{@"ok": @NO, @"detail": @"coordinate is outside every window"};
}

static NSDictionary *LCActivateSpec(NSDictionary *spec) {
    if (spec[@"x"] && spec[@"y"]) {
        return LCTap([spec[@"x"] doubleValue], [spec[@"y"] doubleValue]);
    }
    NSArray<NSObject *> *all = LCCollect();
    if (spec[@"index"]) {
        NSInteger idx = [spec[@"index"] integerValue];
        if (idx >= 0 && idx < (NSInteger)all.count) {
            return LCActivateObject(all[(NSUInteger)idx]);
        }
        return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"index %ld out of range (there are %lu elements; GET /api/v1/guest/ui/tree to refresh)", (long)idx, (unsigned long)all.count]};
    }
    NSString *label = [spec[@"label"] isKindOfClass:NSString.class] ? spec[@"label"] : nil;
    NSString *ident = [spec[@"identifier"] isKindOfClass:NSString.class] ? spec[@"identifier"] : nil;
    NSString *txt   = [spec[@"text"] isKindOfClass:NSString.class] ? spec[@"text"] : nil;
    if (!label.length && !ident.length && !txt.length) {
        return @{@"ok": @NO, @"detail": @"need index / text / label / identifier / x+y"};
    }
    // Locate by on-screen text (old apps have no a11y label, but UILabel/UIButton titles carry it).
    if (txt.length && !label.length && !ident.length) {
        // Exact match first, then substring.
        for (int pass = 0; pass < 2; pass++) {
            for (NSObject *o in all) {
                NSArray<NSString *> *ts = LCTextsOf(o);
                BOOL hit = NO;
                for (NSString *t in ts) {
                    if (pass == 0 ? [t isEqualToString:txt] : [t containsString:txt]) { hit = YES; break; }
                }
                if (!hit) continue;
                NSDictionary *r = LCActivateObject(o);
                if ([r[@"ok"] boolValue]) return r;
            }
        }
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        for (NSObject *o in all) {
            NSArray<NSString *> *ts = LCTextsOf(o);
            if (ts.count) [seen addObject:[ts componentsJoinedByString:@"/"]];
            if (seen.count >= 12) break;
        }
        // Not in the view tree (painted/WebView) -> read the screen with OCR and tap the box centre.
        for (NSDictionary *it in LCOCRRun()[@"items"]) {
            NSString *t2 = it[@"text"];
            if (![t2 containsString:txt]) continue;
            CGFloat cx = [it[@"x"] doubleValue] + [it[@"w"] doubleValue] / 2.0;
            CGFloat cy = [it[@"y"] doubleValue] + [it[@"h"] doubleValue] / 2.0;
            NSDictionary *r = LCTap(cx, cy);
            NSMutableDictionary *m = [r mutableCopy];
            m[@"detail"] = [NSString stringWithFormat:@"OCR matched '%@' -> (%.0f,%.0f): %@",
                            t2, cx, cy, r[@"detail"] ?: @""];
            m[@"via"] = @"ocr";
            return m;
        }
        return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"no text '%@' (neither in the view tree nor in OCR); text visible in the view tree: %@",
                                        txt, [seen componentsJoinedByString:@", "]]};
    }
    for (NSObject *o in all) {
        BOOL match = NO;
        if (ident.length && [o respondsToSelector:@selector(accessibilityIdentifier)]) match = [[o accessibilityIdentifier] isEqualToString:ident];
        if (!match && label.length) {
            NSString *l = o.accessibilityLabel ?: @"";
            match = [l.lowercaseString isEqualToString:label.lowercaseString] || [l containsString:label];
        }
        if (!match) continue;
        NSDictionary *r = LCActivateObject(o);
        if ([r[@"ok"] boolValue]) return r;
    }
    return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"no activatable match for %@", label ?: ident]};
}

static UIView *LCFindTextInputView(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [stack addObject:w];
    }
    UIView *fallback = nil;
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        BOOL isInput = [v isKindOfClass:UITextField.class]
                    || [v isKindOfClass:UITextView.class]
                    || [v isKindOfClass:UISearchBar.class];
        if (isInput) {
            if (!fallback) fallback = v;
            if (!v.hidden && v.alpha > 0.01 && v.window) return v;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return fallback;
}

static NSDictionary *LCTextInput(NSString *text, BOOL replace) {
    UIView *fr = nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [stack addObject:w];
    }
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (v.isFirstResponder) { fr = v; break; }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    if (!fr) {
        // No first responder: find a text input ourselves (old apps often do not focus one).
        fr = LCFindTextInputView();
        if (fr) [fr becomeFirstResponder];
    }
    if (!fr) return @{@"ok": @NO, @"detail": @"no focusable text field on screen"};
    if (replace && ([fr isKindOfClass:UITextField.class] || [fr isKindOfClass:UITextView.class])) {
        // Remote clients usually want to set a field, not append to whatever is already there.
        if ([fr isKindOfClass:UITextField.class]) {
            UITextField *tf = (UITextField *)fr;
            tf.text = text;
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        } else {
            UITextView *tv = (UITextView *)fr;
            tv.text = text;
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
        }
        return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"setText on %@", NSStringFromClass(fr.class)]};
    }
    if ([fr conformsToProtocol:@protocol(UIKeyInput)] || [fr isKindOfClass:UITextField.class] || [fr isKindOfClass:UITextView.class]) {
        [(id<UIKeyInput>)fr insertText:text];
        return @{@"ok": @YES, @"detail": [NSString stringWithFormat:@"insertText on %@", NSStringFromClass(fr.class)]};
    }
    // UISearchBar: look for its inner textField.
    if ([fr isKindOfClass:UISearchBar.class]) {
        UITextField *tf = [(UISearchBar *)fr valueForKey:@"searchField"];
        if ([tf isKindOfClass:UITextField.class]) {
            [tf insertText:text];
            return @{@"ok": @YES, @"detail": @"insertText on UISearchBar.searchField"};
        }
    }
    return @{@"ok": @NO, @"detail": [NSString stringWithFormat:@"%@ does not accept text", NSStringFromClass(fr.class)]};
}

// maxWidth is in OUTPUT PIXELS: size is points and the bitmap is size * scale, so the target
// rect has to be maxWidth / scale points wide while the renderer keeps the device scale.
static UIImage *LCResize(UIImage *img, CGFloat maxWidth) {
    if (!img || maxWidth <= 0) return img;
    CGFloat pixelWidth = img.size.width * img.scale;
    if (pixelWidth <= maxWidth) return img;
    CGFloat ratio = maxWidth / pixelWidth;
    CGSize size = CGSizeMake(floor(img.size.width * ratio), floor(img.size.height * ratio));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
    f.scale = img.scale;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:f] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

// Cheap "is this image basically blank" probe (samples a grid, ignores alpha).
static BOOL LCIsBlankImage(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return YES;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (!w || !h) return YES;
    unsigned char buf[4 * 64];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, 8, 8, 8, 32, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) return YES;
    CGContextDrawImage(ctx, CGRectMake(0, 0, 8, 8), cg);
    CGContextRelease(ctx);
    NSUInteger lit = 0;
    for (int i = 0; i < 64; i++) {
        int v = buf[i * 4] + buf[i * 4 + 1] + buf[i * 4 + 2];
        if (v > 24) lit++;
    }
    return lit <= 2;
}

// Web content is rendered by the WebContent process, so drawViewHierarchy commonly returns black
// for WKWebView-based apps even when the view tree is perfectly fine. WKWebView can render itself
// for us (takeSnapshotWithConfiguration:), which is the only way to get real pixels there.
static UIView *LCFindLargestWebView(UIView *view, CGFloat *bestArea) {
    if (!view || view.hidden || view.alpha < 0.01) return nil;
    static Class kWebViewClass = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ kWebViewClass = NSClassFromString(@"WKWebView"); });
    UIView *best = nil;
    if (kWebViewClass && [view isKindOfClass:kWebViewClass]) {
        CGFloat area = view.bounds.size.width * view.bounds.size.height;
        if (area > *bestArea) { *bestArea = area; best = view; }
    }
    for (UIView *sub in view.subviews) {
        UIView *found = LCFindLargestWebView(sub, bestArea);
        if (found) best = found;
    }
    return best;
}

// Screenshot that prefers live web content over the (frequently black) view hierarchy.
static void LCSnapshotWithWeb(CGFloat maxWidth, void (^done)(UIImage *)) {
    UIImage *base = LCSnapshot(0);
    UIWindow *key = LCKeyWindow();
    CGFloat bestArea = 0;
    UIView *web = nil;
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || w.alpha < 0.01) continue;
            UIView *found = LCFindLargestWebView(w, &bestArea);
            if (found) web = found;
        }
    }
    SEL sel = NSSelectorFromString(@"takeSnapshotWithConfiguration:completionHandler:");
    CGFloat minArea = key ? key.bounds.size.width * key.bounds.size.height * 0.2 : 0;
    if (!web || !key || bestArea < minArea || ![web respondsToSelector:sel]) {
        done(LCResize(base, maxWidth));
        return;
    }
    CGRect frame = [web convertRect:web.bounds toView:nil];
    typedef void (*LCTakeSnapshotFn)(id, SEL, id, void (^)(UIImage *, NSError *));
    ((LCTakeSnapshotFn)objc_msgSend)(web, sel, nil, ^(UIImage *shot, NSError *err) {
        UIImage *out = base ?: shot;
        if (shot && base) {
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:key.bounds];
            out = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [base drawInRect:key.bounds];
                [shot drawInRect:frame];
            }];
        }
        done(LCResize(out, maxWidth));
    });
}

static UIImage *LCSnapshot(CGFloat maxWidth) {
    UIWindow *key = LCKeyWindow();
    if (!key || key.bounds.size.width < 1) return nil;

    // Composite every visible window of the scene instead of only the key window: an empty
    // placeholder window can be "key" while the app content lives in another one, which showed
    // up on device as an all-black screenshot next to a view tree with 33 elements.
    NSMutableArray<UIWindow *> *wins = [NSMutableArray array];
    for (UIScene *scene in LCApp().connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || w.alpha < 0.01) continue;
            [wins addObject:w];
        }
    }
    if (wins.count == 0) [wins addObject:key];
    [wins sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel < b.windowLevel) return NSOrderedAscending;
        if (a.windowLevel > b.windowLevel) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:key.bounds];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (UIWindow *w in wins) {
            CGContextSaveGState(ctx.CGContext);
            CGContextTranslateCTM(ctx.CGContext, w.frame.origin.x, w.frame.origin.y);
            BOOL drew = [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO];
            if (!drew) [w.layer renderInContext:ctx.CGContext];
            CGContextRestoreGState(ctx.CGContext);
        }
    }];
    if (!img) return nil;

    return LCResize(img, maxWidth);
}

// ── OCR ─────────────────────────────────────────────────────────────────────
// Painted text (drawRect / layers / WebView / Flutter) is invisible to the view tree, so read the picture.
// System Vision OCR (Chinese + English) returns normalised boxes mapped back to view coordinates.
// That makes "tap by text" work for any app, not only UIKit natives.
// -- OCR cache and history --------------------------------------------------
// Each OCR run is cached by a screen fingerprint (the same screen is never OCR'd twice)
// and appended to ocr-log.jsonl in the app group so a page's recognised text can be reviewed later.
static NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *gOcrCache;
static NSMutableArray<NSDictionary *> *gOcrHistory;
static NSString *gOcrLogPath;

static void LCOCRInitStore(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gOcrCache = [NSMutableDictionary dictionary];
        gOcrHistory = [NSMutableArray array];
        NSURL *dir = [LCGroupURL() URLByAppendingPathComponent:@"LiveContainer/RemoteControl"];
        if (!dir) dir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        gOcrLogPath = [[dir URLByAppendingPathComponent:@"ocr-log.jsonl"] path];
    });
}

// Screen fingerprint (8 bytes of sha256).
static NSString *LCImageDigest(UIImage *img) {
    NSData *thumb = LCGrayThumbOf(img);
    if (!thumb) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(thumb.bytes, (CC_LONG)thumb.length, digest);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 8; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *LCScreenDigest(void) {
    return LCImageDigest(LCSnapshot(220));
}

// Cached OCR run: returns (items, cached, digest).
static NSDictionary *LCOCRRunWithImage(UIImage *img) {
    LCOCRInitStore();
    NSString *digest = LCImageDigest(img);
    if (digest.length && gOcrCache[digest]) {
        return @{@"items": gOcrCache[digest], @"cached": @YES, @"digest": digest};
    }
    NSArray<NSDictionary *> *items = LCRecognizeImage(img);
    if (digest.length) {
        if (gOcrCache.count > 80) [gOcrCache removeAllObjects];
        gOcrCache[digest] = items;
    }
    NSDictionary *rec = @{@"ts": @([[NSDate date] timeIntervalSince1970]),
                          @"bundleId": NSBundle.mainBundle.bundleIdentifier ?: @"",
                          @"pid": @(getpid()),
                          @"digest": digest ?: @"",
                          @"count": @(items.count),
                          @"items": items};
    [gOcrHistory addObject:rec];
    if (gOcrHistory.count > 200) [gOcrHistory removeObjectAtIndex:0];
    if (gOcrLogPath.length) {
        NSData *line = [[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:rec options:0 error:nil]
                                              encoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:gOcrLogPath];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:gOcrLogPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:gOcrLogPath];
        }
        [fh seekToEndOfFile];
        [fh writeData:line];
        [fh writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    return @{@"items": items, @"cached": @NO, @"digest": digest ?: @""};
}

static NSDictionary *LCOCRRun(void) {
    return LCOCRRunWithImage(LCSnapshot(0));
}

// -- view-structure dump (answers "is this a control or painted?") ---------
static NSDictionary *LCInspectNode(UIView *v, NSInteger depth) {
    if (!v || depth > 8) return @{};
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    LCCollectTexts(v, texts, 0);
    NSMutableArray *kids = [NSMutableArray array];
    for (UIView *sub in v.subviews) [kids addObject:LCInspectNode(sub, depth + 1)];
    return @{@"class": NSStringFromClass(v.class),
             @"frame": @{@"x": @(v.frame.origin.x), @"y": @(v.frame.origin.y),
                         @"w": @(v.frame.size.width), @"h": @(v.frame.size.height)},
             @"hidden": @(v.hidden),
             @"alpha": @(v.alpha),
             @"userInteraction": @(v.userInteractionEnabled),
             @"isControl": @([v isKindOfClass:UIControl.class]),
             @"drawsItself": @(v.contentMode != UIViewContentModeRedraw && v.subviews.count == 0),
             @"texts": texts,
             @"subviews": kids};
}

static NSArray<NSDictionary *> *LCRecognizeImage(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return @[];
    CGSize pts = img.size;                 // point size == window bounds
    __block NSArray<NSDictionary *> *items = @[];
    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCGImage:cg orientation:kCGImagePropertyOrientationUp options:@{}];
    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] init];
    req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    req.recognitionLanguages = @[@"zh-Hans", @"en-US"];
    req.usesLanguageCorrection = YES;
    NSError *err = nil;
    if (![handler performRequests:@[req] error:&err]) {
        fprintf(stderr, "[LCGuestSidecar] ocr failed: %s\n", err.localizedDescription.UTF8String);
        return @[];
    }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (VNRecognizedTextObservation *obs in req.results) {
        VNRecognizedText *best = [obs topCandidates:1].firstObject;
        if (!best.string.length) continue;
        CGRect bb = obs.boundingBox;       // normalised, origin at bottom-left
        CGFloat x = bb.origin.x * pts.width;
        CGFloat w = bb.size.width * pts.width;
        CGFloat h = bb.size.height * pts.height;
        CGFloat y = (1.0 - bb.origin.y - bb.size.height) * pts.height;
        [out addObject:@{@"text": best.string,
                         @"confidence": @(best.confidence),
                         @"x": @(x), @"y": @(y), @"w": @(w), @"h": @(h)}];
    }
    items = out;
    return items;
}

static NSArray<NSDictionary *> *LCRecognizeText(void) {
    return LCRecognizeImage(LCSnapshot(0));
}

// Downscale the screen to a 48x96 thumbnail (UIGraphicsImageRenderer + RGBA bitmap;
// the earlier CGBitmapContextCreate(gray) variant read back all zeros on device, so diff was always 0).
static NSData *LCGrayThumbOf(UIImage *img) {
    if (!img) return nil;
    const CGFloat W = 48, H = 96;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(W, H) format:fmt];
    UIImage *small = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [img drawInRect:CGRectMake(0, 0, W, H)];
    }];
    CGImageRef cg = small.CGImage;
    if (!cg) return nil;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return nil;
    unsigned char *buf = calloc(w * h * 4, 1);
    if (!buf) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    return [NSData dataWithBytesNoCopy:buf length:w * h * 4 freeWhenDone:YES];
}

static NSData *LCGrayThumb(void) {
    return LCGrayThumbOf(LCSnapshot(220));
}

// Ratio of differing pixels between two thumbnails (0-1); catches subtle changes a hash comparison misses.
static double LCDiffRatio(NSData *a, NSData *b) {
    if (!a || !b || a.length != b.length || a.length == 0) return a == b ? 0.0 : 1.0;
    const unsigned char *pa = a.bytes, *pb = b.bytes;
    NSUInteger changed = 0, total = 0;
    for (NSUInteger i = 0; i + 3 < a.length; i += 4) {
        int la = (pa[i] * 30 + pa[i + 1] * 59 + pa[i + 2] * 11) / 100;
        int lb = (pb[i] * 30 + pb[i + 1] * 59 + pb[i + 2] * 11) / 100;
        if (abs(la - lb) > 8) changed++;
        total++;
    }
    return total ? (double)changed / (double)total : 0.0;
}

// -- request handling ------------------------------------------------------

static NSData *LCHandleRequest(NSString *method, NSString *path, NSDictionary *headers, NSData *body) {
    // Authentication.
    NSString *expected = LCReadSidecarToken();
    NSString *auth = headers[@"authorization"];
    if (expected.length) {
        NSString *want = [@"Bearer " stringByAppendingString:expected];
        if (![auth isEqualToString:want]) {
            return LCJSON(@{@"ok": @NO, @"error": @"unauthorized"}, 401, nil);
        }
    }

    NSString *purePath = [path componentsSeparatedByString:@"?"].firstObject;
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    NSRange q = [path rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        for (NSString *pair in [[path substringFromIndex:q.location + 1] componentsSeparatedByString:@"&"]) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count == 2) {
                NSString *decoded = [kv[1] stringByRemovingPercentEncoding] ?: kv[1];
                query[kv[0]] = decoded;
            }
        }
    }

    // All UI work is marshalled onto the main thread.
    __block NSData *result = nil;
    __block BOOL asyncPending = NO;      // web content snapshots complete later, on the main queue
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([purePath isEqualToString:@"/guest/info"]) {
            // Diagnostics: why a capture can be black is otherwise unguessable from the outside
            // (locked screen, offscreen scene, webview surface in another process).
            NSMutableArray *windowInfo = [NSMutableArray array];
            NSMutableArray *webInfo = [NSMutableArray array];
            NSInteger sceneState = -1;
            for (UIScene *scene in LCApp().connectedScenes) {
                sceneState = (NSInteger)scene.activationState;
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                    [windowInfo addObject:@{@"level": @(win.windowLevel),
                                            @"frame": NSStringFromCGRect(win.frame),
                                            @"hidden": @(win.hidden),
                                            @"alpha": @(win.alpha),
                                            @"key": @(win.isKeyWindow)}];
                    CGFloat area = 0;
                    UIView *v = LCFindLargestWebView(win, &area);
                    if (v) {
                        [webInfo addObject:@{@"class": NSStringFromClass(v.class),
                                             @"frame": NSStringFromCGRect([v convertRect:v.bounds toView:nil]),
                                             @"area": @(area),
                                             @"hidden": @(v.hidden),
                                             @"canSnapshot": @([v respondsToSelector:NSSelectorFromString(@"takeSnapshotWithConfiguration:completionHandler:")])}];
                    }
                }
            }
            UIImage *probe = LCSnapshot(0);
            UIWindow *w = LCKeyWindow();
            // view* is the guest's own coordinate space (old apps lay out at their own logical size,
            // which may differ from screen points); pass x/y in that space, and tree frames use it too.
            UIView *root = w.rootViewController.view ?: w;
            result = LCJSON(@{@"ok": @YES, @"pid": @(getpid()),
                              @"bundleId": NSBundle.mainBundle.bundleIdentifier ?: @"",
                              @"width": @(w.bounds.size.width), @"height": @(w.bounds.size.height),
                              @"viewWidth": @(root.bounds.size.width),
                              @"viewHeight": @(root.bounds.size.height),
                              @"sceneState": @(sceneState),
                              @"screenBrightness": @(UIScreen.mainScreen.brightness),
                              @"captureBlank": @(LCIsBlankImage(probe)),
                              @"windows": windowInfo,
                              @"webViews": webInfo}, 200, nil);
        } else if ([purePath isEqualToString:@"/guest/ocr"]) {
            NSString *want = query[@"text"];
            asyncPending = YES;
            LCSnapshotWithWeb(0, ^(UIImage *img) {
                NSDictionary *run = LCOCRRunWithImage(img);
                NSArray<NSDictionary *> *items = run[@"items"];
                if (want.length) {
                    NSMutableArray *hit = [NSMutableArray array];
                    for (NSDictionary *it in items) {
                        if ([it[@"text"] containsString:want]) [hit addObject:it];
                    }
                    result = LCJSON(@{@"ok": @YES, @"count": @(hit.count), @"items": hit,
                                      @"cached": run[@"cached"], @"digest": run[@"digest"]}, 200, nil);
                } else {
                    result = LCJSON(@{@"ok": @YES, @"count": @(items.count), @"items": items,
                                      @"cached": run[@"cached"], @"digest": run[@"digest"]}, 200, nil);
                }
                dispatch_semaphore_signal(sem);
            });
        } else if ([purePath isEqualToString:@"/guest/ocr/history"]) {
            LCOCRInitStore();
            NSInteger limit = query[@"limit"] ? [query[@"limit"] integerValue] : 20;
            NSArray *h = gOcrHistory;
            if (limit > 0 && (NSInteger)h.count > limit) {
                h = [h subarrayWithRange:NSMakeRange(h.count - limit, limit)];
            }
            result = LCJSON(@{@"ok": @YES, @"count": @(h.count), @"logPath": gOcrLogPath ?: @"",
                              @"records": h ?: @[]}, 200, nil);
        } else if ([purePath isEqualToString:@"/guest/inspect"]) {
            // Dump an element's view structure to tell whether its text is a control or painted.
            NSInteger idx = query[@"index"] ? [query[@"index"] integerValue] : -1;
            NSArray<NSObject *> *all = LCCollect();
            if (idx < 0 || idx >= (NSInteger)all.count) {
                result = LCJSON(@{@"ok": @NO, @"error": @"index out of range", @"count": @(all.count)}, 400, nil);
            } else {
                NSObject *o = all[(NSUInteger)idx];
                if ([o isKindOfClass:UIView.class]) {
                    result = LCJSON(@{@"ok": @YES, @"index": @(idx),
                                      @"tree": LCInspectNode((UIView *)o, 0)}, 200, nil);
                } else {
                    result = LCJSON(@{@"ok": @YES, @"index": @(idx), @"notAView": @YES,
                                      @"class": NSStringFromClass(o.class)}, 200, nil);
                }
            }
        } else if ([purePath isEqualToString:@"/guest/ui/tree"]) {
            NSMutableArray *items = [NSMutableArray array];
            NSArray<NSObject *> *all = LCCollect();
            [all enumerateObjectsUsingBlock:^(NSObject *o, NSUInteger i, BOOL *stop) {
                NSMutableDictionary *d = [LCDescribe(o) mutableCopy];
                d[@"index"] = @(i);
                [items addObject:d];
            }];
            result = LCJSON(@{@"ok": @YES, @"count": @(items.count), @"elements": items}, 200, nil);
        } else if ([purePath isEqualToString:@"/guest/ui/activate"] || [purePath isEqualToString:@"/guest/ui/tap"]) {
            NSDictionary *spec = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
            if (![spec isKindOfClass:NSDictionary.class]) spec = @{};
            NSDictionary *r = [purePath hasSuffix:@"/tap"] ? LCTap([spec[@"x"] doubleValue], [spec[@"y"] doubleValue])
                                                          : LCActivateSpec(spec);
            NSMutableDictionary *out = [r mutableCopy]; out[@"ok"] = r[@"ok"] ?: @NO;
            result = LCJSON(out, 200, nil);
        } else if ([purePath isEqualToString:@"/guest/ui/taps"]) {
            NSDictionary *spec = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
            NSArray *steps = [spec isKindOfClass:NSDictionary.class] ? spec[@"steps"] : nil;
            BOOL detect = spec[@"detectChange"] ? [spec[@"detectChange"] boolValue] : YES;
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *step in steps ?: @[]) {
                NSData *before = detect ? LCGrayThumb() : nil;
                NSDictionary *r = [step isKindOfClass:NSDictionary.class] ? LCActivateSpec(step)
                                                                          : @{@"ok": @NO, @"detail": @"step is not an object"};
                NSInteger delay = step[@"delayMs"] ? [step[@"delayMs"] integerValue] : 400;
                if (delay > 0) [NSThread sleepForTimeInterval:delay / 1000.0];
                NSMutableDictionary *item = [@{@"ok": r[@"ok"] ?: @NO, @"detail": r[@"detail"] ?: @""} mutableCopy];
                if (detect) {
                    double ratio = LCDiffRatio(before, LCGrayThumb());
                    item[@"changed"] = @(ratio > 0.002);   // 0.2% of pixels changing counts as a change
                    item[@"diff"] = @(round(ratio * 10000) / 10000.0);
                }
                [out addObject:item];
            }
            result = LCJSON(@{@"ok": @YES, @"count": @(out.count), @"steps": out}, 200, nil);
        } else if ([purePath isEqualToString:@"/guest/ui/text"]) {
            NSDictionary *spec = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : @{};
            NSString *text = [spec isKindOfClass:NSDictionary.class] ? spec[@"text"] : nil;
            BOOL replace = spec[@"replace"] ? [spec[@"replace"] boolValue] : NO;
            result = LCJSON(LCTextInput(text ?: @"", replace), 200, nil);
        } else if ([purePath isEqualToString:@"/guest/screenshot"]) {
            CGFloat maxWidth = query[@"maxWidth"] ? [query[@"maxWidth"] doubleValue] : 600;
            CGFloat quality = query[@"quality"] ? [query[@"quality"] doubleValue] / 100.0 : 0.7;
            asyncPending = YES;
            LCSnapshotWithWeb(maxWidth, ^(UIImage *img) {
                NSData *d = UIImageJPEGRepresentation(img, quality);
                result = d ? LCBinary(d, @"image/jpeg", 200) : LCJSON(@{@"ok": @NO, @"error": @"capture failed"}, 500, nil);
                dispatch_semaphore_signal(sem);
            });
        } else {
            result = LCJSON(@{@"ok": @NO, @"error": @"no route"}, 404, nil);
        }
        if (!asyncPending) dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20ull * NSEC_PER_SEC));
    return result ?: LCJSON(@{@"ok": @NO, @"error": @"timeout"}, 500, nil);
}

// -- socket server ---------------------------------------------------------

static void LCServeConnection(int fd) {  // needs #include <sys/time.h>
    NSMutableData *buf = [NSMutableData data];
    uint8_t chunk[8192];
    NSData *headerEnd = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger headerLen = 0;
    long contentLength = 0;

    while (true) {
        ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
        if (n <= 0) break;
        [buf appendBytes:chunk length:(NSUInteger)n];

        if (headerLen == 0) {
            NSRange r = [buf rangeOfData:headerEnd options:0 range:NSMakeRange(0, buf.length)];
            if (r.location == NSNotFound) {
                if (buf.length > 128 * 1024) break;
                continue;
            }
            headerLen = r.location + r.length;
            NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, r.location)]
                                                   encoding:NSUTF8StringEncoding];
            for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
                NSRange colon = [line rangeOfString:@":"];
                if (colon.location != NSNotFound) {
                    NSString *name = [[line substringToIndex:colon.location] lowercaseString];
                    NSString *value = [[line substringFromIndex:colon.location + 1]
                                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                    if ([name isEqualToString:@"content-length"]) contentLength = value.longLongValue;
                }
            }
        }
        if (buf.length >= headerLen + (NSUInteger)contentLength) break;
        if (buf.length > 64 * 1024 * 1024) break;
    }

    if (buf.length < headerLen) { close(fd); return; }

    NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, headerLen - 4)]
                                           encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray<NSString *> *requestLine = [lines.firstObject componentsSeparatedByString:@" "];
    NSString *method = requestLine.count > 0 ? requestLine[0] : @"GET";
    NSString *path = requestLine.count > 1 ? requestLine[1] : @"/";

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSRange colon = [lines[i] rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[lines[i] substringToIndex:colon.location] lowercaseString];
        NSString *value = [[lines[i] substringFromIndex:colon.location + 1]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        headers[name] = value;
    }

    NSData *body = buf.length > headerLen ? [buf subdataWithRange:NSMakeRange(headerLen, buf.length - headerLen)] : [NSData data];
    fprintf(stderr, "[LCGuestSidecar] %s %s\n", method.UTF8String, path.UTF8String);
    NSData *resp = LCHandleRequest(method, path, headers, body);

    const uint8_t *bytes = resp.bytes;
    NSUInteger remaining = resp.length;
    while (remaining > 0) {
        ssize_t sent = send(fd, bytes, remaining, 0);
        if (sent <= 0) break;
        bytes += sent;
        remaining -= (NSUInteger)sent;
    }
    close(fd);
}

void LCGuestSidecarStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        signal(SIGPIPE, SIG_IGN);
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return;
        int yes = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(kLCGuestSidecarPort);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            fprintf(stderr, "[LCGuestSidecar] bind failed: %s\n", strerror(errno));
            close(fd);
            return;
        }
        if (listen(fd, 16) != 0) {
            fprintf(stderr, "[LCGuestSidecar] listen failed: %s\n", strerror(errno));
            close(fd);
            return;
        }

        // The accept loop must not share a queue with connection handling: with one serial queue the
        // loop never returns, queued handlers never run, and every request hangs until it times out.
        dispatch_queue_t acceptQ = dispatch_queue_create("lc.guest.sidecar.accept", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_t workQ = dispatch_queue_create("lc.guest.sidecar.work", DISPATCH_QUEUE_CONCURRENT);
        dispatch_async(acceptQ, ^{
            fprintf(stderr, "[LCGuestSidecar] listening on 127.0.0.1:%d\n", kLCGuestSidecarPort);
            while (true) {
                int client = accept(fd, NULL, NULL);
                if (client < 0) continue;
                struct timeval tv = { 10, 0 };
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
                setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
                dispatch_async(workQ, ^{ LCServeConnection(client); });
            }
        });
    });
}
