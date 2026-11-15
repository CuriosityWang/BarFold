#import "MenuBarBridge.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// Runtime signatures verified on macOS 27.2 (26B123). No private framework is linked.
@interface NSObject (BFMenuBarRuntime)
- (instancetype)initWithAllowedSystemItems:(NSArray *)systemItems allowedBundleIdentifiers:(NSArray *)bundles;
- (void)activateWithConfiguration:(id)configuration completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end

@implementation BFMenuBarSession {
    id _active;
    id _pending;
    NSUInteger _generation;
    void (^_completion)(NSError *);
}

static NSError *BFError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"BarFold.MenuBar" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}

+ (BOOL)supported {
    static void *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW | RTLD_LOCAL);
    });
    if (!library) return NO;
    Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    Method init = class_getInstanceMethod(configuration, @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:));
    Method activate = class_getInstanceMethod(assertion, @selector(activateWithConfiguration:completionHandler:));
    Method invalidate = class_getInstanceMethod(assertion, @selector(invalidate));
    return init && activate && invalidate && method_getNumberOfArguments(init) == 4
        && method_getNumberOfArguments(activate) == 4 && method_getNumberOfArguments(invalidate) == 2;
}

static void BFReleaseAssertion(id assertion) {
    @try { [assertion invalidate]; }
    @catch (NSException *exception) { NSLog(@"BarFold: assertion release failed: %@", exception.name); }
}

- (void)finish:(NSError *)error generation:(NSUInteger)generation {
    if (generation != _generation || !_completion) return;
    if (error) {
        BFReleaseAssertion(_pending);
        BFReleaseAssertion(_active);
        _active = nil;
    } else {
        BFReleaseAssertion(_active);
        _active = _pending;
    }
    _pending = nil;
    void (^callback)(NSError *) = _completion;
    _completion = nil;
    callback(error);
}

- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Menu bar session requires main thread");
    if (_completion) { completion(BFError(2, @"A visibility update is already running")); return; }
    if (!self.class.supported) { completion(BFError(1, @"Menu bar API unavailable")); return; }
    NSUInteger generation = ++_generation;
    _completion = [completion copy];
    @try {
        // Keep all nine supported system controls, including clock and Control Center.
        id config = [[NSClassFromString(@"MBAssessmentModeConfiguration") alloc]
            initWithAllowedSystemItems:@[@0,@1,@2,@3,@4,@5,@6,@7,@8] allowedBundleIdentifiers:bundles];
        _pending = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!config || !_pending) {
            [self finish:BFError(3, @"Could not create menu bar assertion") generation:generation];
            return;
        }
        __weak BFMenuBarSession *weakSelf = self;
        [_pending activateWithConfiguration:config completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finish:error generation:generation]; });
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [weakSelf finish:BFError(4, @"Menu bar update timed out") generation:generation];
        });
    } @catch (NSException *exception) {
        [self finish:BFError(5, @"Menu bar API rejected the update") generation:generation];
    }
}

- (void)restore {
    ++_generation;
    BFReleaseAssertion(_pending);
    BFReleaseAssertion(_active);
    _pending = nil;
    _active = nil;
    void (^callback)(NSError *) = _completion;
    _completion = nil;
    if (callback) callback(BFError(6, @"Visibility update cancelled"));
}

- (void)dealloc {
    BFReleaseAssertion(_pending);
    BFReleaseAssertion(_active);
}
@end
