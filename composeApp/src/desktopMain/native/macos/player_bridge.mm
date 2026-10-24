#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#define GL_SILENCE_DEPRECATION
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import <GameController/GameController.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

#include <jni.h>
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

#include <atomic>
#include <algorithm>
#include <chrono>
#include "crop_detection.h"
#include <cmath>
#include <dlfcn.h>
#include <mutex>
#include <string>
#include <vector>
#include "hdr_output.h"

@class PlayerMetalView;
@class MpvWebPlayer;
@class NuvioPlayerOpenGLLayer;
static __weak MpvWebPlayer *nuvioMediaOwner;

@interface PlayerMetalView : NSView
- (double)edrMax;
- (double)hdrTargetPeakNits;
- (CGSize)drawableSize;
- (void)updateMetalLayerLayout;
- (void)refreshMetalLayerEdrState;
- (void)configureExtendedDynamicRange:(BOOL)enabled primaries:(NSString *)primaries targetPeakNits:(double)targetPeakNits;
- (BOOL)createMpvRenderContext:(mpv_handle *)mpv error:(NSString **)error;
- (void)destroyMpvRenderContext;
- (void)scheduleRenderUpdate;
- (void)setFullscreenTransitionActive:(BOOL)active;
@end

@interface NuvioMainThreadPriorityLock : NSObject
- (void)beforeLocking;
- (void)afterLocked;
@end

@interface NuvioPlayerOpenGLLayer : CAOpenGLLayer
@property(nonatomic, assign, getter=isNuvioLiveResize) BOOL nuvioLiveResize;
@property(nonatomic, assign, readonly) GLint bufferDepth;
- (instancetype)initWithOwner:(PlayerMetalView *)owner;
- (void)setMpvRenderContext:(mpv_render_context *)renderContext;
- (void)clearMpvRenderContext;
- (void)requestRender;
- (void)requestRenderForced:(BOOL)force;
- (void)lockAndSetContext;
- (void)unlockContext;
@end

@interface PlayerScriptHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) MpvWebPlayer *player;
@end

@interface MpvWebPlayer : NSObject
- (instancetype)initWithHostView:(NSView *)hostView
                       sourceUrl:(NSString *)sourceUrl
                   audioSourceUrl:(NSString *)audioSourceUrl
                    headerLines:(NSArray<NSString *> *)headerLines
                     mpvOptions:(NSArray<NSString *> *)mpvOptions
                   playWhenReady:(BOOL)playWhenReady
                initialPositionMs:(long long)initialPositionMs
          initialProgressFraction:(double)initialProgressFraction
                      controlsUrl:(NSString *)controlsUrl
                           javaVm:(JavaVM *)javaVm
                        eventSink:(jobject)eventSink
                      eventMethod:(jmethodID)eventMethod;
- (void)shutdown;
- (void)requestSeekThumbnail:(long long)positionMs;
- (int)decodeSpeechSpot:(double)start duration:(double)duration output:(NSString *)output;
- (double)speechSourceBytesPerSecond;
- (void)setMediaTitle:(NSString *)title subtitle:(NSString *)subtitle artwork:(NSString *)artwork;
- (void)checkAutoCrop;
- (void)updateNowPlayingPosition:(double)position duration:(double)duration paused:(BOOL)paused;

- (void)updateControlsJson:(NSString *)controlsJson;
- (void)runJavaScript:(NSString *)script;
- (void)setCursorHidden:(BOOL)hidden;
- (void)forceVideoRedraw;
- (void)setStringProperty:(const char *)name value:(NSString *)value;
- (double)doubleProperty:(const char *)name fallback:(double)fallback;
- (BOOL)flagProperty:(const char *)name fallback:(BOOL)fallback;
- (void)setSubtitleAssStyleMode:(NSString *)mode scale:(double)scale;
- (void)setHdrMode:(NSString *)mode;
- (void)setDisplayPanel:(NSString *)panel;
- (void)setPaused:(BOOL)paused;
- (BOOL)isPaused;
- (void)seekToMilliseconds:(long long)positionMs;
- (void)seekByMilliseconds:(long long)offsetMs;
- (void)setSpeed:(double)speed;
- (double)speed;
- (void)setResizeMode:(int)mode;
- (long long)durationMs;
- (long long)positionMs;
- (long long)bufferedPositionMs;
- (BOOL)isLoading;
- (BOOL)isEnded;
- (NSString *)audioTracksJson;
- (NSString *)subtitleTracksJson;
- (NSString *)chaptersJson;
- (BOOL)selectAudioTrackId:(int)trackId;
- (BOOL)selectSubtitleTrackId:(int)trackId;
- (void)addSubtitleUrl:(NSString *)url;
- (void)removeExternalSubtitles;
- (void)removeExternalSubtitlesAndSelect:(int)trackId;
- (void)setSubtitleDelayMs:(int)delayMs;
- (void)applySubtitleStyleWithTextColor:(NSString *)textColor
                        backgroundColor:(NSString *)backgroundColor
                            outlineColor:(NSString *)outlineColor
                             outlineSize:(double)outlineSize
                                    bold:(BOOL)bold
                                fontSize:(double)fontSize
                                 subPos:(int)subPos;
- (void)toggleStatsOverlay;
- (void)handleScriptMessage:(NSDictionary *)message;
- (void)focusControlsWebViewIfNeeded;
- (void)layoutNativeSubviews;
- (void)layoutControlsWebViewToBounds:(NSRect)bounds immediate:(BOOL)immediate;
- (void)hostViewBoundsDidChange:(NSNotification *)notification;
- (void)hostViewFrameDidChange:(NSNotification *)notification;
- (void)windowWillEnterFullScreen:(NSNotification *)notification;
- (void)windowDidEnterFullScreen:(NSNotification *)notification;
- (void)windowWillExitFullScreen:(NSNotification *)notification;
- (void)windowDidExitFullScreen:(NSNotification *)notification;
- (void)activateFullscreenTransitionWithReason:(NSString *)reason;
- (void)beginFullscreenTransitionWithReason:(NSString *)reason;
- (void)finishFullscreenTransitionWithReason:(NSString *)reason;
- (void)handleFullscreenTransitionTimer:(NSTimer *)timer;
- (void)schedulePostResizeRefreshWithReason:(NSString *)reason;
- (void)handleResizeSettleTimer:(NSTimer *)timer;
- (void)configureHdrForCurrentScreenWithReason:(NSString *)reason force:(BOOL)force;
- (void)applyHdrForPolledGamma:(NSString *)gamma primaries:(NSString *)primaries reason:(NSString *)reason force:(BOOL)force;
@end

typedef CFDictionaryRef (*CoreDisplayCreateInfoDictionaryFn)(CGDirectDisplayID displayId);

static void setBoolWithSelector(id target, NSString *selectorName, BOOL value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return;
    }
    typedef void (*Setter)(id, SEL, BOOL);
    Setter setter = (Setter)[target methodForSelector:selector];
    setter(target, selector, value);
}

static double doubleWithSelector(id target, NSString *selectorName, double fallback) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return fallback;
    }
    typedef double (*Getter)(id, SEL);
    Getter getter = (Getter)[target methodForSelector:selector];
    return getter(target, selector);
}

static BOOL setLayerColorSpace(CALayer *layer, CGColorSpaceRef colorSpace) {
    SEL selector = NSSelectorFromString(@"setColorspace:");
    if (!layer || !colorSpace || ![layer respondsToSelector:selector]) {
        return NO;
    }
    typedef void (*Setter)(id, SEL, CGColorSpaceRef);
    Setter setter = (Setter)[layer methodForSelector:selector];
    setter(layer, selector, colorSpace);
    return YES;
}

static BOOL setLayerEdrMetadata(CALayer *layer, double minNits, double maxNits, double opticalOutputScale) {
    if (!layer || maxNits <= 0.0) {
        return NO;
    }

    Class edrMetadataClass = NSClassFromString(@"CAEDRMetadata");
    SEL selector = NSSelectorFromString(@"HDR10MetadataWithMinLuminance:maxLuminance:opticalOutputScale:");
    if (!edrMetadataClass || ![edrMetadataClass respondsToSelector:selector]) {
        return NO;
    }

    typedef id (*Factory)(id, SEL, float, float, float);
    Factory factory = (Factory)[edrMetadataClass methodForSelector:selector];
    id metadata = factory(edrMetadataClass, selector, (float)minNits, (float)maxNits, (float)opticalOutputScale);
    if (!metadata) {
        return NO;
    }

    SEL setterSelector = NSSelectorFromString(@"setEDRMetadata:");
    if (![layer respondsToSelector:setterSelector]) {
        return NO;
    }
    typedef void (*Setter)(id, SEL, id);
    Setter setter = (Setter)[layer methodForSelector:setterSelector];
    setter(layer, setterSelector, metadata);
    return YES;
}

static void clearLayerEdrMetadata(CALayer *layer) {
    SEL selector = NSSelectorFromString(@"setEDRMetadata:");
    if (!layer || ![layer respondsToSelector:selector]) {
        return;
    }
    typedef void (*Setter)(id, SEL, id);
    Setter setter = (Setter)[layer methodForSelector:selector];
    setter(layer, selector, nil);
}

static CGColorSpaceRef copyPqColorSpaceForPrimaries(NSString *primaries) {
    NSString *normalized = [[primaries ?: @"" lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    CFStringRef name = [normalized isEqualToString:@"display-p3"]
        ? kCGColorSpaceDisplayP3_PQ
        : kCGColorSpaceITUR_2100_PQ;
    return CGColorSpaceCreateWithName(name);
}

static NSString *diagnosticSize(CGSize size) {
    return [NSString stringWithFormat:@"%0.0fx%0.0f", size.width, size.height];
}

static NSString *diagnosticRect(NSRect rect) {
    return [NSString stringWithFormat:
        @"%0.0fx%0.0f@%0.0f,%0.0f",
        rect.size.width,
        rect.size.height,
        rect.origin.x,
        rect.origin.y
    ];
}

static CGDirectDisplayID displayIdForScreen(NSScreen *screen) {
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    return screenNumber ? (CGDirectDisplayID)screenNumber.unsignedIntValue : CGMainDisplayID();
}

static double edrMaxForScreen(NSScreen *screen) {
    NSScreen *targetScreen = screen ?: NSScreen.mainScreen;
    double maxValue = doubleWithSelector(
        targetScreen,
        @"maximumPotentialExtendedDynamicRangeColorComponentValue",
        1.0
    );
    if (!std::isfinite(maxValue) || maxValue <= 0.0) {
        return 1.0;
    }
    return maxValue;
}

static CoreDisplayCreateInfoDictionaryFn coreDisplayInfoDictionaryFn(void) {
    static BOOL didLookup = NO;
    static CoreDisplayCreateInfoDictionaryFn fn = nullptr;
    if (!didLookup) {
        didLookup = YES;
        void *handle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY | RTLD_LOCAL
        );
        fn = (CoreDisplayCreateInfoDictionaryFn)dlsym(
            handle ?: RTLD_DEFAULT,
            "CoreDisplay_DisplayCreateInfoDictionary"
        );
    }
    return fn;
}

static double doubleFromCoreDisplayValue(CFTypeRef value) {
    if (!value) {
        return 0.0;
    }
    CFTypeID typeId = CFGetTypeID(value);
    if (typeId == CFNumberGetTypeID()) {
        double result = 0.0;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result)) {
            return result;
        }
        return 0.0;
    }
    if (typeId == CFDictionaryGetTypeID()) {
        CFDictionaryRef dictionary = (CFDictionaryRef)value;
        double directPeak = doubleFromCoreDisplayValue(
            CFDictionaryGetValue(dictionary, CFSTR("NonReferencePeakHDRLuminance"))
        );
        if (directPeak > 0.0) {
            return directPeak;
        }
        return doubleFromCoreDisplayValue(
            CFDictionaryGetValue(dictionary, CFSTR("DisplayBacklight"))
        );
    }
    return 0.0;
}

static double coreDisplayPeakNitsForScreen(NSScreen *screen) {
    CoreDisplayCreateInfoDictionaryFn fn = coreDisplayInfoDictionaryFn();
    if (!fn) {
        return 0.0;
    }
    CFDictionaryRef info = fn(displayIdForScreen(screen ?: NSScreen.mainScreen));
    if (!info) {
        return 0.0;
    }
    double peak = doubleFromCoreDisplayValue(info);
    CFRelease(info);
    if (!std::isfinite(peak) || peak < 100.0 || peak > 10000.0) {
        return 0.0;
    }
    return peak;
}

static double fixedPointNitsFromRegistryValue(CFTypeRef value) {
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0.0;
    }
    double raw = 0.0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &raw) || raw <= 0.0) {
        return 0.0;
    }
    double nits = raw / 65536.0;
    if (!std::isfinite(nits) || nits < 100.0 || nits > 10000.0) {
        return 0.0;
    }
    return nits;
}

static double ioRegistryPeakNits(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOMobileFramebufferShim");
    if (!matching) {
        return 0.0;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(MACH_PORT_NULL, matching, &iterator);
    if (result != KERN_SUCCESS || iterator == IO_OBJECT_NULL) {
        return 0.0;
    }

    double peak = 0.0;
    io_object_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFTypeRef indicatorCap = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("IOMFBIndicatorNitsCap"),
            kCFAllocatorDefault,
            0
        );
        peak = fmax(peak, fixedPointNitsFromRegistryValue(indicatorCap));
        if (indicatorCap) {
            CFRelease(indicatorCap);
        }

        CFTypeRef rtplcCap = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("RTPLCBLNitsCap"),
            kCFAllocatorDefault,
            0
        );
        peak = fmax(peak, fixedPointNitsFromRegistryValue(rtplcCap));
        if (rtplcCap) {
            CFRelease(rtplcCap);
        }

        CFTypeRef backlightCap = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("BLNitsCap"),
            kCFAllocatorDefault,
            0
        );
        peak = fmax(peak, fixedPointNitsFromRegistryValue(backlightCap));
        if (backlightCap) {
            CFRelease(backlightCap);
        }

        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return peak;
}

static double hdrTargetPeakNitsForScreen(NSScreen *screen) {
    double coreDisplayPeak = coreDisplayPeakNitsForScreen(screen);
    if (coreDisplayPeak > 0.0) {
        return coreDisplayPeak;
    }
    double registryPeak = ioRegistryPeakNits();
    if (registryPeak > 0.0) {
        return registryPeak;
    }
    double edrMax = edrMaxForScreen(screen);
    if (edrMax > 1.0) {
        return fmin(fmax(edrMax * 100.0, 100.0), 10000.0);
    }
    return 100.0;
}

static double hdrMetadataMaxNits(void) {
    return 1000.0;
}

static double normalizedHdrMetadataMaxNits(double targetPeakNits) {
    if (std::isfinite(targetPeakNits) && targetPeakNits >= 100.0 && targetPeakNits <= 10000.0) {
        return targetPeakNits;
    }
    return hdrMetadataMaxNits();
}

static CGLPixelFormatObj createPlayerOpenGLPixelFormat(GLint *bufferDepth) {
    CGLPixelFormatObj pixelFormat = nullptr;
    GLint pixelCount = 0;
    CGLPixelFormatAttribute hdrAttributes[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)64,
        kCGLPFAColorFloat,
        kCGLPFANoRecovery,
        kCGLPFAAllowOfflineRenderers,
        (CGLPixelFormatAttribute)0
    };
    CGLError error = CGLChoosePixelFormat(hdrAttributes, &pixelFormat, &pixelCount);
    if (error == kCGLNoError && pixelFormat) {
        if (bufferDepth) {
            *bufferDepth = 16;
        }
        return pixelFormat;
    }

    CGLPixelFormatAttribute fallbackAttributes[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)32,
        kCGLPFANoRecovery,
        kCGLPFAAllowOfflineRenderers,
        (CGLPixelFormatAttribute)0
    };
    pixelFormat = nullptr;
    pixelCount = 0;
    error = CGLChoosePixelFormat(fallbackAttributes, &pixelFormat, &pixelCount);
    if (error == kCGLNoError && pixelFormat) {
        if (bufferDepth) {
            *bufferDepth = 8;
        }
        return pixelFormat;
    }
    return nullptr;
}

static CGLContextObj createPlayerOpenGLContext(CGLPixelFormatObj pixelFormat) {
    CGLContextObj context = nullptr;
    if (!pixelFormat || CGLCreateContext(pixelFormat, nullptr, &context) != kCGLNoError || !context) {
        return nullptr;
    }
    GLint swapInterval = 1;
    CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval);
    CGLEnable(context, kCGLCEMPEngine);
    return context;
}

