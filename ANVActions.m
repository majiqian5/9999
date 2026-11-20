#import "ANVActions.h"
#import "ANVHistory.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

static NSString *const kANVLogPath = @"/var/mobile/andronavbar.log";

static void ANVLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *stamped = [NSString stringWithFormat:@"[%@] %@\n",
                         [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                        dateStyle:NSDateFormatterMediumStyle
                                                        timeStyle:NSDateFormatterMediumStyle],
                         line];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kANVLogPath]) {
        [stamped writeToFile:kANVLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kANVLogPath];
    @try {
        [handle seekToEndOfFile];
        [handle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (__unused NSException *e) {}
}

static void ANVDumpMethods(Class cls, NSString *keyword, NSString *tag) {
    if (!cls) { ANVLog(@"%@ class missing", tag); return; }
    for (int pass = 0; pass < 2; pass++) {
        Class target = (pass == 0) ? cls : object_getClass(cls);
        unsigned int count = 0;
        Method *list = class_copyMethodList(target, &count);
        if (!list) continue;
        NSMutableArray *names = [NSMutableArray array];
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(list[i]));
            if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            [names addObject:name];
            if (names.count >= 40) break;
        }
        free(list);
        if (names.count) {
            ANVLog(@"%@ %@: %@", tag, (pass == 0) ? @"-" : @"+", [names componentsJoinedByString:@" | "]);
        }
    }
}

@implementation ANVActions

#pragma mark - 环境探测

+ (void)note:(NSString *)message {
    ANVLog(@"[bar] %@", message);
}

