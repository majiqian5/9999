#import "ANVRecents.h"
#import "ANVActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - 已关闭（本次 SpringBoard 生命周期内不再显示）

static NSMutableSet<NSString *> *ANVClosedSet(void) {
    static NSMutableSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}

#pragma mark - 运行中的 App

static void ANVAppendUnique(NSMutableArray<NSString *> *ids, NSString *bid) {
    if (!bid.length) return;
    if ([bid hasPrefix:@"com.apple.springboard"]) return;
    if ([bid hasPrefix:@"com.apple.WebKit"]) return;
    if ([bid hasPrefix:@"com.apple.BackBoard"]) return;
    if ([ids containsObject:bid]) return;
    [ids addObject:bid];
}

/// 有截图的 App 目录 = 系统认定“最近用过”的 App，这是最稳的兜底来源
static NSArray<NSString *> *ANVSnapshotDirBundleIDs(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *root = @"/var/mobile/Library/SplashBoard/Snapshots";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:root error:nil];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *name in names) {
        if (!name.length || [name hasPrefix:@"."]) continue;
        if ([name rangeOfString:@"."].location == NSNotFound) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
        NSDate *date = attr[NSFileModificationDate] ?: [NSDate distantPast];
        if ([date timeIntervalSinceNow] < -7 * 24 * 3600) continue;
        [entries addObject:@{@"bid": name, @"date": date}];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];
    for (NSDictionary *e in entries) [out addObject:e[@"bid"]];
    return out;
}