static void *mpvOpenGLGetProcAddress(void *ctx, const char *name) {
    if (!name) {
        return nullptr;
    }
    CFBundleRef framework = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    if (!framework) {
        return nullptr;
    }
    CFStringRef symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
    if (!symbol) {
        return nullptr;
    }
    void *address = CFBundleGetFunctionPointerForName(framework, symbol);
    CFRelease(symbol);
    return address;
}

@implementation NuvioMainThreadPriorityLock {
    NSCondition *_condition;
    BOOL _mainThreadNeedsLock;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _condition = [NSCondition new];
    return self;
}

- (void)beforeLocking {
    [_condition lock];
    if ([NSThread isMainThread]) {
        _mainThreadNeedsLock = YES;
    } else {
        while (_mainThreadNeedsLock) {
            [_condition wait];
        }
    }
    [_condition unlock];
}

- (void)afterLocked {
    if (![NSThread isMainThread]) {
        return;
    }
    [_condition lock];
    _mainThreadNeedsLock = NO;
    [_condition broadcast];
    [_condition unlock];
}

@end

@implementation NuvioPlayerOpenGLLayer {
    __weak PlayerMetalView *_owner;
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _glContext;
    dispatch_queue_t _renderQueue;
    NSRecursiveLock *_displayLock;
    NuvioMainThreadPriorityLock *_mainThreadPriorityLock;
    NSRecursiveLock *_renderLock;
    mpv_render_context *_renderContext;
    std::atomic_bool _needsFlip;
    std::atomic_bool _forceDraw;
    std::atomic_bool _renderQueued;
}

@synthesize nuvioLiveResize = _nuvioLiveResize;
@synthesize bufferDepth = _bufferDepth;

- (instancetype)initWithOwner:(PlayerMetalView *)owner {
    self = [super init];
    if (!self) {
        return nil;
    }
    _owner = owner;
    _renderQueue = dispatch_queue_create("com.nuvio.player.mpvgl", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_renderQueue, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    _displayLock = [NSRecursiveLock new];
    _mainThreadPriorityLock = [NuvioMainThreadPriorityLock new];
    _renderLock = [NSRecursiveLock new];
    _needsFlip.store(false);
    _forceDraw.store(false);
    _renderQueued.store(false);
    _pixelFormat = createPlayerOpenGLPixelFormat(&_bufferDepth);
    _glContext = createPlayerOpenGLContext(_pixelFormat);
    self.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    self.backgroundColor = NSColor.blackColor.CGColor;
    self.opaque = YES;
    self.asynchronous = NO;
    self.needsDisplayOnBoundsChange = YES;
    if (_bufferDepth > 8) {
        self.contentsFormat = kCAContentsFormatRGBA16Float;
    }
    return self;
}

- (void)dealloc {
    if (_glContext) {
        CGLReleaseContext(_glContext);
        _glContext = nullptr;
    }
    if (_pixelFormat) {
        CGLReleasePixelFormat(_pixelFormat);
        _pixelFormat = nullptr;
    }
}

- (void)setNuvioLiveResize:(BOOL)nuvioLiveResize {
    if (_nuvioLiveResize == nuvioLiveResize) {
        return;
    }
    _nuvioLiveResize = nuvioLiveResize;
    if (nuvioLiveResize) {
        self.asynchronous = YES;
        [self requestRenderForced:YES];
    } else {
        self.asynchronous = NO;
    }
}

- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask {
    return _pixelFormat ? CGLRetainPixelFormat(_pixelFormat) : nullptr;
}

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pixelFormat {
    return _glContext ? CGLRetainContext(_glContext) : nullptr;
}

- (BOOL)canDrawInCGLContext:(CGLContextObj)ctx
                pixelFormat:(CGLPixelFormatObj)pf
               forLayerTime:(CFTimeInterval)t
                displayTime:(const CVTimeStamp *)ts {
    if (_nuvioLiveResize && [NSThread isMainThread]) {
        return NO;
    }
    if (!_nuvioLiveResize) {
        self.asynchronous = NO;
    }

    return _forceDraw.load() || _needsFlip.load();
}

- (void)drawInCGLContext:(CGLContextObj)ctx
             pixelFormat:(CGLPixelFormatObj)pf
            forLayerTime:(CFTimeInterval)t
             displayTime:(const CVTimeStamp *)ts {
    [_renderLock lock];
    mpv_render_context *renderContext = _renderContext;
    _needsFlip.store(false);
    _forceDraw.store(false);
    if (!renderContext) {
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glFlush();
        [_renderLock unlock];
        return;
    }

    GLint framebuffer = 0;
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &framebuffer);
    CGFloat scale = self.contentsScale > 0.0 ? self.contentsScale : 1.0;
    CGSize drawableSize = CGSizeMake(
        llround(self.bounds.size.width * scale),
        llround(self.bounds.size.height * scale)
    );
    if (drawableSize.width <= 1.0 || drawableSize.height <= 1.0) {
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glFlush();
        [_renderLock unlock];
        return;
    }
    glViewport(0, 0, (GLsizei)drawableSize.width, (GLsizei)drawableSize.height);
    mpv_opengl_fbo fbo = {
        (int)framebuffer,
        (int)drawableSize.width,
        (int)drawableSize.height,
        0
    };
    int flipY = 1;
    int depth = (int)_bufferDepth;
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_OPENGL_FBO, &fbo },
        { MPV_RENDER_PARAM_FLIP_Y, &flipY },
        { MPV_RENDER_PARAM_DEPTH, &depth },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };
    mpv_render_context_render(renderContext, params);
    mpv_render_context_report_swap(renderContext);
    glFlush();
    [_renderLock unlock];
}

- (void)display {
    [_mainThreadPriorityLock beforeLocking];
    [_displayLock lock];
    [_mainThreadPriorityLock afterLocked];
    if ([NSThread isMainThread]) {
        [super display];
    } else {
        [CATransaction begin];
        [super display];
        [CATransaction commit];
    }
    [CATransaction flush];
    [_displayLock unlock];
}

- (void)setMpvRenderContext:(mpv_render_context *)renderContext {
    [_renderLock lock];
    _renderContext = renderContext;
    _forceDraw.store(true);
    [_renderLock unlock];
    [self requestRenderForced:YES];
}

- (void)clearMpvRenderContext {
    [_renderLock lock];
    _renderContext = nullptr;
    _needsFlip.store(false);
    _forceDraw.store(true);
    [_renderLock unlock];
}

- (void)requestRender {
    [self requestRenderForced:NO];
}

- (void)requestRenderForced:(BOOL)force {
    if (force) {
        _forceDraw.store(true);
    }
    _needsFlip.store(true);
    bool expected = false;
    if (!_renderQueued.compare_exchange_strong(expected, true)) {
        return;
    }

    dispatch_async(_renderQueue, ^{
        self->_renderQueued.store(false);
        [self display];
    });
}

- (void)lockAndSetContext {
    if (!_glContext) {
        return;
    }
    CGLLockContext(_glContext);
    CGLSetCurrentContext(_glContext);
}

- (void)unlockContext {
    if (!_glContext) {
        return;
    }
    CGLUnlockContext(_glContext);
}

@end

static void mpvRenderUpdateCallback(void *callbackContext) {
    PlayerMetalView *view = (__bridge PlayerMetalView *)callbackContext;
    [view scheduleRenderUpdate];
}

@implementation PlayerMetalView {
    NuvioPlayerOpenGLLayer *_openGLLayer;
    mpv_render_context *_mpvRenderContext;
    BOOL _hasConfiguredEdr;
    BOOL _edrEnabled;
    BOOL _fullscreenTransitionActive;
    NSString *_edrPrimaries;
    NSString *_lastAppliedEdrLayerKey;
    double _edrMetadataMaxNits;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) {
        return nil;
    }

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
    _openGLLayer = [[NuvioPlayerOpenGLLayer alloc] initWithOwner:self];
    _openGLLayer.frame = self.bounds;
    _openGLLayer.contentsGravity = kCAGravityResize;
    self.layer = _openGLLayer;
    [self updateMetalLayerLayout];
    return self;
}

- (BOOL)isOpaque {
    return YES;
}

- (CALayer *)makeBackingLayer {
    return _openGLLayer ?: [[NuvioPlayerOpenGLLayer alloc] initWithOwner:self];
}

- (void)layout {
    [super layout];
    [self updateMetalLayerLayout];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateMetalLayerLayout];
}

- (void)setBoundsSize:(NSSize)newSize {
    [super setBoundsSize:newSize];
    [self updateMetalLayerLayout];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateMetalLayerLayout];
    setBoolWithSelector(self, @"setWantsExtendedDynamicRangeContent:", YES);
    setBoolWithSelector(self.window, @"setWantsExtendedDynamicRangeContent:", YES);
    setBoolWithSelector(self.window.contentView, @"setWantsExtendedDynamicRangeContent:", YES);
    setBoolWithSelector(_openGLLayer, @"setWantsExtendedDynamicRangeContent:", YES);
}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    _openGLLayer.nuvioLiveResize = YES;
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    // The bridge clears resize mode on its settle timer, after AppKit has
    // finished the release/fullscreen layout burst.
}

- (void)setFullscreenTransitionActive:(BOOL)active {
    _fullscreenTransitionActive = active;
    BOOL transitionLike = active || self.inLiveResize || self.window.inLiveResize;
    _openGLLayer.nuvioLiveResize = transitionLike;
    if (!transitionLike) {
        [self updateMetalLayerLayout];
        [_openGLLayer requestRenderForced:YES];
    }
}

- (void)updateMetalLayerLayout {
    if (!_openGLLayer) {
        return;
    }

    NSSize boundsSize = self.bounds.size;
    if (boundsSize.width <= 1.0 || boundsSize.height <= 1.0) {
        return;
    }

    CGFloat scale = self.window.backingScaleFactor > 0.0
        ? self.window.backingScaleFactor
        : NSScreen.mainScreen.backingScaleFactor;
    BOOL liveResize = self.inLiveResize || self.window.inLiveResize || _fullscreenTransitionActive;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _openGLLayer.nuvioLiveResize = liveResize;
    _openGLLayer.contentsScale = scale;
    _openGLLayer.frame = self.bounds;
    if (!liveResize) {
        [self refreshMetalLayerEdrState];
        [_openGLLayer requestRenderForced:NO];
    }
    [CATransaction commit];
}

- (void)refreshMetalLayerEdrState {
    if (!_hasConfiguredEdr || !_openGLLayer) {
        return;
    }
    NSString *stateKey = [NSString stringWithFormat:
        @"%@:%@:%0.0f",
        _edrEnabled ? @"hdr" : @"sdr",
        _edrPrimaries ?: @"auto",
        normalizedHdrMetadataMaxNits(_edrMetadataMaxNits)
    ];
    if (_lastAppliedEdrLayerKey && [_lastAppliedEdrLayerKey isEqualToString:stateKey]) {
        return;
    }

    setBoolWithSelector(self, @"setWantsExtendedDynamicRangeContent:", _edrEnabled);
    setBoolWithSelector(self.window, @"setWantsExtendedDynamicRangeContent:", _edrEnabled);
    setBoolWithSelector(self.window.contentView, @"setWantsExtendedDynamicRangeContent:", _edrEnabled);
    setBoolWithSelector(_openGLLayer, @"setWantsExtendedDynamicRangeContent:", _edrEnabled);

    CGColorSpaceRef colorSpace = _edrEnabled
        ? copyPqColorSpaceForPrimaries(_edrPrimaries)
        : CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace) {
        setLayerColorSpace(_openGLLayer, colorSpace);
        CGColorSpaceRelease(colorSpace);
    }

    if (_edrEnabled) {
        setLayerEdrMetadata(_openGLLayer, 0.0, normalizedHdrMetadataMaxNits(_edrMetadataMaxNits), 1.0);
    } else {
        clearLayerEdrMetadata(_openGLLayer);
    }
    _lastAppliedEdrLayerKey = [stateKey copy];
    [_openGLLayer requestRender];
}

- (void)configureExtendedDynamicRange:(BOOL)enabled primaries:(NSString *)primaries targetPeakNits:(double)targetPeakNits {
    _hasConfiguredEdr = YES;
    _edrEnabled = enabled;
    _edrPrimaries = [primaries copy];
    _edrMetadataMaxNits = enabled ? normalizedHdrMetadataMaxNits(targetPeakNits) : hdrMetadataMaxNits();
    _lastAppliedEdrLayerKey = nil;

    setBoolWithSelector(self, @"setWantsExtendedDynamicRangeContent:", enabled);
    setBoolWithSelector(self.window, @"setWantsExtendedDynamicRangeContent:", enabled);
    setBoolWithSelector(self.window.contentView, @"setWantsExtendedDynamicRangeContent:", enabled);
    setBoolWithSelector(_openGLLayer, @"setWantsExtendedDynamicRangeContent:", enabled);

    CGColorSpaceRef colorSpace = enabled
        ? copyPqColorSpaceForPrimaries(primaries)
        : CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace) {
        setLayerColorSpace(_openGLLayer, colorSpace);
    }
    if (colorSpace) {
        CGColorSpaceRelease(colorSpace);
    }

    if (enabled) {
        setLayerEdrMetadata(_openGLLayer, 0.0, _edrMetadataMaxNits, 1.0);
    } else {
        clearLayerEdrMetadata(_openGLLayer);
    }
    _lastAppliedEdrLayerKey = [[NSString stringWithFormat:
        @"%@:%@:%0.0f",
        enabled ? @"hdr" : @"sdr",
        primaries ?: @"auto",
        _edrMetadataMaxNits
    ] copy];
    [_openGLLayer requestRender];
}

- (BOOL)createMpvRenderContext:(mpv_handle *)mpv error:(NSString **)error {
    if (_mpvRenderContext) {
        return YES;
    }
    if (!_openGLLayer) {
        if (error) {
            *error = @"OpenGL layer unavailable";
        }
        return NO;
    }

    [_openGLLayer lockAndSetContext];
    const char *apiType = MPV_RENDER_API_TYPE_OPENGL;
    mpv_opengl_init_params initParams = {
        mpvOpenGLGetProcAddress,
        nullptr
    };
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void *)apiType },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &initParams },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };
    int result = mpv_render_context_create(&_mpvRenderContext, mpv, params);
    [_openGLLayer unlockContext];
    if (result < 0) {
        if (error) {
            *error = [NSString stringWithFormat:@"mpv_render_context_create failed: %s", mpv_error_string(result)];
        }
        return NO;
    }

    [_openGLLayer setMpvRenderContext:_mpvRenderContext];
    mpv_render_context_set_update_callback(
        _mpvRenderContext,
        mpvRenderUpdateCallback,
        (__bridge void *)self
    );
    return YES;
}

- (void)destroyMpvRenderContext {
    if (!_mpvRenderContext) {
        return;
    }
    mpv_render_context *renderContext = _mpvRenderContext;
    _mpvRenderContext = nullptr;
    mpv_render_context_set_update_callback(renderContext, nullptr, nullptr);
    [_openGLLayer clearMpvRenderContext];
    [_openGLLayer lockAndSetContext];
    mpv_render_context_free(renderContext);
    [_openGLLayer unlockContext];
}

- (void)scheduleRenderUpdate {
    [_openGLLayer requestRender];
}

- (double)edrMax {
    return edrMaxForScreen(self.window.screen ?: NSScreen.mainScreen);
}

- (double)hdrTargetPeakNits {
    return hdrTargetPeakNitsForScreen(self.window.screen ?: NSScreen.mainScreen);
}

- (CGSize)drawableSize {
    if (!_openGLLayer) {
        return CGSizeZero;
    }
    CGFloat scale = _openGLLayer.contentsScale > 0.0 ? _openGLLayer.contentsScale : 1.0;
    return CGSizeMake(
        llround(_openGLLayer.bounds.size.width * scale),
        llround(_openGLLayer.bounds.size.height * scale)
    );
}

@end

@implementation PlayerScriptHandler
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.body isKindOfClass:[NSDictionary class]]) {
        [self.player handleScriptMessage:(NSDictionary *)message.body];
    }
}
@end

static NSString *javaScriptStringLiteral(NSString *value) {
    NSArray *array = @[value ?: @""];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:array options:0 error:&error];
    if (!data) {
        return @"\"\"";
    }
    NSString *jsonArray = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (jsonArray.length < 2) {
        return @"\"\"";
    }
    return [jsonArray substringWithRange:NSMakeRange(1, jsonArray.length - 2)];
}

static void setMpvOptionString(mpv_handle *mpv, const char *name, const char *value) {
    mpv_set_option_string(mpv, name, value);
}

