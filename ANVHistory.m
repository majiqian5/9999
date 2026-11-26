#import "ANVHistory.h"
#import "ANVActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

@interface ANVHistory ()
@property (nonatomic, strong) NSMutableArray<NSString *> *backStack;
@property (nonatomic, strong) NSMutableArray<NSString *> *forwardStack;
@property (nonatomic, copy) NSString *current;
@property (nonatomic, assign) NSTimeInterval suppressUntil;
@property (nonatomic, strong) NSTimer *trackTimer;
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [instance startTracking];
        });
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

#pragma mark - 前台 App 探测（SpringBoard._switcherController._currentMainAppLayout）

- (NSString *)frontmostBundleID {
    @try {
        id springBoard = [UIApplication sharedApplication];
        id controller = [springBoard valueForKey:@"_switcherController"];
        if (!controller) return nil;

        SEL mainSel = NSSelectorFromString(@"_currentMainAppLayout");
        id layout = nil;
        if ([controller respondsToSelector:mainSel]) {
            layout = ((id (*)(id, SEL))objc_msgSend)(controller, mainSel);
        }
        if (!layout) {
            @try { layout = [controller valueForKey:@"_currentMainAppLayout"]; } @catch (__unused NSException *e) {}
        }
        if (!layout) return nil;

        SEL itemsSel = NSSelectorFromString(@"allItems");
        id items = nil;
        if ([layout respondsToSelector:itemsSel]) {
            items = ((id (*)(id, SEL))objc_msgSend)(layout, itemsSel);
        }
        for (id item in items) {
            NSString *bundleID = nil;
            @try { bundleID = [item valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
            if (![bundleID isKindOfClass:[NSString class]] || !bundleID.length) {
                @try { bundleID = [item valueForKey:@"displayIdentifier"]; } @catch (__unused NSException *e) {}
            }
            if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) return bundleID;
        }

        NSString *bundleID = nil;
        @try { bundleID = [layout valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
        if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) return bundleID;
    } @catch (__unused NSException *e) {}

    // SpringBoard 里取不到时，走 LSApplicationWorkspace / SBApplicationController
    @try {
        NSString *live = [ANVActions frontmostBundleID];
        if (live.length) return live;
    } @catch (__unused NSException *e) {}
    return nil;
}

- (void)startTracking {
    if (self.trackTimer) return;
    __weak typeof(self) weakSelf = self;
    self.trackTimer = [NSTimer timerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
        NSString *bundleID = [weakSelf frontmostBundleID];
        static int probeLogs = 0;
        if (bundleID.length && probeLogs < 3) {
            probeLogs++;
            [ANVActions note:[NSString stringWithFormat:@"frontmost detect: %@ (back=%lu fwd=%lu)",
                              bundleID, (unsigned long)weakSelf.backStack.count,
                              (unsigned long)weakSelf.forwardStack.count]];
        }
        if (bundleID.length) [weakSelf record:bundleID];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.trackTimer forMode:NSRunLoopCommonModes];
}

- (void)invalidateCurrent {
    self.current = nil;
}

- (NSString *)currentBundleIDForLog {
    return [self frontmostBundleID];
}

#pragma mark - Public

- (void)suppressRecordingFor:(NSTimeInterval)seconds {
    self.suppressUntil = [NSDate date].timeIntervalSince1970 + seconds;
}

- (void)record:(NSString *)bundleID {
    if (!bundleID.length) return;
    if (bundleID.length && [bundleID.lowercaseString isEqualToString:@"com.apple.springboard"]) return;
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

- (void)noteOpenResult:(NSString *)bundleID success:(BOOL)ok {
    if (ok) {
        [self noteProgrammaticOpen:bundleID];
    } else {
        // 打开失败：撤掉这一次的栈操作痕迹，别让它污染历史
        self.current = nil;
        [self suppressRecordingFor:0.6];
    }
}

- (void)noteProgrammaticOpen:(NSString *)bundleID {
    [self suppressRecordingFor:2.0];
    if (bundleID.length) self.current = bundleID;
}

- (NSArray<NSString *> *)visitedBundleIDs {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (self.current.length) [out addObject:self.current];
    for (NSString *bid in [self.backStack reverseObjectEnumerator]) {
        if (bid.length && ![out containsObject:bid]) [out addObject:bid];
    }
    return out;
}

- (NSString *)fallbackRecentBundleID {
    @try {
        NSArray<NSString *> *list = [ANVActions recentBundleIDs];
        NSString *current = self.current;
        for (NSString *bundleID in list) {
            if (current.length && [bundleID isEqualToString:current]) continue;
            return bundleID;
        }
    } @catch (__unused NSException *e) {}

    NSString *live = [self frontmostBundleID];
    if (live.length && ![live isEqualToString:self.current ?: @""]) return live;

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
