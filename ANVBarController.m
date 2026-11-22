#import "ANVBarController.h"
#import "ANVGlyphView.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "ANVActions.h"
#import "ANVHistory.h"
#import "ANVSettings.h"
#import "ANVSpectrumView.h"
#import "ANVWidgets.h"
#import "ANVMusicMonitor.h"

static UIColor *ANVColorForGlyph(ANVGlyphKind kind) {
    switch (kind) {
        case ANVGlyphBack:    return [UIColor colorWithHue:0.57 saturation:1.0 brightness:1.0 alpha:1.0]; // 电光蓝
        case ANVGlyphHome:    return [UIColor colorWithHue:0.36 saturation:1.0 brightness:1.0 alpha:1.0]; // 荧光绿
        case ANVGlyphRecents: return [UIColor colorWithHue:0.92 saturation:1.0 brightness:1.0 alpha:1.0]; // 品红粉
        case ANVGlyphForward: return [UIColor colorWithHue:0.13 saturation:1.0 brightness:1.0 alpha:1.0]; // 亮黄
    }
    return [UIColor whiteColor];
}

@interface ANVBarController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *barView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) NSMutableArray<ANVGlyphView *> *glyphViews;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) ANVSpectrumView *spectrumView;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) NSTimer *frontTimer;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) CGPoint dragStartCenter;
@property (nonatomic, strong) NSTimer *lockTimer;
@property (nonatomic, assign) BOOL hiddenByLock;
@property (nonatomic, strong) UIView *pullTab;
@property (nonatomic, strong) UIView *pullTabPill;
@property (nonatomic, strong) ANVPetView *petView;
@property (nonatomic, assign) CGFloat lastLevel;
@property (nonatomic, strong) ANVLyricsView *lyricsView;
@property (nonatomic, copy) NSString *nowPlayingTitle;
@property (nonatomic, assign) BOOL dockedHidden;
@property (nonatomic, assign) CGFloat pullOver;   // 顶到下限后还继续往下拉了多少（用来触发收起）
@end

// 空白处不接手势，让底下的图标照常能点
@interface ANVPassthroughView : UIView
@end

@implementation ANVPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

@implementation ANVBarController

+ (instancetype)sharedInstance {
    static ANVBarController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ANVBarController alloc] init];
    });
    return instance;
}

#pragma mark - 启动

- (void)start {
    if (self.started) return;
    if (![ANVSettings shared].enabled) { [ANVActions note:@"start skipped: disabled"]; return; }
    self.started = YES;
    [ANVActions note:[NSString stringWithFormat:@"start begin enabled=1 spectrum=%d", [ANVSettings shared].spectrumEnabled]];

    [ANVHistory installHooks];
    [ANVActions logEnvironment];

    @try {
        [self buildWindow];
        [self buildBar];
        [self updateFrame];
        [ANVActions note:[NSString stringWithFormat:@"bar built frame=%@", NSStringFromCGRect(self.barView.frame)]];
    } @catch (NSException *e) {
        [ANVActions note:[NSString stringWithFormat:@"build failed: %@", e.reason]];
        NSLog(@"[AndroNavBar] build failed: %@", e);
        self.started = NO;
        return;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];

    [ANVMusicMonitor shared].micEnabled = [ANVSettings shared].micSpectrum;
    [ANVMusicMonitor shared].simulateEnabled = [ANVSettings shared].simulateSpectrum;

    if ([ANVSettings shared].spectrumEnabled) {
        [[ANVMusicMonitor shared] start];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.displayLink.preferredFramesPerSecond = 30;
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }

    [self buildPullTab];
    self.window.hidden = NO;
    [ANVActions note:@"window shown"];

    // 锁屏时自动隐藏，解锁恢复
    [self.lockTimer invalidate];
    self.lockTimer = [NSTimer timerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
        [self updateLockVisibility];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.lockTimer forMode:NSRunLoopCommonModes];

    // 轮询前台 App，自己维护历史栈，不依赖 hook 是否装得上
    [self.frontTimer invalidate];
    self.frontTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                       target:self
                                                     selector:@selector(pollFrontmost)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (BOOL)isDeviceLocked {
    @try {
        Class lockClass = objc_getClass("SBLockScreenManager");
        if (lockClass && [lockClass respondsToSelector:@selector(sharedInstance)]) {
            id manager = ((id (*)(id, SEL))objc_msgSend)(lockClass, @selector(sharedInstance));
            for (NSString *name in @[@"isLockScreenVisible", @"isLockScreenShowing", @"isUILocked"]) {
                SEL sel = NSSelectorFromString(name);
                if ([manager respondsToSelector:sel]) {
                    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, sel);
                }
            }
        }
        Class workspaceClass = objc_getClass("SBWorkspace");
        if (workspaceClass && [workspaceClass respondsToSelector:@selector(sharedInstance)]) {
            id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, @selector(sharedInstance));
            for (NSString *name in @[@"isLocked", @"isUILocked"]) {
                SEL sel = NSSelectorFromString(name);
                if ([workspace respondsToSelector:sel]) {
                    return ((BOOL (*)(id, SEL))objc_msgSend)(workspace, sel);
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

// 底部安全区高度：iPhone 上有 Home 指示条，插件不能把图标塞进去
- (CGFloat)dockBottomInset {
    return 0.0;   // 只保留「贴屏边」：图标贴着屏幕边缘
    CGFloat inset = 0;
    if (@available(iOS 11.0, *)) {
        inset = self.window.safeAreaInsets.bottom;
    }
    if (inset <= 0) inset = 34.0;       // 兜底：全面屏机型
    return MAX(26.0, inset + 2.0);
}

- (void)updateLockVisibility {
    // 设置里允许「锁屏也显示」时，锁屏就不隐藏
    BOOL locked = [self isDeviceLocked] && ![ANVSettings shared].showOnLockScreen;
    if (locked == self.barView.hidden) return;   // 状态没变
    self.barView.hidden = locked;
    self.pullTab.hidden = (locked || !self.dockedHidden);
    self.hiddenByLock = locked;
    if (locked) [self hidePanel];
    [ANVActions note:[NSString stringWithFormat:@"lock hide -> %d", locked]];
}

- (void)buildPullTab {
    CGFloat w = 64.0, h = 5.0, hitW = 150.0, hitH = 34.0;
    CGRect screen = [UIScreen mainScreen].bounds;

    // 5pt 高的细条太难点中（尤其在底部 Home 指示条上），
    // 所以外面套一个 150×34 的透明热区，里面才是那根细条。
    UIView *tab = [[UIView alloc] initWithFrame:CGRectMake((screen.size.width - hitW) / 2.0,
                                                          screen.size.height - hitH - 1.0,
                                                          hitW, hitH)];
    tab.backgroundColor = [UIColor clearColor];
    tab.hidden = YES;
    tab.userInteractionEnabled = YES;

    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake((hitW - w) / 2.0,
                                                          hitH - h - 2.0, w, h)];
    pill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.34];
    pill.layer.cornerRadius = h / 2.0;
    pill.userInteractionEnabled = NO;
    [tab addSubview:pill];
    self.pullTabPill = pill;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(restoreFromDock)];
    [tab addGestureRecognizer:tap];

    // 点不中也还能往上划：上滑超过 16pt 就恢复
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(handlePullPan:)];
    [tab addGestureRecognizer:pan];

    [self.window.rootViewController.view addSubview:tab];
    self.pullTab = tab;
}