@implementation MpvWebPlayer {
    NSString *_probeSource;
    NSString *_probeAudioSource;
    NSArray<NSString *> *_probeHeaders;
    dispatch_queue_t _thumbnailQueue;
    std::atomic_bool _stopping;
    std::atomic<uint64_t> _thumbnailGeneration;
    std::atomic<double> _sourceBytesPerSecond;
    std::atomic<int64_t> _selectedAudioId;
    NSMutableArray *_remoteCommandTargets;
    BOOL _ownsMediaSession;
    NSUInteger _artworkGeneration;
    BOOL _autoCrop;
    int _autoCropChecks;
    AutoCropBars _cropCandidate;
    AutoCropBars _appliedCrop;
    NSTimeInterval _nextCropCheck;
    NSView *_hostView;
    PlayerMetalView *_videoView;
    WKWebView *_webView;
    PlayerScriptHandler *_scriptHandler;
    mpv_handle *_mpv;
    NSTimer *_timer;
    NSTimer *_resizeSettleTimer;
    NSTimer *_fullscreenTransitionTimer;
    JavaVM *_javaVm;
    jobject _eventSink;
    jmethodID _eventMethod;
    NSString *_lastConfiguredHdrKey;
    NSString *_requestedHdrMode;
    BOOL _displayPanelOled;
    NSString *_lastResizeRefreshKey;
    dispatch_queue_t _mpvEventQueue;
    BOOL _didFocusControlsWebView;
    BOOL _controlsWebReady;
    BOOL _cursorHidden;
    NSMutableArray<NSString *> *_pendingScripts;
    NSString *_subtitleAssStyleMode;
    double _subtitleAssScale;
    BOOL _fullscreenTransitionActive;
    NSString *_pendingControlsJson;
    double _initialStartSeconds;
    BOOL _controlsSyncInFlight;
    BOOL _playbackRestartReported;
    BOOL _trackNotificationsAvailable;
    NSString *_cachedAudioTracksJson;
    NSString *_cachedSubtitleTracksJson;
    NSRect _lastAppliedNativeLayoutBounds;
    BOOL _lastAppliedNativeLayoutWasLiveResize;
    NSTimeInterval _lightweightResizeSettleUntil;
    NSSize _lastControlsViewportNudgeSize;
    NSTimeInterval _lastControlsViewportNudgeAt;
    CGFloat _lastControlsPageZoom;
    CGFloat _controlsUiScaleFactor;
    std::atomic<double> _cachedDurationSeconds;
    std::atomic<double> _cachedPositionSeconds;
    std::atomic<double> _cachedCacheAheadSeconds;
    std::atomic<double> _cachedSpeed;
    std::atomic_bool _cachedPaused;
    std::atomic_bool _cachedLoading;
    std::atomic_bool _cachedEnded;
}

- (instancetype)initWithHostView:(NSView *)hostView
                       sourceUrl:(NSString *)sourceUrl
                   audioSourceUrl:(NSString *)audioSourceUrl
                    headerLines:(NSArray<NSString *> *)headerLines
                     mpvOptions:(NSArray<NSString *> *)mpvOptions
                   playWhenReady:(BOOL)playWhenReady
                initialPositionMs:(long long)initialPositionMs
          initialProgressFraction:(double)initialProgressFraction
                      controlsUrl:(NSString *)controlsUrl
                           javaVm:(JavaVM *)javaVm
                        eventSink:(jobject)eventSink
                      eventMethod:(jmethodID)eventMethod {
    self = [super init];
    if (!self) {
        return nil;
    }

    _cachedDurationSeconds.store(0.0);
    _cachedPositionSeconds.store(initialPositionMs > 0 ? (double)initialPositionMs / 1000.0 : 0.0);
    _cachedCacheAheadSeconds.store(0.0);
    _cachedSpeed.store(1.0);
    _cachedPaused.store(!playWhenReady);
    _cachedLoading.store(true);
    _cachedEnded.store(false);
    _cachedAudioTracksJson = @"[]";
    _cachedSubtitleTracksJson = @"[]";
    _mpvEventQueue = dispatch_queue_create("com.nuvio.desktop.mpv-events", DISPATCH_QUEUE_SERIAL);
    _javaVm = javaVm;
    _eventSink = eventSink;
    _eventMethod = eventMethod;

    _hostView = hostView;
    _hostView.wantsLayer = YES;
    _hostView.layer.backgroundColor = NSColor.blackColor.CGColor;
    [_hostView setPostsFrameChangedNotifications:YES];
    [_hostView setPostsBoundsChangedNotifications:YES];

    _videoView = [[PlayerMetalView alloc] initWithFrame:_hostView.bounds];
    [_hostView addSubview:_videoView];

    _scriptHandler = [PlayerScriptHandler new];
    _scriptHandler.player = self;
    WKUserContentController *contentController = [WKUserContentController new];
    [contentController addScriptMessageHandler:_scriptHandler name:@"player"];

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.userContentController = contentController;
    _webView = [[WKWebView alloc] initWithFrame:_hostView.bounds configuration:configuration];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.wantsLayer = YES;
    [_webView setValue:@NO forKey:@"drawsBackground"];
    [_hostView addSubview:_webView positioned:NSWindowAbove relativeTo:_videoView];
    NSURL *controlsURL = [NSURL URLWithString:controlsUrl ?: @""];
    if (!controlsURL) {
        @throw [NSException exceptionWithName:@"PlayerBridgeError"
                                       reason:@"Invalid native player controls URL."
                                     userInfo:nil];
    }
    if (controlsURL.isFileURL) {
        [_webView loadFileURL:controlsURL allowingReadAccessToURL:[controlsURL URLByDeletingLastPathComponent]];
    } else {
        [_webView loadRequest:[NSURLRequest requestWithURL:controlsURL]];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hostViewFrameDidChange:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:_hostView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hostViewBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_hostView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillEnterFullScreen:)
                                                 name:NSWindowWillEnterFullScreenNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidEnterFullScreen:)
                                                 name:NSWindowDidEnterFullScreenNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillExitFullScreen:)
                                                 name:NSWindowWillExitFullScreenNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidExitFullScreen:)
                                                 name:NSWindowDidExitFullScreenNotification
                                               object:nil];
    [self layoutNativeSubviews];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self focusControlsWebViewIfNeeded];
    });

    _stopping.store(false);
    _thumbnailGeneration.store(0);
    _sourceBytesPerSecond.store(-1);
    _selectedAudioId.store(0);
    _probeSource = [sourceUrl copy];
    _probeAudioSource = [audioSourceUrl copy];
    _probeHeaders = [headerLines copy];
    _thumbnailQueue = dispatch_queue_create("com.nuvio.thumbnail", DISPATCH_QUEUE_SERIAL);
    [self startMpvWithSource:sourceUrl
              audioSourceUrl:audioSourceUrl
                 headerLines:headerLines
                  mpvOptions:mpvOptions
                playWhenReady:playWhenReady
             initialPositionMs:initialPositionMs
       initialProgressFraction:initialProgressFraction];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:self
                                           selector:@selector(syncControls)
                                           userInfo:nil
                                            repeats:YES];
    return self;
}

- (void)focusControlsWebViewIfNeeded {
    if (_didFocusControlsWebView || !_webView || !_webView.window) {
        return;
    }
    _didFocusControlsWebView = YES;
    [_webView.window makeFirstResponder:_webView];
}

- (void)layoutControlsWebViewToBounds:(NSRect)bounds immediate:(BOOL)immediate {
    if (!_webView) {
        return;
    }

    // Match the 2x desktop-scaling baseline used to size the HUD. This keeps its physical size
    // consistent on 1x and Retina displays without disturbing the viewport-aware CSS rules.
    if (@available(macOS 11.0, *)) {
        NSScreen *screen = _webView.window.screen ?: _hostView.window.screen ?: NSScreen.mainScreen;
        CGFloat backingScale = screen.backingScaleFactor > 0.0 ? screen.backingScaleFactor : 1.0;
        CGFloat desiredPageZoom = (2.0 / backingScale) * (_controlsUiScaleFactor > 0.0 ? _controlsUiScaleFactor : 1.0);
        if (fabs(desiredPageZoom - _lastControlsPageZoom) > 0.001) {
            _webView.pageZoom = desiredPageZoom;
            _lastControlsPageZoom = desiredPageZoom;
        }
    }

    if (!NSEqualRects(_webView.frame, bounds)) {
        _webView.frame = bounds;
    }
    if (!immediate) {
        return;
    }

    [_webView setNeedsLayout:YES];
    [_webView layoutSubtreeIfNeeded];
    [_webView setNeedsDisplay:YES];

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    BOOL sizeChanged = !NSEqualSizes(_lastControlsViewportNudgeSize, bounds.size);
    if (!_controlsWebReady || !sizeChanged || now - _lastControlsViewportNudgeAt < 0.05) {
        return;
    }

    _lastControlsViewportNudgeSize = bounds.size;
    _lastControlsViewportNudgeAt = now;
    NSString *script = @"window.nuvioNativeViewportChanged ? window.nuvioNativeViewportChanged() : window.dispatchEvent(new Event('resize'));";
    [_webView evaluateJavaScript:script completionHandler:nil];
}

- (void)layoutNativeSubviews {
    if (!_hostView) {
        return;
    }
    NSRect bounds = _hostView.bounds;
    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return;
    }

    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    BOOL nativeLiveResize = _hostView.inLiveResize || _hostView.window.inLiveResize;
    BOOL wasResizeLikeLayout = _lastAppliedNativeLayoutWasLiveResize
        || _fullscreenTransitionActive
        || (_lightweightResizeSettleUntil > now);
    BOOL hasPreviousBounds = _lastAppliedNativeLayoutBounds.size.width > 1.0
        && _lastAppliedNativeLayoutBounds.size.height > 1.0;
    if (!_fullscreenTransitionActive && !nativeLiveResize && hasPreviousBounds && !NSEqualRects(bounds, _lastAppliedNativeLayoutBounds)) {
        double previousArea = _lastAppliedNativeLayoutBounds.size.width * _lastAppliedNativeLayoutBounds.size.height;
        double currentArea = bounds.size.width * bounds.size.height;
        double areaRatio = previousArea > 1.0 ? currentArea / previousArea : 1.0;
        CGFloat widthDelta = fabs(bounds.size.width - _lastAppliedNativeLayoutBounds.size.width);
        CGFloat heightDelta = fabs(bounds.size.height - _lastAppliedNativeLayoutBounds.size.height);
        if (areaRatio > 1.75 || areaRatio < 0.60 || widthDelta > 480.0 || heightDelta > 320.0) {
            [self activateFullscreenTransitionWithReason:@"layout-jump"];
        }
    }

    BOOL liveResize = nativeLiveResize || _fullscreenTransitionActive;
    BOOL settlingFromResize = !liveResize && wasResizeLikeLayout;
    if (liveResize
        && _lastAppliedNativeLayoutWasLiveResize
        && NSEqualRects(bounds, _lastAppliedNativeLayoutBounds)) {
        return;
    }
    if (liveResize || settlingFromResize) {
        _lightweightResizeSettleUntil = now + 0.45;
    }
    _lastAppliedNativeLayoutBounds = bounds;
    _lastAppliedNativeLayoutWasLiveResize = liveResize;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_videoView) {
        if (liveResize || settlingFromResize) {
            [_videoView setFullscreenTransitionActive:YES];
        }
        if (!NSEqualRects(_videoView.frame, bounds)) {
            _videoView.frame = bounds;
        }
        if (!liveResize && !settlingFromResize) {
            [_videoView setNeedsLayout:YES];
            [_videoView layoutSubtreeIfNeeded];
            [_videoView updateMetalLayerLayout];
        }
    }
    if (_webView) {
        BOOL immediateControlsLayout = _fullscreenTransitionActive || settlingFromResize || (!liveResize && !settlingFromResize);
        [self layoutControlsWebViewToBounds:bounds immediate:immediateControlsLayout];
    }
    [CATransaction commit];

    if (liveResize || settlingFromResize) {
        if (_mpv) {
            [self schedulePostResizeRefreshWithReason:liveResize ? @"live-layout" : @"settle-layout"];
        }
        return;
    }

    CGSize currentDrawableSize = _videoView ? [_videoView drawableSize] : CGSizeZero;
    NSString *resizeKey = [NSString stringWithFormat:
        @"%@:%@:%@:%@",
        diagnosticRect(bounds),
        _videoView ? diagnosticRect(_videoView.frame) : @"none",
        _webView ? diagnosticRect(_webView.frame) : @"none",
        diagnosticSize(currentDrawableSize)
    ];
    if (!_lastResizeRefreshKey || ![_lastResizeRefreshKey isEqualToString:resizeKey]) {
        _lastResizeRefreshKey = resizeKey;
        if (_mpv) {
            [self schedulePostResizeRefreshWithReason:@"layout"];
        }
    }
}

- (void)hostViewFrameDidChange:(NSNotification *)notification {
    [self layoutNativeSubviews];
}

- (void)hostViewBoundsDidChange:(NSNotification *)notification {
    [self layoutNativeSubviews];
}

- (BOOL)notificationBelongsToHostWindow:(NSNotification *)notification {
    NSWindow *window = [notification.object isKindOfClass:[NSWindow class]] ? (NSWindow *)notification.object : nil;
    return window && _hostView.window && window == _hostView.window;
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    if (![self notificationBelongsToHostWindow:notification]) {
        return;
    }
    [self beginFullscreenTransitionWithReason:@"will-enter-fullscreen"];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    if (![self notificationBelongsToHostWindow:notification]) {
        return;
    }
    [self finishFullscreenTransitionWithReason:@"did-enter-fullscreen"];
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
    if (![self notificationBelongsToHostWindow:notification]) {
        return;
    }
    [self beginFullscreenTransitionWithReason:@"will-exit-fullscreen"];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    if (![self notificationBelongsToHostWindow:notification]) {
        return;
    }
    [self finishFullscreenTransitionWithReason:@"did-exit-fullscreen"];
}

- (void)activateFullscreenTransitionWithReason:(NSString *)reason {
    _fullscreenTransitionActive = YES;
    [_fullscreenTransitionTimer invalidate];
    [_videoView setFullscreenTransitionActive:YES];
    _fullscreenTransitionTimer = [NSTimer scheduledTimerWithTimeInterval:1.25
                                                                  target:self
                                                                selector:@selector(handleFullscreenTransitionTimer:)
                                                                userInfo:reason ?: @"unknown"
                                                                 repeats:NO];
}

- (void)beginFullscreenTransitionWithReason:(NSString *)reason {
    [self activateFullscreenTransitionWithReason:reason];
    [self layoutNativeSubviews];
}

- (void)finishFullscreenTransitionWithReason:(NSString *)reason {
    if (!_fullscreenTransitionActive && !_fullscreenTransitionTimer) {
        return;
    }
    [_fullscreenTransitionTimer invalidate];
    _fullscreenTransitionTimer = nil;
    _fullscreenTransitionActive = NO;
    [self layoutNativeSubviews];
    [_resizeSettleTimer invalidate];
    _resizeSettleTimer = nil;
    if (_mpv) {
        NSString *refreshReason = [NSString stringWithFormat:@"fullscreen/%@", reason ?: @"unknown"];
        [self schedulePostResizeRefreshWithReason:refreshReason];
    }
}

- (void)handleFullscreenTransitionTimer:(NSTimer *)timer {
    [self finishFullscreenTransitionWithReason:[NSString stringWithFormat:@"timer/%@", timer.userInfo ?: @"unknown"]];
}

- (void)schedulePostResizeRefreshWithReason:(NSString *)reason {
    if (!_mpv || !_videoView) {
        return;
    }
    [_resizeSettleTimer invalidate];
    _resizeSettleTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                          target:self
                                                        selector:@selector(handleResizeSettleTimer:)
                                                        userInfo:reason ?: @"unknown"
                                                         repeats:NO];
}

- (void)handleResizeSettleTimer:(NSTimer *)timer {
    _resizeSettleTimer = nil;
    if (!_mpv || !_videoView) {
        return;
    }
    if (_hostView.inLiveResize || _hostView.window.inLiveResize || _fullscreenTransitionActive) {
        [self schedulePostResizeRefreshWithReason:timer.userInfo ?: @"unknown"];
        return;
    }
    _lightweightResizeSettleUntil = 0.0;
    [self layoutControlsWebViewToBounds:_hostView.bounds immediate:YES];
    [_videoView setFullscreenTransitionActive:NO];
    [_videoView updateMetalLayerLayout];
    NSString *reason = [NSString stringWithFormat:@"resize-settled/%@", timer.userInfo ?: @"unknown"];
    [self configureHdrForCurrentScreenWithReason:reason force:NO];
}

