#import "ANVSpectrumView.h"

#define kANVSrcBars 10
#define kANVMaxBars 24
#define kANVHaloDots 32

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
    // 逐颗点亮 / 逐颗弹跳：每颗点记下它被电平点到的那一刻和那次弹跳的幅度
    CFTimeInterval _haloPulseAt[kANVHaloDots];
    CGFloat _haloPulseAmp[kANVHaloDots];
    CGFloat _haloLitPrev[kANVHaloDots];
    // 每颗点自己的真实电平（不是整条平均），它一抬头这颗就弹
    CGFloat _haloDotLevel[kANVHaloDots];
    CGFloat _haloDotPrev[kANVHaloDots];
    CFTimeInterval _haloRiseAt[kANVHaloDots];
    CGFloat _haloRiseAmp[kANVHaloDots];
    // 强拍包络：电平突然抬头 = 一下“咚”
    CFTimeInterval _haloLastBeat;
    CGFloat _haloBeatPulse;
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

/// 旋转光环：转速吃真实电平（响的时候转得快、安静时不转），方向随机翻转
/// 点亮的进度也跟着真电平走，电平抬头就一颗一颗往外点，点到的瞬间弹一下
/// 旋转光环：转速吃真实电平，方向随机翻转
/// 逐颗弹跳改成「每颗点跟自己的频段」：哪一段电平抬头，就那一颗往外弹一下
/// 所以真跳起来是一颗接一颗，不是整环一起动
- (void)advanceHaloWithDelta:(CGFloat)delta {
    if (delta <= 0.0) return;

    CGFloat sum = 0.0;
    for (NSUInteger i = 0; i < (NSUInteger)kANVSrcBars; i++) sum += _levels[i];
    CGFloat energy = MIN(MAX(sum / (CGFloat)kANVSrcBars, 0.0), 1.0);

    CGFloat rise = (energy > _haloSmoothEnergy) ? delta * 9.0 : delta * 4.0;
    _haloSmoothEnergy += (energy - _haloSmoothEnergy) * MIN(1.0, rise);
    _haloSmoothEnergy = MIN(MAX(_haloSmoothEnergy, 0.0), 1.0);

    CFTimeInterval nowH = CACurrentMediaTime();

    // 强拍：整条电平突然抬头
    if (_haloSmoothEnergy > 0.20 && _haloSmoothEnergy > _haloLastEnergy + 0.07 &&
        nowH - _haloLastBeat > 0.13) {
        _haloLastBeat = nowH;
        _haloBeatPulse = 1.0;
        if (self.onBeat) self.onBeat(_haloSmoothEnergy);
    }
    _haloBeatPulse *= exp(-delta * 6.0);
    if (_haloBeatPulse < 0.01) _haloBeatPulse = 0.0;

    // 转速：响的时候转得快，彗尾动作再翻一倍
    CGFloat target = 0.0;
    if (_haloSmoothEnergy > 0.02) target = 0.5 + 7.0 * _haloSmoothEnergy;
    if (self.haloMotion == 11) target *= 2.2;
    _haloSpeed += (target - _haloSpeed) * MIN(1.0, delta * 4.0);
    if (_haloSpeed < 0.05) _haloSpeed = 0.0;

    if (_haloDir == 0) {
        _haloDir = 1;
        _haloFlipAt = nowH + 3.0 + (CFTimeInterval)arc4random_uniform(600) / 100.0;
    }
    _haloAngle += (CGFloat)_haloDir * _haloSpeed * delta;
    if (_haloAngle > 1000.0) _haloAngle = fmod(_haloAngle, 2.0 * (CGFloat)M_PI);
    if (_haloAngle < -1000.0) _haloAngle = fmod(_haloAngle, 2.0 * (CGFloat)M_PI);

    BOOL flip = NO;
    if (nowH > _haloFlipAt) flip = YES;
    if (_haloSmoothEnergy > 0.45 && _haloLastEnergy < 0.18) flip = YES;
    if (flip) {
        _haloDir = -_haloDir;
        _haloFlipAt = nowH + 3.0 + (CFTimeInterval)arc4random_uniform(600) / 100.0;
    }

    // 每颗点独立跟踪自己的频段：抬头快、回落慢，抬头那一刻记一次弹跳
    NSInteger n = MIN(MAX(self.barCount, 10), (NSInteger)kANVHaloDots);
    for (NSInteger i = 0; i < n; i++) {
        NSInteger band = (NSInteger)floor((CGFloat)i / (CGFloat)n * (CGFloat)(kANVSrcBars - 1) + 0.5);
        band = MIN(MAX(band, 0), kANVSrcBars - 1);
        CGFloat lv = MIN(MAX(_levels[band], 0.0), 1.0);

        CGFloat prev = _haloDotLevel[i];
        CGFloat rate = (lv > prev) ? delta * 14.0 : delta * 6.0;
        _haloDotLevel[i] += (lv - prev) * MIN(1.0, rate);
        _haloDotLevel[i] = MIN(MAX(_haloDotLevel[i], 0.0), 1.0);

        if (_haloDotLevel[i] > _haloDotPrev[i] + 0.04 && nowH - _haloRiseAt[i] > 0.09) {
            _haloRiseAt[i] = nowH;
            _haloRiseAmp[i] = 0.55 + 0.45 * _haloDotLevel[i];
        }
        _haloDotPrev[i] = _haloDotLevel[i];
        _haloLitPrev[i] = 0.0;
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

/// 旋转光环：椭圆轨道上的亮点，进度跟着真电平一颗一颗点亮，亮起即弹跳
/// 可选九色彩虹、中心彩虹球，以及几种跟着旋律走的动作（呼吸 / 摇摆 / 浮动 / 波浪 / 双环）
- (void)drawHaloInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect content = [self contentRectForRect:rect];
    NSInteger n = MIN(MAX(self.barCount, 10), (NSInteger)kANVHaloDots);
    CGFloat dotScale = MIN(MAX(self.haloDotScale, 0.6), 2.0);
    CFTimeInterval nowD = CACurrentMediaTime();

    CGFloat w = CGRectGetWidth(content);
    CGFloat h = CGRectGetHeight(content);
    CGFloat energy = MIN(MAX(_haloSmoothEnergy, 0.0), 1.0);
    CGFloat beat = _haloBeatPulse;

    // 九色：红 橙 黄 绿 青 蓝 紫 粉 白
    static CGFloat const hues[9] = {0.00, 0.09, 0.14, 0.33, 0.48, 0.58, 0.72, 0.88, 0.00};
    static CGFloat const sats[9] = {0.95, 1.00, 0.95, 1.00, 0.90, 0.95, 0.85, 0.80, 0.00};
    UIColor *(^nineColor)(NSInteger, CGFloat) = ^UIColor *(NSInteger ci, CGFloat alpha) {
        NSInteger k = ci % 9;
        if (k < 0) k += 9;
        if (sats[k] < 0.1) return [UIColor colorWithWhite:1.0 alpha:alpha];
        return [UIColor colorWithHue:hues[k] saturation:sats[k] brightness:1.0 alpha:alpha];
    };

    // 动作拆开成一个个独立开关，每个动作的几何参数差别拉到肉眼一眼就分得出
    NSInteger motion = self.haloMotion;
    BOOL full       = (motion == 5);
    BOOL mBreath    = (motion == 0 || full);
    BOOL mSway      = (motion == 1 || full);
    BOOL mFloat     = (motion == 2 || full);
    BOOL mWave      = (motion == 3 || full);
    BOOL mDouble    = (motion == 4 || full);
    BOOL mSpiral    = (motion == 6 || full);
    BOOL mBurst     = (motion == 7 || full);
    BOOL mWiper     = (motion == 8 || full);
    BOOL mPump      = (motion == 9);
    BOOL mShock     = (motion == 10 || full);
    BOOL mComet     = (motion == 11);
    BOOL mCollide   = (motion == 12);
    BOOL mLemni     = (motion == 13);
    BOOL mMarquee   = (motion == 14);
    BOOL mGravity   = (motion == 15);
    BOOL mHourglass = (motion == 16);
    BOOL mRosette   = (motion == 17 || full);
    BOOL mRings     = (motion == 18 || full);

    // 几何参数
    CGFloat breath   = mBreath ? (1.0 + (0.10 + 0.24 * energy) * sin(_phase * 1.9)) : 1.0;
    CGFloat squash   = mHourglass ? 0.42 * sin(_phase * 2.0) : 0.0;
    CGFloat rx       = w * 0.46 * breath * (1.0 + squash);
    CGFloat ry       = h * 0.44 * breath * (1.0 - squash);
    CGFloat pump     = mPump ? (0.70 + 0.62 * energy) : 1.0;
    CGFloat burstK   = mBurst ? (1.0 + 0.45 * beat) : 1.0;
    CGFloat sway     = mSway ? 0.30 * sin(_phase * 1.25) : 0.0;
    CGFloat floatY   = mFloat ? sin(_phase * 0.9) * h * 0.22 * (0.5 + 0.5 * energy) : 0.0;
    CGFloat waveAmp  = mWave ? h * 0.13 * (0.45 + energy) : 0.0;
    CGFloat spiralA  = mSpiral ? h * 0.20 : 0.0;
    CGFloat wiper    = mWiper ? 1.10 * sin(_phase * 2.0) : 0.0;

    CGPoint center = CGPointMake(CGRectGetMidX(content),
                                 CGRectGetMidY(content) + floatY - beat * h * 0.05);
    CGFloat baseRX = rx * pump * burstK;
    CGFloat baseRY = ry * pump * burstK;

    // 冲击波：强拍后 0.42 秒内把点往外推一把
    CGFloat shockAge = (CGFloat)(nowD - _haloLastBeat);
    CGFloat shockPush = 0.0;
    if (mShock && shockAge >= 0.0 && shockAge < 0.42) {
        shockPush = (1.0 - shockAge / 0.42) * h * 0.16;
    }

    // 轨道底环
    UIBezierPath *track = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(center.x - baseRX * 0.94, center.y - baseRY * 0.94,
                   baseRX * 1.88, baseRY * 1.88)];
    [[UIColor colorWithHue:0.75 saturation:0.5 brightness:1.0 alpha:0.10 + 0.12 * energy] setStroke];
    track.lineWidth = 1.0;
    [track stroke];

    // 涟漪：几圈从中心往外扩的圆环（每记强拍重新起一圈）
    if (mRings) {
        for (NSInteger k = 0; k < 3; k++) {
            CGFloat age = shockAge + (CGFloat)k * 0.24;
            CGFloat p = fmod(age, 0.72) / 0.72;
            CGFloat rrX = baseRX * (0.18 + 1.05 * p);
            CGFloat rrY = baseRY * (0.18 + 1.05 * p);
            UIColor *rc = nineColor((NSInteger)floor(_phase * 2.0) + k, (1.0 - p) * 0.42 * (0.35 + energy));
            CGContextSetStrokeColorWithColor(ctx, rc.CGColor);
            CGContextSetLineWidth(ctx, MAX(0.7, 1.6 * (1.0 - p) * dotScale));
            CGContextStrokeEllipseInRect(ctx, CGRectMake(center.x - rrX, center.y - rrY, rrX * 2.0, rrY * 2.0));
        }
    }

    CGFloat litPos = MIN(1.0, energy * 1.15 + beat * 0.30) * (CGFloat)n;
    NSInteger colorShift = (NSInteger)floor(litPos);
    NSInteger marqIdx = mMarquee ? ((NSInteger)floor(_phase * 3.0 + energy * 8.0) % n) : -1;

    for (NSInteger pass = 2; pass >= 0; pass--) {
        CGFloat trail = (CGFloat)pass * 0.16;
        CGFloat baseAlpha = pass == 0 ? 1.0 : (0.34 - 0.11 * (CGFloat)pass);
        CGFloat baseScale = pass == 0 ? 1.0 : 0.72;

        for (NSInteger i = 0; i < n; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)n;
            CGFloat a = _haloAngle + t * 2.0 * (CGFloat)M_PI - (CGFloat)_haloDir * trail + wiper;

            CGFloat lv = MIN(MAX(_haloDotLevel[i], 0.0), 1.0);
            CGFloat lit = 0.0;
            if ((CGFloat)i < litPos - 1.0) lit = 1.0;
            else if ((CGFloat)i < litPos) lit = litPos - (CGFloat)i;
            lit = MIN(MAX(lit, 0.0), 1.0);
            if (mMarquee) lit = (i == marqIdx) ? 1.0 : 0.14;

            // 逐颗弹跳：这一颗自己的电平刚抬头 → 朝外 + 向上弹一下，再落回去
            CGFloat kick = 0.0;
            if (self.haloBounce) {
                CGFloat age = (CGFloat)(nowD - _haloRiseAt[i]);
                if (age > 0.0 && age < 0.75) {
                    kick = _haloRiseAmp[i] * exp(-age * 4.2) * sin(MIN(age, 0.42) * 14.0);
                }
                if (pass > 0) kick *= 0.55;
            }
            CGFloat hop = kick * h * 0.30;            // 垂直弹起：一颗接一颗往上跳
            CGFloat radialKick = fabs(kick) * h * 0.10;

            CGFloat waveDot = waveAmp * sin(_phase * 3.2 + (CGFloat)i * 0.70) * (pass == 0 ? 1.0 : 0.6);
            CGFloat spiralDot = spiralA * sin(_phase * 3.6 + (CGFloat)i * 1.40) * (pass == 0 ? 1.0 : 0.6);
            CGFloat ros = mRosette ? (1.0 + 0.26 * cos(5.0 * a + _phase * 1.8)) : 1.0;

            CGFloat srx = (baseRX + radialKick + waveDot + spiralDot + shockPush) * ros;
            CGFloat sry = (baseRY + radialKick + waveDot * 0.9 + spiralDot * 0.9 + shockPush) * ros;

            CGFloat x = 0.0, y = 0.0;
            if (mLemni) {
                // 8 字：两个圈套在一起，整条轨迹跟着旋转
                CGFloat u = t * 2.0 * (CGFloat)M_PI;
                CGFloat lx = sin(u) * baseRX;
                CGFloat ly = sin(u * 2.0) * baseRY * 0.62;
                CGFloat rot = _haloAngle;
                x = center.x + lx * cos(rot) - ly * sin(rot);
                y = center.y + lx * sin(rot) + ly * cos(rot) - hop;
                x += cos(u) * radialKick;
            } else {
                x = center.x + cos(a) * srx;
                y = center.y + sin(a) * sry + cos(a) * sway * sry - hop;
            }

            if (mCollide) {
                // 对撞：奇偶分两半，从两侧向中间撞，撞上时抖一下
                CGFloat side = (i % 2) ? 1.0 : -1.0;
                CGFloat close = 1.0 - 0.80 * fabs(cos(_phase * 1.6));
                x += side * baseRX * close * 0.92;
                y += (i % 2 ? 1.0 : -1.0) * h * 0.06 * close;
            }
            if (mGravity) {
                // 坠珠：像一串珠子挂在环上，随电平被顶起来
                y += h * 0.17 * (0.5 + 0.5 * sin(_phase * 1.3 + (CGFloat)i * 0.55)) * (1.0 - 0.55 * energy);
            }

            CGFloat dot = (1.4 + 3.0 * lv) * dotScale * baseScale
                          * (0.55 + 0.45 * lit) * (1.0 + 0.45 * fabs(kick));
            if (mPump) dot *= (0.85 + 0.5 * energy);

            UIColor *color;
            if (self.haloRainbow) {
                color = nineColor(i + colorShift, baseAlpha * (0.18 + 0.82 * lit));
            } else {
                color = [[self colorForBar:(i % kANVSrcBars)] colorWithAlphaComponent:baseAlpha * (0.18 + 0.82 * lit)];
            }

            // 彗尾：点亮的那颗拖一条短尾巴
            if (mComet && pass == 0 && lit > 0.20) {
                CGFloat a2 = a - 0.13;
                CGPoint p2 = CGPointMake(center.x + cos(a2) * srx, center.y + sin(a2) * sry - hop);
                CGContextSetStrokeColorWithColor(ctx, [color colorWithAlphaComponent:0.42 * lit].CGColor);
                CGContextSetLineWidth(ctx, MAX(0.8, dot * 0.7));
                CGContextMoveToPoint(ctx, p2.x, p2.y);
                CGContextAddLineToPoint(ctx, x, y);
                CGContextStrokePath(ctx);
            }

            CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0 * (0.5 + lv) * (1.0 + 0.6 * fabs(kick)), color.CGColor);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y - dot, dot * 2.0, dot * 2.0));
        }
    }

    // 双环：里面再套一圈反向转的小点
    if (mDouble) {
        CGFloat rr = 0.60;
        NSInteger m = 8;
        for (NSInteger j = 0; j < m; j++) {
            CGFloat a = -_haloAngle * 1.35 + (CGFloat)j / (CGFloat)m * 2.0 * (CGFloat)M_PI;
            CGFloat lv = MAX(_haloDotLevel[j % n], 0.15);
            CGFloat r2x = baseRX * rr;
            CGFloat r2y = baseRY * rr;
            CGFloat x = center.x + cos(a) * r2x;
            CGFloat y = center.y + sin(a) * r2y + cos(a) * sway * r2y
                        + sin(_phase * 1.6 + (CGFloat)j) * h * 0.02;
            CGFloat dot = (1.2 + 2.0 * lv) * dotScale;
            UIColor *c = nineColor(j * 3 + (NSInteger)floor(_phase * 2.0), 0.50 + 0.40 * lv);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0 * lv, c.CGColor);
            CGContextSetFillColorWithColor(ctx, c.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y - dot, dot * 2.0, dot * 2.0));
        }
    }

    // 中心圆点：九色循环的彩虹球，跟着电平变大变亮，强拍往上弹
    CGFloat corePulse = self.haloBounce ? beat : 0.0;
    CGFloat coreR = (2.2 + 4.2 * energy + 2.2 * corePulse) * dotScale;
    if (mPump) coreR *= (0.85 + 0.55 * energy);
    CGFloat hop = self.haloBounce ? -h * 0.11 * corePulse : 0.0;
    if (mBurst) hop -= h * 0.05 * beat;
    CGFloat coreX = center.x;
    CGFloat coreY = center.y + hop;
    NSInteger sci = (NSInteger)floor(_phase * 2.2) % 9;

    UIColor *coreGlow = nineColor(sci, 0.16 + 0.26 * energy);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0 + 8.0 * energy + 6.0 * corePulse, coreGlow.CGColor);
    UIColor *core = nineColor(sci, 0.35 + 0.55 * energy);
    CGContextSetFillColorWithColor(ctx, core.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(coreX - coreR, coreY - coreR, coreR * 2.0, coreR * 2.0));

    UIColor *ringColor = nineColor(sci + 2, 0.22 + 0.45 * energy);
    CGContextSetStrokeColorWithColor(ctx, ringColor.CGColor);
    CGContextSetLineWidth(ctx, MAX(0.8, 1.2 * dotScale));
    CGFloat ringR = coreR * 1.55;
    CGContextStrokeEllipseInRect(ctx, CGRectMake(coreX - ringR, coreY - ringR, ringR * 2.0, ringR * 2.0));

    CGFloat hotR = MAX(0.8, coreR * 0.40);
    [[UIColor colorWithWhite:1.0 alpha:0.35 + 0.45 * energy] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(coreX - hotR, coreY - hotR, hotR * 2.0, hotR * 2.0));

    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 静音收敛：能量、弹跳包络、转速一起往 0 收，画面落回一圈暗点