- (void)handlePullPan:(UIPanGestureRecognizer *)pan {
    if (!self.dockedHidden) return;
    CGPoint t = [pan translationInView:self.window];
    if (pan.state == UIGestureRecognizerStateChanged && t.y < -16.0) {
        [self restoreFromDock];
    } else if (pan.state == UIGestureRecognizerStateChanged && t.y > 6.0) {
        // 往下拖一点，让细条跟着走，反馈更明显（松手回弹）
        self.pullTabPill.transform = CGAffineTransformMakeTranslation(0, 0);
    }
}

- (void)dockHide {
    if (self.dockedHidden) return;
    self.dockedHidden = YES;
    [self hidePanel];
    CGRect screen = [UIScreen mainScreen].bounds;
    [UIView animateWithDuration:0.22 animations:^{
        self.barView.center = CGPointMake(self.barView.center.x,
                                          screen.size.height + self.barView.bounds.size.height);
        self.barView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.barView.hidden = YES;
        self.pullTab.hidden = NO;
    }];
    [ANVActions note:@"dock hidden"];
}

- (void)restoreFromDock {
    if (!self.dockedHidden) return;
    self.dockedHidden = NO;
    self.pullTab.hidden = YES;
    self.barView.hidden = NO;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat halfH = self.barView.bounds.size.height / 2.0;
    CGFloat inset = [self dockBottomInset];
    [UIView animateWithDuration:0.2 animations:^{
        self.barView.center = CGPointMake(self.barView.center.x,
                                          screenH - halfH - inset);
        self.barView.alpha = [ANVSettings shared].opacity;
    } completion:^(BOOL finished) {
        [[ANVSettings shared] saveCenter:CGPointMake(0.5,
            (screenH - halfH - inset) / MAX(1.0, screenH))];
        [self updateFrame];
    }];
    [ANVActions note:@"dock restored"];
}

- (void)pollFrontmost {
    @try {
        NSString *bundleID = [ANVActions frontmostBundleID];
        if (bundleID.length) [[ANVHistory shared] record:bundleID];
    } @catch (__unused NSException *e) {}
}

- (NSString *)actionTitleForSlot:(NSInteger)slot {
    switch ([[ANVSettings shared] actionForSlot:slot]) {
        case ANVKeyActionHome: return @"主屏幕";
        case ANVKeyActionRecents: return @"后台";
        case ANVKeyActionForward: return @"前进";
        case ANVKeyActionNone: return @"无动作";
        default: return @"返回";
    }
}

- (NSString *)spectrumStyleTitle {
    static NSArray *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"霓虹柱状", @"点阵", @"上下镜像", @"折线波形", @"跑马灯", @"流水灯",
                  @"呼吸波", @"彩虹粒子冲撞", @"双向对冲", @"螺旋点阵", @"涟漪圆环",
                  @"瀑布下落", @"旋转光环", @"随机闪烁", @"弹跳小球", @"交织斜线",
                  @"心电图", @"七色雨丝"];
    });
    NSInteger i = [ANVSettings shared].spectrumStyle;
    i = MIN(MAX(i, 0), (NSInteger)names.count - 1);
    return names[(NSUInteger)i];
}

- (void)directionTapped:(UIButton *)sender {
    // 直接按点移动，横排竖排都生效（之前按屏高百分比算，位置锁定时会被夹回去看着像没反应）
    CGFloat step = 14.0;
    CGFloat dx = 0, dy = 0;
    switch (sender.tag) {
        case 100: dy = -step; break;
        case 101: dy = step; break;
        case 102: dx = -step; break;
        default: dx = step; break;
    }

    CGRect screen = [UIScreen mainScreen].bounds;
    CGSize bar = self.barView.bounds.size;
    CGPoint center = self.barView.center;
    center.x += dx;
    center.y += dy;

    // 竖排时允许贴到左右边缘；横排时允许贴到底边
    CGFloat halfW = bar.width / 2.0;
    CGFloat halfH = bar.height / 2.0;
    center.x = MIN(MAX(center.x, halfW), screen.size.width - halfW);
    center.y = MIN(MAX(center.y, halfH), screen.size.height - halfH);
    self.barView.center = center;

    CGFloat nx = center.x / MAX(1.0, screen.size.width);
    CGFloat ny = center.y / MAX(1.0, screen.size.height);
    [[ANVSettings shared] saveCenter:CGPointMake(nx, ny)];

    [self layoutWidgets];

    if ([ANVSettings shared].haptics) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }
}