- (void)startMpvWithSource:(NSString *)sourceUrl
            audioSourceUrl:(NSString *)audioSourceUrl
               headerLines:(NSArray<NSString *> *)headerLines
                mpvOptions:(NSArray<NSString *> *)mpvOptions
              playWhenReady:(BOOL)playWhenReady
           initialPositionMs:(long long)initialPositionMs
     initialProgressFraction:(double)initialProgressFraction {
    _mpv = mpv_create();
    if (!_mpv) {
        @throw [NSException exceptionWithName:@"PlayerBridgeError"
                                       reason:@"mpv_create failed"
                                     userInfo:nil];
    }
    _initialStartSeconds = initialPositionMs > 0 ? (double)initialPositionMs / 1000.0 : 0.0;

    NSString *configMode = @"off";
    for (NSString *option in mpvOptions) {
        if ([option hasPrefix:@"@nuvio-config-mode="]) configMode = [option substringFromIndex:19];
    }
    BOOL fullUserConfig = [configMode isEqualToString:@"full"];
    NSMutableSet<NSString *> *configured = [NSMutableSet setWithArray:@[
        @"config", @"osc", @"input-vo-keyboard", @"keep-open", @"vo"
    ]];
    setMpvOptionString(_mpv, "config", "no");
    setMpvOptionString(_mpv, "osc", "no");
    setMpvOptionString(_mpv, "input-vo-keyboard", "no");
    setMpvOptionString(_mpv, "keep-open", "yes");
    setMpvOptionString(_mpv, "vo", "libmpv");
    if (!fullUserConfig) {
    [configured addObjectsFromArray:@[
        @"input-default-bindings", @"script-opts", @"hwdec", @"gpu-hwdec-interop", @"hwdec-codecs",
        @"vd-lavc-software-fallback", @"vd-lavc-threads", @"target-colorspace-hint",
        @"target-colorspace-hint-mode", @"target-colorspace-hint-strict", @"tone-mapping",
        @"hdr-compute-peak", @"dither-depth", @"deband", @"scale", @"cscale",
        @"demuxer-max-bytes", @"demuxer-max-back-bytes", @"demuxer-seekable-cache",
        @"cache", @"cache-pause", @"cache-pause-initial", @"cache-pause-wait",
        @"cache-secs", @"hr-seek"
    ]];
    setMpvOptionString(_mpv, "input-default-bindings", "yes");
    // Match the Windows diagnostics footprint: mpv defaults to 20 / 1.65 respectively.
    setMpvOptionString(_mpv, "script-opts", "stats-font_size=15,stats-border_size=1.25");
    setMpvOptionString(_mpv, "hwdec", "auto");
    setMpvOptionString(_mpv, "gpu-hwdec-interop", "auto");
    setMpvOptionString(_mpv, "hwdec-codecs", "all");
    setMpvOptionString(_mpv, "vd-lavc-software-fallback", "yes");
    setMpvOptionString(_mpv, "vd-lavc-threads", "4");
    setMpvOptionString(_mpv, "target-colorspace-hint", "yes");
    setMpvOptionString(_mpv, "target-colorspace-hint-mode", "source");
    setMpvOptionString(_mpv, "target-colorspace-hint-strict", "no");
    setMpvOptionString(_mpv, "tone-mapping", "auto");
    setMpvOptionString(_mpv, "hdr-compute-peak", "no");
    setMpvOptionString(_mpv, "dither-depth", "auto");
    setMpvOptionString(_mpv, "deband", "yes");
    setMpvOptionString(_mpv, "scale", "spline36");
    setMpvOptionString(_mpv, "cscale", "spline36");
    setMpvOptionString(_mpv, "demuxer-max-bytes", "64MiB");
    setMpvOptionString(_mpv, "demuxer-max-back-bytes", "16MiB");
    setMpvOptionString(_mpv, "demuxer-seekable-cache", "no");
    setMpvOptionString(_mpv, "cache", "yes");
    setMpvOptionString(_mpv, "cache-pause", "yes");
    setMpvOptionString(_mpv, "cache-pause-initial", "yes");
    setMpvOptionString(_mpv, "cache-pause-wait", "0.25");
    setMpvOptionString(_mpv, "cache-secs", "30");
    setMpvOptionString(_mpv, "hr-seek", "no");
    }

    if (headerLines.count > 0) {
        NSString *headers = [headerLines componentsJoinedByString:@","];
        setMpvOptionString(_mpv, "http-header-fields", headers.UTF8String);
    }

    // External audio track (e.g. a YouTube trailer with separate hi-res video + audio).
    // The "-append" action takes the value as a single entry, so a URL containing commas
    // is not split into multiple bogus paths.
    if (audioSourceUrl.length > 0) {
        setMpvOptionString(_mpv, "audio-files-append", audioSourceUrl.UTF8String);
    }

    for (NSString *rawOption in mpvOptions) {
        if ([rawOption hasPrefix:@"@nuvio-config-mode="]) continue;
        BOOL userOption = [rawOption hasPrefix:@"@nuvio-user:"];
        NSString *option = userOption ? [rawOption substringFromIndex:12] : rawOption;
        NSRange separator = [option rangeOfString:@"="];
        if (separator.location == NSNotFound || separator.location == 0) continue;
        NSString *key = [option substringToIndex:separator.location];
        NSString *value = [option substringFromIndex:separator.location + 1];
        if (userOption && (([configMode isEqualToString:@"add"] && [configured containsObject:key]) ||
                           (fullUserConfig && [configured containsObject:key]))) continue;
        setMpvOptionString(_mpv, key.UTF8String, value.UTF8String);
        if (!userOption) [configured addObject:key];
    }

    int initResult = mpv_initialize(_mpv);
    if (initResult < 0) {
        NSString *reason = [NSString stringWithFormat:@"mpv_initialize failed: %s", mpv_error_string(initResult)];
        @throw [NSException exceptionWithName:@"PlayerBridgeError" reason:reason userInfo:nil];
    }

    // Property notifications also cover tracks added/removed after loading and primary/secondary
    // selection changes. Keep all expensive per-track reads on the event queue, never JNI callers.
    _trackNotificationsAvailable = YES;
    for (const char *property : {"track-list", "aid", "sid", "secondary-sid"}) {
        if (mpv_observe_property(_mpv, 1, property, MPV_FORMAT_NONE) < 0) {
            _trackNotificationsAvailable = NO; // Preserve polling if observation is unavailable.
        }
    }

    NSString *renderError = nil;
    if (![_videoView createMpvRenderContext:_mpv error:&renderError]) {
        NSString *reason = renderError ?: @"mpv render context failed";
        @throw [NSException exceptionWithName:@"PlayerBridgeError" reason:reason userInfo:nil];
    }

    std::vector<const char *> command = {"loadfile", sourceUrl.UTF8String};
    std::string loadOptions;
    if (initialPositionMs > 0 || initialProgressFraction > 0.0) {
        char startBuffer[64];
        if (initialPositionMs > 0) {
            snprintf(startBuffer, sizeof(startBuffer), "start=%.3f", (double)initialPositionMs / 1000.0);
        } else {
            snprintf(startBuffer, sizeof(startBuffer), "start=%.6f%%", initialProgressFraction * 100.0);
        }
        loadOptions = startBuffer;
        command.push_back("replace");
        command.push_back("-1");
        command.push_back(loadOptions.c_str());
    }
    command.push_back(NULL);
    int commandResult = mpv_command(_mpv, command.data());
    if (commandResult < 0) {
        NSString *reason = [NSString stringWithFormat:@"mpv loadfile failed: %s", mpv_error_string(commandResult)];
        @throw [NSException exceptionWithName:@"PlayerBridgeError" reason:reason userInfo:nil];
    }

    [self setPaused:!playWhenReady];
}

- (void)syncControls {
    if (!_webView || !_mpv) {
        return;
    }
    [self layoutNativeSubviews];
    [self focusControlsWebViewIfNeeded];
    if (_controlsSyncInFlight || !_mpvEventQueue) {
        return;
    }
    _controlsSyncInFlight = YES;

    mpv_handle *mpv = _mpv;
    dispatch_async(_mpvEventQueue, ^{
        @autoreleasepool {
            if (self->_mpv != mpv) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_controlsSyncInFlight = NO;
                });
                return;
            }

            // The Kotlin player waits for these lifecycle events before accepting snapshots.
            // Polling properties alone leaves it permanently "loading", triggering its stall
            // recovery even while libmpv is already decoding and presenting the video.
            NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
            BOOL refreshTracks = !self->_trackNotificationsAvailable;
            for (int count = 0; count < 128; count++) {
                mpv_event *event = mpv_wait_event(mpv, 0.0);
                if (!event || event->event_id == MPV_EVENT_NONE) break;
                switch (event->event_id) {
                    case MPV_EVENT_START_FILE:
                        self->_playbackRestartReported = NO;
                        refreshTracks = YES;
                        break;
                    case MPV_EVENT_PROPERTY_CHANGE:
                        if (event->reply_userdata == 1) refreshTracks = YES;
                        break;
                    case MPV_EVENT_FILE_LOADED:
                        refreshTracks = YES;
                        [events addObject:@{ @"type": @"fileLoaded", @"value": @1 }];
                        break;
                    case MPV_EVENT_PLAYBACK_RESTART:
                        // Seeks and buffering also raise PLAYBACK_RESTART. The shared layer
                        // uses it as the first-frame signal, once for each loaded file.
                        if (!self->_playbackRestartReported) {
                            self->_playbackRestartReported = YES;
                            [events addObject:@{ @"type": @"playbackRestart", @"value": @1 }];
                        }
                        break;
                    case MPV_EVENT_END_FILE: {
                        mpv_event_end_file *end = (mpv_event_end_file *)event->data;
                        if (end && end->reason == MPV_END_FILE_REASON_ERROR) {
                            NSString *prefix = self->_playbackRestartReported
                                ? @"mpvPlaybackError:" : @"mpvStartupError:";
                            NSString *message = [NSString stringWithUTF8String:mpv_error_string(end->error)];
                            [events addObject:@{ @"type": [prefix stringByAppendingString:message], @"value": @0 }];
                        }
                        break;
                    }
                    default:
                        break;
                }
            }

            if (refreshTracks) {
                NSString *audio = [self tracksJsonForType:@"audio"];
                NSString *subtitles = [self tracksJsonForType:@"sub"];
                @synchronized (self) {
                    self->_cachedAudioTracksJson = audio;
                    self->_cachedSubtitleTracksJson = subtitles;
                }
            }

            double duration = [self doubleProperty:"duration" fallback:0.0];
            double position = [self doubleProperty:"time-pos" fallback:0.0];
            double cacheAhead = [self cacheAheadSecondsForPosition:position];
            BOOL paused = [self rawIsPaused];
            BOOL ended = [self rawIsEnded];
            BOOL loading = [self rawLoadingWithPaused:paused ended:ended duration:duration];
            double speed = [self rawSpeed];
            self->_selectedAudioId.store((int64_t)[self doubleProperty:"aid" fallback:0]);
            double size = [self doubleProperty:"file-size" fallback:0];
            self->_sourceBytesPerSecond.store(duration > 0 && size > 0 ? size / duration : -1);
            if (self->_autoCrop && CFAbsoluteTimeGetCurrent() >= self->_nextCropCheck) [self checkAutoCrop];
            NSString *audioTracks = [self audioTracksJson] ?: @"[]";
            NSString *subtitleTracks = [self subtitleTracksJson] ?: @"[]";
            NSString *gamma = [[self stringProperty:"video-params/gamma" fallback:@""] lowercaseString];
            NSString *primaries = [[self stringProperty:"video-params/primaries" fallback:@""] lowercaseString];
            [self updateCachedDuration:duration
                              position:position
                            cacheAhead:cacheAhead
                                paused:paused
                                 loading:loading
                                   ended:ended
                                   speed:speed];

            dispatch_async(dispatch_get_main_queue(), ^{
                self->_controlsSyncInFlight = NO;
                if (!self->_webView || self->_mpv != mpv) {
                    return;
                }
                // Publish after refreshing the cached snapshot so the first-frame callback
                // cannot expose the initial loading/zero-position placeholder to Kotlin.
                for (NSDictionary *event in events) {
                    [self sendPlayerEvent:event[@"type"] value:[event[@"value"] doubleValue]];
                }
                [self updateNowPlayingPosition:position duration:duration paused:paused];
                [self applyHdrForPolledGamma:gamma primaries:primaries reason:@"sync" force:NO];
                NSString *script = [NSString stringWithFormat:
                    @"window.playerUpdate({duration:%0.3f,position:%0.3f,buffered:%0.3f,paused:%@,loading:%@,audioTracks:%@,subtitleTracks:%@})",
                    duration,
                    position,
                    (double)[self bufferedPositionMs] / 1000.0,
                    paused ? @"true" : @"false",
                    loading ? @"true" : @"false",
                    audioTracks,
                    subtitleTracks];
                [self->_webView evaluateJavaScript:script completionHandler:nil];
            });
        }
    });
}

- (void)configureHdrForCurrentScreenIfNeeded {
    [self configureHdrForCurrentScreenWithReason:@"legacy" force:NO];
}

- (void)setHdrMode:(NSString *)mode {
    if (![@[@"Auto", @"AlwaysTonemap", @"AlwaysPassthrough"] containsObject:mode]) return;
    _requestedHdrMode = [mode copy];
    [self configureHdrForCurrentScreenWithReason:@"mode-change" force:YES];
}

- (void)setDisplayPanel:(NSString *)panel {
    if (![@[@"lcd", @"oled"] containsObject:panel]) return;
    const BOOL oled = [panel isEqualToString:@"oled"];
    if (_displayPanelOled == oled) return;
    _displayPanelOled = oled;
    [self configureHdrForCurrentScreenWithReason:@"display-panel-change" force:YES];
}

- (void)configureHdrForCurrentScreenWithReason:(NSString *)reason force:(BOOL)force {
    [self applyHdrForPolledGamma:[self stringProperty:"video-params/gamma" fallback:@""]
                      primaries:[self stringProperty:"video-params/primaries" fallback:@""]
                         reason:reason force:force];
}

- (void)applyHdrForPolledGamma:(NSString *)gamma primaries:(NSString *)primaries reason:(NSString *)reason force:(BOOL)force {
    if (!_mpv || !_videoView) return;
    NSString *normalizedGamma = [[gamma ?: @"" lowercaseString] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const bool sourceHdr = [normalizedGamma containsString:@"pq"]
        || [normalizedGamma containsString:@"2084"] || [normalizedGamma containsString:@"hlg"];
    NSString *modeName = _requestedHdrMode ?: @"Auto";
    MacosHdrMode mode = [modeName isEqualToString:@"AlwaysTonemap"] ? MacosHdrMode::Tonemap
        : [modeName isEqualToString:@"AlwaysPassthrough"] ? MacosHdrMode::Passthrough : MacosHdrMode::Auto;
    const double headroom = [_videoView edrMax];
    const double peak = normalizedHdrMetadataMaxNits([_videoView hdrTargetPeakNits]);
    const MacosHdrOutput output = macosHdrOutput(mode, sourceHdr, headroom, _displayPanelOled);
    NSString *stateKey = [NSString stringWithFormat:@"%@:%@:%@:%0.2f:%0.0f:%d", modeName,
        normalizedGamma, primaries ?: @"", headroom, peak, (int)_displayPanelOled];
    if (!force && [_lastConfiguredHdrKey isEqualToString:stateKey]) return;

    // One main-thread owner: never queue an older automatic HDR write after a newer mode.
    // Reset all managed properties on every transition, including the return to Auto.
    mpv_set_property_string(_mpv, "target-colorspace-hint", "no");
    mpv_set_property_string(_mpv, "target-colorspace-hint-mode", "target");
    mpv_set_property_string(_mpv, "target-colorspace-hint-strict", "no");
    mpv_set_property_string(_mpv, "tone-mapping", "auto");
    mpv_set_property_string(_mpv, "hdr-compute-peak", "no");
    mpv_set_property_string(_mpv, "target-prim", output.primaries);
    mpv_set_property_string(_mpv, "target-trc", output.transfer);
    NSString *targetPeak = output.extendedRange ? [NSString stringWithFormat:@"%.0f", peak] : @"203";
    mpv_set_property_string(_mpv, "target-peak", targetPeak.UTF8String);
    mpv_set_property_string(_mpv, "target-contrast", output.targetContrast);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_videoView configureExtendedDynamicRange:output.extendedRange
                                   primaries:[NSString stringWithUTF8String:output.primaries]
                              targetPeakNits:peak];
    [CATransaction commit];
    _lastConfiguredHdrKey = stateKey;
    [self forceVideoRedraw];
    NSString *actualPrimaries = [self stringProperty:"target-prim" fallback:@"unknown"];
    NSString *actualTransfer = [self stringProperty:"target-trc" fallback:@"unknown"];
    fprintf(stderr, "Info: (MacosHdr) mode=%s sourceHdr=%d output=%s primaries=%s transfer=%s reason=%s\n",
        modeName.UTF8String, sourceHdr, output.extendedRange ? "hdr" : "sdr",
        actualPrimaries.UTF8String, actualTransfer.UTF8String, reason.UTF8String);
}

