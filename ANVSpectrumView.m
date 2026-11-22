#import "ANVSpectrumView.h"

#define kANVSrcBars 10
#define kANVMaxBars 24

@interface ANVSpectrumView ()
@end

@implementation ANVSpectrumView {
    float _levels[kANVSrcBars];
    CGFloat _haloAngle;        // 光环当前转角（累计，跟着频谱变速）
    CGFloat _haloSpeed;        // 平滑后的角速度
    NSInteger _haloDir;        // 1 顺时针 -1 逆时针
    CFTimeInterval _haloFlipAt;
    CGFloat _haloLastEnergy;
    CGFloat _haloSmoothEnergy;
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
        _haloDotScale = 1.0;
        _haloRainbow = YES;
        _haloBounce = YES;
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
    [self advanceHaloWithDelta:delta];
    if (self.style >= ANVSpectrumStyleMarquee) [self setNeedsDisplay];
}

/// 旋转光环：转速吃真实电平（响的时候转得快、安静时慢慢飘），方向随机翻转
- (void)advanceHaloWithDelta:(CGFloat)delta {
    CGFloat sum = 0.0;
    for (NSUInteger i = 0; i < (NSUInteger)kANVSrcBars; i++) sum += _levels[i];
    CGFloat energy = sum / (CGFloat)kANVSrcBars;

    // 平滑一下，避免电平抖一下光环就抽一下
    _haloSmoothEnergy += (energy - _haloSmoothEnergy) * MIN(1.0, delta * 5.0);

    // 没声音就彻底停：转速直接归零，不再「安静时慢慢飘」
    CGFloat target = 0.0;
    if (_haloSmoothEnergy > 0.02) {
        target = 0.35 + 6.0 * _haloSmoothEnergy;         // rad/s，响的时候最多约 6.3
    }
    _haloSpeed += (target - _haloSpeed) * MIN(1.0, delta * 4.0);
    if (_haloSpeed < 0.05) _haloSpeed = 0.0;             // 停住，不再微转

    if (_haloDir == 0) {
        _haloDir = 1;
        _haloFlipAt = CACurrentMediaTime() + 3.0 + (CFTimeInterval)arc4random_uniform(600) / 100.0;
    }
    _haloAngle += (CGFloat)_haloDir * _haloSpeed * delta;
    if (_haloAngle > 1000.0) _haloAngle = fmod(_haloAngle, 2.0 * (CGFloat)M_PI);
    if (_haloAngle < -1000.0) _haloAngle = fmod(_haloAngle, 2.0 * (CGFloat)M_PI);

    CFTimeInterval nowH = CACurrentMediaTime();
    BOOL flip = NO;
    if (nowH > _haloFlipAt) flip = YES;                                   // 定时随机翻转
    // 强拍也能提前打断：上一帧还很安静、这一帧突然很响
    if (_haloSmoothEnergy > 0.45 && _haloLastEnergy < 0.18) flip = YES;
    if (flip) {
        _haloDir = -_haloDir;
        _haloFlipAt = nowH + 3.0 + (CFTimeInterval)arc4random_uniform(600) / 100.0;
    }
    _haloLastEnergy = _haloSmoothEnergy;
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

/// 旋转光环：椭圆轨道上的亮点，逐个按电平点亮，可选九色彩虹与跳动
- (void)drawHaloInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 10);
    CGFloat rx = CGRectGetWidth(content) * 0.46;
    CGFloat ry = CGRectGetHeight(content) * 0.44;
    CGFloat dotScale = MIN(MAX(self.haloDotScale, 0.6), 2.0);

    // 九色：红 橙 黄 绿 青 蓝 紫 粉 白
    static CGFloat const hues[9] = {0.00, 0.09, 0.14, 0.33, 0.48, 0.58, 0.72, 0.88, 0.00};
    static CGFloat const sats[9] = {0.95, 1.00, 0.95, 1.00, 0.90, 0.95, 0.85, 0.80, 0.00};

    // 轨道底环
    UIBezierPath *track = [UIBezierPath bezierPathWithOvalInRect:
        CGRectInset(content, CGRectGetWidth(content) * 0.04, CGRectGetHeight(content) * 0.06)];
    [[UIColor colorWithHue:0.75 saturation:0.5 brightness:1.0 alpha:0.10 + 0.12 * _haloSmoothEnergy] setStroke];
    track.lineWidth = 1.0;
    [track stroke];

    CGFloat litPos = _haloSmoothEnergy * (CGFloat)n;      // 亮到第几个点
    NSInteger colorShift = (NSInteger)floor(litPos);      // 颜色随电平往前滚

    CGFloat bounceAmp = 0.0;
    if (self.haloBounce) {
        bounceAmp = CGRectGetHeight(content) * 0.10 * (0.25 + _haloSmoothEnergy);
    }

    for (NSInteger pass = 2; pass >= 0; pass--) {
        CGFloat trail = (CGFloat)pass * 0.16;
        CGFloat baseAlpha = pass == 0 ? 1.0 : (0.34 - 0.11 * (CGFloat)pass);
        CGFloat baseScale = pass == 0 ? 1.0 : 0.72;
        for (NSInteger i = 0; i < n; i++) {
            CGFloat angle = _haloAngle + (CGFloat)i / (CGFloat)n * 2.0 * (CGFloat)M_PI
                            - (CGFloat)_haloDir * trail;
            CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.12f);

            CGFloat litFactor = 0.0;
            if ((CGFloat)i < litPos - 1.0) litFactor = 1.0;
            else if ((CGFloat)i < litPos) litFactor = litPos - (CGFloat)i;
            litFactor = MIN(MAX(litFactor, 0.0), 1.0);

            // 跳动：每个点亮起时向外弹一下
            CGFloat bounce = bounceAmp * litFactor * sin(_phase * 6.0 + (CGFloat)i * 0.9);
            CGFloat rx2 = rx + bounce;
            CGFloat ry2 = ry + bounce * 0.7;

            CGFloat x = CGRectGetMidX(content) + cos(angle) * rx2;
            CGFloat y = CGRectGetMidY(content) + sin(angle) * ry2;

            CGFloat dot = (1.5 + 3.2 * level) * dotScale * baseScale * (0.55 + 0.45 * litFactor);

            UIColor *color;
            if (self.haloRainbow) {
                NSInteger ci = (i + colorShift) % 9;
                if (ci < 0) ci += 9;
                CGFloat hue = fmod(hues[ci] + (ci == 8 ? _phase * 0.05 : 0.0), 1.0);
                color = [UIColor colorWithHue:hue saturation:sats[ci] brightness:1.0 alpha:1.0];
            } else {
                color = [self colorForBar:i];
            }
            color = [color colorWithAlphaComponent:baseAlpha * (0.18 + 0.82 * litFactor)];

            CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0 * (0.5 + level), color.CGColor);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y - dot, dot * 2.0, dot * 2.0));
        }
    }

    // 中心小光球
    CGFloat coreR = (2.0 + 4.0 * _haloSmoothEnergy) * dotScale;
    UIColor *core = [UIColor colorWithHue:fmod(0.72 + _haloSmoothEnergy * 0.2, 1.0)
                                saturation:0.85 brightness:1.0
                                    alpha:0.25 + 0.65 * _haloSmoothEnergy];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0, core.CGColor);
    CGContextSetFillColorWithColor(ctx, core.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMidX(content) - coreR,
                                               CGRectGetMidY(content) - coreR,
                                               coreR * 2.0, coreR * 2.0));
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