- (void)showPanel {
    if (self.panelView) { [self hidePanel]; return; }

    CGFloat width = 240.0;
    CGFloat rowH = 38.0;
    ANVSettings *st = [ANVSettings shared];
    NSArray *titles = @[
        [NSString stringWithFormat:@"键 1 · %@", [self actionTitleForSlot:0]],
        [NSString stringWithFormat:@"键 2 · %@", [self actionTitleForSlot:1]],
        [NSString stringWithFormat:@"键 3 · %@", [self actionTitleForSlot:2]],
        [NSString stringWithFormat:@"键 4 · %@", [self actionTitleForSlot:3]],
        [NSString stringWithFormat:@"大小 %ld%% · 调大", (long)lround(st.scale * 100)],
        [NSString stringWithFormat:@"大小 %ld%% · 调小", (long)lround(st.scale * 100)],
        [NSString stringWithFormat:@"频谱 · %@", st.spectrumEnabled ? @"开" : @"关"],
        [NSString stringWithFormat:@"样式 · %@", [self spectrumStyleTitle]],
        [NSString stringWithFormat:@"灵敏度 %ld%% · 加", (long)lround(st.spectrumSensitivity * 100)],
        [NSString stringWithFormat:@"灵敏度 %ld%% · 减", (long)lround(st.spectrumSensitivity * 100)],
        [NSString stringWithFormat:@"频谱宽 %ld%% · 加", (long)lround(st.spectrumWidth * 100)],
        [NSString stringWithFormat:@"频谱宽 %ld%% · 减", (long)lround(st.spectrumWidth * 100)],
        [NSString stringWithFormat:@"频谱高 %ld%% · 加", (long)lround(st.spectrumHeight * 100)],
        [NSString stringWithFormat:@"频谱高 %ld%% · 减", (long)lround(st.spectrumHeight * 100)],
        [NSString stringWithFormat:@"柱数 %ld · 加", (long)st.spectrumBars],
        [NSString stringWithFormat:@"柱数 %ld · 减", (long)st.spectrumBars],
        [NSString stringWithFormat:@"柱粗 %ld%% · 加", (long)lround(st.spectrumThickness * 100)],
        [NSString stringWithFormat:@"柱粗 %ld%% · 减", (long)lround(st.spectrumThickness * 100)],
        [NSString stringWithFormat:@"方向 · %@", [self orientationTitle]],
        [NSString stringWithFormat:@"宠物 · %@", st.petEnabled ? @"开" : @"关"],
        [NSString stringWithFormat:@"宠物 %ld%% · 加", (long)lround(st.petScale * 100)],
        [NSString stringWithFormat:@"宠物 %ld%% · 减", (long)lround(st.petScale * 100)],
        [NSString stringWithFormat:@"宠物造型 · %@", [self petStyleTitle]],
        [NSString stringWithFormat:@"动作 · %@", [self petActionTitle]],
        [NSString stringWithFormat:@"锁屏显示 · %@", ([ANVSettings shared].showOnLockScreen ? @"开" : @"关")],
        [NSString stringWithFormat:@"举牌歌词 · %@", st.lyricEnabled ? @"开" : @"关"],
        [NSString stringWithFormat:@"歌词 %ld%% · 加", (long)lround(st.lyricScale * 100)],
        [NSString stringWithFormat:@"歌词 %ld%% · 减", (long)lround(st.lyricScale * 100)],
        [NSString stringWithFormat:@"麦克风频谱 · %@", st.micSpectrum ? @"开" : @"关"],
        [NSString stringWithFormat:@"模拟频谱 · %@", st.simulateSpectrum ? @"开" : @"关"],
        [NSString stringWithFormat:@"位置 · %@", st.positionLocked ? @"已锁定" : @"可拖动"],
        @"位置复位",
        @"关闭",
    ];

    NSArray *tags = @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9,
                      @200, @201, @202, @203, @204, @205, @206, @207,
                      @210, @211, @212, @213, @217, @218, @219, @214, @215, @216,
                      @10, @11, @13, @14, @15];

    if (titles.count > 18) rowH = 30.0;

    CGFloat dirRowH = 46.0;
    CGFloat contentH = rowH * (CGFloat)titles.count + 8.0;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    CGFloat maxScrollH = MAX(180.0, screenH * 0.66 - dirRowH);
    CGFloat scrollH = MIN(contentH, maxScrollH);
    CGFloat panelH = scrollH + dirRowH + 10.0;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;

    // 行太多会超出屏幕，套一层滚动视图，能上下滑
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, width, scrollH)];
    scroll.contentSize = CGSizeMake(width, MAX(contentH, scrollH));
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = YES;
    scroll.backgroundColor = [UIColor clearColor];
    scroll.clipsToBounds = YES;
    [panel addSubview:scroll];

    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, 4 + rowH * i, width, rowH);
        row.tag = i < tags.count ? [tags[i] integerValue] : (NSInteger)i;
        row.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [row setTitle:titles[i] forState:UIControlStateNormal];
        [row setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [row addTarget:self action:@selector(panelRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:row];

        if (i + 1 < titles.count) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, 4 + rowH * (i + 1), width - 24, 0.5)];
            line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
            line.userInteractionEnabled = NO;
            [scroll addSubview:line];
        }
    }

    // 上下左右微调行（每个方向按一次移动 1% 屏幕）
    UIView *dirRow = [[UIView alloc] initWithFrame:CGRectMake(0, scrollH + 4, width, dirRowH)];
    NSArray *dirTitles = @[@"↑", @"↓", @"←", @"→"];
    NSArray *dirTags = @[@100, @101, @102, @103];
    CGFloat dirW = 40.0;
    CGFloat dirGap = 8.0;
    CGFloat dirTotal = dirW * 4 + dirGap * 3;
    CGFloat dirX = (width - dirTotal) / 2.0;
    for (NSUInteger i = 0; i < 4; i++) {
        UIButton *dir = [UIButton buttonWithType:UIButtonTypeCustom];
        dir.frame = CGRectMake(dirX + i * (dirW + dirGap), 4, dirW, 36);
        dir.tag = [dirTitles[i] isEqualToString:@"↑"] ? 100 : (NSInteger)[dirTags[i] integerValue];
        dir.layer.cornerRadius = 8.0;
        dir.layer.borderWidth = 1.0;
        dir.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        dir.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        dir.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [dir setTitle:dirTitles[i] forState:UIControlStateNormal];
        [dir setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [dir addTarget:self action:@selector(directionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [dirRow addSubview:dir];
    }
    [panel addSubview:dirRow];

    self.panelView = panel;
    // 面板放到全屏容器上，否则超出 bar 边界就收不到点击
    [self.window.rootViewController.view addSubview:panel];
    CGRect barFrame = self.barView.frame;
    CGFloat top = CGRectGetMinY(barFrame) - CGRectGetHeight(panel.bounds) - 8.0;
    if (top < 60.0) top = 60.0;                       // 不许顶出状态栏
    if (top + CGRectGetHeight(panel.bounds) > screenH - 8.0) {
        top = screenH - 8.0 - CGRectGetHeight(panel.bounds);
    }
    panel.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - width) / 2.0,
                             top, width, CGRectGetHeight(panel.bounds));
}