- (JNIEnv *)jniEnvDidAttach:(BOOL *)didAttach {
    if (didAttach) {
        *didAttach = NO;
    }
    if (!_javaVm) {
        return nullptr;
    }

    JNIEnv *env = nullptr;
    jint status = _javaVm->GetEnv((void **)&env, JNI_VERSION_1_6);
    if (status == JNI_OK) {
        return env;
    }
    if (status != JNI_EDETACHED) {
        return nullptr;
    }
    if (_javaVm->AttachCurrentThread((void **)&env, nullptr) != JNI_OK) {
        return nullptr;
    }
    if (didAttach) {
        *didAttach = YES;
    }
    return env;
}

- (void)sendPlayerEvent:(NSString *)type value:(double)value {
    if (!_eventSink || !_eventMethod) {
        return;
    }

    BOOL didAttach = NO;
    JNIEnv *env = [self jniEnvDidAttach:&didAttach];
    if (!env) {
        return;
    }

    jstring eventType = env->NewStringUTF(type.UTF8String);
    env->CallVoidMethod(_eventSink, _eventMethod, eventType, (jdouble)value);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
    if (eventType) {
        env->DeleteLocalRef(eventType);
    }
    if (didAttach) {
        _javaVm->DetachCurrentThread();
    }
}

- (void)updateControlsJson:(NSString *)controlsJson {
    if (!_webView) {
        return;
    }
    if (!controlsJson) {
        return;
    }
    _pendingControlsJson = [controlsJson copy];
    [self flushPendingControlsJsonIfReady];
}

- (void)flushPendingControlsJsonIfReady {
    if (!_webView || !_pendingControlsJson) {
        return;
    }
    if (!_controlsWebReady) {
        return;
    }
    NSString *controlsJson = [_pendingControlsJson copy];
    NSString *jsonString = javaScriptStringLiteral(controlsJson);
    NSString *script = [NSString stringWithFormat:
        @"(function(){if(!window.playerControls)return 'missing';window.playerControls(JSON.parse(%@));return 'applied';})()",
        jsonString];
    [_webView evaluateJavaScript:script completionHandler:^(id _Nullable jsResult, NSError * _Nullable error) {
        if (error) {
            return;
        }
        NSString *resultText = [jsResult isKindOfClass:[NSString class]] ? (NSString *)jsResult : @"unknown";
        if ([resultText isEqualToString:@"missing"]) {
            _controlsWebReady = NO;
            return;
        }
        if (_pendingControlsJson && [_pendingControlsJson isEqualToString:controlsJson]) {
            _pendingControlsJson = nil;
        }
    }];
}

- (void)shutdown {
    _stopping.store(true);
    ++_thumbnailGeneration;
    if (_ownsMediaSession) {
        for (NSArray *pair in _remoteCommandTargets) [(MPRemoteCommand *)pair[0] removeTarget:pair[1]];
        _remoteCommandTargets = nil;
        if (nuvioMediaOwner == self) {
            MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
            MPNowPlayingInfoCenter.defaultCenter.playbackState = MPNowPlayingPlaybackStateStopped;
            nuvioMediaOwner = nil;
        }
        _ownsMediaSession = NO;
        ++_artworkGeneration;
    }
    [self setCursorHidden:NO];
    _pendingScripts = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    _timer = nil;
    [_resizeSettleTimer invalidate];
    _resizeSettleTimer = nil;
    [_fullscreenTransitionTimer invalidate];
    _fullscreenTransitionTimer = nil;
    _controlsWebReady = NO;
    _pendingControlsJson = nil;
    if (_mpvEventQueue) {
        dispatch_sync(_mpvEventQueue, ^{});
    }
    [_videoView configureExtendedDynamicRange:NO primaries:@"bt.709" targetPeakNits:203.0];
    [_videoView destroyMpvRenderContext];
    if (_mpv) {
        mpv_terminate_destroy(_mpv);
        _mpv = NULL;
    }
    [_webView.configuration.userContentController removeScriptMessageHandlerForName:@"player"];
    [_webView removeFromSuperview];
    [_videoView removeFromSuperview];
    _webView = nil;
    _videoView = nil;
    _scriptHandler = nil;
    if (_eventSink) {
        BOOL didAttach = NO;
        JNIEnv *env = [self jniEnvDidAttach:&didAttach];
        if (env) {
            env->DeleteGlobalRef(_eventSink);
        }
        if (didAttach) {
            _javaVm->DetachCurrentThread();
        }
        _eventSink = nullptr;
    }
    _eventMethod = nullptr;
    _javaVm = nullptr;
}

- (void)setPaused:(BOOL)paused {
    if (!_mpv) return;
    int flag = paused ? 1 : 0;
    mpv_set_property(_mpv, "pause", MPV_FORMAT_FLAG, &flag);
    _cachedPaused.store(paused);
}

- (BOOL)isPaused {
    return _cachedPaused.load();
}

- (BOOL)rawIsPaused {
    if (!_mpv) return _cachedPaused.load();
    int flag = 1;
    mpv_get_property(_mpv, "pause", MPV_FORMAT_FLAG, &flag);
    return flag != 0;
}

- (void)seekToMilliseconds:(long long)positionMs {
    if (!_mpv) return;
    std::string seconds = std::to_string((double)positionMs / 1000.0);
    const char *command[] = {"seek", seconds.c_str(), "absolute+keyframes", NULL};
    mpv_command(_mpv, command);
    _cachedPositionSeconds.store(fmax((double)positionMs / 1000.0, 0.0));
}

- (void)seekByMilliseconds:(long long)offsetMs {
    if (!_mpv) return;
    std::string seconds = std::to_string((double)offsetMs / 1000.0);
    const char *command[] = {"seek", seconds.c_str(), "relative+keyframes", NULL};
    mpv_command(_mpv, command);
    double nextPosition = fmax(_cachedPositionSeconds.load() + ((double)offsetMs / 1000.0), 0.0);
    _cachedPositionSeconds.store(nextPosition);
}

- (void)setSpeed:(double)speed {
    if (!_mpv) return;
    double clamped = fmax(0.25, fmin(4.0, speed));
    mpv_set_property(_mpv, "speed", MPV_FORMAT_DOUBLE, &clamped);
    _cachedSpeed.store(clamped);

    // The demuxer cache is measured in content time, so faster-than-real-time playback
    // drains it faster in wall-clock terms. Scale it with the rate to avoid rebuffering.
    double factor = fmax(1.0, clamped);
    std::string cacheSecs = std::to_string(30.0 * factor);
    mpv_set_property_string(_mpv, "cache-secs", cacheSecs.c_str());
    mpv_set_property_string(_mpv, "demuxer-readahead-secs", cacheSecs.c_str());
}

- (double)speed {
    return _cachedSpeed.load();
}

- (double)rawSpeed {
    return [self doubleProperty:"speed" fallback:_cachedSpeed.load()];
}

- (void)setResizeMode:(int)mode {
    if (!_mpv) return;
    // Fit/Fill/Zoom also disable the managed crop without touching the user's vf chain.

    NSString *keepaspect = mode == 1 ? @"no" : @"yes";
    NSString *panscan = mode == 2 ? @"1.0" : @"0.0";

    dispatch_queue_t queue = _mpvEventQueue;
    if (!queue) {
        [self setStringProperty:"keepaspect" value:keepaspect];
        [self setStringProperty:"panscan" value:panscan];
        [self setStringProperty:"video-unscaled" value:@"no"];
        return;
    }

    dispatch_async(queue, ^{
        mpv_handle *mpv = self->_mpv;
        if (!mpv) {
            return;
        }
        self->_autoCrop = mode == 3;
        self->_autoCropChecks = 0;
        self->_cropCandidate = AutoCropBars{};
        self->_appliedCrop = AutoCropBars{};
        self->_nextCropCheck = 0;
        mpv_set_property_string(mpv, "video-crop", "");
        mpv_set_property_string(mpv, "keepaspect", keepaspect.UTF8String);
        mpv_set_property_string(mpv, "panscan", panscan.UTF8String);
        mpv_set_property_string(mpv, "video-unscaled", "no");
    });
}

- (long long)durationMs {
    return (long long)llround(fmax(_cachedDurationSeconds.load(), 0.0) * 1000.0);
}

- (long long)positionMs {
    return (long long)llround(fmax(_cachedPositionSeconds.load(), 0.0) * 1000.0);
}

- (double)rawPositionSeconds {
    double position = [self doubleProperty:"time-pos" fallback:0.0];
    return std::isfinite(position) ? fmax(position, 0.0) : 0.0;
}

- (double)effectiveCachePositionSeconds {
    double position = [self rawPositionSeconds];
    if (_initialStartSeconds > 0.0 && position + 5.0 < _initialStartSeconds) {
        return _initialStartSeconds;
    }
    return position;
}

- (double)cacheAheadSeconds {
    return [self cacheAheadSecondsForPosition:[self rawPositionSeconds]];
}

- (double)cacheAheadSecondsForPosition:(double)position {
    double safePosition = std::isfinite(position) ? fmax(position, 0.0) : 0.0;
    double effectivePosition = safePosition;
    if (_initialStartSeconds > 0.0 && safePosition + 5.0 < _initialStartSeconds) {
        effectivePosition = _initialStartSeconds;
    }
    double cacheTime = [self doubleProperty:"demuxer-cache-time" fallback:0.0];
    if (std::isfinite(cacheTime) && cacheTime > 0.0) {
        if (cacheTime >= effectivePosition - 5.0) {
            return fmax(cacheTime - effectivePosition, 0.0);
        }
        return cacheTime;
    }

    double cacheDuration = [self doubleProperty:"demuxer-cache-duration" fallback:0.0];
    if (std::isfinite(cacheDuration) && cacheDuration > 0.0) {
        return cacheDuration;
    }

    return 0.0;
}

- (long long)bufferedPositionMs {
    double bufferedPosition = _cachedPositionSeconds.load() + _cachedCacheAheadSeconds.load();
    return (long long)llround(fmax(bufferedPosition, 0.0) * 1000.0);
}

- (BOOL)isLoading {
    return _cachedLoading.load();
}

- (BOOL)rawLoadingWithPaused:(BOOL)paused ended:(BOOL)eofReached duration:(double)duration {
    BOOL idle = [self flagProperty:"core-idle" fallback:YES];
    BOOL seeking = [self flagProperty:"seeking" fallback:NO];
    BOOL bufferingCache = [self flagProperty:"paused-for-cache" fallback:NO];
    BOOL fileReady = duration > 0.0
        || [self int64Property:"track-list/count" fallback:0] > 0;
    return !fileReady || (idle && !paused && !eofReached) || seeking || bufferingCache;
}

- (BOOL)isEnded {
    return _cachedEnded.load();
}

- (BOOL)rawIsEnded {
    return [self flagProperty:"eof-reached" fallback:_cachedEnded.load()];
}

- (void)updateCachedDuration:(double)duration
                    position:(double)position
                  cacheAhead:(double)cacheAhead
                      paused:(BOOL)paused
                     loading:(BOOL)loading
                       ended:(BOOL)ended
                       speed:(double)speed {
    _cachedDurationSeconds.store(std::isfinite(duration) ? fmax(duration, 0.0) : 0.0);
    _cachedPositionSeconds.store(std::isfinite(position) ? fmax(position, 0.0) : 0.0);
    _cachedCacheAheadSeconds.store(std::isfinite(cacheAhead) ? fmax(cacheAhead, 0.0) : 0.0);
    _cachedSpeed.store(std::isfinite(speed) ? fmax(0.25, fmin(4.0, speed)) : 1.0);
    _cachedPaused.store(paused);
    _cachedLoading.store(loading);
    _cachedEnded.store(ended);
}

- (NSString *)audioTracksJson {
    @synchronized (self) {
        return _cachedAudioTracksJson ?: @"[]";
    }
}

- (NSString *)subtitleTracksJson {
    @synchronized (self) {
        return _cachedSubtitleTracksJson ?: @"[]";
    }
}

- (void)toggleStatsOverlay {
    [self command:@[@"script-binding", @"stats/display-stats-toggle"]];
}

- (NSString *)chaptersJson {
    if (!_mpv) return @"[]";
    NSMutableArray<NSDictionary *> *chapters = [NSMutableArray array];
    long long count = [self int64Property:"chapter-list/count" fallback:0];
    for (long long index = 0; index < count; index++) {
        NSString *prefix = [NSString stringWithFormat:@"chapter-list/%lld", index];
        NSString *timeKey = [prefix stringByAppendingString:@"/time"];
        double startTime = [self doubleProperty:timeKey.UTF8String fallback:-1.0];
        if (!std::isfinite(startTime) || startTime < 0.0) continue;
        NSString *titleKey = [prefix stringByAppendingString:@"/title"];
        NSString *title = [[self stringProperty:titleKey.UTF8String fallback:@""]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [chapters addObject:@{ @"startTime": @(startTime), @"title": title ?: @"" }];
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:chapters options:0 error:nil];
    return data ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]") : @"[]";
}

- (BOOL)selectAudioTrackId:(int)trackId {
    if (!_mpv) return NO;
    int64_t id = trackId;
    return mpv_set_property(_mpv, "aid", MPV_FORMAT_INT64, &id) >= 0;
}

- (BOOL)selectSubtitleTrackId:(int)trackId {
    if (!_mpv) return NO;
    int result;
    if (trackId < 0) {
        result = mpv_set_property_string(_mpv, "sid", "no");
    } else {
        int64_t id = trackId;
        result = mpv_set_property(_mpv, "sid", MPV_FORMAT_INT64, &id);
    }
    [self refreshSubtitleAssStyle];
    return result >= 0;
}

- (void)addSubtitleUrl:(NSString *)url {
    if (!_mpv || url.length == 0) return;
    [self command:@[@"sub-add", url, @"select"]];
    [self refreshSubtitleAssStyle];
}

- (void)removeExternalSubtitles {
    if (!_mpv) return;
    [self removeExternalSubtitleTracks];
    [self setStringProperty:"sid" value:@"no"];
}

- (void)removeExternalSubtitlesAndSelect:(int)trackId {
    if (!_mpv) return;
    [self removeExternalSubtitleTracks];
    if (trackId >= 0) {
        [self selectSubtitleTrackId:trackId];
    } else {
        [self setStringProperty:"sid" value:@"no"];
    }
}

- (void)setSubtitleDelayMs:(int)delayMs {
    if (!_mpv) return;
    int clamped = MAX(-60000, MIN(60000, delayMs));
    double delaySeconds = (double)clamped / 1000.0;
    mpv_set_property(_mpv, "sub-delay", MPV_FORMAT_DOUBLE, &delaySeconds);
}

- (void)applySubtitleStyleWithTextColor:(NSString *)textColor
                        backgroundColor:(NSString *)backgroundColor
                            outlineColor:(NSString *)outlineColor
                             outlineSize:(double)outlineSize
                                    bold:(BOOL)bold
                                fontSize:(double)fontSize
                                  subPos:(int)subPos {
    if (!_mpv) return;
    [self setStringProperty:"sub-ass-override" value:@"force"];
    [self setStringProperty:"sub-color" value:textColor ?: @"#FFFFFFFF"];
    [self setStringProperty:"sub-back-color" value:backgroundColor ?: @"#00000000"];
    [self setStringProperty:"sub-outline-color" value:outlineColor ?: @"#FF000000"];
    [self setStringProperty:"sub-border-style"
                      value:[(backgroundColor ?: @"") hasPrefix:@"#00"] ? @"outline-and-shadow" : @"opaque-box"];
    [self setStringProperty:"sub-bold" value:bold ? @"yes" : @"no"];

    double outline = MAX(0.0, MIN(8.0, outlineSize));
    mpv_set_property(_mpv, "sub-outline-size", MPV_FORMAT_DOUBLE, &outline);

    double size = MAX(24.0, MIN(96.0, fontSize));
    mpv_set_property(_mpv, "sub-font-size", MPV_FORMAT_DOUBLE, &size);

    int64_t position = MAX(0, MIN(150, subPos));
    mpv_set_property(_mpv, "sub-pos", MPV_FORMAT_INT64, &position);
    [self refreshSubtitleAssStyle];
}

