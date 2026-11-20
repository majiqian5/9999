#import "ANVBarController.h"
#import "ANVGlyphView.h"
#import "ANVActions.h"
#import "ANVHistory.h"
#import "ANVSettings.h"

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
    if (![ANVSettings shared].enabled) return;
    self.started = YES;

    [ANVHistory installHooks];

    @try {
        [self buildWindow];
        [self buildBar];
        [self updateFrame];
    } @catch (NSException *e) {
        NSLog(@"[AndroNavBar] build failed: %@", e);
        self.started = NO;
        return;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];

    self.window.hidden = NO;
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    [self.barView addGestureRecognizer:pan];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    press.minimumPressDuration = 0.65;
    press.cancelsTouchesInView = NO;
    press.delegate = self;
    [self.barView addGestureRecognizer:press];

    [self.window.rootViewController.view addSubview:self.barView];
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

    // 长按整条：临时淡出 5 秒，方便全屏看视频/玩游戏
    [UIView animateWithDuration:0.2 animations:^{
        self.barView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.barView.userInteractionEnabled = NO;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.barView.userInteractionEnabled = YES;
        [UIView animateWithDuration:0.25 animations:^{
            self.barView.alpha = [ANVSettings shared].opacity;
        }];
    });
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
    ANVGlyphKind kind = (ANVGlyphKind)sender.tag;

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
