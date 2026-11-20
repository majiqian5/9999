#import "ANVHistory.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

@interface ANVHistory ()
@property (nonatomic, strong) NSMutableArray<NSString *> *backStack;
@property (nonatomic, strong) NSMutableArray<NSString *> *forwardStack;
@property (nonatomic, copy) NSString *current;
@property (nonatomic, assign) NSTimeInterval suppressUntil;
@end

static ANVHistory *ANVSharedHistory(void) {
    return [ANVHistory shared];
}

#pragma mark - Runtime hooks

static void (*ANVOrigSetDisplayed)(id, SEL, BOOL);
static void ANVSetDisplayedHook(id self, SEL _cmd, BOOL displayed) {
    ANVOrigSetDisplayed(self, _cmd, displayed);
    if (displayed) {
        @try {
            NSString *bundleID = [self valueForKey:@"bundleIdentifier"];
            if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) {
                [ANVSharedHistory() record:bundleID];
            }
        } @catch (__unused NSException *e) {}
    }
}

static void (*ANVOrigSetFrontmost)(id, SEL, BOOL);
static void ANVSetFrontmostHook(id self, SEL _cmd, BOOL frontmost) {
    ANVOrigSetFrontmost(self, _cmd, frontmost);
    if (frontmost) {
        @try {
            NSString *bundleID = [self valueForKey:@"bundleIdentifier"];
            if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) {
                [ANVSharedHistory() record:bundleID];
            }
        } @catch (__unused NSException *e) {}
    }
}

@implementation ANVHistory

+ (instancetype)shared {
    static ANVHistory *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ANVHistory alloc] init];
        instance.backStack = [NSMutableArray array];
        instance.forwardStack = [NSMutableArray array];
    });
    return instance;
}

+ (void)installHooks {
    Class appClass = objc_getClass("SBApplication");
    if (!appClass) return;

    SEL displayedSel = sel_registerName("setDisplayed:");
    Method displayedMethod = class_getInstanceMethod(appClass, displayedSel);
    if (displayedMethod && !ANVOrigSetDisplayed) {
        MSHookMessageEx(appClass, displayedSel, (IMP)ANVSetDisplayedHook,
                        (IMP *)&ANVOrigSetDisplayed);
    }

    SEL frontmostSel = sel_registerName("setFrontmost:");
    Method frontmostMethod = class_getInstanceMethod(appClass, frontmostSel);
    if (frontmostMethod && !ANVOrigSetFrontmost) {
        MSHookMessageEx(appClass, frontmostSel, (IMP)ANVSetFrontmostHook,
                        (IMP *)&ANVOrigSetFrontmost);
    }
}

#pragma mark - Public

- (void)suppressRecordingFor:(NSTimeInterval)seconds {
    self.suppressUntil = [NSDate date].timeIntervalSince1970 + seconds;
}

- (void)record:(NSString *)bundleID {
    if (!bundleID.length) return;
    if (bundleID.length && [bundleID isEqualToString:@"com.apple.springboard"]) return;
    if ([NSDate date].timeIntervalSince1970 < self.suppressUntil) return;
    if ([bundleID isEqualToString:self.current ?: @""]) return;

    if (self.current.length) {
        [self.backStack addObject:self.current];
        if (self.backStack.count > 12) [self.backStack removeObjectAtIndex:0];
    }
    self.current = bundleID;
    [self.forwardStack removeAllObjects];
}

- (NSString *)currentBundleID {
    if (self.current.length) return self.current;
    return nil;
}

- (NSString *)bundleIDForBack {
    if (self.backStack.count) {
        return self.backStack.lastObject;
    }
    return [self fallbackRecentBundleID];
}

- (NSString *)bundleIDForForward {
    if (self.forwardStack.count) {
        return self.forwardStack.lastObject;
    }
    return nil;
}

- (NSString *)moveBack {
    NSString *target = nil;
    if (self.backStack.count) {
        target = self.backStack.lastObject;
        [self.backStack removeLastObject];
        if (self.current.length) [self.forwardStack addObject:self.current];
    } else {
        target = [self fallbackRecentBundleID];
        if (target.length) {
            if (self.current.length) [self.forwardStack addObject:self.current];
        }
    }
    if (target.length) self.current = target;
    return target;
}

- (NSString *)moveForward {
    if (!self.forwardStack.count) return nil;
    NSString *target = self.forwardStack.lastObject;
    [self.forwardStack removeLastObject];
    if (self.current.length) [self.backStack addObject:self.current];
    self.current = target;
    return target;
}

- (void)noteProgrammaticOpen:(NSString *)bundleID {
    [self suppressRecordingFor:2.0];
    if (bundleID.length) self.current = bundleID;
}

- (NSString *)fallbackRecentBundleID {
    @try {
        Class recentsClass = objc_getClass("SBRecentAppLayouts");
        if (!recentsClass) return nil;
        id recents = [recentsClass performSelector:@selector(sharedInstance)];
        if (![recents respondsToSelector:@selector(_recentsFromPrefs)]) return nil;
        NSArray *layouts = [recents performSelector:@selector(_recentsFromPrefs)];
        for (id layout in layouts) {
            @try {
                NSDictionary *map = [layout valueForKey:@"rolesToLayoutItemsMap"];
                for (id item in map.allValues) {
                    NSString *bundleID = [item valueForKey:@"displayIdentifier"];
                    if ([bundleID isKindOfClass:[NSString class]] &&
                        bundleID.length &&
                        ![bundleID isEqualToString:self.current ?: @""]) {
                        return bundleID;
                    }
                }
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

@end