- (void)setSubtitleAssStyleMode:(NSString *)mode scale:(double)scale {
    if (![@[@"no", @"yes", @"scale", @"force"] containsObject:mode]) return;
    _subtitleAssStyleMode = [mode copy];
    _subtitleAssScale = fmax(0.1, fmin(5.0, scale));
    [self refreshSubtitleAssStyle];
    [self forceVideoRedraw];
}

- (void)refreshSubtitleAssStyle {
    NSString *codec = [[self stringProperty:"current-tracks/sub/codec" fallback:@""] lowercaseString];
    BOOL ass = [codec isEqualToString:@"ass"] || [codec isEqualToString:@"ssa"];
    [self setStringProperty:"sub-ass-override" value:ass ? (_subtitleAssStyleMode ?: @"force") : @"force"];
    double scale = ass && _subtitleAssScale > 0.0 ? _subtitleAssScale : 1.0;
    if (_mpv) mpv_set_property(_mpv, "sub-scale", MPV_FORMAT_DOUBLE, &scale);
}

- (void)runJavaScript:(NSString *)script {
    if (!_webView || script.length == 0) return;
    if (!_controlsWebReady) {
        if (!_pendingScripts) _pendingScripts = [NSMutableArray array];
        [_pendingScripts addObject:script];
        return;
    }
    [_webView evaluateJavaScript:script completionHandler:nil];
}

- (void)setCursorHidden:(BOOL)hidden {
    if (_cursorHidden == hidden) return;
    _cursorHidden = hidden;
    if (hidden) [NSCursor hide]; else [NSCursor unhide];
}

- (void)forceVideoRedraw {
    [_videoView updateMetalLayerLayout];
    [_videoView scheduleRenderUpdate];
    [_videoView setNeedsDisplay:YES];
}

- (double)doubleProperty:(const char *)name fallback:(double)fallback {
    if (!_mpv) return fallback;
    double value = fallback;
    if (mpv_get_property(_mpv, name, MPV_FORMAT_DOUBLE, &value) < 0) {
        return fallback;
    }
    return value;
}

- (long long)int64Property:(const char *)name fallback:(long long)fallback {
    if (!_mpv) return fallback;
    int64_t value = fallback;
    if (mpv_get_property(_mpv, name, MPV_FORMAT_INT64, &value) < 0) {
        return fallback;
    }
    return value;
}

- (BOOL)flagProperty:(const char *)name fallback:(BOOL)fallback {
    if (!_mpv) return fallback;
    int flag = fallback ? 1 : 0;
    if (mpv_get_property(_mpv, name, MPV_FORMAT_FLAG, &flag) < 0) {
        return fallback;
    }
    return flag != 0;
}

- (NSString *)stringProperty:(const char *)name fallback:(NSString *)fallback {
    if (!_mpv) return fallback ?: @"";
    char *value = nullptr;
    if (mpv_get_property(_mpv, name, MPV_FORMAT_STRING, &value) < 0 || !value) {
        return fallback ?: @"";
    }
    NSString *result = [NSString stringWithUTF8String:value] ?: (fallback ?: @"");
    mpv_free(value);
    return result;
}

- (void)setStringProperty:(const char *)name value:(NSString *)value {
    if (!_mpv) return;
    mpv_set_property_string(_mpv, name, (value ?: @"").UTF8String);
}

- (void)command:(NSArray<NSString *> *)args {
    if (!_mpv || args.count == 0) return;
    std::vector<const char *> cargs;
    cargs.reserve(args.count + 1);
    for (NSString *arg in args) {
        cargs.push_back((arg ?: @"").UTF8String);
    }
    cargs.push_back(nullptr);
    mpv_command(_mpv, cargs.data());
}

- (void)removeExternalSubtitleTracks {
    long long count = [self int64Property:"track-list/count" fallback:0];
    if (count <= 0) return;
    for (long long index = count - 1; index >= 0; index--) {
        NSString *typeKey = [NSString stringWithFormat:@"track-list/%lld/type", index];
        NSString *externalKey = [NSString stringWithFormat:@"track-list/%lld/external", index];
        NSString *idKey = [NSString stringWithFormat:@"track-list/%lld/id", index];
        NSString *type = [self stringProperty:typeKey.UTF8String fallback:@""];
        BOOL external = [self flagProperty:externalKey.UTF8String fallback:NO];
        if ([type isEqualToString:@"sub"] && external) {
            long long trackId = [self int64Property:idKey.UTF8String fallback:-1];
            if (trackId >= 0) {
                [self command:@[@"sub-remove", [NSString stringWithFormat:@"%lld", trackId]]];
            }
        }
    }
}

- (NSString *)tracksJsonForType:(NSString *)wantedType {
    if (!_mpv) return @"[]";
    NSMutableArray<NSDictionary *> *tracks = [NSMutableArray array];
    long long count = [self int64Property:"track-list/count" fallback:0];
    long long primarySubtitleId = [wantedType isEqualToString:@"sub"]
        ? [self int64Property:"current-tracks/sub/id"
                    fallback:[self int64Property:"sid" fallback:-1]]
        : -1;
    int logicalIndex = 0;

    for (long long index = 0; index < count; index++) {
        NSString *prefix = [NSString stringWithFormat:@"track-list/%lld", index];
        NSString *type = [self stringProperty:[[prefix stringByAppendingString:@"/type"] UTF8String] fallback:@""];
        if (![type isEqualToString:wantedType]) {
            continue;
        }

        long long trackId = [self int64Property:[[prefix stringByAppendingString:@"/id"] UTF8String] fallback:logicalIndex + 1];
        NSString *title = [self trackStringAtIndex:index field:@"title"];
        NSString *language = [self trackStringAtIndex:index field:@"lang"];
        NSString *codec = [self trackStringAtIndex:index field:@"codec"];
        NSString *decoderDescription = [self trackStringAtIndex:index field:@"decoder-desc"];
        NSString *channels = [self trackStringAtIndex:index field:@"demux-channels"];
        long long channelCount = [self int64Property:[[prefix stringByAppendingString:@"/demux-channel-count"] UTF8String] fallback:0];
        // mpv reports both sid and secondary-sid tracks as selected; expose only the
        // primary/bottom track through the existing selected flag.
        BOOL trackSelected =
            [self flagProperty:[[prefix stringByAppendingString:@"/selected"] UTF8String] fallback:NO];
        BOOL selected = [wantedType isEqualToString:@"sub"]
            ? trackSelected || (primarySubtitleId >= 0 && trackId == primarySubtitleId)
            : trackSelected;
        BOOL forced = [self flagProperty:[[prefix stringByAppendingString:@"/forced"] UTF8String] fallback:NO];
        NSString *label = [self formatTrackTitleWithType:type
                                                   index:logicalIndex
                                                   title:title
                                                language:language
                                                   codec:codec
                                      decoderDescription:decoderDescription
                                                channels:channels
                                            channelCount:(int)channelCount];
        [tracks addObject:@{
            @"index": @(logicalIndex),
            @"id": [NSString stringWithFormat:@"%lld", trackId],
            @"label": label ?: @"",
            @"language": language ?: @"",
            @"selected": @(selected),
            @"forced": @(forced),
        }];
        logicalIndex += 1;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:tracks options:0 error:nil];
    if (!data) return @"[]";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]";
}

- (NSString *)trackStringAtIndex:(long long)index field:(NSString *)field {
    NSString *key = [NSString stringWithFormat:@"track-list/%lld/%@", index, field];
    return [[self stringProperty:key.UTF8String fallback:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)formatTrackTitleWithType:(NSString *)type
                                 index:(int)index
                                 title:(NSString *)title
                              language:(NSString *)language
                                 codec:(NSString *)codec
                    decoderDescription:(NSString *)decoderDescription
                              channels:(NSString *)channels
                          channelCount:(int)channelCount {
    NSString *base = [self ifNotBlank:title]
        ?: [self localizedLanguageName:language]
        ?: ([type isEqualToString:@"sub"]
            ? [NSString stringWithFormat:@"Subtitle %d", index + 1]
            : [NSString stringWithFormat:@"Track %d", index + 1]);
    NSString *codecName = [self codecDisplayName:codec] ?: [self codecDisplayName:decoderDescription];
    NSString *channelName = [type isEqualToString:@"audio"]
        ? [self channelLayoutNameWithChannels:channels channelCount:channelCount]
        : nil;
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    for (NSString *detail in @[channelName ?: @"", codecName ?: @""]) {
        if (detail.length == 0) continue;
        if ([base rangeOfString:detail options:NSCaseInsensitiveSearch].location == NSNotFound) {
            [details addObject:detail];
        }
    }
    return details.count == 0
        ? base
        : [NSString stringWithFormat:@"%@ (%@)", base, [details componentsJoinedByString:@", "]];
}

- (NSString *)ifNotBlank:(NSString *)value {
    NSString *trimmed = [(value ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? nil : trimmed;
}

- (NSString *)localizedLanguageName:(NSString *)languageCode {
    NSString *code = [self ifNotBlank:languageCode];
    if (!code) return nil;
    return [[NSLocale currentLocale] displayNameForKey:NSLocaleLanguageCode value:code] ?: code;
}

- (NSString *)channelLayoutNameWithChannels:(NSString *)channels channelCount:(int)channelCount {
    NSString *normalized = [self ifNotBlank:channels];
    if (normalized && ![normalized isEqualToString:@"unknown"]) {
        NSString *lower = normalized.lowercaseString;
        if ([lower isEqualToString:@"mono"]) return @"Mono";
        if ([lower isEqualToString:@"stereo"]) return @"Stereo";
        return normalized;
    }
    switch (channelCount) {
        case 1: return @"Mono";
        case 2: return @"Stereo";
        case 6: return @"5.1";
        case 8: return @"7.1";
        default:
            return channelCount > 0 ? [NSString stringWithFormat:@"%dch", channelCount] : nil;
    }
}

- (NSString *)codecDisplayName:(NSString *)value {
    NSString *raw = [self ifNotBlank:value];
    if (!raw) return nil;
    NSString *codec = raw.lowercaseString;
    if ([codec containsString:@"eac3"] || [codec containsString:@"e-ac-3"] || [codec containsString:@"e ac-3"]) {
        return ([codec containsString:@"joc"] || [codec containsString:@"atmos"]) ? @"E-AC-3-JOC" : @"E-AC-3";
    }
    if ([codec containsString:@"truehd"] || [codec containsString:@"true hd"]) return @"TrueHD";
    if ([codec containsString:@"ac3"] || [codec containsString:@"ac-3"]) return @"AC-3";
    if ([codec containsString:@"dts-hd"] || [codec containsString:@"dtshd"] || [codec containsString:@"dts hd"]) return @"DTS-HD";
    if ([codec containsString:@"dts"] || [codec isEqualToString:@"dca"]) return @"DTS";
    if ([codec containsString:@"aac"]) return @"AAC";
    if ([codec containsString:@"mp3"] || [codec containsString:@"mpeg audio"]) return @"MP3";
    if ([codec containsString:@"mp2"]) return @"MP2";
    if ([codec containsString:@"opus"]) return @"Opus";
    if ([codec containsString:@"vorbis"]) return @"Vorbis";
    if ([codec containsString:@"flac"]) return @"FLAC";
    if ([codec containsString:@"alac"]) return @"ALAC";
    if ([codec containsString:@"pcm"] || [codec containsString:@"wav"]) return @"WAV";
    if ([codec containsString:@"amr_wb"] || [codec containsString:@"amr-wb"]) return @"AMR-WB";
    if ([codec containsString:@"amr_nb"] || [codec containsString:@"amr-nb"]) return @"AMR-NB";
    if ([codec containsString:@"amr"]) return @"AMR";
    if ([codec containsString:@"iamf"]) return @"IAMF";
    if ([codec containsString:@"mpegh"] || [codec containsString:@"mpeg-h"]) return @"MPEG-H";
    if ([codec containsString:@"pgs"] || [codec containsString:@"hdmv"]) return @"PGS";
    if ([codec containsString:@"subrip"] || [codec isEqualToString:@"srt"]) return @"SRT";
    if ([codec containsString:@"ass"] || [codec containsString:@"ssa"]) return @"SSA";
    if ([codec containsString:@"webvtt"] || [codec isEqualToString:@"vtt"]) return @"VTT";
    if ([codec containsString:@"ttml"]) return @"TTML";
    if ([codec containsString:@"mov_text"] || [codec containsString:@"tx3g"]) return @"TX3G";
    if ([codec containsString:@"dvb"]) return @"DVB";
    return raw;
}

- (void)handleScriptMessage:(NSDictionary *)message {
    NSString *type = message[@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        return;
    }

    id rawValue = message[@"value"];
    NSNumber *value = [rawValue isKindOfClass:[NSNumber class]] ? rawValue : nil;
    if ([type isEqualToString:@"controlsReady"]) {
        _controlsWebReady = YES;
        [self flushPendingControlsJsonIfReady];
        NSArray<NSString *> *pending = [_pendingScripts copy];
        [_pendingScripts removeAllObjects];
        for (NSString *script in pending) [self runJavaScript:script];
        [self syncControls];
        return;
    }
    if ([type isEqualToString:@"setControlsUiScalePercent"] && value) {
        _controlsUiScaleFactor = fmax(0.5, fmin(1.5, 1.0 + value.doubleValue / 100.0));
        [self layoutControlsWebViewToBounds:_hostView.bounds immediate:YES];
        return;
    }
    if ([type isEqualToString:@"selectAudioTrack"] && value) {
        [self selectAudioTrackId:(int)llround(value.doubleValue)];
        [self syncControls];
        return;
    }
    if ([type isEqualToString:@"selectSubtitleTrack"] && value) {
        [self selectSubtitleTrackId:(int)llround(value.doubleValue)];
        [self syncControls];
        return;
    }
    if ([type isEqualToString:@"toggleFullscreen"]) {
        [self beginFullscreenTransitionWithReason:@"control-toggle"];
    }

    if (_eventSink && _eventMethod) {
        [self sendPlayerEvent:type value:value ? value.doubleValue : 0.0];
        return;
    }

    if ([type isEqualToString:@"toggle"]) {
        [self setPaused:![self isPaused]];
        [self syncControls];
    } else if ([type isEqualToString:@"seekPercent"]) {
        double duration = [self doubleProperty:"duration" fallback:0.0];
        if (duration > 0.0 && value) {
            [self seekToMilliseconds:(long long)llround(duration * value.doubleValue * 1000.0)];
        }
    } else if ([type isEqualToString:@"scrubFinish"] && value) {
        [self seekToMilliseconds:(long long)llround(value.doubleValue)];
    }
}

// Workers use independent libmpv connections; no main/UI queue is blocked by network I/O.
- (mpv_handle *)newProbe {
    if (_stopping.load() || !_probeSource.length) return nullptr;
    mpv_handle *probe = mpv_create();
    if (!probe) return nullptr;
    for (const auto &option : std::vector<std::pair<const char *, const char *>>{
        {"config", "no"}, {"terminal", "no"}, {"load-scripts", "no"}, {"ytdl", "no"},
        {"input-default-bindings", "no"}, {"osc", "no"}, {"cache", "no"},
        {"network-timeout", "10"}, {"demuxer-readahead-secs", "1"}, {"demuxer-max-bytes", "8MiB"}}) {
        mpv_set_option_string(probe, option.first, option.second);
    }
    std::string headers;
    for (NSString *line in _probeHeaders) {
        if (!headers.empty()) headers += ',';
        for (char ch : std::string(line.UTF8String)) {
            if (ch == ',' || ch == '\\') headers += '\\';
            headers += ch;
        }
    }
    if (!headers.empty()) mpv_set_option_string(probe, "http-header-fields", headers.c_str());
    return probe;
}

- (double)speechSourceBytesPerSecond {
    if (![_probeSource hasPrefix:@"http://"] && ![_probeSource hasPrefix:@"https://"]) return -1;
    return _sourceBytesPerSecond.load();
}

- (int)decodeSpeechSpot:(double)start duration:(double)duration output:(NSString *)output {
    if (!std::isfinite(start) || !std::isfinite(duration) || duration <= 0 || duration > 120 || !output.length) return -1;
    mpv_handle *probe = [self newProbe];
    if (!probe) return -1;
    for (const auto &option : std::vector<std::pair<const char *, const char *>>{
        {"vid", "no"}, {"sid", "no"}, {"audio-display", "no"}, {"audio-spdif", ""}, {"af", ""},
        {"ao", "pcm"}, {"ao-pcm-waveheader", "no"}, {"audio-samplerate", "16000"},
        {"audio-channels", "mono"}, {"audio-format", "float"}, {"hr-seek", "yes"}, {"keep-open", "no"}}) {
        mpv_set_option_string(probe, option.first, option.second);
    }
    mpv_set_option_string(probe, "ao-pcm-file", output.fileSystemRepresentation);
    mpv_set_option_string(probe, "start", std::to_string(std::max(0.0, start)).c_str());
    mpv_set_option_string(probe, "end", std::to_string(std::max(0.0, start) + duration).c_str());
    int64_t aid = _selectedAudioId.load();
    if (aid > 0 && !_probeAudioSource.length) mpv_set_option_string(probe, "aid", std::to_string(aid).c_str());
    NSString *source = _probeAudioSource.length ? _probeAudioSource : _probeSource;
    int result = -1;
    if (mpv_initialize(probe) >= 0) {
        const char *load[] = {"loadfile", source.UTF8String, nullptr};
        if (mpv_command(probe, load) >= 0) {
            auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(90);
            while (!_stopping.load() && std::chrono::steady_clock::now() < deadline) {
                mpv_event *event = mpv_wait_event(probe, 0.1);
                if (event->event_id == MPV_EVENT_END_FILE) {
                    auto end = static_cast<mpv_event_end_file *>(event->data);
                    result = end && end->reason == MPV_END_FILE_REASON_EOF ? 0 : -2;
                    break;
                }
                if (event->event_id == MPV_EVENT_SHUTDOWN) break;
            }
        }
    }
    mpv_terminate_destroy(probe);
    return result;
}

- (void)requestSeekThumbnail:(long long)positionMs {
    if (_stopping.load() || !_thumbnailQueue) return;
    uint64_t generation = ++_thumbnailGeneration;
    dispatch_async(_thumbnailQueue, ^{
        @autoreleasepool {
            if (self->_stopping.load() || generation != self->_thumbnailGeneration.load()) return;
            mpv_handle *probe = [self newProbe];
            if (!probe) return;
            for (const auto &option : std::vector<std::pair<const char *, const char *>>{
                {"audio", "no"}, {"sid", "no"}, {"vo", "null"}, {"pause", "yes"}, {"hwdec", "no"},
                {"hr-seek", "no"}, {"vf", "lavfi=[scale=256:-2]"}, {"screenshot-format", "jpg"},
                {"screenshot-jpeg-quality", "64"}}) mpv_set_option_string(probe, option.first, option.second);
            mpv_set_option_string(probe, "start", std::to_string(std::max(0LL, positionMs) / 1000.0).c_str());
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"nuvio-thumb-%@.jpg", NSUUID.UUID.UUIDString]];
            NSData *image = nil;
            int initialized = mpv_initialize(probe);
            if (initialized < 0) fprintf(stderr, "Warn: (SeekThumbnail) initialize: %s\n", mpv_error_string(initialized));
            if (initialized >= 0) {
                const char *load[] = {"loadfile", self->_probeSource.UTF8String, nullptr};
                if (mpv_command(probe, load) >= 0) {
                    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
                    while (!self->_stopping.load() && generation == self->_thumbnailGeneration.load() &&
                           std::chrono::steady_clock::now() < deadline) {
                        mpv_event *event = mpv_wait_event(probe, 0.05);
                        if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) {
                            const char *screenshot[] = {"screenshot-to-file", path.fileSystemRepresentation, "video", nullptr};
                            int captured = mpv_command(probe, screenshot);
                            if (captured >= 0) image = [NSData dataWithContentsOfFile:path];
                            else fprintf(stderr, "Warn: (SeekThumbnail) screenshot: %s\n", mpv_error_string(captured));
                            break;
                        }
                        if (event->event_id == MPV_EVENT_END_FILE || event->event_id == MPV_EVENT_SHUTDOWN) break;
                    }
                }
            }
            mpv_terminate_destroy(probe);
            if (!image.length) image = [NSData dataWithContentsOfFile:path];
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            if (!image.length || self->_stopping.load() || generation != self->_thumbnailGeneration.load()) return;
            NSString *url = [@"data:image/jpeg;base64," stringByAppendingString:[image base64EncodedStringWithOptions:0]];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_stopping.load() || generation != self->_thumbnailGeneration.load()) return;
                [self runJavaScript:[NSString stringWithFormat:
                    @"window.nuvioSeekThumbnailReady && window.nuvioSeekThumbnailReady(%lld,%@)", positionMs, javaScriptStringLiteral(url)]];
            });
        }
    });
}