- (void)settleSilence {
    _haloSmoothEnergy *= 0.82;
    _haloLastEnergy = _haloSmoothEnergy;
    _haloBeatPulse *= 0.8;
    _haloSpeed *= 0.75;
    if (_haloSpeed < 0.03) _haloSpeed = 0.0;
    if (_haloSmoothEnergy < 0.01) _haloSmoothEnergy = 0.0;
    [self setNeedsDisplay];
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

#pragma mark - 新增 10 种风格

/// 18 双螺旋：两条正弦光点绳随电平拉开
- (void)drawHelixInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 8);
    CGFloat step = CGRectGetWidth(c) / (CGFloat)n;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.08f);
        CGFloat x = CGRectGetMinX(c) + ((CGFloat)i + 0.5) * step;
        CGFloat amp = CGRectGetHeight(c) * 0.42 * (0.25 + level);
        CGFloat midY = CGRectGetMidY(c);
        CGFloat y1 = midY + sin(_phase * 2.2 + (CGFloat)i * 0.42) * amp;
        CGFloat y2 = midY - sin(_phase * 2.2 + (CGFloat)i * 0.42 + (CGFloat)M_PI) * amp;
        CGFloat dot = 1.2 + 2.6 * level;
        UIColor *c1 = [UIColor colorWithHue:fmod(0.55 + (CGFloat)i * 0.02 + _phase * 0.05, 1.0)
                                   saturation:1.0 brightness:1.0 alpha:0.95];
        UIColor *c2 = [UIColor colorWithHue:fmod(0.95 + (CGFloat)i * 0.02 + _phase * 0.05, 1.0)
                                   saturation:1.0 brightness:1.0 alpha:0.95];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, c1.CGColor);
        CGContextSetFillColorWithColor(ctx, c1.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y1 - dot, dot * 2, dot * 2));
        CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, c2.CGColor);
        CGContextSetFillColorWithColor(ctx, c2.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x - dot, y2 - dot, dot * 2, dot * 2));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 19 音柱爆点：点从中心按柱子角度向外炸开，半径吃电平
