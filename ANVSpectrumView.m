#import "ANVSpectrumView.h"

#define kANVSpectrumBars 10

@implementation ANVSpectrumView {
    float _levels[kANVSpectrumBars];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)updateLevels:(const float *)levels count:(NSUInteger)count {
    NSUInteger n = MIN(count, (NSUInteger)kANVSpectrumBars);
    BOOL changed = NO;
    for (NSUInteger i = 0; i < kANVSpectrumBars; i++) {
        float value = i < n ? levels[i] : 0.0f;
        if (fabs(value - _levels[i]) > 0.01f) changed = YES;
        _levels[i] = value;
    }
    if (changed) [self setNeedsDisplay];
}

- (UIColor *)colorForBar:(NSInteger)index {
    // 彩虹：色相从红渐变到紫
    CGFloat t = (CGFloat)index / (CGFloat)(kANVSpectrumBars - 1);
    CGFloat hue = t * 0.83;              // 0 -> 红, 0.83 -> 紫
    return [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0];
}

- (void)layoutForWidth:(CGFloat)width
                 start:(CGFloat *)startX
               barWidth:(CGFloat *)barWidth
                   gap:(CGFloat *)gap {
    // 原来写死 4pt 柱宽 + 2pt 间距，10 根只有 58pt，缩在导航条正中间。
    // 现在按可用宽度均分，柱宽随条长自适应（条越宽柱子越粗、铺满整条）。
    NSInteger bars = MAX((NSInteger)kANVSpectrumBars, 1);
    CGFloat gp = MAX(2.0, width / (CGFloat)bars * 0.22);
    CGFloat bw = (width - gp * (CGFloat)(bars - 1)) / (CGFloat)bars;
    if (bw < 1.5) {
        bw = 1.5;
        gp = MAX(0.5, (width - bw * (CGFloat)bars) / (CGFloat)MAX(bars - 1, 1));
    }
    CGFloat total = bw * (CGFloat)bars + gp * (CGFloat)(bars - 1);
    CGFloat sx = (width - total) / 2.0;
    if (startX) *startX = sx;
    if (barWidth) *barWidth = bw;
    if (gap) *gap = gp;
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    if (_phase > 1000.0) _phase = 0;
    if (self.style >= ANVSpectrumStyleMarquee) [self setNeedsDisplay];
}

#pragma mark - 各种样式

- (void)drawBarsInContext:(CGContextRef)ctx rect:(CGRect)rect mirrored:(BOOL)mirrored {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    CGFloat maxHeight = mirrored ? CGRectGetHeight(rect) / 2.0 : CGRectGetHeight(rect);
    CGFloat baseY = mirrored ? CGRectGetMidY(rect) : CGRectGetMaxY(rect);
    CGFloat minWidth = 4.0 * barWidth;

    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat level = MAX(_levels[i], 0.05f);
        CGFloat height = MAX(2.0, maxHeight * level);
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = mirrored
            ? CGRectMake(x, baseY - height, barWidth, height * 2.0)
            : CGRectMake(x, baseY - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 5.0, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:barWidth / 2.0];
        [path fill];
    }
    (void)minWidth;
}

- (void)drawDotsInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    NSInteger rows = 6;
    CGFloat dot = 3.0;
    CGFloat rowGap = (CGRectGetHeight(rect) - rows * dot) / (CGFloat)(rows > 1 ? rows - 1 : 1);

    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        NSInteger lit = (NSInteger)lround(_levels[i] * rows);
        for (NSInteger r = 0; r < rows; r++) {
            CGFloat y = CGRectGetMaxY(rect) - dot - r * (dot + rowGap);
            CGFloat x = startX + i * (barWidth + gap) + (barWidth - dot) / 2.0;
            UIColor *color = [self colorForBar:i];
            if (r < lit) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
            } else {
                CGContextSetFillColorWithColor(ctx,
                    [color colorWithAlphaComponent:0.18].CGColor);
            }
            CGContextFillEllipseInRect(ctx, CGRectMake(x, y, dot, dot));
        }
    }
}