- (void)checkAutoCrop {
    _nextCropCheck = CFAbsoluteTimeGetCurrent() + (_autoCropChecks >= 3 ? 15 : 3);
    char name[] = "screenshot-raw", flag[] = "video";
    mpv_node values[2] = {};
    values[0].format = values[1].format = MPV_FORMAT_STRING;
    values[0].u.string = name; values[1].u.string = flag;
    mpv_node_list list{2, values, nullptr};
    mpv_node args{}; args.format = MPV_FORMAT_NODE_ARRAY; args.u.list = &list;
    mpv_node result{};
    if (mpv_command_node(_mpv, &args, &result) < 0) return;
    int64_t w = 0, h = 0, stride = 0;
    std::string format;
    const uint8_t *pixels = nullptr;
    size_t byteSize = 0;
    if (result.format == MPV_FORMAT_NODE_MAP && result.u.list) {
        for (int i = 0; i < result.u.list->num; ++i) {
            std::string key = result.u.list->keys[i];
            const mpv_node &v = result.u.list->values[i];
            if (key == "w" && v.format == MPV_FORMAT_INT64) w = v.u.int64;
            if (key == "h" && v.format == MPV_FORMAT_INT64) h = v.u.int64;
            if (key == "stride" && v.format == MPV_FORMAT_INT64) stride = v.u.int64;
            if (key == "format" && v.format == MPV_FORMAT_STRING) format = v.u.string;
            if (key == "data" && v.format == MPV_FORMAT_BYTE_ARRAY && v.u.ba) {
                pixels = static_cast<uint8_t *>(v.u.ba->data); byteSize = v.u.ba->size;
            }
        }
    }
    int bpp = format == "rgba64" ? 8 :
        (format == "bgra" || format == "bgr0" || format == "rgba" || format == "rgb0") ? 4 : 0;
    AutoCropBars bars;
    bool valid = bpp && h > 0 && stride > 0 && (uint64_t)stride * (uint64_t)h <= byteSize &&
        detectAutoCropBars(pixels, w, h, stride, bpp, bars);
    mpv_free_node_contents(&result);
    if (!valid || bars.top > 0.35 || bars.left > 0.35) return; // Ignore fades/mostly-black scenes.
    const int fw = (int)[self doubleProperty:"video-params/w" fallback:w];
    const int fh = (int)[self doubleProperty:"video-params/h" fallback:h];
    if (fw <= 0 || fh <= 0) return;
    // screenshot-raw may include the existing crop. Convert its measurements back to source space.
    if (std::abs(w - (int)llround(fw * (1 - 2 * _appliedCrop.left))) <= 2 && w != fw)
        bars.left = bars.right = _appliedCrop.left + bars.left * (1 - 2 * _appliedCrop.left);
    if (std::abs(h - (int)llround(fh * (1 - 2 * _appliedCrop.top))) <= 2 && h != fh)
        bars.top = bars.bottom = _appliedCrop.top + bars.top * (1 - 2 * _appliedCrop.top);
    if (_autoCropChecks == 0) _cropCandidate = bars;
    else {
        _cropCandidate.top = std::min(_cropCandidate.top, bars.top);
        _cropCandidate.left = std::min(_cropCandidate.left, bars.left);
    }
    if (++_autoCropChecks < 3) return;
    _appliedCrop.top = _appliedCrop.bottom = _cropCandidate.top;
    _appliedCrop.left = _appliedCrop.right = _cropCandidate.left;
    int x = (int)llround(fw * _appliedCrop.left), y = (int)llround(fh * _appliedCrop.top);
    NSString *crop = x || y ? [NSString stringWithFormat:@"%dx%d+%d+%d", fw - 2*x, fh - 2*y, x, y] : @"";
    mpv_set_property_string(_mpv, "video-crop", crop.UTF8String);
}

- (void)setMediaTitle:(NSString *)title subtitle:(NSString *)subtitle artwork:(NSString *)artwork {
    if (_stopping.load() || !title.length) return;
    nuvioMediaOwner = self;
    if (!_ownsMediaSession) {
        _ownsMediaSession = YES;
        _remoteCommandTargets = [NSMutableArray array];
        __weak MpvWebPlayer *weakSelf = self;
        MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
        NSArray *commands = @[center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                              center.stopCommand, center.changePlaybackPositionCommand];
        for (MPRemoteCommand *command in commands) {
            command.enabled = YES;
            id token = [command addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
                MpvWebPlayer *player = weakSelf;
                if (!player || player->_stopping.load() || nuvioMediaOwner != player) return MPRemoteCommandHandlerStatusNoSuchContent;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (player->_stopping.load()) return;
                    if (command == center.changePlaybackPositionCommand) {
                        [player seekToMilliseconds:(long long)(((MPChangePlaybackPositionCommandEvent *)event).positionTime * 1000)];
                    } else {
                        NSString *type = command == center.playCommand ? @"mediaPlay" :
                            command == center.pauseCommand || command == center.stopCommand ? @"mediaPause" :
                            ([player isPaused] ? @"mediaPlay" : @"mediaPause");
                        [player sendPlayerEvent:type value:0];
                    }
                });
                return MPRemoteCommandHandlerStatusSuccess;
            }];
            [_remoteCommandTargets addObject:@[command, token]];
        }
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = title;
    info[MPMediaItemPropertyArtist] = subtitle ?: @"";
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    [self updateNowPlayingPosition:_cachedPositionSeconds.load() duration:_cachedDurationSeconds.load() paused:_cachedPaused.load()];
    NSUInteger generation = ++_artworkGeneration;
    NSURL *url = [NSURL URLWithString:artwork ?: @""];
    if (![@[@"http", @"https"] containsObject:url.scheme.lowercaseString]) return;
    __weak MpvWebPlayer *weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length || data.length > 8 * 1024 * 1024) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            MpvWebPlayer *player = weakSelf;
            if (!player || player->_stopping.load() || nuvioMediaOwner != player || generation != player->_artworkGeneration) return;
            NSImage *image = [[NSImage alloc] initWithData:data];
            if (!image) return;
            NSMutableDictionary *current = [MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo mutableCopy];
            current[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size requestHandler:^NSImage *(CGSize size) { return image; }];
            MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = current;
        });
    }] resume];
}

- (void)updateNowPlayingPosition:(double)position duration:(double)duration paused:(BOOL)paused {
    if (!_ownsMediaSession || _stopping.load() || nuvioMediaOwner != self) return;
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary];
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(std::max(0.0, position));
    info[MPMediaItemPropertyPlaybackDuration] = @(std::max(0.0, duration));
    info[MPNowPlayingInfoPropertyPlaybackRate] = paused ? @0 : @(_cachedSpeed.load());
    center.nowPlayingInfo = info;
    center.playbackState = paused ? MPNowPlayingPlaybackStatePaused : MPNowPlayingPlaybackStatePlaying;
}

@end