- (void)drawBurstInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    CGPoint mid = CGPointMake(CGRectGetMidX(c), CGRectGetMidY(c));
    CGFloat maxR = MIN(CGRectGetWidth(c), CGRectGetHeight(c)) * 0.48;
    NSInteger n = MAX(self.barCount, 8);
    for (NSInteger ring = 0; ring < 3; ring++) {
        CGFloat k = 0.35 + 0.28 * (CGFloat)ring;
        for (NSInteger i = 0; i < n; i++) {
            CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.08f);
            CGFloat a = (CGFloat)i / (CGFloat)n * 2.0 * (CGFloat)M_PI + _phase * 0.6 + ring * 0.4;
            CGFloat r = maxR * k * (0.25 + level) * (ring == 0 ? 1.0 : 1.25);
            CGFloat dot = 1.4 + 2.4 * level;
            UIColor *col = [self colorForBar:i];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0 * level, col.CGColor);
            CGContextSetFillColorWithColor(ctx,
                [col colorWithAlphaComponent:0.9 - 0.25 * (CGFloat)ring].CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(mid.x + cos(a) * r - dot,
                                                       mid.y + sin(a) * r - dot,
                                                       dot * 2, dot * 2));
        }
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 20 霓虹波浪：三层主流光正弦波，振幅/亮度吃电平
- (void)drawNeonWaveInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 10);
    for (NSInteger layer = 0; layer < 3; layer++) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        CGFloat yBase = CGRectGetMinY(c) + CGRectGetHeight(c) * (0.35 + 0.15 * (CGFloat)layer);
        for (NSInteger i = 0; i <= 40; i++) {
            CGFloat level = [self levelAtIndex:MIN((NSInteger)((CGFloat)i / 40.0 * (CGFloat)n), n - 1)];
            CGFloat x = CGRectGetMinX(c) + (CGFloat)i / 40.0 * CGRectGetWidth(c);
            CGFloat amp = CGRectGetHeight(c) * 0.26 * (0.2 + level);
            CGFloat y = yBase + sin(_phase * 3.0 + (CGFloat)i * 0.35 + (CGFloat)layer * 1.2) * amp;
            if (i == 0) [path moveToPoint:CGPointMake(x, y)];
            else [path addLineToPoint:CGPointMake(x, y)];
        }
        UIColor *col = [UIColor colorWithHue:fmod(0.58 + (CGFloat)layer * 0.12 + _phase * 0.06, 1.0)
                                   saturation:1.0 brightness:1.0
                                       alpha:1.0 - 0.22 * (CGFloat)layer];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        path.lineWidth = 2.0 - 0.4 * (CGFloat)layer;
        [path stroke];
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 21 旋转射线：从中心甩出光束，长度吃电平，整体旋转
- (void)drawSpokesInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    CGPoint mid = CGPointMake(CGRectGetMidX(c), CGRectGetMidY(c));
    CGFloat maxR = MIN(CGRectGetWidth(c), CGRectGetHeight(c)) * 0.5;
    NSInteger n = MAX(self.barCount, 8);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    for (NSInteger i = 0; i < n; i++) {
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.08f);
        CGFloat a = (CGFloat)i / (CGFloat)n * 2.0 * (CGFloat)M_PI + _phase * 1.1;
        CGFloat r = maxR * (0.2 + 0.8 * level);
        UIColor *col = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * level, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 2.6);
        CGContextMoveToPoint(ctx, mid.x + cos(a) * maxR * 0.12, mid.y + sin(a) * maxR * 0.12);
        CGContextAddLineToPoint(ctx, mid.x + cos(a) * r, mid.y + sin(a) * r);
        CGContextStrokePath(ctx);
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 22 脉冲光环：三层扩散圆环，半径按电平周期性外扩
- (void)drawPulseRingInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    CGPoint mid = CGPointMake(CGRectGetMidX(c), CGRectGetMidY(c));
    CGFloat maxR = MIN(CGRectGetWidth(c), CGRectGetHeight(c)) * 0.46;
    CGFloat bass = MAX([self levelAtIndex:0], 0.08f);
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat t = fmod(_phase * 0.45 + (CGFloat)i / 3.0, 1.0);
        CGFloat r = maxR * (0.18 + t) * (0.7 + 0.5 * bass);
        CGFloat alpha = (1.0 - t) * (0.35 + 0.6 * bass);
        UIColor *col = [UIColor colorWithHue:fmod(0.62 + t * 0.5 + _phase * 0.05, 1.0)
                                   saturation:1.0 brightness:1.0 alpha:alpha];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 9.0, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 2.2);
        CGContextAddEllipseInRect(ctx, CGRectMake(mid.x - r, mid.y - r, r * 2, r * 2));
        CGContextStrokePath(ctx);
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 23 横向流星：光条横向飞过，亮度吃电平
- (void)drawMeteorInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    NSInteger n = MAX(self.barCount, 8);
    for (NSInteger i = 0; i < n; i++) {
        CGFloat level = MAX([self levelAtIndex:(i % kANVSrcBars)], 0.08f);
        CGFloat y = CGRectGetMinY(c) + ((CGFloat)i + 0.5) / (CGFloat)n * CGRectGetHeight(c);
        CGFloat x = CGRectGetMinX(c) + fmod(_phase * (70.0 + 30.0 * (CGFloat)(i % 3)) + (CGFloat)i * 60.0,
                                           CGRectGetWidth(c) + 60.0) - 30.0;
        CGFloat len = 16.0 + 44.0 * level;
        CGFloat h = 1.4 + 2.2 * level;
        UIColor *col = [self colorForBar:i];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * level, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, h);
        CGContextMoveToPoint(ctx, x, y);
        CGContextAddLineToPoint(ctx, x + len, y);
        CGContextStrokePath(ctx);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.85].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x + len - 1.6, y - 1.6, 3.2, 3.2));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 24 对称羽翼：以中线为中心左右对称展开的羽状光柱