- (void)hidePanel {
    [self.panelView removeFromSuperview];
    self.panelView = nil;
}

- (NSString *)petActionTitle {
    NSInteger a = [ANVSettings shared].petAction;
    if (a <= 0) return @"随机";
    return [ANVPetView titleForAction:a - 1];
}

- (void)applyPetAction {
    NSInteger a = [ANVSettings shared].petAction;
    if (!self.petView) return;
    if (a <= 0) {
        [self pickRandomPetAction];
    } else {
        self.petView.action = a - 1;
    }
}

// 随机动作：有音乐时更爱跳舞/蹦跳，深夜更爱睡觉
- (void)pickRandomPetAction {
    if (!self.petView) return;
    NSUInteger r = arc4random_uniform(17);
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal component:NSCalendarUnitHour fromDate:[NSDate date]];
    if ((hour >= 23 || hour < 7) && arc4random_uniform(100) < 40) r = 9;      // 睡觉
    if (_lastLevel > 0.55 && arc4random_uniform(100) < 45) r = (arc4random_uniform(2) ? 2 : 10);  // 跳舞/蹦跳
    self.petView.action = (NSInteger)r;
    self.petView.partnerStyle = (NSInteger)arc4random_uniform(3);
}

- (NSString *)petStyleTitle {
    switch ([ANVSettings shared].petStyle) {
        case 1: return @"小猫";
        case 2: return @"小兔";
        case 3: return @"小熊";
        default: return @"随机";
    }
}

- (NSString *)orientationTitle {
    switch ([ANVSettings shared].barOrientation) {
        case 1: return @"左侧竖排";
        case 2: return @"右侧竖排";
        default: return @"底部横排";
    }
}

- (void)applyWidgetSettings {
    [self layoutWidgets];
}

- (void)applySpectrumSettings {
    ANVSettings *st = [ANVSettings shared];
    self.spectrumView.barCount = st.spectrumBars;
    self.spectrumView.widthRatio = st.spectrumWidth;
    self.spectrumView.heightRatio = st.spectrumHeight;
    self.spectrumView.thickness = st.spectrumThickness;
}

- (void)refreshPanel {
    [self hidePanel];
    [self showPanel];
}

- (void)rebuildBar {
    [self hidePanel];
    [self.barView removeFromSuperview];
    self.barView = nil;
    self.spectrumView = nil;
    self.blurView = nil;
    [self.glyphViews removeAllObjects];
    [self.buttons removeAllObjects];
    [self buildBar];
    [self updateFrame];
}