/// 真正在跑的 App（SBApplicationController 里 pid > 0 的）
static NSArray<NSString *> *ANVRunningBundleIDs(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    @try {
        Class ctlClass = objc_getClass("SBApplicationController");
        if (!ctlClass || ![ctlClass respondsToSelector:@selector(sharedInstance)]) return out;
        id ctl = [ctlClass performSelector:@selector(sharedInstance)];
        SEL s = NSSelectorFromString(@"allApplications");
        if (![ctl respondsToSelector:s]) return out;
        NSArray *apps = [ctl performSelector:s];
        for (id app in apps) {
            @try {
                NSString *bid = [app valueForKey:@"bundleIdentifier"];
                if (![bid isKindOfClass:[NSString class]] || !bid.length) continue;
                id pidObj = [app valueForKey:@"pid"];
                NSInteger pid = [pidObj respondsToSelector:@selector(integerValue)] ? [pidObj integerValue] : 0;
                if (pid <= 0) continue;
                ANVAppendUnique(out, bid);
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    return out;
}

static NSArray<NSString *> *ANVSwitcherBundleIDs(void) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];

    // 1) 系统最近使用（SBRecentAppLayouts）
    @try {
        for (NSString *bid in [ANVActions recentBundleIDs]) ANVAppendUnique(ids, bid);
    } @catch (__unused NSException *e) {}

    // 2) 旧的 SBAppSwitcherModel（iOS 13/14/15 有效）
    @try {
        Class modelClass = objc_getClass("SBAppSwitcherModel");
        if (modelClass) {
            id model = [modelClass performSelector:@selector(sharedInstance)];
            NSArray *layouts = nil;
            for (NSString *name in @[@"appLayouts", @"_appLayouts", @"layouts"]) {
                SEL sel = NSSelectorFromString(name);
                if ([model respondsToSelector:sel]) {
                    layouts = [model performSelector:sel];
                    if (layouts.count) break;
                }
            }
            for (id layout in layouts) {
                NSArray *items = nil;
                for (NSString *name in @[@"allItems", @"items", @"_items"]) {
                    SEL sel = NSSelectorFromString(name);
                    if ([layout respondsToSelector:sel]) {
                        items = [layout performSelector:sel];
                        if (items.count) break;
                    }
                }
                for (id item in items) {
                    NSString *bid = nil;
                    for (NSString *name in @[@"bundleIdentifier", @"_bundleIdentifier", @"displayIdentifier"]) {
                        if ([item respondsToSelector:NSSelectorFromString(name)]) {
                            bid = [item valueForKey:name];
                            break;
                        }
                    }
                    ANVAppendUnique(ids, bid);
                }
            }
        }
    } @catch (__unused NSException *e) {}

    // 3) 当前前台（保证第一张是正在用的 App）
    NSString *front = [ANVActions frontmostBundleID];
    if (front.length && ![front hasPrefix:@"com.apple.springboard"]) {
        [ids removeObject:front];
        [ids insertObject:front atIndex:0];
    }

    // 4) 自己记的开 App 历史
    @try {
        for (NSString *bid in [ANVActions historyBundleIDs]) ANVAppendUnique(ids, bid);
    } @catch (__unused NSException *e) {}

    // 5) 有截图的 App（系统后台一定会给它们截图）
    @try {
        for (NSString *bid in ANVSnapshotDirBundleIDs()) ANVAppendUnique(ids, bid);
    } @catch (__unused NSException *e) {}

    // 6) 真在跑的 App
    @try {
        for (NSString *bid in ANVRunningBundleIDs()) ANVAppendUnique(ids, bid);
    } @catch (__unused NSException *e) {}

    // 已经手动关掉的不再显示（但前台 App 重新用起来时要放出来）
    NSMutableSet *closed = ANVClosedSet();
    if (front.length) [closed removeObject:front];
    NSMutableArray *final = [NSMutableArray array];
    for (NSString *bid in ids) {
        if ([closed containsObject:bid]) continue;
        [final addObject:bid];
        if (final.count >= 9) break;
    }

    [ANVActions note:[NSString stringWithFormat:@"recents apps: %lu -> %@",
                      (unsigned long)final.count,
                      [final componentsJoinedByString:@","]]];
    return final;
}

#pragma mark - 关掉一个后台（系统后台里移除 + 结束进程）

static BOOL ANVRemoveFromSwitcherModel(NSString *bundleID) {
    @try {
        Class modelClass = objc_getClass("SBAppSwitcherModel");
        if (!modelClass) return NO;
        id model = [modelClass performSelector:@selector(sharedInstance)];
        NSArray *layouts = nil;
        for (NSString *name in @[@"appLayouts", @"_appLayouts", @"layouts"]) {
            SEL sel = NSSelectorFromString(name);
            if ([model respondsToSelector:sel]) {
                layouts = [model performSelector:sel];
                if (layouts.count) break;
            }
        }
        for (id layout in layouts) {
            NSArray *items = [layout respondsToSelector:NSSelectorFromString(@"allItems")]
                           ? [layout performSelector:NSSelectorFromString(@"allItems")] : nil;
            BOOL matched = NO;
            for (id item in items) {
                NSString *bid = [item respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]
                              ? [item valueForKey:@"bundleIdentifier"] : nil;
                if (!bid && [item respondsToSelector:NSSelectorFromString(@"displayIdentifier")]) {
                    bid = [item valueForKey:@"displayIdentifier"];
                }
                if (bid && [bid isEqualToString:bundleID]) { matched = YES; break; }
            }
            if (!matched) continue;
            for (NSString *name in @[@"removeAppLayout:", @"_removeAppLayout:",
                                     @"removeAppLayout:forReason:",
                                     @"removeDisplayItem:"]) {
                SEL sel = NSSelectorFromString(name);
                if (![model respondsToSelector:sel]) continue;
                NSMethodSignature *sig = [model methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = model;
                inv.selector = sel;
                __unsafe_unretained id argLayout = layout;
                [inv setArgument:&argLayout atIndex:2];
                if ([name hasSuffix:@"forReason:"]) {
                    NSInteger reason = 1;
                    [inv setArgument:&reason atIndex:3];
                }
                @try { [inv invoke]; } @catch (__unused NSException *e) {}
                [ANVActions note:[NSString stringWithFormat:@"close %@ via %@", bundleID, name]];
                return YES;
            }
            break;
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

/// 真正结束 App 进程（Android 那种“划掉就是关掉”）
static BOOL ANVTerminateBundleID(NSString *bundleID) {
    NSInteger pid = 0;
    @try {
        Class ctlClass = objc_getClass("SBApplicationController");
        id ctl = [ctlClass respondsToSelector:@selector(sharedInstance)]
               ? [ctlClass performSelector:@selector(sharedInstance)] : nil;
        SEL f = NSSelectorFromString(@"applicationForBundleIdentifier:");
        if ([ctl respondsToSelector:f]) {
            id app = [ctl performSelector:f withObject:bundleID];
            id pidObj = [app valueForKey:@"pid"];
            if ([pidObj respondsToSelector:@selector(integerValue)]) pid = [pidObj integerValue];
        }
    } @catch (__unused NSException *e) {}
    if (pid <= 0) return NO;

    @try {
        Class svcClass = objc_getClass("FBSSystemService");
        if (!svcClass) {
            dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
            svcClass = objc_getClass("FBSSystemService");
        }
        if (!svcClass || ![svcClass respondsToSelector:@selector(sharedService)]) return NO;
        id svc = [svcClass performSelector:@selector(sharedService)];
        for (NSString *name in @[@"terminateApplication:forBundleID:reason:",
                                 @"terminateApplicationForBundleID:reason:"]) {
            SEL sel = NSSelectorFromString(name);
            if (![svc respondsToSelector:sel]) continue;
            NSMethodSignature *sig = [svc methodSignatureForSelector:sel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = svc;
            inv.selector = sel;
            if ([name isEqualToString:@"terminateApplication:forBundleID:reason:"]) {
                int argPid = (int)pid;
                NSString *bid = bundleID;
                NSInteger reason = 3;
                [inv setArgument:&argPid atIndex:2];
                [inv setArgument:&bid atIndex:3];
                [inv setArgument:&reason atIndex:4];
            } else {
                NSString *bid = bundleID;
                NSInteger reason = 3;
                [inv setArgument:&bid atIndex:2];
                [inv setArgument:&reason atIndex:3];
            }
            @try {
                [inv invoke];
                [ANVActions note:[NSString stringWithFormat:@"kill %@ pid=%ld via %@", bundleID, (long)pid, name]];
                return YES;
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

#pragma mark - 图标 / 截图

static UIImage *ANVIconImageForBundleID(NSString *bundleID) {
    if (!bundleID.length) return nil;

    // 1) UIImage 私有接口（SpringBoard 里一直可用）
    @try {
        SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:sel]) {
            NSMethodSignature *sig = [UIImage methodSignatureForSelector:sel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = [UIImage class];
            inv.selector = sel;
            NSString *bid = bundleID;
            int format = 0;
            CGFloat scale = [UIScreen mainScreen].scale;
            [inv setArgument:&bid atIndex:2];
            [inv setArgument:&format atIndex:3];
            [inv setArgument:&scale atIndex:4];
            [inv invoke];
            __unsafe_unretained id out = nil;
            [inv getReturnValue:&out];
            if ([out isKindOfClass:[UIImage class]]) return out;
        }
    } @catch (__unused NSException *e) {}

    // 2) LSApplicationProxy 的 iconData
    @try {
        Class proxyClass = objc_getClass("LSApplicationProxy");
        SEL factory = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([proxyClass respondsToSelector:factory]) {
            id proxy = [proxyClass performSelector:factory withObject:bundleID];
            SEL dataSel = NSSelectorFromString(@"iconDataForVariant:");
            if ([proxy respondsToSelector:dataSel]) {
                NSMethodSignature *sig = [proxy methodSignatureForSelector:dataSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = proxy;
                inv.selector = dataSel;
                int variant = 2;
                [inv setArgument:&variant atIndex:2];
                [inv invoke];
                __unsafe_unretained id data = nil;
                [inv getReturnValue:&data];
                if ([data isKindOfClass:[NSData class]] && [data length]) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) return img;
                }
            }
        }
    } @catch (__unused NSException *e) {}

    return nil;
}

/// 真机截图（XBApplicationSnapshot，取不到就返回 nil，由图标顶上）
static UIImage *ANVSnapshotForBundleID(NSString *bundleID) {
    @try {
        Class mgrClass = objc_getClass("XBApplicationSnapshotManager");
        if (!mgrClass) {
            dlopen("/System/Library/PrivateFrameworks/SplashBoard.framework/SplashBoard", RTLD_LAZY);
            mgrClass = objc_getClass("XBApplicationSnapshotManager");
        }
        if (!mgrClass) return nil;
        id mgr = [mgrClass respondsToSelector:@selector(sharedInstance)]
               ? [mgrClass performSelector:@selector(sharedInstance)] : nil;
        SEL f = NSSelectorFromString(@"snapshotForBundleID:");
        if (![mgr respondsToSelector:f]) return nil;
        id snap = [mgr performSelector:f withObject:bundleID];
        if (!snap) return nil;
        for (NSString *name in @[@"imageForInterfaceOrientation:", @"_imageForInterfaceOrientation:"]) {
            SEL s = NSSelectorFromString(name);
            if (![snap respondsToSelector:s]) continue;
            NSMethodSignature *sig = [snap methodSignatureForSelector:s];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = snap;
            inv.selector = s;
            NSInteger orientation = 1; // UIInterfaceOrientationPortrait
            [inv setArgument:&orientation atIndex:2];
            [inv invoke];
            __unsafe_unretained id img = nil;
            [inv getReturnValue:&img];
            if ([img isKindOfClass:[UIImage class]]) return img;
        }
        for (NSString *name in @[@"image", @"snapshotImage"]) {
            SEL s = NSSelectorFromString(name);
            if (![snap respondsToSelector:s]) continue;
            id img = [snap performSelector:s];
            if ([img isKindOfClass:[UIImage class]]) return img;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

static NSString *ANVAppNameForBundleID(NSString *bundleID) {
    @try {
        Class proxyClass = objc_getClass("LSApplicationProxy");
        SEL factory = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([proxyClass respondsToSelector:factory]) {
            id proxy = [proxyClass performSelector:factory withObject:bundleID];
            for (NSString *name in @[@"localizedName"]) {
                if ([proxy respondsToSelector:NSSelectorFromString(name)]) {
                    NSString *v = [proxy valueForKey:name];
                    if (v.length) return v;
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return [bundleID componentsSeparatedByString:@"."].lastObject;
}

#pragma mark - 单张卡片

@interface ANVRecentsCard : UIView
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *glassView;
@end

@implementation ANVRecentsCard

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.layer.cornerRadius = 18.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = NO;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.42;
    self.layer.shadowRadius = 14.0;
    self.layer.shadowOffset = CGSizeMake(0, 8);

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.frame = self.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.layer.cornerRadius = 18.0;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [self addSubview:glass];
    self.glassView = glass;

    self.artView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.layer.cornerRadius = 14.0;
    self.artView.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:self.artView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.nameLabel.layer.shadowOpacity = 0.55;
    self.nameLabel.layer.shadowRadius = 3.0;
    self.nameLabel.layer.shadowOffset = CGSizeMake(0, 1);
    [self addSubview:self.nameLabel];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat nameH = 26.0;
    self.artView.frame = CGRectMake(10.0, 10.0, w - 20.0, h - nameH - 18.0);
    self.nameLabel.frame = CGRectMake(8.0, h - nameH - 6.0, w - 16.0, nameH);
}

@end

#pragma mark - 卡片后台本体

@interface ANVRecents () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UIView *cardsHost;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) NSMutableArray<ANVRecentsCard *> *cards;
@property (nonatomic, strong) NSMutableArray<NSString *> *bundleIDs;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) CGFloat cardW;
@property (nonatomic, assign) CGFloat cardH;
@property (nonatomic, assign) CGFloat peek;
@property (nonatomic, assign) CGFloat dragY;
@end

@implementation ANVRecents

+ (instancetype)shared {
    static ANVRecents *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[ANVRecents alloc] init]; });
    return instance;
}

- (BOOL)isShowing { return self.container != nil; }

- (void)toggleInHost:(UIView *)host {
    if (self.container) { [self dismiss]; return; }
    if (!host) return;

    CGRect bounds = host.bounds;
    CGFloat sw = bounds.size.width;
    CGFloat sh = bounds.size.height;
    self.cardW = MIN(sw * 0.62, 268.0);
    self.cardH = MIN(sh * 0.46, self.cardW * 1.72);
    self.peek = MIN(26.0, self.cardW * 0.11);

    self.bundleIDs = [ANVSwitcherBundleIDs() mutableCopy];
    if (!self.bundleIDs.count) {
        [ANVActions note:@"recents: no running apps"];
        return;
    }
    self.selectedIndex = 0;
    self.dragY = 0.0;

    UIView *container = [[UIView alloc] initWithFrame:bounds];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.container = container;

    // 背景：几乎全透明，让桌面本身透出来，只加一层很淡的压暗
    UIView *dim = [[UIView alloc] initWithFrame:bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.14];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:dim];

    UIView *cardsHost = [[UIView alloc] initWithFrame:bounds];
    cardsHost.backgroundColor = [UIColor clearColor];
    cardsHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:cardsHost];
    self.cardsHost = cardsHost;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, MAX(28.0, sh * 0.12), sw, 20)];
    hint.text = self.bundleIDs.count > 1
              ? @"左右滑动切换 · 上滑关闭 · 点卡片打开"
              : @"上滑关闭 · 点卡片打开";
    hint.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    hint.textAlignment = NSTextAlignmentCenter;
    [container addSubview:hint];
    self.hintLabel = hint;

    self.cards = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)self.bundleIDs.count; i++) {
        NSString *bid = self.bundleIDs[i];
        ANVRecentsCard *card = [[ANVRecentsCard alloc] initWithFrame:
            CGRectMake(0, 0, self.cardW, self.cardH)];
        card.bundleID = bid;

        UIImage *snap = ANVSnapshotForBundleID(bid);
        UIImage *icon = ANVIconImageForBundleID(bid);
        if (snap) {
            card.artView.image = snap;
            card.artView.contentMode = UIViewContentModeScaleAspectFill;
        } else if (icon) {
            card.artView.image = icon;
            // 只有图标时居中留白，别把图标拉满整张卡
            card.artView.contentMode = UIViewContentModeScaleAspectFit;
        } else {
            card.artView.image = nil;
            card.artView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
        }
        card.nameLabel.text = ANVAppNameForBundleID(bid);

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(cardTapped:)];
        [card addGestureRecognizer:tap];

        UIPanGestureRecognizer *cardPan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(cardPanned:)];
        cardPan.maximumNumberOfTouches = 1;
        [card addGestureRecognizer:cardPan];

        [cardsHost addSubview:card];
        [self.cards addObject:card];
    }

    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(backgroundTapped:)];
    bgTap.delegate = self;
    [container addGestureRecognizer:bgTap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [container addGestureRecognizer:pan];

    [self layoutCardsAnimated:NO];

    container.alpha = 0.0;
    [host insertSubview:container atIndex:0];
    [UIView animateWithDuration:0.24 animations:^{
        container.alpha = 1.0;
    }];
    [ANVActions note:[NSString stringWithFormat:@"recents show: %lu apps", (unsigned long)self.bundleIDs.count]];
}

- (void)dismiss {
    UIView *container = self.container;
    if (!container) return;
    self.container = nil;
    [UIView animateWithDuration:0.18 animations:^{
        container.alpha = 0.0;
        for (UIView *v in self.cardsHost.subviews) v.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        [container removeFromSuperview];
    }];
    self.cards = nil;
    self.cardsHost = nil;
    self.hintLabel = nil;
}

#pragma mark - 层叠布局

- (void)layoutCardsAnimated:(BOOL)animated {
    CGSize host = self.cardsHost.bounds.size;
    // 当前这张永远居中，后面的卡片往右后方错开叠上去
    CGPoint base = CGPointMake(host.width / 2.0, host.height * 0.46);
    NSInteger selected = self.selectedIndex;

    void (^block)(void) = ^{
        for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) {
            ANVRecentsCard *card = self.cards[i];
            CGFloat d = (CGFloat)(i - selected);
            CGFloat absD = fabs(d);
            CGFloat shown = MIN(absD, 4.0);
            CGFloat scale = MAX(0.74, 1.0 - shown * 0.055);
            card.center = CGPointMake(base.x + d * self.peek, base.y + shown * 9.0);
            card.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                     CGAffineTransformMakeRotation(d * 0.012));
            card.alpha = (absD > 3.0) ? 0.0 : MAX(0.55, 0.95 - absD * 0.12);
            card.userInteractionEnabled = (absD <= 3.0);
        }
    };

    // 按“离当前卡片越远越先加”，最后把当前卡放到最上层：
    // 点击/拖动命中的就是看得见的那张，不会再出现“滑了没反应”
    NSMutableArray<ANVRecentsCard *> *ordered = [NSMutableArray array];
    NSArray<ANVRecentsCard *> *sorted = [self.cards sortedArrayUsingComparator:
        ^NSComparisonResult(ANVRecentsCard *a, ANVRecentsCard *b) {
            NSInteger ia = (NSInteger)[self.cards indexOfObject:a];
            NSInteger ib = (NSInteger)[self.cards indexOfObject:b];
            NSInteger da = ABS(ia - selected);
            NSInteger db = ABS(ib - selected);
            if (da == db) return NSOrderedSame;
            return (da > db) ? NSOrderedAscending : NSOrderedDescending;
        }];
    for (ANVRecentsCard *card in sorted) [ordered addObject:card];

    if (animated) {
        [UIView animateWithDuration:0.24 delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:block completion:nil];
    } else {
        block();
    }
    for (ANVRecentsCard *card in ordered) [self.cardsHost bringSubviewToFront:card];
}