- (void)drawWingsInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    CGPoint mid = CGPointMake(CGRectGetMidX(c), CGRectGetMidY(c));
    NSInteger half = MAX(self.barCount / 2, 4);
    CGFloat slot = CGRectGetWidth(c) / 2.0 / (CGFloat)half;
    for (NSInteger i = 0; i < half; i++) {
        CGFloat level = MAX([self levelAtIndex:(i * 2) % kANVSrcBars], 0.08f);
        CGFloat len = CGRectGetHeight(c) * 0.46 * (0.2 + level);
        UIColor *col = [self colorForBar:i * 2];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0 * level, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, MAX(1.2, slot * 0.55));
        for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
            CGFloat a = (CGFloat)M_PI + sgn * ((CGFloat)i / (CGFloat)half) * 0.75;
            CGContextMoveToPoint(ctx, mid.x, mid.y);
            CGContextAddLineToPoint(ctx, mid.x + cos(a) * len, mid.y - sin(a) * len * 0.55);
            CGContextStrokePath(ctx);
        }
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 25 等离子云：几团软光斑叠加，颜色跟电平走
- (void)drawPlasmaInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    NSInteger blobs = 5;
    for (NSInteger i = 0; i < blobs; i++) {
        CGFloat level = MAX([self levelAtIndex:(NSInteger)(i * kANVSrcBars / blobs)], 0.1f);
        CGFloat x = CGRectGetMinX(c) + CGRectGetWidth(c) *
                    (0.2 + 0.6 * (0.5 + 0.5 * sin(_phase * 1.3 + (CGFloat)i * 1.7)));
        CGFloat y = CGRectGetMidY(c) + sin(_phase * 1.9 + (CGFloat)i * 2.1) * CGRectGetHeight(c) * 0.22;
        CGFloat r = CGRectGetHeight(c) * (0.18 + 0.32 * level);
        UIColor *col = [UIColor colorWithHue:fmod(0.68 + (CGFloat)i * 0.06 + _phase * 0.04, 1.0)
                                   saturation:0.9 brightness:1.0
                                       alpha:0.35 + 0.5 * level];
        CGGradientRef g = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)
            @[(id)col.CGColor, (id)[col colorWithAlphaComponent:0.0].CGColor], NULL);
        CGContextDrawRadialGradient(ctx, g, CGPointMake(x, y), 0,
                                   CGPointMake(x, y), r, 0);
        CGGradientRelease(g);
    }
}

