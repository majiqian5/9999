#import "ANVSpectrumView.h"

#define kANVSrcBars 10
#define kANVMaxBars 24

@interface ANVSpectrumView ()
@end

@implementation ANVSpectrumView {
    float _levels[kANVSrcBars];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        _barCount = 10;
        _widthRatio = 1.0;
        _heightRatio = 1.0;
        _thickness = 0.62;
    }
    return self;
}

#pragma mark - 参数

- (void)setBarCount:(NSInteger)barCount {
    _barCount = MIN(MAX(barCount, 4), kANVMaxBars);
    [self setNeedsDisplay];
}

- (void)setWidthRatio:(CGFloat)widthRatio {
    _widthRatio = MIN(MAX(widthRatio, 0.2), 1.0);
    [self setNeedsDisplay];
}

- (void)setHeightRatio:(CGFloat)heightRatio {
    _heightRatio = MIN(MAX(heightRatio, 0.2), 1.0);
    [self setNeedsDisplay];
}

- (void)setThickness:(CGFloat)thickness {
    _thickness = MIN(MAX(thickness, 0.15), 1.0);
    [self setNeedsDisplay];
}

- (void)setStyle:(ANVSpectrumStyle)style {
    _style = style;
    [self setNeedsDisplay];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsDisplay];
}

- (void)updateLevels:(const float *)levels count:(NSUInteger)count {
    NSUInteger n = MIN(count, (NSUInteger)kANVSrcBars);
    BOOL changed = NO;
    for (NSUInteger i = 0; i < kANVSrcBars; i++) {
        float value = i < n ? levels[i] : 0.0f;
        if (fabs(value - _levels[i]) > 0.01f) changed = YES;
        _levels[i] = value;
    }
    if (changed) [self setNeedsDisplay];
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    if (_phase > 1000.0) _phase = 0;
    if (self.style >= ANVSpectrumStyleMarquee) [self setNeedsDisplay];
}

#pragma mark - 取值 / 配色

/// 显示用的柱子数量可以从 10 个源频段插值出来，数量可调
- (CGFloat)levelAtIndex:(NSInteger)index {
    NSInteger n = self.barCount;
    if (n <= 1) return _levels[0];
    CGFloat src = (CGFloat)index / (CGFloat)(n - 1) * (CGFloat)(kANVSrcBars - 1);
    NSInteger lo = (NSInteger)floor(src);
    NSInteger hi = MIN(lo + 1, (NSInteger)kANVSrcBars - 1);
    CGFloat t = src - (CGFloat)lo;
    return _levels[lo] * (1.0 - t) + _levels[hi] * t;
}

- (UIColor *)colorForBar:(NSInteger)index {
    NSInteger n = MAX(self.barCount - 1, 1);
    CGFloat hue = ((CGFloat)index / (CGFloat)n) * 0.83;   // 红 -> 紫
    return [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0];
}

#pragma mark - 布局（宽/高/数量/粗细都跟着设置走）

- (CGRect)contentRectForRect:(CGRect)rect {
    CGFloat w = CGRectGetWidth(rect) * self.widthRatio;
    CGFloat h = CGRectGetHeight(rect) * self.heightRatio;
    return CGRectMake(CGRectGetMinX(rect) + (CGRectGetWidth(rect) - w) / 2.0,
                      CGRectGetMaxY(rect) - h,          // 底部对齐，高度往上收
                      w, h);
}

- (void)layoutForRect:(CGRect)rect
                start:(CGFloat *)startX
             barWidth:(CGFloat *)barWidth
                  gap:(CGFloat *)gap
             contentH:(CGFloat *)contentH {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 1);
    CGFloat slot = CGRectGetWidth(content) / (CGFloat)n;
    CGFloat bw = slot * self.thickness;
    bw = MAX(bw, 1.0);
    CGFloat gp = MAX(slot - bw, 0.0);
    if (startX) *startX = CGRectGetMinX(content);
    if (barWidth) *barWidth = bw;
    if (gap) *gap = gp;
    if (contentH) *contentH = CGRectGetHeight(content);
}

#pragma mark - 各种样式

- (void)drawBarsInContext:(CGContextRef)ctx rect:(CGRect)rect mirrored:(BOOL)mirrored {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];

    CGRect content = [self contentRectForRect:rect];
    CGFloat maxHeight = mirrored ? contentH / 2.0 : contentH;
    CGFloat baseY = mirrored ? CGRectGetMidY(content) : CGRectGetMaxY(content);

    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat level = MAX([self levelAtIndex:i], 0.05f);
        CGFloat height = MAX(2.0, maxHeight * level);
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = mirrored
            ? CGRectMake(x, baseY - height, barWidth, height * 2.0)
            : CGRectMake(x, baseY - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 5.0, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:MIN(barWidth, height) / 2.0];
        [path fill];
    }
}