#pragma mark - 手势

- (NSInteger)indexOfCard:(UIView *)view {
    for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) {
        if (self.cards[i] == view) return i;
    }
    return NSNotFound;
}

- (void)cardTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;
    NSInteger index = [self indexOfCard:tap.view];
    if (index == NSNotFound) return;

    if (index != self.selectedIndex) {
        self.selectedIndex = index;
        [self layoutCardsAnimated:YES];
        return;
    }
    NSString *bid = (index < (NSInteger)self.bundleIDs.count) ? self.bundleIDs[index] : nil;
    [self dismiss];
    if (!bid.length) return;
    [ANVClosedSet() removeObject:bid];
    [ANVActions openBundleID:bid];
}

/// 卡片上的拖动：横着划 = 切换；向上划 = 关掉这张
- (void)cardPanned:(UIPanGestureRecognizer *)pan {
    ANVRecentsCard *card = (ANVRecentsCard *)pan.view;
    if (![card isKindOfClass:[ANVRecentsCard class]]) return;
    NSInteger index = [self indexOfCard:card];
    if (index == NSNotFound) return;

    CGPoint t = [pan translationInView:self.container];
    CGPoint v = [pan velocityInView:self.container];

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.dragY = 0.0;
        if (index != self.selectedIndex) {
            self.selectedIndex = index;
            [self layoutCardsAnimated:YES];
        }
        return;
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        if (fabs(t.x) > fabs(t.y) + 12.0) {
            // 横向：一次翻一张，翻完清零，避免一下翻好几张
            CGFloat step = MAX(44.0, self.peek * 1.6);
            NSInteger count = (NSInteger)self.bundleIDs.count;
            if (t.x < -step && self.selectedIndex + 1 < count) {
                self.selectedIndex = MIN(count - 1, self.selectedIndex + 1);
                [pan setTranslation:CGPointZero inView:self.container];
                [self layoutCardsAnimated:YES];
            } else if (t.x > step && self.selectedIndex - 1 >= 0) {
                self.selectedIndex = MAX(0, self.selectedIndex - 1);
                [pan setTranslation:CGPointZero inView:self.container];
                [self layoutCardsAnimated:YES];
            }
            return;
        }

        // 纵向：卡片跟手往上走，松手过阈值就关
        CGFloat dy = t.y;
        if (dy > 0.0) dy = 0.0;         // 只允许往上
        self.dragY += dy;
        card.center = CGPointMake(card.center.x, card.center.y + dy);
        [pan setTranslation:CGPointZero inView:self.container];
        CGFloat progress = MAX(0.0, MIN(1.0, -self.dragY / 180.0));
        card.alpha = 1.0 - progress * 0.65;
        return;
    }

    if (pan.state != UIGestureRecognizerStateEnded &&
        pan.state != UIGestureRecognizerStateCancelled) return;

    if (self.dragY < -70.0 || (v.y < -500.0 && self.dragY < -24.0)) {
        [self closeCardAt:index];
    } else {
        [self layoutCardsAnimated:YES];
    }
}