/// 26 激光矩阵：网格点阵按柱位电平点亮
- (void)drawLaserGridInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    NSInteger cols = MAX(self.barCount, 8);
    NSInteger rows = 3;
    CGFloat cw = CGRectGetWidth(c) / (CGFloat)cols;
    CGFloat ch = CGRectGetHeight(c) / (CGFloat)rows;
    for (NSInteger y = 0; y < rows; y++) {
        for (NSInteger x = 0; x < cols; x++) {
            CGFloat level = [self levelAtIndex:(x % kANVSrcBars)];
            CGFloat lit = MIN(1.0, MAX(0.0, level * 1.6 - (CGFloat)(rows - 1 - y) * 0.28));
            if (lit <= 0.02) continue;
            CGFloat dot = 1.1 + 2.0 * lit;
            UIColor *col = [UIColor colorWithHue:fmod(0.72 + (CGFloat)x * 0.03 + _phase * 0.06, 1.0)
                                       saturation:0.85 brightness:1.0 alpha:0.35 + 0.6 * lit];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0 * lit, col.CGColor);
            CGContextSetFillColorWithColor(ctx, col.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMinX(c) + ((CGFloat)x + 0.5) * cw - dot,
                                                       CGRectGetMinY(c) + ((CGFloat)y + 0.5) * ch - dot,
                                                       dot * 2, dot * 2));
        }
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 27 心跳光带：一条随低频起伏的主光带 + 两端流光
- (void)drawBeatBeamInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect c = [self contentRectForRect:rect];
    CGFloat bass = MAX([self levelAtIndex:0], 0.06f);
    CGFloat mid = [self levelAtIndex:kANVSrcBars / 2];
    CGFloat h = CGRectGetHeight(c) * (0.10 + 0.36 * bass);
    CGFloat y = CGRectGetMidY(c) - h / 2.0;
    UIColor *col = [UIColor colorWithHue:fmod(0.55 + bass * 0.35 + _phase * 0.05, 1.0)
                               saturation:1.0 brightness:1.0 alpha:0.9];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 14.0 * bass, col.CGColor);
    UIBezierPath *beam = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMinX(c) + 2, y,
                                                            CGRectGetWidth(c) - 4, h) cornerRadius:h / 2.0];
    [[col colorWithAlphaComponent:0.75] setFill];
    [beam fill];
    CGFloat lit = 0.4 + 0.6 * mid;
    CGFloat x = CGRectGetMinX(c) + 2 + (CGRectGetWidth(c) - 4) *
                (0.5 + 0.5 * sin(_phase * 2.6));
    UIColor *spark = [UIColor colorWithWhite:1.0 alpha:lit];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0, spark.CGColor);
    CGContextSetFillColorWithColor(ctx, spark.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(x - h * 0.6, CGRectGetMidY(c) - h * 0.6, h * 1.2, h * 1.2));
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
        case ANVSpectrumStyleHelix:
            [self drawHelixInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleBurst:
            [self drawBurstInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleNeonWave:
            [self drawNeonWaveInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleSpokes:
            [self drawSpokesInContext:ctx rect:rect];
            break;
        case ANVSpectrumStylePulseRing:
            [self drawPulseRingInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleMeteor:
            [self drawMeteorInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleWings:
            [self drawWingsInContext:ctx rect:rect];
            break;
        case ANVSpectrumStylePlasma:
            [self drawPlasmaInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleLaserGrid:
            [self drawLaserGridInContext:ctx rect:rect];
            break;
        case ANVSpectrumStyleBeatBeam:
            [self drawBeatBeamInContext:ctx rect:rect];
            break;
        default:
            [self drawBarsInContext:ctx rect:rect mirrored:NO];
            break;
    }
}

@end