- (void)drawDotsInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];

    NSInteger rows = 6;
    CGFloat dot = MIN(barWidth, contentH / (CGFloat)rows) ;
    dot = MAX(dot, 1.5);
    CGFloat rowGap = (contentH - rows * dot) / (CGFloat)(rows > 1 ? rows - 1 : 1);
    rowGap = MAX(rowGap, 0.5);

    for (NSInteger i = 0; i < self.barCount; i++) {
        NSInteger lit = (NSInteger)lround([self levelAtIndex:i] * rows);
        CGFloat x = startX + i * (barWidth + gap) + (barWidth - dot) / 2.0;
        UIColor *color = [self colorForBar:i];
        for (NSInteger r = 0; r < rows; r++) {
            CGFloat y = CGRectGetMaxY(content) - dot - r * (dot + rowGap);
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
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];

    CGMutablePathRef path = CGPathCreateMutable();
    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat x = startX + i * (barWidth + gap) + barWidth / 2.0;
        CGFloat y = CGRectGetMaxY(content) - MAX([self levelAtIndex:i], 0.03f) * contentH;
        if (i == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }

    CGContextSetLineWidth(ctx, 2.5);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0,
        [UIColor colorWithHue:0.55 saturation:1.0 brightness:1.0 alpha:1.0].CGColor);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);

    for (NSInteger i = 0; i < self.barCount - 1; i++) {
        CGPoint p0 = CGPointMake(startX + i * (barWidth + gap) + barWidth / 2.0,
                                 CGRectGetMaxY(content) - MAX([self levelAtIndex:i], 0.03f) * contentH);
        CGPoint p1 = CGPointMake(startX + (i + 1) * (barWidth + gap) + barWidth / 2.0,
                                 CGRectGetMaxY(content) - MAX([self levelAtIndex:i + 1], 0.03f) * contentH);
        CGContextSetStrokeColorWithColor(ctx, [self colorForBar:i].CGColor);
        CGContextMoveToPoint(ctx, p0.x, p0.y);
        CGContextAddLineToPoint(ctx, p1.x, p1.y);
        CGContextStrokePath(ctx);
    }
    CGPathRelease(path);
}

- (void)drawMarqueeInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];

    CGFloat t = fmod(_phase / 2.6, 2.0);
    CGFloat pos = t <= 1.0 ? t : 2.0 - t;
    CGFloat headIndex = pos * (CGFloat)(self.barCount - 1);

    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat distance = fabs((CGFloat)i - headIndex);
        CGFloat glow = MAX(0.0, 1.0 - distance / 2.4);
        CGFloat level = MAX([self levelAtIndex:i], 0.10f);
        CGFloat height = MAX(6.0, contentH * level * (0.30 + 0.70 * glow));
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(content) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        UIColor *fill = glow > 0.55
            ? [UIColor colorWithWhite:1.0 alpha:0.55 + 0.45 * glow]
            : [color colorWithAlphaComponent:0.30 + 0.7 * glow];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0 * glow, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:MIN(barWidth, height) / 2.0];
        [path fill];
    }
}

- (void)drawStreamInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];

    NSInteger n = MAX(self.barCount, 1);
    CGFloat cycle = fmod(_phase / 1.8, 1.0) * (CGFloat)n;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat distance = fabs((CGFloat)i - cycle);
        distance = MIN(distance, (CGFloat)n - distance);
        CGFloat glow = MAX(0.0, 1.0 - distance / 3.0);
        CGFloat level = MAX([self levelAtIndex:i], 0.10f);
        CGFloat height = MAX(6.0, contentH * level * (0.4 + 0.6 * glow));
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(content) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        UIColor *fill = [color colorWithAlphaComponent:0.25 + 0.75 * glow];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * glow, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:MIN(barWidth, height) / 2.0];
        [path fill];
    }
}

- (void)drawPulseInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];

    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat wave = 0.5 + 0.5 * sin(_phase * 2.2 + (CGFloat)i * 0.75);
        CGFloat level = MAX([self levelAtIndex:i], 0.10f);
        CGFloat height = MAX(6.0, contentH * level * (0.30 + 0.70 * wave));
        CGFloat x = startX + i * (barWidth + gap);
        CGRect barRect = CGRectMake(x, CGRectGetMaxY(content) - height, barWidth, height);

        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:MIN(barWidth, height) / 2.0];
        [path fill];
    }
}


#pragma mark - 新增特效