static void runOnMainSync(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static void runOnMainAsync(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static void throwJavaError(JNIEnv *env, NSString *message) {
    jclass exceptionClass = env->FindClass("java/lang/IllegalStateException");
    if (exceptionClass) {
        env->ThrowNew(exceptionClass, message.UTF8String);
    }
}

static std::string jstringToString(JNIEnv *env, jstring value) {
    if (!value) return std::string();
    jsize length = env->GetStringLength(value);
    const jchar *chars = env->GetStringChars(value, nullptr);
    if (!chars) {
        return std::string();
    }
    NSString *string = [NSString stringWithCharacters:(const unichar *)chars length:(NSUInteger)length];
    env->ReleaseStringChars(value, chars);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return std::string();
    }
    std::string result((const char *)data.bytes, data.length);
    return result;
}

static NSArray<NSString *> *jstringArrayToNSArray(JNIEnv *env, jobjectArray values) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (!values) {
        return result;
    }
    jsize count = env->GetArrayLength(values);
    for (jsize index = 0; index < count; index++) {
        jstring item = (jstring)env->GetObjectArrayElement(values, index);
        std::string value = jstringToString(env, item);
        if (!value.empty()) {
            [result addObject:[NSString stringWithUTF8String:value.c_str()]];
        }
        env->DeleteLocalRef(item);
    }
    return result;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_create(
    JNIEnv *env,
    jobject /* bridge */,
    jlong hostViewPtr,
    jstring sourceUrl,
    jstring sourceAudioUrl,
    jobjectArray headerLines,
    jboolean playWhenReady,
    jlong initialPositionMs,
    jdouble initialProgressFraction,
    jstring controlsPageUrl,
    jboolean nvidiaRtxSuperResolutionEnabled,
    jboolean nvidiaRtxHdrEnabled,
    jboolean isAnimeContent,
    jstring animeSvpFilter,
    jobjectArray extraMpvOptions,
    jobject eventSink
) {
    // These features currently have Windows-only implementations. Keep the complete shared JNI
    // signature so subsequent arguments (especially eventSink) retain the correct ABI positions.
    (void)nvidiaRtxSuperResolutionEnabled;
    (void)nvidiaRtxHdrEnabled;
    (void)isAnimeContent;
    (void)animeSvpFilter;
    NSView *hostView = (__bridge NSView *)(void *)(intptr_t)hostViewPtr;
    if (!hostView) {
        throwJavaError(env, @"Unable to resolve the AWT host NSView for native playback.");
        return 0;
    }

    JavaVM *javaVm = nullptr;
    env->GetJavaVM(&javaVm);
    jobject eventSinkRef = nullptr;
    jmethodID eventMethod = nullptr;
    if (eventSink) {
        eventSinkRef = env->NewGlobalRef(eventSink);
        jclass eventSinkClass = env->GetObjectClass(eventSink);
        eventMethod = env->GetMethodID(eventSinkClass, "onPlayerEvent", "(Ljava/lang/String;D)V");
        env->DeleteLocalRef(eventSinkClass);
        if (!eventMethod) {
            if (eventSinkRef) {
                env->DeleteGlobalRef(eventSinkRef);
            }
            throwJavaError(env, @"Native player event sink is missing onPlayerEvent(String, Double).");
            return 0;
        }
    }

    std::string source = jstringToString(env, sourceUrl);
    std::string audioSource = sourceAudioUrl ? jstringToString(env, sourceAudioUrl) : std::string();
    std::string controls = jstringToString(env, controlsPageUrl);
    NSArray<NSString *> *headers = jstringArrayToNSArray(env, headerLines);
    NSArray<NSString *> *mpvOptions = jstringArrayToNSArray(env, extraMpvOptions);
    __block MpvWebPlayer *player = nil;
    __block NSString *error = nil;
    runOnMainSync(^{
        @try {
            player = [[MpvWebPlayer alloc]
                initWithHostView:hostView
                    sourceUrl:[NSString stringWithUTF8String:source.c_str()]
                   audioSourceUrl:(audioSource.empty() ? nil : [NSString stringWithUTF8String:audioSource.c_str()])
                    headerLines:headers
                     mpvOptions:mpvOptions
                   playWhenReady:playWhenReady == JNI_TRUE
                initialPositionMs:initialPositionMs
          initialProgressFraction:initialProgressFraction
                     controlsUrl:[NSString stringWithUTF8String:controls.c_str()]
                          javaVm:javaVm
                       eventSink:eventSinkRef
                     eventMethod:eventMethod];
        } @catch (NSException *exception) {
            error = exception.reason ?: exception.name;
        }
    });

    if (error) {
        if (eventSinkRef) {
            env->DeleteGlobalRef(eventSinkRef);
        }
        throwJavaError(env, error);
        return 0;
    }

    return (jlong)(intptr_t)CFBridgingRetain(player);
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_dispose(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge_transfer MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainSync(^{
        [player shutdown];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_updateControls(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle,
    jstring controlsJson
) {
    if (handle == 0) return;
    std::string controls = jstringToString(env, controlsJson);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player updateControlsJson:[NSString stringWithUTF8String:controls.c_str()]];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setPaused(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jboolean paused
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player setPaused:paused == JNI_TRUE];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_seekTo(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jlong positionMs
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player seekToMilliseconds:positionMs];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_seekBy(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jlong offsetMs
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player seekByMilliseconds:offsetMs];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setSpeed(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jfloat speed
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player setSpeed:speed];
    });
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_durationMs(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return 0;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player durationMs];
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_positionMs(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return 0;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player positionMs];
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_bufferedPositionMs(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return 0;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player bufferedPositionMs];
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_isLoading(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return JNI_TRUE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player isLoading] ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_isEnded(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return JNI_FALSE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player isEnded] ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_isPaused(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return JNI_TRUE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player isPaused] ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jfloat JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_speed(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return 1.0f;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return (jfloat)[player speed];
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setResizeMode(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jint mode
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player setResizeMode:(int)mode];
    });
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_audioTracksJson(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return env->NewStringUTF("[]");
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    NSString *json = [player audioTracksJson] ?: @"[]";
    return env->NewStringUTF(json.UTF8String);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_subtitleTracksJson(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return env->NewStringUTF("[]");
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    NSString *json = [player subtitleTracksJson] ?: @"[]";
    return env->NewStringUTF(json.UTF8String);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_chaptersJson(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return env->NewStringUTF("[]");
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    NSString *json = [player chaptersJson] ?: @"[]";
    return env->NewStringUTF(json.UTF8String);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_selectAudioTrack(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jint trackId
) {
    if (handle == 0) return JNI_FALSE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    __block BOOL selected = NO;
    runOnMainSync(^{
        selected = [player selectAudioTrackId:(int)trackId];
    });
    return selected ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_requestSeekThumbnail(
    JNIEnv *, jobject, jlong handle, jlong positionMs
) {
    if (!handle) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    [player requestSeekThumbnail:positionMs];
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_selectSubtitleTrack(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jint trackId
) {
    if (handle == 0) return JNI_FALSE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    __block BOOL selected = NO;
    runOnMainSync(^{
        selected = [player selectSubtitleTrackId:(int)trackId];
    });
    return selected ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_addSubtitleUrl(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle,
    jstring url
) {
    if (handle == 0) return;
    std::string subtitleUrl = jstringToString(env, url);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player addSubtitleUrl:[NSString stringWithUTF8String:subtitleUrl.c_str()]];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_clearExternalSubtitles(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player removeExternalSubtitles];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_clearExternalSubtitlesAndSelect(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jint trackId
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player removeExternalSubtitlesAndSelect:(int)trackId];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setSubtitleDelayMs(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle,
    jint delayMs
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player setSubtitleDelayMs:(int)delayMs];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_applySubtitleStyle(
    JNIEnv *env,
    jobject /* bridge */,
    jlong handle,
    jstring textColor,
    jstring backgroundColor,
    jstring outlineColor,
    jfloat outlineSize,
    jboolean bold,
    jfloat fontSize,
    jint subPos,
    jstring fontName
) {
    if (handle == 0) return;
    std::string text = jstringToString(env, textColor);
    std::string background = jstringToString(env, backgroundColor);
    std::string outline = jstringToString(env, outlineColor);
    std::string font = jstringToString(env, fontName);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{
        [player applySubtitleStyleWithTextColor:[NSString stringWithUTF8String:text.c_str()]
                                backgroundColor:[NSString stringWithUTF8String:background.c_str()]
                                    outlineColor:[NSString stringWithUTF8String:outline.c_str()]
                                     outlineSize:(double)outlineSize
                                            bold:bold == JNI_TRUE
                                        fontSize:(double)fontSize
                                          subPos:(int)subPos];
        [player setStringProperty:"sub-font" value:[NSString stringWithUTF8String:font.c_str()]];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_toggleStatsOverlay(
    JNIEnv * /* env */,
    jobject /* bridge */,
    jlong handle
) {
    if (handle == 0) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player toggleStatsOverlay]; });
}

// Shared playback JNI entry points. Cocoa/WebKit changes are serialized on the main thread.
extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setMpvProperty(
    JNIEnv *env, jobject, jlong handle, jstring key, jstring value
) {
    if (!handle) return;
    std::string keyText = jstringToString(env, key);
    std::string valueText = jstringToString(env, value);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    if (keyText == "@nuvio-hdr-mode") {
        runOnMainAsync(^{ [player setHdrMode:[NSString stringWithUTF8String:valueText.c_str()]]; });
        return;
    }
    if (keyText == "@nuvio-display-panel") {
        runOnMainAsync(^{ [player setDisplayPanel:[NSString stringWithUTF8String:valueText.c_str()]]; });
        return;
    }
    // Other internal Windows/SVP directives are not libmpv properties.
    if (keyText.empty() || keyText[0] == '@') return;
    runOnMainAsync(^{
        [player setStringProperty:keyText.c_str() value:[NSString stringWithUTF8String:valueText.c_str()]];
    });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_runJavaScript(
    JNIEnv *env, jobject, jlong handle, jstring script
) {
    if (!handle) return;
    std::string text = jstringToString(env, script);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player runJavaScript:[NSString stringWithUTF8String:text.c_str()]]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setCursorHidden(
    JNIEnv *, jobject, jlong handle, jboolean hidden
) {
    if (!handle) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player setCursorHidden:hidden == JNI_TRUE]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_forceVideoRedraw(
    JNIEnv *, jobject, jlong handle
) {
    if (!handle) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player forceVideoRedraw]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setSubtitleAssStyleMode(
    JNIEnv *env, jobject, jlong handle, jstring mode, jdouble scale
) {
    if (!handle) return;
    std::string text = jstringToString(env, mode);
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player setSubtitleAssStyleMode:[NSString stringWithUTF8String:text.c_str()] scale:scale]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setMediaSessionMetadata(
    JNIEnv *env, jobject, jlong handle, jstring title, jstring subtitle, jstring artwork
) {
    if (!handle) return;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    NSString *t = [NSString stringWithUTF8String:jstringToString(env, title).c_str()];
    NSString *st = [NSString stringWithUTF8String:jstringToString(env, subtitle).c_str()];
    NSString *art = [NSString stringWithUTF8String:jstringToString(env, artwork).c_str()];
    runOnMainAsync(^{ [player setMediaTitle:t subtitle:st artwork:art]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setVolume(
    JNIEnv *, jobject, jlong handle, jfloat volume
) {
    if (!handle) return;
    std::string value = std::to_string(fmax(0.0, fmin(200.0, volume)));
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player setStringProperty:"volume" value:[NSString stringWithUTF8String:value.c_str()]]; });
}

extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setMute(
    JNIEnv *, jobject, jlong handle, jboolean muted
) {
    if (!handle) return;
    std::string value = std::string(muted == JNI_TRUE ? "yes" : "no");
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    runOnMainAsync(^{ [player setStringProperty:"mute" value:[NSString stringWithUTF8String:value.c_str()]]; });
}

extern "C" JNIEXPORT jfloat JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_volume(
    JNIEnv *, jobject, jlong handle
) {
    if (!handle) return 100.0f;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    __block double value = 0;
    runOnMainSync(^{ value = [player doubleProperty:"volume" fallback:100.0]; });
    return (jfloat)value;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_isMuted(
    JNIEnv *, jobject, jlong handle
) {
    if (!handle) return JNI_FALSE;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    __block double value = 0;
    runOnMainSync(^{ value = [player flagProperty:"mute" fallback:NO]; });
    return value ? JNI_TRUE : JNI_FALSE;
}

// Process-scoped power assertions work in windowed, fullscreen and PiP playback without
// synthesizing input or changing the idle clock used by Nuvio's own screensaver.
extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setMacosDisplaySleepInhibited(
    JNIEnv *, jobject, jboolean inhibited
) {
    static std::mutex assertionMutex;
    static IOPMAssertionID displayAssertion = kIOPMNullAssertionID;
    std::lock_guard<std::mutex> lock(assertionMutex);
    if (inhibited == JNI_TRUE) {
        if (displayAssertion != kIOPMNullAssertionID) return JNI_TRUE;
        // Preventing display idle sleep also prevents system idle sleep (IOPMLib contract).
        IOPMAssertionID assertion = kIOPMNullAssertionID;
        IOReturn result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn,
            CFSTR("Nuvio video playback display"), &assertion);
        if (result != kIOReturnSuccess) return JNI_FALSE;
        displayAssertion = assertion;
        return JNI_TRUE;
    }
    if (displayAssertion == kIOPMNullAssertionID) return JNI_TRUE;
    if (IOPMAssertionRelease(displayAssertion) != kIOReturnSuccess) return JNI_FALSE;
    displayAssertion = kIOPMNullAssertionID;
    return JNI_TRUE;
}

// The hardware idle clock also sees input consumed by WebKit and native video surfaces.
extern "C" JNIEXPORT jlong JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_systemIdleMs(JNIEnv *, jobject) {
    const double seconds = CGEventSourceSecondsSinceLastEventType(
        kCGEventSourceStateHIDSystemState, kCGAnyInputEventType);
    if (!std::isfinite(seconds) || seconds < 0.0 || seconds > (double)INT64_MAX / 1000.0) return -1;
    return (jlong)(seconds * 1000.0);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_isForegroundProcess(JNIEnv *, jobject) {
    // The screensaver calls this on AWT's event thread. AppKit accessibility can be waiting
    // for that same thread, so synchronously asking NSApp on the main queue deadlocks both.
    // Process Manager reads foreground identity without crossing either UI event queue.
    ProcessSerialNumber foreground = {0, 0};
    ProcessSerialNumber current = {0, 0};
    Boolean same = false;
    if (GetFrontProcess(&foreground) != noErr || GetCurrentProcess(&current) != noErr ||
        SameProcess(&foreground, &current, &same) != noErr) return JNI_FALSE;
    return same ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_requestMacosShutdown(
    JNIEnv *, jobject, jboolean confirmed
) {
    // Allows linkage tests without ever triggering shutdown. Only the expired idle countdown
    // passes true. Send the normal loginwindow event, without a shell or privileged helper.
    if (confirmed != JNI_TRUE) return JNI_FALSE;
    __block OSStatus status = noErr;
    runOnMainSync(^{
        const ProcessSerialNumber systemProcess = {0, kSystemProcess};
        AEAddressDesc target = {typeNull, nullptr};
        AppleEvent event = {typeNull, nullptr};
        status = AECreateDesc(typeProcessSerialNumber, &systemProcess, sizeof(systemProcess), &target);
        if (status == noErr) {
            status = AECreateAppleEvent(kCoreEventClass, kAEShutDown, &target,
                kAutoGenerateReturnID, kAnyTransactionID, &event);
            if (status == noErr) {
                status = AESendMessage(&event, nullptr, kAENoReply, kAEDefaultTimeout);
            }
        }
        AEDisposeDesc(&event);
        AEDisposeDesc(&target);
    });
    if (status != noErr) fprintf(stderr, "Warning: (Screensaver) macOS shutdown request failed: %d\n", (int)status);
    return status == noErr ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_decodeSpeechSpot(
    JNIEnv *env, jobject, jlong handle, jdouble start, jdouble duration, jstring output
) {
    if (!handle) return -1;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    NSString *path = [NSString stringWithUTF8String:jstringToString(env, output).c_str()];
    return [player decodeSpeechSpot:start duration:duration output:path];
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_speechSourceBytesPerSecond(JNIEnv *, jobject, jlong handle) {
    if (!handle) return -1;
    MpvWebPlayer *player = (__bridge MpvWebPlayer *)(void *)(intptr_t)handle;
    return [player speechSourceBytesPerSecond];
}

extern "C" JNIEXPORT jint JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_pollGamepads(JNIEnv *env, jobject, jint mask, jintArray out) {
    if (!out || env->GetArrayLength(out) < 64) return 0;
    std::vector<jint> storage(64);
    jint *state = storage.data();
    __block jint connected = 0;
    runOnMainSync(^{
        NSArray<GCController *> *connectedControllers = GCController.controllers;
        static NSMutableArray *slots = nil;
        if (!slots) slots = [NSMutableArray arrayWithArray:@[NSNull.null,NSNull.null,NSNull.null,NSNull.null,NSNull.null,NSNull.null,NSNull.null,NSNull.null]];
        for (NSUInteger i = 0; i < 8; ++i) if (slots[i] != NSNull.null && ![connectedControllers containsObject:slots[i]]) slots[i] = NSNull.null;
        for (GCController *controller in connectedControllers) {
            if ([slots containsObject:controller]) continue;
            NSUInteger vacant = [slots indexOfObject:NSNull.null];
            if (vacant != NSNotFound) slots[vacant] = controller;
        }
        NSArray *controllers = slots;
        for (NSUInteger i = 0; i < MIN((NSUInteger)8, controllers.count); ++i) {
            if (!(mask & (1 << i))) continue;
            if (controllers[i] == NSNull.null) continue;
            GCExtendedGamepad *pad = [(GCController *)controllers[i] extendedGamepad];
            if (!pad) continue;
            connected |= 1 << i;
            jint *slot = state + i * 8;
            slot[0] = (pad.dpad.up.pressed ? 0x1 : 0) | (pad.dpad.down.pressed ? 0x2 : 0) |
                (pad.dpad.left.pressed ? 0x4 : 0) | (pad.dpad.right.pressed ? 0x8 : 0) |
                (pad.buttonMenu.pressed ? 0x10 : 0) | (pad.buttonOptions.pressed ? 0x20 : 0) |
                (pad.leftThumbstickButton.pressed ? 0x40 : 0) | (pad.rightThumbstickButton.pressed ? 0x80 : 0) |
                (pad.leftShoulder.pressed ? 0x100 : 0) | (pad.rightShoulder.pressed ? 0x200 : 0) |
                (pad.buttonA.pressed ? 0x1000 : 0) | (pad.buttonB.pressed ? 0x2000 : 0) |
                (pad.buttonX.pressed ? 0x4000 : 0) | (pad.buttonY.pressed ? 0x8000 : 0);
            slot[1] = (int)llround(pad.leftTrigger.value * 255);
            slot[2] = (int)llround(pad.rightTrigger.value * 255);
            slot[3] = (int)llround(pad.leftThumbstick.xAxis.value * 32767);
            slot[4] = (int)llround(pad.leftThumbstick.yAxis.value * 32767);
            slot[5] = (int)llround(pad.rightThumbstick.xAxis.value * 32767);
            slot[6] = (int)llround(pad.rightThumbstick.yAxis.value * 32767);
            slot[7] = (int)(CFAbsoluteTimeGetCurrent() * 60);
        }
    });
    for (int i = 0; i < 8; ++i) if (mask & (1 << i)) env->SetIntArrayRegion(out, i * 8, 8, state + i * 8);
    return connected;
}

// Preserve native macOS decorations/insets while making the window compact and floating.
extern "C" JNIEXPORT void JNICALL
Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setCompactPlayerWindow(
    JNIEnv *, jobject, jlong viewPointer, jboolean enabled
) {
    if (!viewPointer) return;
    NSView *view = (__bridge NSView *)(void *)(intptr_t)viewPointer;
    runOnMainAsync(^{
        NSWindow *window = view.window;
        if (!window) return;
        static char stateKey;
        NSDictionary *prior = objc_getAssociatedObject(window, &stateKey);
        NSArray<NSButton *> *buttons = @[[window standardWindowButton:NSWindowCloseButton] ?: [NSButton new],
            [window standardWindowButton:NSWindowMiniaturizeButton] ?: [NSButton new],
            [window standardWindowButton:NSWindowZoomButton] ?: [NSButton new]];
        if (enabled == JNI_TRUE && !prior) {
            prior = @{ @"title": @(window.titleVisibility), @"transparent": @(window.titlebarAppearsTransparent),
                @"level": @(window.level), @"collection": @(window.collectionBehavior),
                @"hidden": @[@(buttons[0].hidden), @(buttons[1].hidden), @(buttons[2].hidden)] };
            objc_setAssociatedObject(window, &stateKey, prior, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            window.titleVisibility = NSWindowTitleHidden;
            window.titlebarAppearsTransparent = YES;
            window.level = NSFloatingWindowLevel;
            window.collectionBehavior |= NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
            for (NSButton *button in buttons) button.hidden = YES;
        } else if (enabled == JNI_FALSE && prior) {
            window.titleVisibility = (NSWindowTitleVisibility)[prior[@"title"] integerValue];
            window.titlebarAppearsTransparent = [prior[@"transparent"] boolValue];
            window.level = [prior[@"level"] integerValue];
            window.collectionBehavior = [prior[@"collection"] unsignedIntegerValue];
            for (NSUInteger i = 0; i < buttons.count; ++i) buttons[i].hidden = [prior[@"hidden"][i] boolValue];
            objc_setAssociatedObject(window, &stateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}
