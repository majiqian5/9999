#import "ANVBarController.h"
#import "ANVGlyphView.h"
#import "ANVActions.h"
#import "ANVHistory.h"
#import "ANVSettings.h"
#import "ANVSpectrumView.h"
#import "ANVMusicMonitor.h"

static UIColor *ANVColorForGlyph(ANVGlyphKind kind) {
    switch (kind) {
        case ANVGlyphBack:    return [UIColor colorWithRed:0.31 green:0.76 blue:1.00 alpha:1.0]; // 蓝
        case ANVGlyphHome:    return [UIColor colorWithRed:0.39 green:0.90 blue:0.45 alpha:1.0]; // 绿
        case ANVGlyphRecents: return [UIColor colorWithRed:1.00 green:0.24 blue:0.50 alpha:1.0]; // 粉
        case ANVGlyphForward: return [UIColor colorWithRed:1.00 green:0.78 blue:0.26 alpha:1.0]; // 黄
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

    if ([ANVSettings shared].spectrumEnabled) {
        [[ANVMusicMonitor shared] start];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.displayLink.preferredFramesPerSecond = 30;
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }

    self.window.hidden = NO;
    [ANVActions note:@"window shown"];

    // 轮询前台 App，自己维护历史栈，不依赖 hook 是否装得上
    [self.frontTimer invalidate];
    self.frontTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                       target:self
                                                     selector:@selector(pollFrontmost)
                                                     userInfo:nil
                                                      repeats:YES];
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

- (void)showPanel {
    if (self.panelView) { [self hidePanel]; return; }

    CGFloat width = 240.0;
    CGFloat rowH = 38.0;
    NSArray *titles = @[
        [NSString stringWithFormat:@"键 1 · %@", [self actionTitleForSlot:0]],
        [NSString stringWithFormat:@"键 2 · %@", [self actionTitleForSlot:1]],
        [NSString stringWithFormat:@"键 3 · %@", [self actionTitleForSlot:2]],
        [NSString stringWithFormat:@"键 4 · %@", [self actionTitleForSlot:3]],
        [NSString stringWithFormat:@"大小 %ld%% · 调大", (long)lround([ANVSettings shared].scale * 100)],
        [NSString stringWithFormat:@"大小 %ld%% · 调小", (long)lround([ANVSettings shared].scale * 100)],
        [NSString stringWithFormat:@"频谱 · %@", [ANVSettings shared].spectrumEnabled ? @"开" : @"关"],
        @"位置复位",
        @"关闭",
    ];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, rowH * titles.count + 8)];
    panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;

    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, 4 + rowH * i, width, rowH);
        row.tag = i;
        row.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [row setTitle:titles[i] forState:UIControlStateNormal];
        [row setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [row addTarget:self action:@selector(panelRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:row];

        if (i + 1 < titles.count) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, 4 + rowH * (i + 1), width - 24, 0.5)];
            line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
            line.userInteractionEnabled = NO;
            [panel addSubview:line];
        }
    }

    self.panelView = panel;
    [self.barView addSubview:panel];
    panel.center = CGPointMake(CGRectGetMidX(self.barView.bounds),
                               CGRectGetMinY(self.barView.bounds) - CGRectGetHeight(panel.bounds) / 2.0 - 8);
}

- (void)hidePanel {
    [self.panelView removeFromSuperview];
    self.panelView = nil;
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
        case 7:
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
    self.window.hidden = YES;
    self.window = nil;
    self.barView = nil;
    self.started = NO;
}

#pragma mark - 窗口

- (void)buildWindow {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 240, 64)];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.opaque = NO;

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor clearColor];
    root.view.userInteractionEnabled = YES;
    self.window.rootViewController = root;

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
    CGFloat padH = 14.0 * scale;
    CGFloat padV = 10.0 * scale;
    CGFloat barHeight = glyph + padV * 2;

    self.barView = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
                                                            glyph * 4 + spacing * 3 + padH * 2,
                                                            barHeight)];
    self.barView.backgroundColor = [UIColor clearColor];
    self.barView.layer.cornerRadius = barHeight / 2.0;
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

    // 真频谱放最底层，图标在上层
    if (settings.spectrumEnabled) {
        CGRect spectrumFrame = CGRectInset(self.barView.bounds, padH + 6, padV + 6);
        self.spectrumView = [[ANVSpectrumView alloc] initWithFrame:spectrumFrame];
        self.spectrumView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.barView addSubview:self.spectrumView];
    }

    self.glyphViews = [NSMutableArray array];
    self.buttons = [NSMutableArray array];

    CGFloat originX = padH;
    for (NSInteger kind = ANVGlyphBack; kind <= ANVGlyphForward; kind++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(originX, padV, glyph, glyph);
        button.tag = kind;
        button.backgroundColor = [UIColor clearColor];

        ANVGlyphView *glyphView = [[ANVGlyphView alloc] initWithFrame:button.bounds];
        glyphView.kind = (ANVGlyphKind)kind;
        glyphView.glyphColor = ANVColorForGlyph((ANVGlyphKind)kind);
        glyphView.lineWidth = 3.2 * (scale < 1.0 ? 1.0 : scale);

        UIImage *customImage = [self customImageForSlot:kind];
        if (customImage) [glyphView setGlyphImage:customImage];
        [button addSubview:glyphView];

        [button addTarget:self action:@selector(glyphTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(glyphDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(glyphUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

        [self.barView addSubview:button];
        [self.glyphViews addObject:glyphView];
        [self.buttons addObject:button];

        originX += glyph + spacing;
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
                if (image) return image;
            }
        }
    }
    return nil;
}

#pragma mark - 频谱刷新

- (void)tick:(CADisplayLink *)link {
    if (!self.spectrumView) return;

    float levels[12] = {0};
    [[ANVMusicMonitor shared] fillLevels:levels count:12];

    CGFloat sensitivity = [ANVSettings shared].spectrumSensitivity;
    for (NSUInteger i = 0; i < 12; i++) {
        levels[i] = MIN(1.0f, levels[i] * sensitivity);
    }
    [self.spectrumView updateLevels:levels count:12];
}

#pragma mark - 布局

- (void)updateFrame {
    if (!self.window || !self.barView) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    CGSize barSize = self.barView.bounds.size;
    ANVSettings *settings = [ANVSettings shared];

    CGFloat halfW = barSize.width / 2.0;
    CGFloat halfH = barSize.height / 2.0;
    CGFloat maxX = MAX(halfW + 4, screen.size.width - halfW - 4);
    CGFloat maxY = MAX(halfH + 30, screen.size.height - halfH - 10);

    CGPoint center = CGPointMake(screen.size.width * settings.centerX,
                                 screen.size.height * settings.centerY);
    center.x = MIN(MAX(center.x, halfW + 4), maxX);
    center.y = MIN(MAX(center.y, halfH + 24), maxY);

    self.window.frame = CGRectMake(center.x - halfW, center.y - halfH,
                                   barSize.width, barSize.height);
    self.barView.frame = self.window.bounds;
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
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            self.dragging = YES;
            self.dragStartCenter = self.window.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [pan translationInView:nil];
            CGPoint center = CGPointMake(self.dragStartCenter.x + translation.x,
                                         self.dragStartCenter.y + translation.y);
            self.window.center = center;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            self.dragging = NO;
            CGRect screen = [UIScreen mainScreen].bounds;
            CGPoint center = self.window.center;
            if (screen.size.width > 0 && screen.size.height > 0) {
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