/// 七色彩虹粒子左右冲撞：每个粒子一个速度，撞到边界反弹
- (void)drawParticlesInContext:(CGContextRef)ctx rect:(CGRect)rect doubleSided:(BOOL)doubleSided {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 6);
    CGFloat W = CGRectGetWidth(content);
    CGFloat H = CGRectGetHeight(content);
    CGFloat dot = MAX(2.0, W / (CGFloat)n * self.thickness * 0.85);

    for (NSInteger i = 0; i < n; i++) {
        CGFloat speed = 0.55 + (CGFloat)(i % 5) * 0.18;
        CGFloat raw = _phase * speed + (CGFloat)i * 0.6;
        CGFloat travel = fmod(raw, 2.0);                  // 0..2
        CGFloat pos = travel <= 1.0 ? travel : 2.0 - travel;   // 来回反弹
        if (doubleSided && (i % 2)) pos = 1.0 - pos;
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.12f);
        CGFloat yBase = CGRectGetMaxY(content) - level * H;
        CGFloat y = doubleSided ? (i % 2 ? CGRectGetMinY(content) + level * H : yBase) : yBase;
        CGFloat x = CGRectGetMinX(content) + pos * (W - dot);

        UIColor *color = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * level, color.CGColor);
        CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.85].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x, y - dot / 2.0, dot, dot));
        // 拖尾
        CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.25].CGColor);
        CGFloat tailW = dot * 2.6;
        CGRect tail = (pos > 0.5)
            ? CGRectMake(x - tailW, y - dot * 0.4, tailW, dot * 0.8)
            : CGRectMake(x + dot, y - dot * 0.4, tailW, dot * 0.8);
        CGContextFillEllipseInRect(ctx, tail);
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 螺旋点阵：一圈一圈往上走
- (void)drawSpiralInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 8);
    CGFloat dot = MAX(1.8, CGRectGetWidth(content) / (CGFloat)n * self.thickness * 0.7);
    for (NSInteger i = 0; i < n; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)n;
        CGFloat x = CGRectGetMinX(content) + t * CGRectGetWidth(content);
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.12f);
        CGFloat amp = CGRectGetHeight(content) * level * 0.5;
        CGFloat y = CGRectGetMidY(content) + sin(_phase * 2.4 + t * M_PI * 2.0) * amp;
        UIColor *color = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, color.CGColor);
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x - dot / 2.0, y - dot / 2.0, dot, dot));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 涟漪：从中间向外扩三圈
- (void)drawRippleInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger rings = 3;
    for (NSInteger r = 0; r < rings; r++) {
        CGFloat t = fmod(_phase * 0.6 + (CGFloat)r / (CGFloat)rings, 1.0);
        CGFloat radius = t * CGRectGetWidth(content) * 0.5;
        CGFloat alpha = (1.0 - t) * 0.9;
        UIColor *color = [UIColor colorWithHue:fmod(t * 0.83 + 0.1, 1.0)
                                    saturation:1.0 brightness:1.0 alpha:alpha];
        CGContextSetStrokeColorWithColor(ctx, color.CGColor);
        CGContextSetLineWidth(ctx, 1.8);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(CGRectGetMidX(content) - radius,
                                                     CGRectGetMidY(content) - radius * 0.6,
                                                     radius * 2.0, radius * 1.2));
    }
}

/// 瀑布：柱子从上往下落
- (void)drawWaterfallInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];
    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat level = MAX([self levelAtIndex:i], 0.08f);
        CGFloat h = contentH * level;
        CGFloat x = startX + i * (barWidth + gap);
        CGFloat drift = fmod(_phase * 40.0 + (CGFloat)i * 12.0, contentH);
        CGFloat y = CGRectGetMinY(content) + drift;
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, barWidth, h)
                                                        cornerRadius:MIN(barWidth, h) / 2.0];
        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.85].CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, color.CGColor);
        [p fill];
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 光环：一圈绕一轴旋转的亮点
- (void)drawHaloInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 10);
    CGFloat rx = CGRectGetWidth(content) * 0.46;
    CGFloat ry = CGRectGetHeight(content) * 0.44;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat angle = _phase * 1.8 + (CGFloat)i / (CGFloat)n * M_PI * 2.0;
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.15f);
        CGFloat x = CGRectGetMidX(content) + cos(angle) * rx;
        CGFloat y = CGRectGetMidY(content) + sin(angle) * ry;
        CGFloat dot = 1.6 + 2.6 * level;
        UIColor *color = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0, color.CGColor);
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y - dot, dot * 2.0, dot * 2.0));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 随机闪烁：每根柱子按自己的节奏亮灭
- (void)drawStrobeInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat phase = _phase * (1.1 + (CGFloat)(i % 7) * 0.23) + (CGFloat)i;
        CGFloat on = 0.5 + 0.5 * sin(phase * 3.0);
        CGFloat level = MAX([self levelAtIndex:i], 0.1f) * (0.35 + 0.65 * on);
        CGFloat h = MAX(3.0, contentH * level);
        CGFloat x = startX + i * (barWidth + gap);
        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.35 + 0.65 * on].CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 9.0 * on, color.CGColor);
        CGContextFillRect(ctx, CGRectMake(x, CGRectGetMaxY([self contentRectForRect:rect]) - h, barWidth, h));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 弹跳小球：每根柱子变成一个小球，按电平往上弹