- (void)panelRowTapped:(UIButton *)row {
    ANVSettings *settings = [ANVSettings shared];
    NSInteger index = row.tag;

    if (index <= 3) {
        NSInteger next = ([[ANVSettings shared] actionForSlot:index] + 1) % 5;
        [settings saveAction:(ANVKeyAction)next forSlot:index];
        [self hidePanel];
        [self showPanel];
        return;
    }

    switch (index) {
        case 4: [settings saveScalePercent:lround(settings.scale * 100) + 10]; [self rebuildBar]; break;
        case 5: [settings saveScalePercent:lround(settings.scale * 100) - 10]; [self rebuildBar]; break;
        case 7: {
            [settings saveSpectrumStyle:(settings.spectrumStyle + 1) % 18];
            self.spectrumView.style = (ANVSpectrumStyle)settings.spectrumStyle;
        self.spectrumView.barCount = settings.spectrumBars;
        self.spectrumView.widthRatio = settings.spectrumWidth;
        self.spectrumView.heightRatio = settings.spectrumHeight;
        self.spectrumView.thickness = settings.spectrumThickness;
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 8: {
            [settings saveSpectrumSensitivity:settings.spectrumSensitivity + 0.1];
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 9: {
            [settings saveSpectrumSensitivity:settings.spectrumSensitivity - 0.1];
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 218: [settings savePetAction:(settings.petAction + 1) % 18]; [self applyPetAction]; [self hidePanel]; [self showPanel]; break;
        case 219: [settings saveShowOnLockScreen:!settings.showOnLockScreen]; [self updateLockVisibility]; [self hidePanel]; [self showPanel]; break;
        case 217: [settings savePetStyle:(settings.petStyle + 1) % 4]; [self rebuildBar]; [self hidePanel]; [self showPanel]; break;
        case 210: [settings saveBarOrientation:(settings.barOrientation + 1) % 3]; [self rebuildBar]; [self hidePanel]; [self showPanel]; break;
        case 211: [settings savePetEnabled:!settings.petEnabled]; [self rebuildBar]; [self hidePanel]; [self showPanel]; break;
        case 212: [settings savePetScale:settings.petScale + 0.1]; [self applyWidgetSettings]; [self hidePanel]; [self showPanel]; break;
        case 213: [settings savePetScale:settings.petScale - 0.1]; [self applyWidgetSettings]; [self hidePanel]; [self showPanel]; break;
        case 214: [settings saveLyricEnabled:!settings.lyricEnabled]; [self rebuildBar]; [self hidePanel]; [self showPanel]; break;
        case 215: [settings saveLyricScale:settings.lyricScale + 0.1]; [self applyWidgetSettings]; [self hidePanel]; [self showPanel]; break;
        case 216: [settings saveLyricScale:settings.lyricScale - 0.1]; [self applyWidgetSettings]; [self hidePanel]; [self showPanel]; break;
        case 200: [settings saveSpectrumWidth:settings.spectrumWidth + 0.1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 201: [settings saveSpectrumWidth:settings.spectrumWidth - 0.1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 202: [settings saveSpectrumHeight:settings.spectrumHeight + 0.1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 203: [settings saveSpectrumHeight:settings.spectrumHeight - 0.1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 204: [settings saveSpectrumBars:settings.spectrumBars + 1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 205: [settings saveSpectrumBars:settings.spectrumBars - 1]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 206: [settings saveSpectrumThickness:settings.spectrumThickness + 0.06]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 207: [settings saveSpectrumThickness:settings.spectrumThickness - 0.06]; [self applySpectrumSettings]; [self refreshPanel]; break;
        case 10: {
            [settings saveMicSpectrum:!settings.micSpectrum];
            [ANVMusicMonitor shared].micEnabled = settings.micSpectrum;
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 11: {
            [settings saveSimulateSpectrum:!settings.simulateSpectrum];
            [ANVMusicMonitor shared].simulateEnabled = settings.simulateSpectrum;
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 12: {
            [settings saveEdgeToEdge:!settings.edgeToEdge];
            [self updateFrame];
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 13: {
            [settings savePositionLocked:!settings.positionLocked];
            [self hidePanel];
            [self showPanel];
            break;
        }
        case 6: {
            BOOL on = !settings.spectrumEnabled;
            [settings saveSpectrumEnabled:on];
            if (on) {
                [[ANVMusicMonitor shared] start];
                if (!self.displayLink) {
                    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
                    self.displayLink.preferredFramesPerSecond = 30;
                    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
                }
            } else {
                [[ANVMusicMonitor shared] stop];
                [self.displayLink invalidate];
                self.displayLink = nil;
            }
            [self rebuildBar];
            break;
        }
        case 14:
            [settings saveCenter:CGPointMake(0.5, 0.86)];
            [self updateFrame];
            break;
        default:
            [self hidePanel];
            break;
    }

    if (settings.haptics) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self.lockTimer invalidate];
    self.lockTimer = nil;
    [self.pullTab removeFromSuperview];
    self.pullTab = nil;
    self.window.hidden = YES;
    self.window = nil;
    self.barView = nil;
    self.started = NO;
}

#pragma mark - 窗口

- (void)buildWindow {
    CGRect screen = [UIScreen mainScreen].bounds;
    self.window = [[UIWindow alloc] initWithFrame:screen];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.opaque = NO;

    ANVPassthroughView *root = [[ANVPassthroughView alloc] initWithFrame:screen];
    root.backgroundColor = [UIColor clearColor];
    root.userInteractionEnabled = YES;

    UIViewController *controller = [[UIViewController alloc] init];
    controller.view = root;
    self.window.rootViewController = controller;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                self.window.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
}

- (void)buildBar {
    ANVSettings *settings = [ANVSettings shared];
    CGFloat scale = settings.scale;

    CGFloat glyph = 44.0 * scale;
    CGFloat spacing = 10.0 * scale;
    CGFloat padLong = 14.0 * scale;    // 排布方向两端留白
    CGFloat padShort = 1.5 * scale;    // 垂直方向留白（贴屏边，几乎不留缝）
    CGFloat barLength = glyph * 4 + spacing * 3 + padLong * 2;
    CGFloat barThick = glyph + padShort * 2;
    BOOL vertical = (settings.barOrientation != 0);
    CGFloat barW = vertical ? barThick : barLength;
    CGFloat barH = vertical ? barLength : barThick;

    self.barView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, barW, barH)];
    self.barView.backgroundColor = [UIColor clearColor];
    self.barView.layer.cornerRadius = MIN(barW, barH) / 2.0;

    // 玻璃胶囊：外发光 + 顶部高光，尽量贴近参考图的质感
    self.barView.layer.shadowColor = [UIColor colorWithHue:0.75 saturation:1.0 brightness:1.0 alpha:1.0].CGColor;
    self.barView.layer.shadowOpacity = 0.45;
    self.barView.layer.shadowRadius = 14.0;
    self.barView.layer.shadowOffset = CGSizeZero;
    self.barView.layer.masksToBounds = NO;

    if (!settings.transparentBackground) {
        self.barView.layer.masksToBounds = YES;
        self.barView.layer.borderWidth = 1.0;
        self.barView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;

        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        self.blurView.frame = self.barView.bounds;
        self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.barView addSubview:self.blurView];

        UIView *tint = [[UIView alloc] initWithFrame:self.barView.bounds];
        tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tint.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.35];
        tint.userInteractionEnabled = NO;
        [self.barView addSubview:tint];
    }

    // 玻璃高光（上下两层渐变，模拟被光打亮的胶囊）
    CAGradientLayer *gloss = [CAGradientLayer layer];
    gloss.frame = self.barView.bounds;
    gloss.cornerRadius = self.barView.layer.cornerRadius;
    gloss.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.34].CGColor,
                     (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                     (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor];
    gloss.locations = @[@0.0, @0.45, @1.0];
    gloss.startPoint = CGPointMake(0.5, 0.0);
    gloss.endPoint = CGPointMake(0.5, 0.65);
    [self.barView.layer addSublayer:gloss];

    // 真频谱放最底层，图标在上层
    if (settings.spectrumEnabled) {
        // 铺满整条：频谱占满导航条的宽和高，柱子按条长均分
        CGRect bounds = self.barView.bounds;
        CGRect spectrumFrame = bounds;
        if (vertical) {
            // 竖排时频谱整体旋转 90°，柱子从侧边往里长
            spectrumFrame = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
        }
        self.spectrumView = [[ANVSpectrumView alloc] initWithFrame:spectrumFrame];
        if (vertical) {
            self.spectrumView.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
            self.spectrumView.transform = CGAffineTransformMakeRotation(
                settings.barOrientation == 1 ? M_PI_2 : -M_PI_2);
        }
        self.spectrumView.style = (ANVSpectrumStyle)settings.spectrumStyle;
        self.spectrumView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.barView addSubview:self.spectrumView];
    }

    self.glyphViews = [NSMutableArray array];
    self.buttons = [NSMutableArray array];

    for (NSInteger kind = ANVGlyphBack; kind <= ANVGlyphForward; kind++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        if (vertical) {
            button.frame = CGRectMake(padShort,
                                      padLong + kind * (glyph + spacing),
                                      glyph, glyph);
        } else {
            button.frame = CGRectMake(padLong + kind * (glyph + spacing),
                                      padShort,
                                      glyph, glyph);
        }
        button.tag = kind;
        button.backgroundColor = [UIColor clearColor];

        ANVGlyphView *glyphView = [[ANVGlyphView alloc] initWithFrame:button.bounds];
        glyphView.kind = (ANVGlyphKind)kind;
        glyphView.glyphColor = ANVColorForGlyph((ANVGlyphKind)kind);
        glyphView.lineWidth = 3.2 * (scale < 1.0 ? 1.0 : scale);

        UIImage *customImage = [self customImageForSlot:kind];
        if (customImage) [glyphView setGlyphImage:customImage];
        [ANVActions note:[NSString stringWithFormat:
            @"glyph %ld frame=%@ img=%@ color=%@",
            (long)kind, NSStringFromCGRect(button.frame),
            customImage ? NSStringFromCGSize(customImage.size) : @"vector",
            glyphView.glyphColor]];
        [button addSubview:glyphView];

        [button addTarget:self action:@selector(glyphTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(glyphDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(glyphUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

        [self.barView addSubview:button];
        [self.glyphViews addObject:glyphView];
        [self.buttons addObject:button];
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO;
    pan.delegate = self;
    pan.minimumNumberOfTouches = 1;   // 单指可拖，跟上一版一致
    [self.barView addGestureRecognizer:pan];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.65;
    press.cancelsTouchesInView = NO;
    press.delegate = self;
    [self.barView addGestureRecognizer:press];

    UILongPressGestureRecognizer *resetPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleResetPress:)];
    resetPress.minimumPressDuration = 2.6;
    resetPress.cancelsTouchesInView = NO;
    resetPress.delegate = self;
    [self.barView addGestureRecognizer:resetPress];

    [self.window.rootViewController.view addSubview:self.barView];
    [self updateFrame];
    [self buildWidgets];
}

#pragma mark - 自定义图标

- (UIImage *)customImageForSlot:(NSInteger)slot {
    // 想换图标就把 PNG 放进这两个目录，命名 slot0.png ~ slot3.png
    NSArray<NSString *> *directories = @[
        @"/var/jb/Library/Application Support/AndroNavBar/icons",
        @"/var/mobile/Library/Application Support/AndroNavBar/icons",
    ];
    for (NSString *directory in directories) {
        for (NSString *ext in @[@"png", @"jpg", @"jpeg"]) {
            NSString *path = [directory stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"slot%ld.%@", (long)slot, ext]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                UIImage *image = [UIImage imageWithContentsOfFile:path];
                [ANVActions note:[NSString stringWithFormat:@"icon file %@ size=%@",
                                  path, NSStringFromCGSize(image.size)]];
                if (image && image.size.width >= 4) return image;
            }
        }
    }
    return nil;
}

#pragma mark - 频谱刷新

- (void)tick:(CADisplayLink *)link {
    if (!self.spectrumView) return;

    float levels[10] = {0};
    [[ANVMusicMonitor shared] fillLevels:levels count:10];

    CGFloat sensitivity = [ANVSettings shared].spectrumSensitivity;
    for (NSUInteger i = 0; i < 10; i++) {
        levels[i] = MIN(1.0f, levels[i] * sensitivity);
    }
    static CFTimeInterval lastStamp = 0;
    CFTimeInterval now = CACurrentMediaTime();
    CGFloat delta = lastStamp > 0 ? (CGFloat)(now - lastStamp) : 1.0 / 30.0;
    lastStamp = now;
    static CFTimeInterval lastDeadLog = 0;
    if (![ANVMusicMonitor shared].axsAvailable) {
        CFTimeInterval nowT = CACurrentMediaTime();
        if (nowT - lastDeadLog > 6.0) {
            lastDeadLog = nowT;
            [ANVActions note:@"spectrum: AxsEQ 无数据，只有自带动画在动"];
        }
    }
    [self.spectrumView advancePhase:delta];

    if (self.petView) {
        _lastLevel = levels[0];
        self.petView.energy = levels[0];
        [self.petView advancePhase:delta];
        // 随机模式：每 6~13 秒换一个动作；跳舞时还会被强拍带着多跳两下
        static CFTimeInterval lastAction = 0;
        static CFTimeInterval actionSpan = 8.0;
        static CGFloat lastBeat = 0.0;
        CFTimeInterval nowA = CACurrentMediaTime();
        if (lastAction == 0) { lastAction = nowA; actionSpan = 8.0; }
        if ([ANVSettings shared].petAction == 0 && nowA - lastAction > actionSpan) {
            lastAction = nowA;
            actionSpan = 6.0 + (CFTimeInterval)arc4random_uniform(8);
            [self pickRandomPetAction];
        }
        if (self.petView.action == 2) {
            // 强拍（电平突然抬头）时重新起跳，看起来是真的跟节奏
            if (levels[0] > 0.75 && lastBeat < 0.45) {
                self.petView.action = 2;
            }
            lastBeat = levels[0];
        }
        static CFTimeInterval lastPetLyric = 0;
        CFTimeInterval nowP = CACurrentMediaTime();
        if (nowP - lastPetLyric > 4.0) {
            lastPetLyric = nowP;
            self.petView.lyricText = [ANVSettings shared].lyricEnabled ? [self currentLyricLine] : nil;
        }
    }
    if (self.lyricsView) {
        [self.lyricsView advancePhase:delta];
        static CFTimeInterval lastLyric = 0;
        CFTimeInterval nowL = CACurrentMediaTime();
        if (nowL - lastLyric > 4.0) {
            lastLyric = nowL;
            self.lyricsView.text = [self currentLyricLine];
        }
    }
    [self.spectrumView updateLevels:levels count:10];
}

#pragma mark - 布局


#pragma mark - 宠物 / 举牌歌词

- (void)buildWidgets {
    ANVSettings *st = [ANVSettings shared];

    [self.petView removeFromSuperview];
    self.petView = nil;
    [self.lyricsView removeFromSuperview];
    self.lyricsView = nil;

    if (st.petEnabled) {
        self.petView = [[ANVPetView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        self.petView.sizeScale = st.petScale;
        NSInteger style = st.petStyle;
        if (style == 0) style = 1 + (NSInteger)(arc4random_uniform(3));   // 每次重建随机挑一只
        self.petView.style = style - 1;
        self.petView.partnerStyle = (NSInteger)arc4random_uniform(3);
        NSInteger pa = st.petAction;
        self.petView.action = (pa <= 0) ? (NSInteger)arc4random_uniform(17) : (pa - 1);
        [self.window.rootViewController.view addSubview:self.petView];
    }
    if (st.lyricEnabled && !st.petEnabled) {
        self.lyricsView = [[ANVLyricsView alloc] initWithFrame:CGRectMake(0, 0, 240, 28)];
        self.lyricsView.textScale = st.lyricScale;
        self.lyricsView.text = [self currentLyricLine];
        [self.window.rootViewController.view addSubview:self.lyricsView];
    }
    [self layoutWidgets];
}

- (NSString *)currentLyricLine {
    // 有歌词文件就按行轮播；没有就显示正在播放的歌名
    NSString *path = @"/var/mobile/Library/AndroNavBar/lyrics.txt";
    NSString *txt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (txt.length) {
        NSArray *lines = [txt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSMutableArray *valid = [NSMutableArray array];
        for (NSString *l in lines) if (l.length) [valid addObject:l];
        if (valid.count) {
            // 随机举牌：每次随机挑一句，不再固定顺序
            NSUInteger idx = arc4random_uniform((uint32_t)valid.count);
            return valid[idx];
        }
    }
    if (self.nowPlayingTitle.length) return self.nowPlayingTitle;
    return @"AndroNavBar";
}

- (void)layoutWidgets {
    ANVSettings *st = [ANVSettings shared];
    BOOL vertical = (st.barOrientation != 0);
    CGRect bar = self.barView.frame;
    CGFloat thickness = vertical ? bar.size.width : bar.size.height;

    CGFloat petSide = thickness * 1.15 * st.petScale;
    CGFloat lyricH = MAX(20.0, 24.0 * st.lyricScale);
    CGFloat lyricW = MAX(96.0, 132.0 * st.lyricScale);
    NSString *line = st.lyricEnabled ? [self currentLyricLine] : nil;
    BOOL onLeftHalf = (CGRectGetMidX(bar) < [UIScreen mainScreen].bounds.size.width / 2.0);

    if (self.petView) {
        CGFloat signW = line.length ? lyricW : 0.0;
        CGFloat petW = petSide + signW;
        CGFloat petH = petSide;
        self.petView.sizeScale = st.petScale;
        self.petView.textScale = st.lyricScale;
        self.petView.lyricText = line;

        CGPoint center;
        if (vertical) {
            center = CGPointMake(onLeftHalf ? CGRectGetMaxX(bar) + petW / 2.0 + 4.0
                                            : CGRectGetMinX(bar) - petW / 2.0 - 4.0,
                                 CGRectGetMidY(bar));
        } else {
            center = CGPointMake(CGRectGetMinX(bar) + petW / 2.0,
                                 CGRectGetMinY(bar) - petH / 2.0 + 4.0);
        }
        self.petView.bounds = CGRectMake(0, 0, petW, petH);
        self.petView.center = center;
    }

    if (self.lyricsView) {
        self.lyricsView.textScale = st.lyricScale;
        self.lyricsView.bounds = CGRectMake(0, 0, lyricW, lyricH);
        if (vertical) {
            self.lyricsView.center = CGPointMake(onLeftHalf ? CGRectGetMaxX(bar) + lyricW / 2.0 + 6.0
                                                            : CGRectGetMinX(bar) - lyricW / 2.0 - 6.0,
                                                 CGRectGetMidY(bar));
        } else {
            self.lyricsView.center = CGPointMake(CGRectGetMidX(bar),
                                                 CGRectGetMinY(bar) - lyricH / 2.0 - 8.0);
        }
    }
}

- (void)updateFrame {
    if (!self.window || !self.barView) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    if (!CGRectEqualToRect(self.window.frame, screen)) self.window.frame = screen;

    CGSize barSize = self.barView.bounds.size;
    ANVSettings *settings = [ANVSettings shared];

    CGFloat halfW = barSize.width / 2.0;
    CGFloat halfH = barSize.height / 2.0;
    // 底边留出 Home 指示条的高度，图标别压在系统手势区（否则又挡 Home 条又点不灵）
    CGFloat bottomInset = [self dockBottomInset];
    CGFloat maxX = MAX(halfW, screen.size.width - halfW);
    CGFloat maxY = MAX(halfH, screen.size.height - halfH - bottomInset);

    CGPoint center = CGPointMake(screen.size.width * settings.centerX,
                                 screen.size.height * settings.centerY);
    center.x = MIN(MAX(center.x, halfW), maxX);
    center.y = MIN(MAX(center.y, halfH), maxY);

    self.barView.center = center;
}

- (void)orientationChanged:(NSNotification *)note {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self updateFrame];
    });
}

#pragma mark - 手势

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    // 双指拖动，避免在列表里滑动时误把导航条拖走
    if ([ANVSettings shared].positionLocked) return;

    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            self.dragging = YES;
            self.pullOver = 0.0;
            self.dragStartCenter = self.barView.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [pan translationInView:nil];
            CGPoint center = CGPointMake(self.dragStartCenter.x + translation.x,
                                         self.dragStartCenter.y + translation.y);

            // 拖动过程中就夹住，不许越过 Home 指示条那条线（松手也不会再掉下去）
            CGRect screen = [UIScreen mainScreen].bounds;
            CGSize bar = self.barView.bounds.size;
            CGFloat halfH3 = bar.height / 2.0;
            CGFloat limitY = screen.size.height - halfH3 - [self dockBottomInset];
            center.y = MIN(center.y, limitY);
            center.y = MAX(center.y, halfH3);
            center.x = MIN(MAX(center.x, bar.width / 2.0),
                           screen.size.width - bar.width / 2.0);

            // 已经顶到下限还继续往下拽多少，记录下来给松手判断用
            CGFloat wanted = self.dragStartCenter.y + translation.y;
            self.pullOver = MAX(0.0, wanted - limitY);

            self.barView.center = center;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            self.dragging = NO;
            CGRect screen = [UIScreen mainScreen].bounds;
            CGPoint center = self.barView.center;

            // 只有拖到屏幕外一大截才收起；落在底边附近则直接吸附贴边
            CGFloat halfH2 = self.barView.bounds.size.height / 2.0;
            CGFloat bottomY = screen.size.height - halfH2 - [self dockBottomInset];
            // 顶到下限后还往下拽 60pt 以上，才当成「拖出去收起」
            if (self.pullOver > 60.0) {
                [self dockHide];
                break;
            }
            if (center.y > bottomY - 34.0) {
                self.barView.center = CGPointMake(center.x, bottomY);   // 无空隙贴边
                [[ANVSettings shared] saveCenter:CGPointMake(center.x / screen.size.width,
                                                             bottomY / screen.size.height)];
                [self updateFrame];
                break;
            }
            if (screen.size.width > 0 && screen.size.height > 0) {
                center.x = MIN(MAX(center.x, self.barView.bounds.size.width / 2.0),
                           screen.size.width - self.barView.bounds.size.width / 2.0);
            center.y = MIN(MAX(center.y, self.barView.bounds.size.height / 2.0),
                           screen.size.height - self.barView.bounds.size.height / 2.0 - [self dockBottomInset]);
            CGPoint normalized = CGPointMake(center.x / screen.size.width,
                                                 center.y / screen.size.height);
                [[ANVSettings shared] saveCenter:normalized];
                [self updateFrame];
            }
            break;
        }
        default:
            break;
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    if (self.dragging) return;

    // 长按 0.65 秒：打开面板（设置页没入口时的替代入口）
    [self showPanel];
}

- (void)handleResetPress:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;

    // 长按 2.6 秒：位置重置回底部居中
    [[ANVSettings shared] saveCenter:CGPointMake(0.5, 0.86)];
    [UIView animateWithDuration:0.2 animations:^{
        self.barView.alpha = [ANVSettings shared].opacity;
    }];
    self.barView.userInteractionEnabled = YES;
    [self updateFrame];

    if ([ANVSettings shared].haptics) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
}

#pragma mark - 按键

- (void)glyphDown:(UIButton *)sender {
    ANVGlyphView *glyph = self.glyphViews[sender.tag];
    [glyph setGlowHighlighted:YES];
    [UIView animateWithDuration:0.08 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.88, 0.88);
    }];
}

- (void)glyphUp:(UIButton *)sender {
    ANVGlyphView *glyph = self.glyphViews[sender.tag];
    [glyph setGlowHighlighted:NO];
    [UIView animateWithDuration:0.12 animations:^{
        sender.transform = CGAffineTransformIdentity;
    }];
}

- (void)glyphTapped:(UIButton *)sender {
    // 每个位子执行什么动作由设置决定
    ANVKeyAction action = [[ANVSettings shared] actionForSlot:sender.tag];
    if (action == ANVKeyActionNone) {
        ANVGlyphView *glyph = self.glyphViews[sender.tag];
        [glyph setGlowHighlighted:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [glyph setGlowHighlighted:NO];
        });
        return;
    }

    ANVGlyphKind kind = ANVGlyphBack;
    switch (action) {
        case ANVKeyActionHome: kind = ANVGlyphHome; break;
        case ANVKeyActionRecents: kind = ANVGlyphRecents; break;
        case ANVKeyActionForward: kind = ANVGlyphForward; break;
        default: kind = ANVGlyphBack; break;
    }

    if ([ANVSettings shared].haptics) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    }

    BOOL ok = [ANVActions performGlyph:kind];
    if (!ok && [ANVSettings shared].haptics) {
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeWarning];
    }
}

@end