+ (void)logEnvironment {
    ANVLog(@"--- AndroNavBar probe begin ---");
    ANVLog(@"UIApplication: homePress=%d homePressCompletion=%d",
           [[UIApplication sharedApplication] respondsToSelector:NSSelectorFromString(@"_simulateHomeButtonPress")],
           [[UIApplication sharedApplication] respondsToSelector:NSSelectorFromString(@"_simulateHomeButtonPressWithCompletion:")]);

    Class switcherClass = objc_getClass("SBMainSwitcherViewController");
    id switcher = [switcherClass respondsToSelector:@selector(sharedInstance)] ? [(id)switcherClass performSelector:@selector(sharedInstance)] : nil;
    ANVLog(@"switcher class=%@ toggle=%d toggleWithSource=%d toggleMain=%d activate=%d",
           switcherClass,
           [switcher respondsToSelector:NSSelectorFromString(@"toggleSwitcherNoninteractively")],
           [switcher respondsToSelector:NSSelectorFromString(@"toggleSwitcherNoninteractivelyWithSource:")],
           [switcher respondsToSelector:NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:")],
           [switcher respondsToSelector:NSSelectorFromString(@"activateSwitcherNoninteractively")]);

    Class appClass = objc_getClass("SBApplication");
    ANVLog(@"SBApplication setDisplayed=%d setFrontmost=%d",
           [appClass instancesRespondToSelector:NSSelectorFromString(@"setDisplayed:")],
           [appClass instancesRespondToSelector:NSSelectorFromString(@"setFrontmost:")]);

    Class wsClass = objc_getClass("LSApplicationWorkspace");
    id ws = [wsClass respondsToSelector:@selector(defaultWorkspace)] ? [(id)wsClass performSelector:@selector(defaultWorkspace)] : nil;
    ANVLog(@"LSApplicationWorkspace=%@ open=%d", wsClass,
           [ws respondsToSelector:NSSelectorFromString(@"openApplicationWithBundleID:")]);
    ANVLog(@"switcher extra: activateWithSource=%d present=%d underscoreToggle=%d",
           [switcher respondsToSelector:NSSelectorFromString(@"activateSwitcherWithSource:")],
           [switcher respondsToSelector:NSSelectorFromString(@"presentAppSwitcher")],
           [switcher respondsToSelector:NSSelectorFromString(@"_toggleMainSwitcherNoninteractivelyWithSource:animated:")]);

    id appController = [objc_getClass("SBApplicationController") respondsToSelector:@selector(sharedInstance)]
                     ? [objc_getClass("SBApplicationController") performSelector:@selector(sharedInstance)] : nil;
    ANVLog(@"frontmost via SBApplicationController=%d", [appController respondsToSelector:NSSelectorFromString(@"frontmostApplication")]);
    Class wsProbe = objc_getClass("LSApplicationWorkspace");
    id wsInstance = [wsProbe respondsToSelector:@selector(defaultWorkspace)] ? [wsProbe performSelector:@selector(defaultWorkspace)] : nil;
    ANVLog(@"frontmost via LSApplicationWorkspace=%d", [wsInstance respondsToSelector:NSSelectorFromString(@"frontmostApplication")]);
    // 把真正存在的方法名列出来，不再靠猜
    ANVDumpMethods(objc_getClass("SBMainSwitcherViewController"), @"witcher", @"SEL switcher");
    ANVDumpMethods(objc_getClass("SBApplicationController"), @"ront", @"SEL appCtl");
    ANVDumpMethods(objc_getClass("SBRecentAppLayouts"), @"ecent", @"SEL recents");
    ANVDumpMethods(objc_getClass("LSApplicationWorkspace"), @"ront", @"SEL workspace");
    ANVDumpMethods(objc_getClass("SBUIController"), @"ome", @"SEL uic");
    ANVDumpMethods(objc_getClass("SBApplication"), @"ront", @"SEL app front");
    ANVDumpMethods(objc_getClass("SBApplication"), @"isplay", @"SEL app isplay");
    ANVDumpMethods(objc_getClass("SBApplication"), @"ctiv", @"SEL app activ");
    ANVDumpMethods(objc_getClass("SBApplicationController"), @"pplication", @"SEL appCtl app");
    ANVDumpMethods(objc_getClass("SpringBoard"), @"ctiv", @"SEL sb activ");
    ANVDumpMethods(objc_getClass("SpringBoard"), @"witch", @"SEL sb switch");
    ANVDumpMethods(objc_getClass("SBMainWorkspace"), @"ctiv", @"SEL workspace activ");
    ANVDumpMethods(objc_getClass("SBWorkspace"), @"ctiv", @"SEL ws activ");
    ANVLog(@"--- probe end ---");
}

#pragma mark - App 切换

+ (BOOL)openBundleID:(NSString *)bundleID {
    if (!bundleID.length) return NO;
    @try {
        Class workspaceClass = objc_getClass("LSApplicationWorkspace");
        if (!workspaceClass) return NO;
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        SEL sel = @selector(openApplicationWithBundleID:);
        if (![workspace respondsToSelector:sel]) return NO;
        BOOL (*openFn)(id, SEL, NSString *) = (BOOL (*)(id, SEL, NSString *))objc_msgSend;
        BOOL ok = openFn(workspace, sel, bundleID);
        if (ok) [[ANVHistory shared] noteProgrammaticOpen:bundleID];
        ANVLog(@"open %@ -> %d", bundleID, ok);
        return ok;
    } @catch (NSException *e) {
        ANVLog(@"open exception: %@", e);
        return NO;
    }
}

#pragma mark - 主屏幕

+ (BOOL)goHome {
    UIApplication *app = [UIApplication sharedApplication];

    // iOS 15+ 用带 completion 的版本；更老的系统用无参版本
    for (NSString *name in @[@"_simulateHomeButtonPressWithCompletion:", @"_simulateHomeButtonPress"]) {
        SEL sel = NSSelectorFromString(name);
        if ([app respondsToSelector:sel]) {
            @try {
                if ([name hasSuffix:@":"]) {
                    [app performSelector:sel withObject:nil];
                } else {
                    [app performSelector:sel];
                }
                ANVLog(@"goHome via UIApplication %@ -> yes", name);
                return YES;
            } @catch (NSException *e) {
                ANVLog(@"goHome %@ exception: %@", name, e);
            }
        }
    }

    // 备用：让多任务控制器回到主屏布局
    @try {
        Class switcherClass = objc_getClass("SBMainSwitcherViewController");
        Class layoutClass = objc_getClass("SBAppLayout");
        if (switcherClass && layoutClass) {
            id switcher = [switcherClass performSelector:@selector(sharedInstance)];
            SEL dismissSel = NSSelectorFromString(@"_dismissSwitcherNoninteractivelyToAppLayout:dismissFloatingSwitcher:animated:");
            if ([switcher respondsToSelector:dismissSel] &&
                [layoutClass respondsToSelector:@selector(homeScreenAppLayout)]) {
                id homeLayout = [layoutClass performSelector:@selector(homeScreenAppLayout)];
                NSMethodSignature *sig = [switcher methodSignatureForSelector:dismissSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = switcher;
                inv.selector = dismissSel;
                BOOL yes1 = YES, yes2 = YES;
                [inv setArgument:&homeLayout atIndex:2];
                [inv setArgument:&yes1 atIndex:3];
                [inv setArgument:&yes2 atIndex:4];
                [inv invoke];
                ANVLog(@"goHome via switcher dismiss -> yes");
                return YES;
            }
        }
    } @catch (NSException *e) {
        ANVLog(@"goHome switcher exception: %@", e);
    }

    // 老系统兜底
    @try {
        Class uicClass = objc_getClass("SBUIController");
        if (uicClass) {
            id uic = [uicClass performSelector:@selector(sharedInstance)];
            for (NSString *name in @[@"handleHomeButtonSinglePress", @"_handleHomeButtonSinglePress", @"clickedHomeButton"]) {
                SEL sel = NSSelectorFromString(name);
                if ([uic respondsToSelector:sel]) {
                    [uic performSelector:sel];
                    ANVLog(@"goHome via SBUIController %@ -> yes", name);
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {
        ANVLog(@"goHome SBUIController exception: %@", e);
    }

    ANVLog(@"goHome FAILED");
    return NO;
}

#pragma mark - 后台 / 多任务

+ (BOOL)toggleAppSwitcher {
    // iOS 16：SBMainSwitcherViewController 这个类根本不存在，走 UIController 的 home 双击
    if (!objc_getClass("SBMainSwitcherViewController")) {
        Class uicClass = objc_getClass("SBUIController");
        id uic = [uicClass respondsToSelector:@selector(sharedInstance)]
               ? [uicClass performSelector:@selector(sharedInstance)] : nil;
        for (NSString *name in @[@"handleHomeButtonDoublePressDown",
                                 @"handleHomeButtonDoublePress",
                                 @"handleHomeButtonDoublePressUp"]) {
            SEL sel = NSSelectorFromString(name);
            if (![uic respondsToSelector:sel]) continue;
            @try {
                [uic performSelector:sel];
                ANVLog(@"switcher via SBUIController %@ -> yes", name);
                return YES;
            } @catch (NSException *e) {
                ANVLog(@"switcher %@ exception: %@", name, e);
            }
        }
    }

    @try {
        Class switcherClass = objc_getClass("SBMainSwitcherViewController");
        if (!switcherClass) return NO;
        id switcher = [switcherClass performSelector:@selector(sharedInstance)];
        if (!switcher) return NO;

        // iOS 10 及更早
        SEL plainToggle = NSSelectorFromString(@"toggleSwitcherNoninteractively");
        if ([switcher respondsToSelector:plainToggle]) {
            [switcher performSelector:plainToggle];
            ANVLog(@"switcher via toggleSwitcherNoninteractively -> yes");
            return YES;
        }
        // iOS 11+
        SEL withSource = NSSelectorFromString(@"toggleSwitcherNoninteractivelyWithSource:");
        if ([switcher respondsToSelector:withSource]) {
            NSMethodSignature *sig = [switcher methodSignatureForSelector:withSource];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = switcher;
            inv.selector = withSource;
            NSUInteger source = 1;
            [inv setArgument:&source atIndex:2];
            [inv invoke];
            ANVLog(@"switcher via toggleSwitcherNoninteractivelyWithSource: -> yes");
            return YES;
        }
        // iOS 15/16 新名字
        SEL toggleMain = NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:");
        if ([switcher respondsToSelector:toggleMain]) {
            NSMethodSignature *sig = [switcher methodSignatureForSelector:toggleMain];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = switcher;
            inv.selector = toggleMain;
            NSUInteger source = 1;
            BOOL animated = YES;
            [inv setArgument:&source atIndex:2];
            [inv setArgument:&animated atIndex:3];
            [inv invoke];
            ANVLog(@"switcher via toggleMainSwitcherNoninteractivelyWithSource:animated: -> yes");
            return YES;
        }
        SEL toggleMain2 = NSSelectorFromString(@"_toggleMainSwitcherNoninteractivelyWithSource:animated:");
        if ([switcher respondsToSelector:toggleMain2]) {
            NSMethodSignature *sig = [switcher methodSignatureForSelector:toggleMain2];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = switcher;
            inv.selector = toggleMain2;
            NSUInteger source = 1;
            BOOL animated = YES;
            [inv setArgument:&source atIndex:2];
            [inv setArgument:&animated atIndex:3];
            [inv invoke];
            ANVLog(@"switcher via _toggleMainSwitcherNoninteractivelyWithSource:animated: -> yes");
            return YES;
        }
        SEL activate = NSSelectorFromString(@"activateSwitcherNoninteractively");
        if ([switcher respondsToSelector:activate]) {
            [switcher performSelector:activate];
            ANVLog(@"switcher via activateSwitcherNoninteractively -> yes");
            return YES;
        }
        SEL activateWithSource = NSSelectorFromString(@"activateSwitcherWithSource:");
        if ([switcher respondsToSelector:activateWithSource]) {
            NSMethodSignature *sig = [switcher methodSignatureForSelector:activateWithSource];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = switcher;
            inv.selector = activateWithSource;
            NSUInteger source = 1;
            [inv setArgument:&source atIndex:2];
            [inv invoke];
            ANVLog(@"switcher via activateSwitcherWithSource: -> yes");
            return YES;
        }
        SEL present = NSSelectorFromString(@"presentAppSwitcher");
        if ([switcher respondsToSelector:present]) {
            [switcher performSelector:present];
            ANVLog(@"switcher via presentAppSwitcher -> yes");
            return YES;
        }
        SEL legacyToggle = NSSelectorFromString(@"toggleSwitcher");
        if ([switcher respondsToSelector:legacyToggle]) {
            [switcher performSelector:legacyToggle];
            ANVLog(@"switcher via toggleSwitcher -> yes");
            return YES;
        }
    } @catch (NSException *e) {
        ANVLog(@"switcher exception: %@", e);
    }
    ANVLog(@"switcher FAILED (no selector matched)");

    // 最后兜底：连按两次 Home，等价于双击 Home 键调出多任务
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        SEL sel = NSSelectorFromString(@"_simulateHomeButtonPressWithCompletion:");
        if ([app respondsToSelector:sel]) {
            [app performSelector:sel withObject:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [app performSelector:sel withObject:nil];
            });
            ANVLog(@"switcher via double home press -> tried");
            return YES;
        }
    } @catch (NSException *e) {
        ANVLog(@"double home exception: %@", e);
    }
    return NO;
}

#pragma mark - 最近 App 列表

+ (NSArray<NSString *> *)recentBundleIDs {
    ANVLog(@"recents: begin");
    id recents = nil;
    Class recentsClass = objc_getClass("SBRecentAppLayouts");
    if (recentsClass && [recentsClass respondsToSelector:@selector(sharedInstance)]) {
        recents = [recentsClass performSelector:@selector(sharedInstance)];
    }
    if (!recents) { ANVLog(@"recents: sharedInstance 为 nil"); return @[]; }

    NSArray *layouts = nil;
    SEL incl = NSSelectorFromString(@"recentsIncludingHiddenAppLayouts:");
    if ([recents respondsToSelector:incl]) {
        @try {
            NSMethodSignature *sig = [recents methodSignatureForSelector:incl];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = recents;
            inv.selector = incl;
            BOOL yes = YES;
            [inv setArgument:&yes atIndex:2];
            [inv invoke];
            __unsafe_unretained id result = nil;
            [inv getReturnValue:&result];
            if ([result isKindOfClass:[NSArray class]]) layouts = result;
        } @catch (NSException *e) {
            ANVLog(@"recents invoke exception: %@", e);
        }
    }
    if (!layouts.count && [recents respondsToSelector:NSSelectorFromString(@"_recentsFromPrefs")]) {
        @try { layouts = [recents performSelector:NSSelectorFromString(@"_recentsFromPrefs")]; }
        @catch (__unused NSException *e) {}
    }

    ANVLog(@"recents: layouts=%lu", (unsigned long)layouts.count);
    NSMutableArray<NSString *> *bundleIDs = [NSMutableArray array];
    NSInteger debugIndex = 0;
    for (id layout in layouts) {
        if (debugIndex < 2) {
            ANVLog(@"recents: layout[%ld] class=%@ desc=%.160@",
                   (long)debugIndex, NSStringFromClass([layout class]), [layout description]);
            debugIndex++;
        }
        NSMutableArray *candidates = [NSMutableArray array];
        @try {
            id items = [layout valueForKey:@"allItems"];
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in items) {
                    id ident = [item valueForKey:@"displayIdentifier"];
                    if (![ident isKindOfClass:[NSString class]]) ident = [item valueForKey:@"bundleIdentifier"];
                    if ([ident isKindOfClass:[NSString class]] && [ident length]) [candidates addObject:ident];
                }
            }
        } @catch (__unused NSException *e) {}
        if (!candidates.count) {
            @try {
                NSDictionary *map = [layout valueForKey:@"rolesToLayoutItemsMap"];
                for (id item in map.allValues) {
                    id ident = [item valueForKey:@"displayIdentifier"];
                    if ([ident isKindOfClass:[NSString class]] && [ident length]) [candidates addObject:ident];
                }
            } @catch (__unused NSException *e) {}
        }
        if (!candidates.count) {
            @try {
                id ident = [layout valueForKey:@"bundleIdentifier"];
                if ([ident isKindOfClass:[NSString class]] && [(NSString *)ident length]) [candidates addObject:ident];
            } @catch (__unused NSException *e) {}
        }
        for (NSString *bundleID in candidates) {
            if ([bundleID isEqualToString:@"com.apple.springboard"]) continue;
            if ([bundleIDs containsObject:bundleID]) continue;
            [bundleIDs addObject:bundleID];
            break;
        }
    }
    ANVLog(@"recents -> %@", bundleIDs);
    return bundleIDs;
}

#pragma mark - 当前 App

+ (NSString *)frontmostBundleID {
    @try {
        Class workspaceClass = objc_getClass("LSApplicationWorkspace");
        id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)]
                     ? [(id)workspaceClass performSelector:@selector(defaultWorkspace)] : nil;
        for (NSString *name in @[@"frontmostApplication", @"frontmostDisplayIdentifier"]) {
            SEL sel = NSSelectorFromString(name);
            if (![workspace respondsToSelector:sel]) continue;
            id value = [workspace performSelector:sel];
            NSString *bundleID = [value isKindOfClass:[NSString class]] ? value : [value valueForKey:@"bundleIdentifier"];
            if ([bundleID isKindOfClass:[NSString class]] && bundleID.length) return bundleID;
        }
    } @catch (__unused NSException *e) {}

    @try {
        Class appControllerClass = objc_getClass("SBApplicationController");
        if (appControllerClass) {
            id controller = [appControllerClass performSelector:@selector(sharedInstance)];
            for (NSString *name in @[@"frontmostApplication", @"frontmostApplicationWithDisplayIdentifier"]) {
                SEL sel = NSSelectorFromString(name);
                if ([controller respondsToSelector:sel]) {
                    id app = [controller performSelector:sel];
                    NSString *bundleID = [app valueForKey:@"bundleIdentifier"];
                    if ([bundleID isKindOfClass:[NSString class]]) return bundleID;
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return [[ANVHistory shared] currentBundleID];
}

#pragma mark - 总入口

+ (BOOL)performGlyph:(ANVGlyphKind)kind {
    BOOL result = NO;
    switch (kind) {
        case ANVGlyphBack: {
            NSString *target = [[ANVHistory shared] moveBack];
            ANVLog(@"back target=%@", target);
            result = target.length ? [self openBundleID:target] : NO;
            break;
        }
        case ANVGlyphHome:
            result = [self goHome];
            break;
        case ANVGlyphRecents:
            result = [self toggleAppSwitcher];
            break;
        case ANVGlyphForward: {
            NSString *target = [[ANVHistory shared] moveForward];
            ANVLog(@"forward target=%@", target);
            result = target.length ? [self openBundleID:target] : NO;
            break;
        }
    }
    ANVLog(@"performGlyph %ld -> %d", (long)kind, result);
    return result;
}

@end
