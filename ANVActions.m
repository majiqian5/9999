#import "ANVActions.h"
#import "ANVHistory.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation ANVActions

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
        return ok;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

#pragma mark - 主屏幕

+ (BOOL)goHome {
    // 方案 A：让多任务控制器直接回到主屏布局（iOS 14–16 常用做法）
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
                return YES;
            }
        }
    } @catch (__unused NSException *e) {}

    // 方案 B：模拟 Home 键单击
    @try {
        Class uicClass = objc_getClass("SBUIController");
        if (uicClass) {
            id uic = [uicClass performSelector:@selector(sharedInstance)];
            for (NSString *name in @[@"handleHomeButtonSinglePress",
                                     @"_handleHomeButtonSinglePress",
                                     @"clickedHomeButton"]) {
                SEL sel = NSSelectorFromString(name);
                if ([uic respondsToSelector:sel]) {
                    [uic performSelector:sel];
                    return YES;
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 后台 / 多任务

+ (BOOL)toggleAppSwitcher {
    @try {
        Class switcherClass = objc_getClass("SBMainSwitcherViewController");
        if (!switcherClass) return NO;
        id switcher = [switcherClass performSelector:@selector(sharedInstance)];
        if (!switcher) return NO;

        // iOS 11+：带 source 参数的版本
        SEL withSource = NSSelectorFromString(@"toggleSwitcherNoninteractivelyWithSource:");
        if ([switcher respondsToSelector:withSource]) {
            [switcher performSelector:withSource withObject:nil];
            return YES;
        }
        // iOS 10 及更早
        SEL plainToggle = NSSelectorFromString(@"toggleSwitcherNoninteractively");
        if ([switcher respondsToSelector:plainToggle]) {
            [switcher performSelector:plainToggle];
            return YES;
        }
        // 兜底：直接激活动画
        SEL activate = NSSelectorFromString(@"activateSwitcherNoninteractively");
        if ([switcher respondsToSelector:activate]) {
            [switcher performSelector:activate];
            return YES;
        }
        SEL legacyToggle = NSSelectorFromString(@"toggleSwitcher");
        if ([switcher respondsToSelector:legacyToggle]) {
            [switcher performSelector:legacyToggle];
            return YES;
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 当前 App

+ (NSString *)frontmostBundleID {
    @try {
        Class appControllerClass = objc_getClass("SBApplicationController");
        if (appControllerClass) {
            id controller = [appControllerClass performSelector:@selector(sharedInstance)];
            for (NSString *name in @[@"frontmostApplication",
                                     @"frontmostApplicationWithDisplayIdentifier"]) {
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
    switch (kind) {
        case ANVGlyphBack: {
            NSString *target = [[ANVHistory shared] moveBack];
            if (target.length) return [self openBundleID:target];
            // 没有历史时，退回“打开多任务”
            return [self toggleAppSwitcher];
        }
        case ANVGlyphHome:
            return [self goHome];
        case ANVGlyphRecents:
            return [self toggleAppSwitcher];
        case ANVGlyphForward: {
            NSString *target = [[ANVHistory shared] moveForward];
            if (target.length) return [self openBundleID:target];
            return NO;
        }
    }
    return NO;
}

@end
