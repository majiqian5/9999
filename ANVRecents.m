#import "ANVRecents.h"
#import "ANVActions.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#pragma mark - 运行中的 App

/// 从 SpringBoard 的 SBAppSwitcherModel 里取最近用过的 App（最新的在前）
static NSArray<NSString *> *ANVSwitcherBundleIDs(void) {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];

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
                    for (NSString *name in @[@"bundleIdentifier", @"_bundleIdentifier"]) {
                        if ([item respondsToSelector:NSSelectorFromString(name)]) {
                            bid = [item valueForKey:name];
                            break;
                        }
                    }
                    if (!bid.length) continue;
                    if ([bid hasPrefix:@"com.apple.springboard"]) continue;
                    if (![ids containsObject:bid]) [ids addObject:bid];
                }
            }
        }
    } @catch (NSException *e) {
        [ANVActions note:[NSString stringWithFormat:@"recents switcher model exception: %@", e.reason]];
    }

    NSString *front = [ANVActions frontmostBundleID];
    if (front.length && ![front hasPrefix:@"com.apple.springboard"] && ![ids containsObject:front]) {
        [ids insertObject:front atIndex:0];
    }

    if (!ids.count) {
        NSArray<NSString *> *history = [ANVActions recentBundleIDs];
        for (NSString *bid in history) {
            if (!bid.length || [ids containsObject:bid]) continue;
            [ids addObject:bid];
            if (ids.count >= 8) break;
        }
    }
    return ids;
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
            for (NSString *name in @[@"localizedName", @"bundleVersion"]) {
                if ([proxy respondsToSelector:NSSelectorFromString(name)]) {
                    NSString *v = [proxy valueForKey:name];
                    if (v.length && ![name isEqualToString:@"bundleVersion"]) return v;
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return [bundleID componentsSeparatedByString:@"."].lastObject;
}

#pragma mark - 单张卡片

@interface ANVRecentsCard : UIView
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIView *glassView;
@end

@implementation ANVRecentsCard

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.layer.cornerRadius = 20.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = NO;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.45;
    self.layer.shadowRadius = 16.0;
    self.layer.shadowOffset = CGSizeMake(0, 10);

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.frame = self.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.layer.cornerRadius = 20.0;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [self addSubview:glass];
    self.glassView = glass;

    self.artView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.layer.cornerRadius = 16.0;
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
@property (nonatomic, assign) CGFloat panStartOffset;
@property (nonatomic, assign) CGFloat cardW;
@property (nonatomic, assign) CGFloat cardH;
@property (nonatomic, assign) CGFloat spacing;
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
    if (self.showing) { [self dismiss]; return; }
    if (!host) return;

    CGRect bounds = host.bounds;
    CGFloat sw = bounds.size.width;
    CGFloat sh = bounds.size.height;
    self.cardW = sw * 0.50;
    self.cardH = MIN(sh * 0.42, self.cardW * 1.62);
    self.spacing = MIN(76.0, self.cardW * 0.30);

    self.bundleIDs = [ANVSwitcherBundleIDs() mutableCopy];
    if (!self.bundleIDs.count) {
        [ANVActions note:@"recents: no running apps"];
        return;
    }
    self.selectedIndex = 0;

    UIView *container = [[UIView alloc] initWithFrame:bounds];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.container = container;

    // 背景：几乎全透明，让桌面本身透出来（跟视频一致），只加一层很淡的压暗
    UIView *dim = [[UIView alloc] initWithFrame:bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:dim];

    UIView *cardsHost = [[UIView alloc] initWithFrame:bounds];
    cardsHost.backgroundColor = [UIColor clearColor];
    cardsHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:cardsHost];
    self.cardsHost = cardsHost;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(0, sh * 0.10, sw, 20)];
    hint.text = @"左右滑动切换 · 点卡片打开";
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
        card.tag = i;

        UIImage *snap = ANVSnapshotForBundleID(bid);
        UIImage *icon = ANVIconImageForBundleID(bid);
        if (snap) {
            card.artView.image = snap;
            card.artView.contentMode = UIViewContentModeScaleAspectFill;
        } else if (icon) {
            card.artView.image = icon;
            card.artView.contentMode = UIViewContentModeScaleAspectFit;
        } else {
            card.artView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
            card.artView.contentMode = UIViewContentModeCenter;
        }
        card.nameLabel.text = ANVAppNameForBundleID(bid);

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(cardTapped:)];
        [card addGestureRecognizer:tap];

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
    [UIView animateWithDuration:0.26 animations:^{
        container.alpha = 1.0;
    }];
    [ANVActions note:[NSString stringWithFormat:@"recents show: %lu apps", (unsigned long)self.bundleIDs.count]];
}

- (void)dismiss {
    UIView *container = self.container;
    if (!container) return;
    self.container = nil;
    [UIView animateWithDuration:0.20 animations:^{
        container.alpha = 0.0;
        for (UIView *v in self.cardsHost.subviews) v.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        [container removeFromSuperview];
    }];
    self.cards = nil;
    self.cardsHost = nil;
    self.hintLabel = nil;
}

- (void)layoutCardsAnimated:(BOOL)animated {
    CGPoint center = CGPointMake(self.cardsHost.bounds.size.width / 2.0,
                                 self.cardsHost.bounds.size.height * 0.44);
    void (^block)(void) = ^{
        for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) {
            ANVRecentsCard *card = self.cards[i];
            CGFloat d = (CGFloat)(i - self.selectedIndex);
            CGFloat absD = fabs(d);
            CGFloat scale = 1.0 - MIN(absD, 4.0) * 0.045;
            CGFloat angle = d * 0.045;
            card.center = CGPointMake(center.x + d * self.spacing, center.y + absD * 16.0);
            card.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                     CGAffineTransformMakeRotation(angle));
            card.alpha = (absD > 3.5) ? 0.0 : MAX(0.35, 1.0 - absD * 0.08);
            card.layer.zPosition = 200.0 - absD * 20.0;
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.24 delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:block completion:nil];
    } else {
        block();
    }
}

#pragma mark - 手势

- (void)cardTapped:(UITapGestureRecognizer *)tap {
    NSInteger index = tap.view.tag;
    if (index != self.selectedIndex) {
        self.selectedIndex = index;
        [self layoutCardsAnimated:YES];
        return;
    }
    NSString *bid = (index < (NSInteger)self.bundleIDs.count) ? self.bundleIDs[index] : nil;
    [self dismiss];
    if (bid.length) [ANVActions openBundleID:bid];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateRecognized) return;
    [self dismiss];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g
shouldReceiveTouch:(UITouch *)touch {
    if ([g isKindOfClass:[UITapGestureRecognizer class]] &&
        [touch.view isKindOfClass:[ANVRecentsCard class]]) {
        return NO;
    }
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.container];
    NSInteger count = (NSInteger)self.bundleIDs.count;

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.panStartOffset = 0.0;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat step = self.spacing * 1.4;
        NSInteger shift = (NSInteger)floor((t.x + (t.x < 0 ? -step / 2.0 : step / 2.0)) / step);
        NSInteger target = MAX(0, MIN(count - 1, self.selectedIndex + shift));
        if (target != self.selectedIndex) {
            self.selectedIndex = target;
            self.panStartOffset = t.x;
            [self layoutCardsAnimated:YES];
        }
    } else if (pan.state == UIGestureRecognizerStateEnded ||
               pan.state == UIGestureRecognizerStateCancelled) {
        if (t.y > 90.0) [self dismiss];
    }
}

@end