- (void)drawLineInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    CGMutablePathRef path = CGPathCreateMutable();
    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat x = startX + i * (barWidth + gap) + barWidth / 2.0;
        CGFloat y = CGRectGetMaxY(rect) - MAX(_levels[i], 0.03f) * CGRectGetHeight(rect);
        if (i == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }

    CGContextSetLineWidth(ctx, 2.5);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0,
        [UIColor colorWithHue:0.55 saturation:1.0 brightness:1.0 alpha:1.0].CGColor);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);

    // 用彩虹段再描一遍，做出流光感
    for (NSInteger i = 0; i < kANVSpectrumBars - 1; i++) {
        CGPoint p0 = CGPointMake(startX + i * (barWidth + gap) + barWidth / 2.0,
                                 CGRectGetMaxY(rect) - MAX(_levels[i], 0.03f) * CGRectGetHeight(rect));
        CGPoint p1 = CGPointMake(startX + (i + 1) * (barWidth + gap) + barWidth / 2.0,
                                 CGRectGetMaxY(rect) - MAX(_levels[i + 1], 0.03f) * CGRectGetHeight(rect));
        CGContextSetStrokeColorWithColor(ctx, [self colorForBar:i].CGColor);
        CGContextMoveToPoint(ctx, p0.x, p0.y);
        CGContextAddLineToPoint(ctx, p1.x, p1.y);
        CGContextStrokePath(ctx);
    }
    CGPathRelease(path);
}

- (void)drawMarqueeInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    // 往返：period 2.6 秒走完一轮
    CGFloat t = fmod(_phase / 2.6, 2.0);
    CGFloat pos = t <= 1.0 ? t : 2.0 - t;                 // 0 -> 1 -> 0
    CGFloat headIndex = pos * (CGFloat)(kANVSpectrumBars - 1);

    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat distance = fabs((CGFloat)i - headIndex);
        CGFloat glow = MAX(0.0, 1.0 - distance / 2.4);       // 灯头附近最亮
        CGFloat level = MAX(_levels[i], 0.10f);
        CGFloat animated = 0.30 + 0.70 * glow;               // 只有跑马灯在动
        CGFloat height = MAX(6.0, CGRectGetHeight(rect) * level * animated);
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(rect) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        UIColor *fill = glow > 0.55
            ? [UIColor colorWithWhite:1.0 alpha:0.55 + 0.45 * glow]
            : [color colorWithAlphaComponent:0.30 + 0.7 * glow];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0 * glow, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:barWidth / 2.0];
        [path fill];
    }
}

- (void)drawStreamInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    // 单向循环：1.8 秒一轮
    CGFloat cycle = fmod(_phase / 1.8, 1.0) * (CGFloat)kANVSpectrumBars;
    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat distance = fabs((CGFloat)i - cycle);
        distance = MIN(distance, (CGFloat)kANVSpectrumBars - distance);
        CGFloat glow = MAX(0.0, 1.0 - distance / 3.0);
        CGFloat level = MAX(_levels[i], 0.10f);
        CGFloat height = MAX(6.0, CGRectGetHeight(rect) * level * (0.4 + 0.6 * glow));
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(rect) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        UIColor *fill = [color colorWithAlphaComponent:0.25 + 0.75 * glow];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * glow, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:barWidth / 2.0];
        [path fill];
    }
}

- (void)drawPulseInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0;
    [self layoutForWidth:CGRectGetWidth(rect) start:&startX barWidth:&barWidth gap:&gap];

    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat wave = 0.5 + 0.5 * sin(_phase * 2.2 + (CGFloat)i * 0.75);
        CGFloat level = MAX(_levels[i], 0.10f);
        CGFloat height = MAX(6.0, CGRectGetHeight(rect) * level * (0.30 + 0.70 * wave));
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(rect) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:barWidth / 2.0];
        [path fill];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    switch (self.style) {
        case ANVSpectrumStyleDots:
            [self drawDotsInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleMirror:
            [self drawBarsInContext:ctx rect:rect mirrored:YES];
            break;
        case ANVSpectrumStyleLine:
            [self drawLineInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleMarquee:
            [self drawMarqueeInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleStream:
            [self drawStreamInContext:ctx rect:rect];
            break;
        case ANVSpectrumStylePulse:
            [self drawPulseInContext:ctx rect:rect];
            break;
        default:
            [self drawBarsInContext:ctx rect:rect mirrored:NO];
            break;
    }
}

@end
