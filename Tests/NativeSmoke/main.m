#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "MenuBarBridge.h"

static NSString *prefix;
static int failures = 0;

static id attribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    AXUIElementCopyAttributeValue(element, key, &value);
    return CFBridgingRelease(value);
}

static NSSet<NSString *> *snapshot(void) {
    NSMutableSet *found = [NSMutableSet set];
    NSRunningApplication *agent = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.MenuBarAgent"].firstObject;
    if (!agent) return found;
    AXUIElementRef root = AXUIElementCreateApplication(agent.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.25);
    for (id w in attribute(root, kAXChildrenAttribute)) {
        AXUIElementRef window = (__bridge AXUIElementRef)w;
        if (![attribute(window, kAXRoleAttribute) isEqual:@"AXWindow"]) continue;
        for (id g in attribute(window, kAXChildrenAttribute)) {
            AXUIElementRef group = (__bridge AXUIElementRef)g;
            for (id c in attribute(group, kAXChildrenAttribute)) {
                AXUIElementRef child = (__bridge AXUIElementRef)c;
                pid_t pid = 0; AXUIElementGetPid(child, &pid);
                NSString *bundle = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
                if (bundle) [found addObject:bundle];
                if (pid == agent.processIdentifier) {
                    for (id l in attribute(child, kAXChildrenAttribute)) {
                        NSString *identifier = attribute((__bridge AXUIElementRef)l, kAXIdentifierAttribute);
                        if (identifier) [found addObject:identifier];
                    }
                }
            }
        }
    }
    CFRelease(root);
    return found;
}

static void spin(double seconds) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void check(BOOL condition, NSString *label) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", label.UTF8String);
    if (!condition) failures++;
}

static NSArray *allowing(NSArray<NSString *> *hidden) {
    NSMutableSet *allowed = [NSMutableSet set];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        if (app.bundleIdentifier && ![hidden containsObject:app.bundleIdentifier]) [allowed addObject:app.bundleIdentifier];
    }
    return allowed.allObjects;
}

static void apply(BFMenuBarSession *session, NSArray<NSString *> *hidden) {
    __block BOOL done = NO;
    __block NSError *failure;
    [session applyAllowedBundles:allowing(hidden) completion:^(NSError *error) { failure = error; done = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:6];
    while (!done && deadline.timeIntervalSinceNow > 0) spin(0.05);
    check(done && !failure, @"native activation completed");
    spin(0.5);
}

static void checkControls(NSSet *before, NSSet *after) {
    for (NSString *suffix in @[@"wifi", @"sound", @"battery", @"clock", @"controlcenter"]) {
        NSString *key = [@"com.apple.menuextra." stringByAppendingString:suffix];
        if ([before containsObject:key]) check([after containsObject:key], [@"preserved " stringByAppendingString:suffix]);
    }
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    prefix = NSProcessInfo.processInfo.environment[@"BARFOLD_TEST_PREFIX"] ?: @"local.barfold.fixture.";
    if (!AXIsProcessTrusted() || !BFMenuBarSession.supported) { fprintf(stderr, "Accessibility or native API unavailable\n"); return 2; }
    NSString *visible = [prefix stringByAppendingString:@"visible"];
    NSString *collapsed = [prefix stringByAppendingString:@"collapsed"];
    NSString *hidden = [prefix stringByAppendingString:@"hidden"];
    if (argc > 1 && strcmp(argv[1], "--hold") == 0) {
        BFMenuBarSession *held = [BFMenuBarSession new];
        apply(held, @[hidden]);
        spin(15);
        [held restore];
        return 0;
    }
    NSSet *before = snapshot();
    NSDate *readyDeadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ((! [before containsObject:visible] || ![before containsObject:collapsed] || ![before containsObject:hidden]) && readyDeadline.timeIntervalSinceNow > 0) {
        spin(0.1);
        before = snapshot();
    }
    check([before containsObject:visible] && [before containsObject:collapsed] && [before containsObject:hidden], @"three fixtures discovered");
    if (failures) {
        for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
            if ([app.bundleIdentifier hasPrefix:prefix]) {
                fprintf(stderr, "fixture %s visible-in-AX=%d\n", app.bundleIdentifier.UTF8String, [before containsObject:app.bundleIdentifier]);
            }
        }
        return 1;
    }
    BFMenuBarSession *session = [BFMenuBarSession new];
    apply(session, @[collapsed, hidden]);
    NSSet *closed = snapshot();
    check([closed containsObject:visible] && ![closed containsObject:collapsed] && ![closed containsObject:hidden], @"collapsed: only always-visible fixture remains");
    checkControls(before, closed);
    apply(session, @[hidden]);
    NSSet *opened = snapshot();
    check([opened containsObject:visible] && [opened containsObject:collapsed] && ![opened containsObject:hidden], @"expanded: permanent-hidden fixture remains hidden");
    checkControls(before, opened);
    [session restore]; spin(0.5);
    NSSet *restored = snapshot();
    check([restored containsObject:visible] && [restored containsObject:collapsed] && [restored containsObject:hidden], @"restored: all fixtures return");
    apply(session, @[hidden]);
    session = nil; spin(0.5);
    check([snapshot() containsObject:hidden], @"session destruction restores hidden fixture");
    session = [BFMenuBarSession new];
    __block int callbacks = 0;
    __block BOOL cancelled = NO;
    [session applyAllowedBundles:allowing(@[hidden]) completion:^(NSError *error) { callbacks++; cancelled = error != nil; }];
    [session restore];
    check(callbacks == 1 && cancelled, @"restore cancels pending activation exactly once");
    apply(session, @[hidden]);
    check(![snapshot() containsObject:hidden], @"late callback cannot cancel a newer assertion");
    [session restore]; spin(0.5);
    check(callbacks == 1 && [snapshot() containsObject:hidden], @"cancelled assertion does not hide items again");

    NSTask *child = [NSTask new];
    child.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
    child.arguments = @[@"--hold"];
    child.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    NSError *launchError;
    check([child launchAndReturnError:&launchError], @"launched process-exit fixture");
    if (!launchError) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while ([snapshot() containsObject:hidden] && deadline.timeIntervalSinceNow > 0) spin(0.1);
        check(![snapshot() containsObject:hidden], @"child process holds hidden state");
        [child terminate];
        [child waitUntilExit];
        spin(0.5);
        check([snapshot() containsObject:hidden], @"process exit restores hidden fixture");
    }
    return failures ? 1 : 0;
}}