- (void)closeCardAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.cards.count) return;
    ANVRecentsCard *card = self.cards[index];
    NSString *bid = (index < (NSInteger)self.bundleIDs.count) ? self.bundleIDs[index] : nil;

    if (bid.length) {
        [ANVClosedSet() addObject:bid];
        BOOL removed = ANVRemoveFromSwitcherModel(bid);
        BOOL killed = ANVTerminateBundleID(bid);
        [ANVActions note:[NSString stringWithFormat:@"recents close %@ switcher=%d kill=%d",
                          bid, removed, killed]];
    }

    [UIView animateWithDuration:0.22 animations:^{
        card.center = CGPointMake(card.center.x, card.center.y - 280.0);
        card.alpha = 0.0;
    } completion:^(BOOL finished) {
        [card removeFromSuperview];
        [self.cards removeObject:card];
        if (bid.length) [self.bundleIDs removeObject:bid];
        if (!self.cards.count) { [self dismiss]; return; }
        self.selectedIndex = MAX(0, MIN((NSInteger)self.cards.count - 1, index));
        NSString *front = [ANVActions frontmostBundleID];
        if (front.length) {
            for (NSInteger i = 0; i < (NSInteger)self.bundleIDs.count; i++) {
                if ([self.bundleIDs[i] isEqualToString:front]) { self.selectedIndex = i; break; }
            }
        }
        [self layoutCardsAnimated:YES];
    }];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateRecognized) return;
    [self dismiss];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    for (ANVRecentsCard *card in self.cards) {
        if (touch.view == card || [touch.view isDescendantOfView:card]) {
            return (g.view == card);   // 卡上的手势只给卡片自己的 pan，容器的手势不抢
        }
    }
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.container];
    NSInteger count = (NSInteger)self.bundleIDs.count;

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.selectedIndex = MAX(0, MIN(count - 1, self.selectedIndex));
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (fabs(t.x) < fabs(t.y)) return;
        CGFloat step = MAX(60.0, self.peek * 2.0);
        if (fabs(t.x) > step) {
            NSInteger shift = (t.x < 0) ? 1 : -1;
            NSInteger target = MAX(0, MIN(count - 1, self.selectedIndex + shift));
            if (target != self.selectedIndex) {
                self.selectedIndex = target;
                [pan setTranslation:CGPointZero inView:self.container];
                [self layoutCardsAnimated:YES];
            }
        }
    } else if (pan.state == UIGestureRecognizerStateEnded ||
               pan.state == UIGestureRecognizerStateCancelled) {
        if (t.y > 90.0 && fabs(t.y) > fabs(t.x)) [self dismiss];
    }
}

@end