- (void)drawBounceBallInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat startX = 0, barWidth = 0, gap = 0, contentH = 0;
    [self layoutForRect:rect start:&startX barWidth:&barWidth gap:&gap contentH:&contentH];
    CGRect content = [self contentRectForRect:rect];
    for (NSInteger i = 0; i < self.barCount; i++) {
        CGFloat level = MAX([self levelAtIndex:i], 0.1f);
        CGFloat hop = fabs(sin(_phase * 2.6 + (CGFloat)i * 0.5)) * contentH * level * 0.7;
        CGFloat d = MAX(3.0, barWidth * 0.9);
        CGFloat x = startX + i * (barWidth + gap) + (barWidth - d) / 2.0;
        CGFloat y = CGRectGetMaxY(content) - d - hop;
        UIColor *color = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, color.CGColor);
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x, y, d, d));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 交织斜线
- (void)drawBraidInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger lines = 4;
    for (NSInteger l = 0; l < lines; l++) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGFloat slope = (l % 2 ? 1.0 : -1.0) * CGRectGetHeight(content) * 0.5;
        CGFloat shift = fmod(_phase * 30.0 + (CGFloat)l * 24.0, CGRectGetWidth(content));
        CGPathMoveToPoint(path, NULL, CGRectGetMinX(content) + shift, CGRectGetMaxY(content));
        CGPathAddLineToPoint(path, NULL, CGRectGetMinX(content) + shift + CGRectGetWidth(content) * 0.5,
                             CGRectGetMaxY(content) - slope);
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithHue:fmod((CGFloat)l * 0.2 + _phase * 0.1, 1.0)
                       saturation:1.0 brightness:1.0 alpha:0.75].CGColor);
        CGContextSetLineWidth(ctx, 1.6);
        CGContextAddPath(ctx, path);
        CGContextStrokePath(ctx);
        CGPathRelease(path);
    }
}

/// 心电图：一条折线，遇到电平就跳一下
- (void)drawHeartbeatInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    CGMutablePathRef path = CGPathCreateMutable();
    NSInteger steps = MAX(self.barCount * 2, 20);
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        CGFloat x = CGRectGetMinX(content) + t * CGRectGetWidth(content);
        CGFloat level = [self levelAtIndex:(i % kANVSrcBars)];
        CGFloat spike = (i % 6 == 0) ? level * 0.7 : 0.0;
        CGFloat y = CGRectGetMaxY(content) - CGRectGetHeight(content) * (0.12 + spike);
        if (i == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }
    UIColor *color = [UIColor colorWithHue:fmod(_phase * 0.2, 1.0) saturation:0.9 brightness:1.0 alpha:1.0];
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0, color.CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);
    CGPathRelease(path);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 七色雨丝：斜向落下的短线
- (void)drawRainStreakInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 10);
    for (NSInteger i = 0; i < n; i++) {
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.1f);
        CGFloat x = CGRectGetMinX(content) + ((CGFloat)i + 0.5) / (CGFloat)n * CGRectGetWidth(content);
        CGFloat y = CGRectGetMinY(content) + fmod(_phase * (60.0 + 20.0 * (CGFloat)(i % 4)) + (CGFloat)i * 30.0,
                                                  CGRectGetHeight(content));
        CGFloat len = CGRectGetHeight(content) * 0.18 * (0.5 + level);
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(x, y)];
        [p addLineToPoint:CGPointMake(x - len * 0.25, y + len)];
        UIColor *color = [self colorForBar:i];
        CGContextSetStrokeColorWithColor(ctx, [color colorWithAlphaComponent:0.8].CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 5.0, color.CGColor);
        p.lineWidth = 1.6;
        [p stroke];
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
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
        case ANVSpectrumStyleParticles:
            [self drawParticlesInContext:ctx rect:rect doubleSided:NO];
            break;
        case ANVSpectrumStyleDoubleCollide:
            [self drawParticlesInContext:ctx rect:rect doubleSided:YES];
            break;
        case ANVSpectrumStyleSpiral:
            [self drawSpiralInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleRipple:
            [self drawRippleInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleWaterfall:
            [self drawWaterfallInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleHalo:
            [self drawHaloInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleStrobe:
            [self drawStrobeInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleBounceBall:
            [self drawBounceBallInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleBraid:
            [self drawBraidInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleHeartbeat:
            [self drawHeartbeatInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleRainStreak:
            [self drawRainStreakInContext:ctx rect:rect];
            break;
        default:
            [self drawBarsInContext:ctx rect:rect mirrored:NO];
            break;
    }
}

@end
