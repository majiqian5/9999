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
    CGFloat bw = 4.0;
    CGFloat gp = 2.0;
    CGFloat total = kANVSpectrumBars * bw + (kANVSpectrumBars - 1) * gp;
    CGFloat sx = (width - total) / 2.0;
    if (startX) *startX = sx;
    if (barWidth) *barWidth = bw;
    if (gap) *gap = gp;
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
        default:
            [self drawBarsInContext:ctx rect:rect mirrored:NO];
            break;
    }
}

@end
