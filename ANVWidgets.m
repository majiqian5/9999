#import "ANVWidgets.h"

#pragma mark - 彩虹字

static void ANVDrawRainbowText(NSString *text, CGRect rect, CGFloat fontSize,
                               CGFloat phase, BOOL scrolling) {
    if (!text.length) return;
    UIFont *font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightHeavy];
    NSDictionary *attrs = @{NSFontAttributeName: font};
    CGSize size = [text sizeWithAttributes:attrs];
    CGFloat avail = CGRectGetWidth(rect) - 8.0;

    // 只有装不下才滚，装得下就居中定住
    CGFloat x = CGRectGetMinX(rect) + 4.0;
    CGFloat y = CGRectGetMidY(rect) - size.height / 2.0;
    if (scrolling && size.width > avail) {
        CGFloat span = size.width + avail;
        CGFloat offset = fmod(phase * 28.0, span);
        x = CGRectGetMinX(rect) + CGRectGetWidth(rect) - 4.0 - offset;
    } else if (size.width <= avail) {
        x = CGRectGetMidX(rect) - size.width / 2.0;
    }

    // 关键：把字裁在牌子/气泡里，绝不会跑到气泡外面
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectInset(rect, 3.0, 1.0));
    }

    CGFloat cursor = x;
    NSInteger n = (NSInteger)text.length;
    for (NSInteger i = 0; i < n; i++) {
        NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
        CGFloat t = (CGFloat)i / (CGFloat)MAX(n - 1, 1);
        CGFloat hue = fmod(t * 0.83 + phase * 0.12, 1.0);
        UIColor *color = [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0];
        CGSize chSize = [ch sizeWithAttributes:attrs];
        [ch drawAtPoint:CGPointMake(cursor, y)
           withAttributes:@{NSFontAttributeName: font,
                            NSForegroundColorAttributeName: color}];
        cursor += chSize.width;
    }
    if (ctx) CGContextRestoreGState(ctx);
}

// 歌词牌 / 独立歌词条共用的「亮玻璃」胶囊：不再是黑块
static void ANVDrawFrostedCapsule(CGContextRef ctx, CGRect rect, CGFloat hue, CGFloat radius, CGFloat opacity) {
    UIBezierPath *cap = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.92 * opacity].CGColor,
                        (id)[UIColor colorWithWhite:0.96 alpha:0.80 * opacity].CGColor,
                        (id)[UIColor colorWithWhite:0.90 alpha:0.70 * opacity].CGColor];
    CGGradientRef grad = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0,
        [UIColor colorWithHue:hue saturation:0.9 brightness:1.0 alpha:0.45].CGColor);
    CGContextAddPath(ctx, cap.CGPath);
    CGContextClip(ctx);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)), 0);
    CGContextRestoreGState(ctx);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);

    [[UIColor colorWithHue:hue saturation:0.85 brightness:1.0 alpha:0.75] setStroke];
    cap.lineWidth = 1.3;
    [cap stroke];
}

#pragma mark - 五只宠物（取自 com.doubao.ccpet，100×100 逻辑坐标）

static void PetEllipse(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat rx, CGFloat ry, UIColor *color) {
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextAddEllipseInRect(c, CGRectMake(cx - rx, cy - ry, rx * 2, ry * 2));
    CGContextFillPath(c);
    CGContextRestoreGState(c);
}

static void PetCircle(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat r, UIColor *color) {
    PetEllipse(c, cx, cy, r, r, color);
}

static void PetStroke(CGContextRef c, UIBezierPath *path, UIColor *color, CGFloat width) {
    CGContextSaveGState(c);
    CGContextSetStrokeColorWithColor(c, color.CGColor);
    CGContextSetLineWidth(c, width);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextAddPath(c, path.CGPath);
    CGContextStrokePath(c);
    CGContextRestoreGState(c);
}

static void PetFill(CGContextRef c, UIBezierPath *path, UIColor *color) {
    CGContextSaveGState(c);
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextAddPath(c, path.CGPath);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
}

static UIColor *PetShade(UIColor *base, CGFloat factor) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![base getRed:&r green:&g blue:&b alpha:&a]) return base;
    return [UIColor colorWithRed:MIN(1, r * factor) green:MIN(1, g * factor)
                            blue:MIN(1, b * factor) alpha:a];
}

static UIColor *ANVBodyColorForStyle(NSInteger style) {
    switch (style) {
        case 1: return [UIColor colorWithRed:1.0 green:0.84 blue:0.30 alpha:1];   // 电气黄
        case 2: return [UIColor colorWithRed:1.0 green:0.70 blue:0.80 alpha:1];   // 樱花粉
        case 3: return [UIColor colorWithRed:0.20 green:0.24 blue:0.32 alpha:1];  // 墨蓝企鹅
        case 4: return [UIColor colorWithRed:0.95 green:0.97 blue:1.0 alpha:1];   // 幽灵白
        case 5: return [UIColor colorWithRed:0.42 green:0.85 blue:0.50 alpha:1];  // 草绿小恐龙
        case 6: return [UIColor colorWithRed:0.95 green:0.72 blue:0.45 alpha:1];  // 柴犬橘
        case 7: return [UIColor colorWithRed:1.00 green:0.88 blue:0.30 alpha:1];  // 小黄鸭
        case 8: return [UIColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1];  // 熊猫白
        case 9: return [UIColor colorWithRed:0.88 green:0.82 blue:1.00 alpha:1];  // 独角兽紫
        default: return [UIColor colorWithRed:0.62 green:0.85 blue:1.0 alpha:1];  // 天蓝团子
    }
}

static void ANVStrokeEyes(CGContextRef c, CGPoint l, CGPoint r, CGFloat rad,
                          UIColor *dark, BOOL closed) {
    if (closed) {
        for (NSInteger i = 0; i < 2; i++) {
            CGPoint p = (i == 0) ? l : r;
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(p.x, p.y + rad)
                                                              radius:rad
                                                          startAngle:M_PI
                                                            endAngle:0
                                                           clockwise:YES];
            PetStroke(c, arc, dark, 2.0);
        }
        return;
    }
    UIColor *white = [UIColor colorWithWhite:1 alpha:0.9];
    for (NSInteger i = 0; i < 2; i++) {
        CGPoint p = (i == 0) ? l : r;
        PetCircle(c, p.x, p.y, rad, dark);
        PetCircle(c, p.x - rad * 0.35, p.y - rad * 0.35, rad * 0.34, white);
    }
}

#pragma mark - ANVPetView

@implementation ANVPetView {
    CGFloat _phase;
    CGFloat _actionPhase;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        _sizeScale = 1.0;
        _energy = 0.0;
        _textScale = 1.0;
        _style = 0;
        _partnerStyle = 1;
        _action = 0;
        _petCount = 1;
        _petSideMode = 0;
        _bubbleW = 120.0;
        _bubbleH = 24.0;
        _bubbleAlpha = 0.85;
        _songProgress = 0.0;
        _songProgressValid = NO;
    }
    return self;
}

- (void)setSizeScale:(CGFloat)sizeScale {
    _sizeScale = MIN(MAX(sizeScale, 0.6), 1.6);
    [self setNeedsDisplay];
}

- (void)setTextScale:(CGFloat)textScale {
    _textScale = MIN(MAX(textScale, 0.6), 1.6);
    [self setNeedsDisplay];
}

- (void)setLyricText:(NSString *)lyricText {
    if ([_lyricText isEqualToString:lyricText]) return;
    _lyricText = [lyricText copy];
    [self setNeedsDisplay];
}

- (void)setEnergy:(CGFloat)energy {
    _energy = MIN(MAX(energy, 0.0), 1.0);
}

- (void)setStyle:(NSInteger)style {
    _style = MIN(MAX(style, 0), 9);
    [self setNeedsDisplay];
}

- (void)setPartnerStyle:(NSInteger)partnerStyle {
    _partnerStyle = MIN(MAX(partnerStyle, 0), 9);
    [self setNeedsDisplay];
}

- (void)setPetSideMode:(NSInteger)petSideMode {
    _petSideMode = MIN(MAX(petSideMode, 0), 2);
    [self setNeedsDisplay];
}

- (void)setPetCount:(NSInteger)petCount {
    _petCount = MIN(MAX(petCount, 1), 5);
    [self setNeedsDisplay];
}

- (void)setAction:(NSInteger)action {
    NSInteger clamped = MIN(MAX(action, 0), [ANVPetView actionCount] - 1);
    if (clamped != _action) _actionPhase = 0.0;
    _action = clamped;
    [self setNeedsDisplay];
}

+ (NSInteger)actionCount { return 22; }

+ (NSString *)titleForAction:(NSInteger)action {
    switch (MIN(MAX(action, 0), 21)) {
        case 0:  return @"发呆";
        case 1:  return @"点头";
        case 2:  return @"跳舞";
        case 3:  return @"荡秋千";
        case 4:  return @"打架";
        case 5:  return @"谈恋爱";
        case 6:  return @"唱歌";
        case 7:  return @"招手";
        case 8:  return @"转圈";
        case 9:  return @"睡觉";
        case 10: return @"蹦跳";
        case 11: return @"甩尾巴";
        case 12: return @"送花";
        case 13: return @"打滚";
        case 14: return @"吹泡泡";
        case 15: return @"星星环绕";
        case 16: return @"爱心发射";
        case 17: return @"走动";
        case 18: return @"翻跟头";
        case 19: return @"开枪扫射";
        case 20: return @"放烟花";
        default: return @"迪斯科";
    }
}

+ (NSString *)titleForStyle:(NSInteger)style {
    switch (MIN(MAX(style, 0), 9)) {
        case 1:  return @"电气狐";
        case 2:  return @"樱花猫";
        case 3:  return @"企鹅";
        case 4:  return @"小幽灵";
        case 5:  return @"小恐龙";
        case 6:  return @"柴犬";
        case 7:  return @"小黄鸭";
        case 8:  return @"熊猫";
        case 9:  return @"独角兽";
        default: return @"蓝团子";
    }
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    _actionPhase += delta;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    NSInteger count = MIN(MAX(self.petCount, 1), 5);
    CGFloat side = CGRectGetHeight(rect);
    if (side < 12.0) return;
    CGFloat W = CGRectGetWidth(rect);
    NSInteger mode = MIN(MAX(self.petSideMode, 0), 2);

    NSInteger leftN = count, rightN = 0;
    CGFloat leftX = CGRectGetMinX(rect), rightX = 0;
    if (mode == 2) {
        leftN = (count + 1) / 2;
        rightN = count - leftN;
        rightX = CGRectGetMaxX(rect) - side * rightN;
    } else if (mode == 1) {
        leftN = 0; rightN = count;
        rightX = CGRectGetMaxX(rect) - side * count;
    }

    // 招牌位置：左边 / 右边 / 居中（两侧时挂中间）
    if (self.lyricText.length) {
        CGFloat bw = MIN(MAX(self.bubbleW, 60.0), MAX(W - 4.0, 60.0));
        CGFloat bh = MIN(MAX(self.bubbleH, 16.0), 44.0);
        CGFloat x = CGRectGetMaxX(rect) - bw - 2.0;
        if (mode == 1) x = CGRectGetMinX(rect) + 2.0;
        else if (mode == 2) x = (W - bw) / 2.0;
        x += self.bubbleDX;
        CGFloat y = CGRectGetMinY(rect) - bh * 0.10 + self.bubbleDY;
        [self drawSignInContext:ctx rect:CGRectMake(x, y, bw, bh)];
    }

    // 走动/翻跟头占用群外空隙
    CGFloat walkRoom = MAX(0.0, W - side * count) * 0.5;
    CGFloat walkX = 0.0;
    if (_action == 17) walkX = (0.5 - 0.5 * cos(_actionPhase * 1.1)) * walkRoom;
    else if (_action == 18) walkX = (0.5 - 0.5 * cos(_actionPhase * 1.8)) * walkRoom;

    if (leftN > 0) {
        [self drawGroupInContext:ctx startX:leftX walkX:walkX count:leftN
                          origin:0 side:side bottom:CGRectGetMaxY(rect)];
    }
    if (rightN > 0) {
        [self drawGroupInContext:ctx startX:rightX walkX:-walkX count:rightN
                          origin:leftN side:side bottom:CGRectGetMaxY(rect)];
    }

    // 气氛装饰跟着整体
    CGRect herd = CGRectMake(CGRectGetMinX(rect) + walkX, CGRectGetMinY(rect), side * count, side);
    switch (_action) {
        case 2:
        case 6:  [self drawNotesAround:ctx rect:herd]; break;
        case 5:
        case 16: [self drawHeartsAround:ctx rect:herd]; break;
        case 9:  [self drawZZZ:ctx rect:herd]; break;
        case 14: [self drawBubblesAround:ctx rect:herd]; break;
        case 15: [self drawStarsOrbit:ctx rect:herd]; break;
        case 19: [self drawGunfire:ctx rect:herd]; break;
        case 20: [self drawFireworks:ctx rect:herd]; break;
        case 21: [self drawDisco:ctx rect:herd]; break;
        default: break;
    }
}

/// 画一群宠物（index 从 origin 开始编号，保证每只造型/相位不同）
- (void)drawGroupInContext:(CGContextRef)ctx startX:(CGFloat)startX walkX:(CGFloat)walkX
                      count:(NSInteger)n origin:(NSInteger)origin
                       side:(CGFloat)side bottom:(CGFloat)bottom {
    NSInteger act = MIN(MAX(_action, 0), 21);
    for (NSInteger k = 0; k < n; k++) {
        NSInteger gi = origin + k;
        CGFloat t = _phase + (CGFloat)gi * 0.55;
        CGFloat at = _actionPhase + (CGFloat)gi * 0.45;
        CGFloat dx = walkX, dy = 0, rot = 0, sy = 1.0;
        BOOL eyesClosed = NO, mouthOpen = NO, pivotTop = NO;

        // 跟音乐互动：有节奏时整群一起蹦一下
        if (_energy > 0.05) {
            CGFloat beat = MAX(0.0, sin(_phase * (4.0 + _energy * 3.0) + (CGFloat)gi * 0.9));
            dy -= beat * side * 0.10 * (0.3 + _energy);
        }

        switch (act) {
            case 1: dy -= fabs(sin(t * 4.2)) * side * 0.05 * (0.4 + _energy); break;
            case 2: {
                CGFloat beat = sin(t * (5.0 + _energy * 4.0));
                dx += beat * side * 0.06;
                dy -= fabs(beat) * side * 0.14;
                rot = beat * 0.18;
                sy = 1.0 - fabs(beat) * 0.05;
                mouthOpen = YES;
                break;
            }
            case 3: rot = sin(at * 1.5) * 0.55; pivotTop = YES; break;
            case 4: dx += sin(at * 8.0) * side * 0.10; rot = sin(at * 8.0) * 0.12; break;
            case 5: rot = (gi % 2 == 0 ? 1.0 : -1.0) * 0.10; break;
            case 6: mouthOpen = YES; rot = sin(t * 2.0) * 0.04; break;
            case 7: rot = sin(t * 6.0 + (CGFloat)gi) * 0.10; break;
            case 8: rot = sin(at * 2.2 + (CGFloat)gi) * 0.30; break;
            case 9: eyesClosed = YES; sy = 1.0 - (0.5 + 0.5 * sin(t * 1.2)) * 0.03; break;
            case 10: {
                CGFloat j = MAX(0.0, sin(at * 4.0 + (CGFloat)gi));
                dy -= j * side * 0.18;
                sy = 1.0 + j * 0.04;
                break;
            }
            case 11: rot = sin(t * 7.0) * 0.07; break;
            case 12: rot = (gi % 2 == 0 ? -0.14 : 0.10); break;
            case 13: rot = at * 2.0; pivotTop = YES; break;
            case 15: rot = sin(t * 1.6 + (CGFloat)gi) * 0.10; break;
            case 16: dy -= fabs(sin(at * 2.2 + (CGFloat)gi)) * side * 0.10; break;
            case 17: dy -= fabs(sin(at * 5.5 + (CGFloat)gi)) * side * 0.06;
                     rot = sin(at * 5.5 + (CGFloat)gi) * 0.05; break;
            case 18: rot = at * 4.4; break;
            default: dy -= fabs(sin(t * 3.0)) * 2.0 * (0.35 + _energy); break;
        }

        CGRect petRect = CGRectMake(startX + (CGFloat)k * side + dx, bottom - side * sy + dy,
                                    side, side * sy);

        if (act == 3) {
            CGPoint anchor = CGPointMake(CGRectGetMidX(petRect), CGRectGetMinY(petRect) - side * 0.20);
            CGPoint seat = CGPointMake(CGRectGetMidX(petRect), CGRectGetMaxY(petRect) - side * 0.80);
            CGContextSaveGState(ctx);
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.35].CGColor);
            CGContextSetLineWidth(ctx, 1.0);
            for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
                CGContextMoveToPoint(ctx, anchor.x, anchor.y);
                CGContextAddLineToPoint(ctx, seat.x + sgn * side * 0.22, seat.y);
                CGContextStrokePath(ctx);
            }
            CGContextRestoreGState(ctx);
        }

        CGContextSaveGState(ctx);
        if (rot != 0.0) {
            CGPoint pv = pivotTop ? CGPointMake(CGRectGetMidX(petRect), CGRectGetMinY(petRect))
                                  : CGPointMake(CGRectGetMidX(petRect), CGRectGetMidY(petRect));
            CGContextTranslateCTM(ctx, pv.x, pv.y);
            CGContextRotateCTM(ctx, rot);
            CGContextTranslateCTM(ctx, -pv.x, -pv.y);
        }
        [self drawPetInContext:ctx rect:petRect
                          style:((self.style + gi) % 10)
                      eyeClosed:eyesClosed
                      mouthOpen:mouthOpen];
        CGContextRestoreGState(ctx);
    }
}

- (void)drawSignInContext:(CGContextRef)ctx rect:(CGRect)rect {
    CGRect board = CGRectInset(rect, 1.0, 1.0);
    board.size.height = MAX(16.0, board.size.height);
    CGFloat radius = MIN(CGRectGetHeight(board) / 2.0, 11.0);
    ANVDrawFrostedCapsule(ctx, board, 0.75, radius, self.bubbleAlpha);

    UIBezierPath *tail = [UIBezierPath bezierPath];
    [tail moveToPoint:CGPointMake(CGRectGetMinX(board) + 6.0, CGRectGetMaxY(board) - 2.0)];
    [tail addLineToPoint:CGPointMake(CGRectGetMinX(board) + 2.0, CGRectGetMaxY(board) + radius * 0.8)];
    [tail addLineToPoint:CGPointMake(CGRectGetMinX(board) + 15.0, CGRectGetMaxY(board) - 2.0)];
    [tail closePath];
    [[UIColor colorWithWhite:1.0 alpha:0.82] setFill];
    [tail fill];

    ANVDrawRainbowText(self.lyricText, board,
                       MAX(7.0, CGRectGetHeight(board) * 0.48 * self.textScale),
                       _phase, YES);

    [self drawBubbleProgressInContext:ctx board:board];
}

/// 气泡彩虹边框 = 歌曲进度环：九色环绕，随歌曲时间越走越短
/// 圆角矩形周长取点：d 为从左上角起顺时针走的距离
static CGPoint ANVRoundRectPoint(CGRect r, CGFloat rad, CGFloat d) {
    CGFloat w = CGRectGetWidth(r), h = CGRectGetHeight(r);
    rad = MIN(rad, MIN(w, h) / 2.0);
    CGFloat L1 = MAX(w - 2.0 * rad, 0.0);        // 上下直边
    CGFloat L2 = MAX(h - 2.0 * rad, 0.0);        // 左右直边
    CGFloat arc = (CGFloat)M_PI_2 * rad;

    CGFloat segs[8] = {L1, arc, L2, arc, L1, arc, L2, arc};
    CGFloat dd = fmod(d, 2.0 * L1 + 2.0 * L2 + 4.0 * arc);
    if (dd < 0) dd += 2.0 * L1 + 2.0 * L2 + 4.0 * arc;
    NSInteger i = 0;
    while (i < 8 && dd > segs[i]) { dd -= segs[i]; i++; }

    CGFloat minX = CGRectGetMinX(r), minY = CGRectGetMinY(r);
    CGFloat maxX = CGRectGetMaxX(r), maxY = CGRectGetMaxY(r);
    switch (i) {
        case 0: return CGPointMake(minX + rad + dd, minY);                       // 上边
        case 1: { CGFloat a = -M_PI_2 + dd / MAX(rad, 0.001);
                  return CGPointMake(maxX - rad + rad * cos(a), minY + rad + rad * sin(a)); }
        case 2: return CGPointMake(maxX, minY + rad + dd);                       // 右边
        case 3: { CGFloat a = dd / MAX(rad, 0.001);
                  return CGPointMake(maxX - rad + rad * cos(a), maxY - rad + rad * sin(a)); }
        case 4: return CGPointMake(maxX - rad - dd, maxY);                       // 下边
        case 5: { CGFloat a = M_PI_2 + dd / MAX(rad, 0.001);
                  return CGPointMake(minX + rad + rad * cos(a), maxY - rad + rad * sin(a)); }
        case 6: return CGPointMake(minX, maxY - rad - dd);                       // 左边
        default: { CGFloat a = M_PI + dd / MAX(rad, 0.001);
                  return CGPointMake(minX + rad + rad * cos(a), minY + rad + rad * sin(a)); }
    }
}

/// 歌曲进度直接画在气泡原有的紫色边框上（不额外加框）
- (void)drawBubbleProgressInContext:(CGContextRef)ctx board:(CGRect)board {
    CGRect r = CGRectInset(board, 0.6, 0.6);
    if (CGRectGetWidth(r) < 16.0 || CGRectGetHeight(r) < 12.0) return;
    CGFloat rad = MIN(CGRectGetHeight(r) / 2.0, 11.0);

    if (!self.songProgressValid) return;      // 没有歌曲就保持原紫色描边

    static CGFloat const hues[9] = {0.00, 0.09, 0.14, 0.33, 0.48, 0.58, 0.72, 0.88, 0.00};
    static CGFloat const sats[9] = {0.95, 1.00, 0.95, 1.00, 0.90, 0.95, 0.85, 0.80, 0.00};

    CGFloat w = CGRectGetWidth(r), h = CGRectGetHeight(r);
    CGFloat P = 2.0 * MAX(w - 2.0 * rad, 0.0) + 2.0 * MAX(h - 2.0 * rad, 0.0)
                + 4.0 * (CGFloat)M_PI_2 * rad;
    CGFloat remain = MAX(0.0, 1.0 - MIN(MAX(self.songProgress, 0.0), 1.0));
    CGFloat span = P * remain;
    if (span < 2.0) return;

    NSInteger segs = MAX(24, MIN(96, (NSInteger)(span / 3.0)));
    for (NSInteger i = 0; i < segs; i++) {
        CGFloat d0 = span * (CGFloat)i / (CGFloat)segs;
        CGFloat d1 = span * (CGFloat)(i + 1) / (CGFloat)segs + 0.8;
        CGPoint p0 = ANVRoundRectPoint(r, rad, d0);
        CGPoint p1 = ANVRoundRectPoint(r, rad, d1);
        NSInteger ci = (NSInteger)(i * 9 / segs) % 9;
        UIColor *col = [UIColor colorWithHue:hues[ci] saturation:sats[ci]
                                  brightness:1.0 alpha:0.95];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 4.0, col.CGColor);
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 1.9);
        CGContextMoveToPoint(ctx, p0.x, p0.y);
        CGContextAddLineToPoint(ctx, p1.x, p1.y);
        CGContextStrokePath(ctx);
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);

    // 进度头亮点
    CGPoint head = ANVRoundRectPoint(r, rad, span);
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(head.x - 2.2, head.y - 2.2, 4.4, 4.4));
}

- (void)drawPetInContext:(CGContextRef)ctx rect:(CGRect)rect
                   style:(NSInteger)style eyeClosed:(BOOL)closed mouthOpen:(BOOL)open {
    CGFloat side = CGRectGetWidth(rect);
    if (side < 10.0) return;

    UIColor *body = ANVBodyColorForStyle(style);
    UIColor *accent = PetShade(body, 0.84);
    UIColor *dark = [UIColor colorWithWhite:(style == 3 ? 0.10 : 0.14) alpha:1];

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGContextScaleCTM(ctx, side / 100.0, side / 100.0);
    CGContextTranslateCTM(ctx, -50, -50);

    // 影子
    PetEllipse(ctx, 50, 92, 26, 5, [UIColor colorWithWhite:0 alpha:0.14]);

    if (style == 1) {                       // 电气狐
        UIBezierPath *earL = [UIBezierPath bezierPath];
        [earL moveToPoint:CGPointMake(32, 36)];
        [earL addQuadCurveToPoint:CGPointMake(20, 8) controlPoint:CGPointMake(22, 26)];
        [earL addQuadCurveToPoint:CGPointMake(44, 30) controlPoint:CGPointMake(34, 20)];
        PetFill(ctx, earL, body);
        UIBezierPath *earR = [UIBezierPath bezierPath];
        [earR moveToPoint:CGPointMake(68, 36)];
        [earR addQuadCurveToPoint:CGPointMake(80, 8) controlPoint:CGPointMake(78, 26)];
        [earR addQuadCurveToPoint:CGPointMake(56, 30) controlPoint:CGPointMake(66, 20)];
        PetFill(ctx, earR, body);
        PetFill(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectMake(17, 6, 12, 12)],
                [UIColor colorWithWhite:0.15 alpha:1]);
        PetFill(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectMake(71, 6, 12, 12)],
                [UIColor colorWithWhite:0.15 alpha:1]);

        PetEllipse(ctx, 50, 58, 27, 27, body);
        ANVStrokeEyes(ctx, CGPointMake(40, 52), CGPointMake(60, 52), 5.0, dark, closed);
        PetCircle(ctx, 30, 63, 5.0, [UIColor colorWithRed:0.95 green:0.32 blue:0.32 alpha:0.85]);
        PetCircle(ctx, 70, 63, 5.0, [UIColor colorWithRed:0.95 green:0.32 blue:0.32 alpha:0.85]);
        PetCircle(ctx, 50, 59, 1.6, dark);
        UIBezierPath *m1 = [UIBezierPath bezierPath];
        [m1 moveToPoint:CGPointMake(45, 67)];
        [m1 addQuadCurveToPoint:CGPointMake(55, 67) controlPoint:CGPointMake(50, open ? 74 : 71)];
        PetStroke(ctx, m1, dark, 1.8);
        UIBezierPath *tail = [UIBezierPath bezierPath];
        [tail moveToPoint:CGPointMake(76, 76)];
        [tail addLineToPoint:CGPointMake(84, 66)];
        [tail addLineToPoint:CGPointMake(80, 64)];
        [tail addLineToPoint:CGPointMake(92, 52)];
        [tail addLineToPoint:CGPointMake(86, 66)];
        [tail addLineToPoint:CGPointMake(91, 67)];
        [tail addLineToPoint:CGPointMake(80, 82)];
        PetFill(ctx, tail, [UIColor colorWithRed:1 green:0.78 blue:0.2 alpha:1]);
    } else if (style == 2) {                // 樱花猫
        UIBezierPath *earL = [UIBezierPath bezierPath];
        [earL moveToPoint:CGPointMake(30, 34)];
        [earL addLineToPoint:CGPointMake(28, 12)];
        [earL addLineToPoint:CGPointMake(48, 28)];
        PetFill(ctx, earL, body);
        UIBezierPath *earR = [UIBezierPath bezierPath];
        [earR moveToPoint:CGPointMake(70, 34)];
        [earR addLineToPoint:CGPointMake(72, 12)];
        [earR addLineToPoint:CGPointMake(52, 28)];
        PetFill(ctx, earR, body);
        PetFill(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectMake(31, 20, 9, 11)],
                [UIColor colorWithRed:1 green:0.78 blue:0.84 alpha:1]);
        PetFill(ctx, [UIBezierPath bezierPathWithOvalInRect:CGRectMake(60, 20, 9, 11)],
                [UIColor colorWithRed:1 green:0.78 blue:0.84 alpha:1]);

        PetCircle(ctx, 50, 57, 28, body);
        ANVStrokeEyes(ctx, CGPointMake(40, 52), CGPointMake(60, 52), 4.6, dark, closed);
        UIBezierPath *nose = [UIBezierPath bezierPath];
        [nose moveToPoint:CGPointMake(47, 63)];
        [nose addLineToPoint:CGPointMake(53, 63)];
        [nose addLineToPoint:CGPointMake(50, 67)];
        PetFill(ctx, nose, [UIColor colorWithRed:1 green:0.55 blue:0.66 alpha:1]);
        UIBezierPath *mouth = [UIBezierPath bezierPath];
        [mouth moveToPoint:CGPointMake(50, 67)];
        [mouth addQuadCurveToPoint:CGPointMake(44, 71) controlPoint:CGPointMake(47, open ? 73 : 72)];
        [mouth moveToPoint:CGPointMake(50, 67)];
        [mouth addQuadCurveToPoint:CGPointMake(56, 71) controlPoint:CGPointMake(53, open ? 73 : 72)];
        PetStroke(ctx, mouth, dark, 1.2);
        for (NSInteger k = 0; k < 2; k++) {
            CGFloat y = 61 + (CGFloat)k * 4;
            UIBezierPath *w1 = [UIBezierPath bezierPath];
            [w1 moveToPoint:CGPointMake(22, y)];
            [w1 addLineToPoint:CGPointMake(34, y + 1)];
            PetStroke(ctx, w1, [UIColor colorWithWhite:1 alpha:0.85], 1.0);
            UIBezierPath *w2 = [UIBezierPath bezierPath];
            [w2 moveToPoint:CGPointMake(78, y)];
            [w2 addLineToPoint:CGPointMake(66, y + 1)];
            PetStroke(ctx, w2, [UIColor colorWithWhite:1 alpha:0.85], 1.0);
        }
        PetCircle(ctx, 33, 65, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.7 alpha:0.5]);
        PetCircle(ctx, 67, 65, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.7 alpha:0.5]);
        UIBezierPath *tail2 = [UIBezierPath bezierPath];
        [tail2 moveToPoint:CGPointMake(76, 80)];
        [tail2 addQuadCurveToPoint:CGPointMake(92, 66) controlPoint:CGPointMake(96, 88)];
        PetStroke(ctx, tail2, accent, 5);
    } else if (style == 3) {                // 企鹅
        UIColor *white = [UIColor colorWithWhite:1 alpha:0.97];
        UIColor *orange = [UIColor colorWithRed:1 green:0.66 blue:0.2 alpha:1];
        PetEllipse(ctx, 50, 60, 26, 30, [UIColor colorWithWhite:0.10 alpha:1]);
        PetEllipse(ctx, 25, 62, 6, 14, [UIColor colorWithWhite:0.10 alpha:1]);
        PetEllipse(ctx, 75, 62, 6, 14, [UIColor colorWithWhite:0.10 alpha:1]);
        PetEllipse(ctx, 50, 62, 17, 22, white);
        ANVStrokeEyes(ctx, CGPointMake(42, 49), CGPointMake(58, 49), 4.4, dark, closed);
        UIBezierPath *beak = [UIBezierPath bezierPath];
        [beak moveToPoint:CGPointMake(45, 57)];
        [beak addLineToPoint:CGPointMake(55, 57)];
        [beak addLineToPoint:CGPointMake(50, open ? 66 : 64)];
        PetFill(ctx, beak, orange);
        PetEllipse(ctx, 38, 88, 8, 3.5, orange);
        PetEllipse(ctx, 62, 88, 8, 3.5, orange);
    } else if (style == 4) {                // 小幽灵
        UIBezierPath *body = [UIBezierPath bezierPath];
        [body moveToPoint:CGPointMake(24, 62)];
        [body addQuadCurveToPoint:CGPointMake(50, 22) controlPoint:CGPointMake(24, 24)];
        [body addQuadCurveToPoint:CGPointMake(76, 62) controlPoint:CGPointMake(76, 24)];
        [body addLineToPoint:CGPointMake(70, 74)];
        [body addQuadCurveToPoint:CGPointMake(62, 82) controlPoint:CGPointMake(66, 84)];
        [body addQuadCurveToPoint:CGPointMake(54, 74) controlPoint:CGPointMake(58, 84)];
        [body addQuadCurveToPoint:CGPointMake(46, 82) controlPoint:CGPointMake(50, 84)];
        [body addQuadCurveToPoint:CGPointMake(38, 74) controlPoint:CGPointMake(42, 84)];
        [body addQuadCurveToPoint:CGPointMake(30, 82) controlPoint:CGPointMake(34, 84)];
        [body addQuadCurveToPoint:CGPointMake(24, 62) controlPoint:CGPointMake(26, 80)];
        PetFill(ctx, body, [UIColor colorWithRed:0.96 green:0.98 blue:1 alpha:0.96]);
        ANVStrokeEyes(ctx, CGPointMake(41, 50), CGPointMake(59, 50), 4.4, dark, closed);
        PetCircle(ctx, 32, 60, 4.0, [UIColor colorWithRed:1 green:0.7 blue:0.78 alpha:0.5]);
        PetCircle(ctx, 68, 60, 4.0, [UIColor colorWithRed:1 green:0.7 blue:0.78 alpha:0.5]);
        UIBezierPath *mouth3 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(50, 58.5)
                                                              radius:open ? 3.8 : 3.2
                                                          startAngle:0 endAngle:M_PI clockwise:YES];
        PetStroke(ctx, mouth3, dark, 1.4);
    } else if (style == 5) {                // 小恐龙
        // 尾巴 + 背刺
        UIBezierPath *dt = [UIBezierPath bezierPath];
        [dt moveToPoint:CGPointMake(74, 72)];
        [dt addQuadCurveToPoint:CGPointMake(92, 60) controlPoint:CGPointMake(88, 78)];
        PetStroke(ctx, dt, accent, 6);
        for (NSInteger i = 0; i < 3; i++) {
            UIBezierPath *spike = [UIBezierPath bezierPath];
            CGFloat y = 40.0 + (CGFloat)i * 12.0;
            [spike moveToPoint:CGPointMake(28, y)];
            [spike addLineToPoint:CGPointMake(20, y - 5)];
            [spike addLineToPoint:CGPointMake(28, y - 9)];
            [spike closePath];
            PetFill(ctx, spike, [UIColor colorWithRed:1 green:0.62 blue:0.3 alpha:1]);
        }
        PetEllipse(ctx, 52, 58, 27, 24, body);
        PetEllipse(ctx, 40, 80, 9, 6, accent);
        PetEllipse(ctx, 64, 80, 9, 6, accent);
        ANVStrokeEyes(ctx, CGPointMake(42, 52), CGPointMake(62, 52), 5.0, dark, closed);
        PetCircle(ctx, 33, 64, 4.2, [UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:0.55]);
        PetCircle(ctx, 71, 64, 4.2, [UIColor colorWithRed:1 green:0.55 blue:0.55 alpha:0.55]);
        UIBezierPath *dm = [UIBezierPath bezierPath];
        [dm moveToPoint:CGPointMake(44, 68)];
        [dm addQuadCurveToPoint:CGPointMake(60, 68) controlPoint:CGPointMake(52, open ? 77 : 73)];
        PetStroke(ctx, dm, dark, 1.6);
    } else if (style == 6) {                // 柴犬
        UIBezierPath *e1 = [UIBezierPath bezierPath];
        [e1 moveToPoint:CGPointMake(30, 34)];
        [e1 addLineToPoint:CGPointMake(26, 14)];
        [e1 addLineToPoint:CGPointMake(44, 26)];
        PetFill(ctx, e1, accent);
        UIBezierPath *e2 = [UIBezierPath bezierPath];
        [e2 moveToPoint:CGPointMake(70, 34)];
        [e2 addLineToPoint:CGPointMake(74, 14)];
        [e2 addLineToPoint:CGPointMake(56, 26)];
        PetFill(ctx, e2, accent);
        PetCircle(ctx, 50, 56, 27, body);
        PetEllipse(ctx, 50, 68, 17, 11, [UIColor colorWithRed:1 green:0.97 blue:0.92 alpha:1]);
        ANVStrokeEyes(ctx, CGPointMake(40, 50), CGPointMake(60, 50), 4.6, dark, closed);
        PetEllipse(ctx, 50, 62, 4, 3, dark);
        UIBezierPath *sm = [UIBezierPath bezierPath];
        [sm moveToPoint:CGPointMake(44, 70)];
        [sm addQuadCurveToPoint:CGPointMake(56, 70) controlPoint:CGPointMake(50, open ? 78 : 74)];
        PetStroke(ctx, sm, dark, 1.5);
        PetCircle(ctx, 31, 64, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.6 alpha:0.5]);
        PetCircle(ctx, 69, 64, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.6 alpha:0.5]);
    } else if (style == 7) {                // 小黄鸭
        PetEllipse(ctx, 50, 60, 28, 26, body);
        PetEllipse(ctx, 38, 30, 15, 15, body);
        UIBezierPath *beak = [UIBezierPath bezierPath];
        [beak moveToPoint:CGPointMake(50, 28)];
        [beak addLineToPoint:CGPointMake(66, 34)];
        [beak addLineToPoint:CGPointMake(50, 40)];
        [beak closePath];
        PetFill(ctx, beak, [UIColor colorWithRed:1 green:0.58 blue:0.22 alpha:1]);
        PetCircle(ctx, 41, 26, 2.4, dark);
        ANVStrokeEyes(ctx, CGPointMake(42, 55), CGPointMake(62, 55), 4.6, dark, closed);
        PetEllipse(ctx, 30, 68, 10, 7, accent);
        UIBezierPath *wing = [UIBezierPath bezierPath];
        [wing moveToPoint:CGPointMake(30, 62)];
        [wing addQuadCurveToPoint:CGPointMake(46, 76) controlPoint:CGPointMake(26, 76)];
        PetStroke(ctx, wing, accent, 3);
        PetCircle(ctx, 31, 66, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.6 alpha:0.55]);
        PetCircle(ctx, 69, 66, 4.0, [UIColor colorWithRed:1 green:0.6 blue:0.6 alpha:0.55]);
    } else if (style == 8) {                // 熊猫
        PetCircle(ctx, 28, 30, 11, [UIColor colorWithWhite:0.16 alpha:1]);
        PetCircle(ctx, 72, 30, 11, [UIColor colorWithWhite:0.16 alpha:1]);
        PetCircle(ctx, 50, 58, 29, body);
        PetEllipse(ctx, 37, 52, 11, 13, [UIColor colorWithWhite:0.16 alpha:1]);
        PetEllipse(ctx, 63, 52, 11, 13, [UIColor colorWithWhite:0.16 alpha:1]);
        PetCircle(ctx, 37, 52, 4.6, [UIColor whiteColor]);
        PetCircle(ctx, 63, 52, 4.6, [UIColor whiteColor]);
        PetCircle(ctx, 37, 52, 2.6, dark);
        PetCircle(ctx, 63, 52, 2.6, dark);
        PetEllipse(ctx, 50, 64, 4, 3, dark);
        UIBezierPath *pm = [UIBezierPath bezierPath];
        [pm moveToPoint:CGPointMake(44, 69)];
        [pm addQuadCurveToPoint:CGPointMake(56, 69) controlPoint:CGPointMake(50, open ? 77 : 73)];
        PetStroke(ctx, pm, dark, 1.5);
        PetEllipse(ctx, 50, 82, 18, 7, [UIColor colorWithWhite:0.16 alpha:1]);
    } else if (style == 9) {                // 独角兽
        UIBezierPath *horn = [UIBezierPath bezierPath];
        [horn moveToPoint:CGPointMake(44, 34)];
        [horn addLineToPoint:CGPointMake(50, 6)];
        [horn addLineToPoint:CGPointMake(56, 34)];
        [horn closePath];
        PetFill(ctx, horn, [UIColor colorWithHue:0.55 saturation:0.6 brightness:1.0 alpha:1]);
        PetCircle(ctx, 50, 58, 28, body);
        // 鬃毛
        for (NSInteger i = 0; i < 4; i++) {
            UIColor *mc = [UIColor colorWithHue:fmod(0.92 + (CGFloat)i * 0.12, 1.0)
                                      saturation:0.9 brightness:1.0 alpha:1];
            PetCircle(ctx, 26 + (CGFloat)i * 5, 42 + (CGFloat)i * 9, 6.0, mc);
        }
        ANVStrokeEyes(ctx, CGPointMake(40, 52), CGPointMake(60, 52), 4.8, dark, closed);
        PetCircle(ctx, 50, 62, 2.6, [UIColor colorWithHue:0.9 saturation:0.9 brightness:1 alpha:1]);
        PetCircle(ctx, 31, 64, 4.2, [UIColor colorWithRed:1 green:0.7 blue:0.85 alpha:0.55]);
        PetCircle(ctx, 69, 64, 4.2, [UIColor colorWithRed:1 green:0.7 blue:0.85 alpha:0.55]);
        UIBezierPath *um = [UIBezierPath bezierPath];
        [um moveToPoint:CGPointMake(45, 68)];
        [um addQuadCurveToPoint:CGPointMake(55, 68) controlPoint:CGPointMake(50, open ? 76 : 72)];
        PetStroke(ctx, um, dark, 1.5);
        PetEllipse(ctx, 50, 84, 16, 6, accent);
    } else {                                // 蓝团子
        PetEllipse(ctx, 26, 30, 9, 15, accent);
        PetEllipse(ctx, 74, 30, 9, 15, accent);
        PetCircle(ctx, 50, 56, 30, body);
        ANVStrokeEyes(ctx, CGPointMake(39, 50), CGPointMake(61, 50), 5.2, dark, closed);
        PetCircle(ctx, 29, 62, 4.6, [UIColor colorWithRed:1 green:0.72 blue:0.78 alpha:0.6]);
        PetCircle(ctx, 71, 62, 4.6, [UIColor colorWithRed:1 green:0.72 blue:0.78 alpha:0.6]);
        UIBezierPath *mouth = [UIBezierPath bezierPath];
        [mouth moveToPoint:CGPointMake(45, 66)];
        [mouth addQuadCurveToPoint:CGPointMake(55, 66) controlPoint:CGPointMake(50, open ? 74 : 70)];
        PetStroke(ctx, mouth, dark, 1.8);
        UIBezierPath *tail3 = [UIBezierPath bezierPath];
        [tail3 moveToPoint:CGPointMake(77, 74)];
        [tail3 addQuadCurveToPoint:CGPointMake(88, 82) controlPoint:CGPointMake(92, 70)];
        PetStroke(ctx, tail3, accent, 6);
    }

    CGContextRestoreGState(ctx);
}

#pragma mark - 气氛装饰

static void ANVFilledHeart(CGContextRef ctx, CGPoint c, CGFloat s, UIColor *color) {
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - s * 0.92, c.y - s * 0.85, s * 0.92, s * 0.92));
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x, c.y - s * 0.85, s * 0.92, s * 0.92));
    UIBezierPath *tri = [UIBezierPath bezierPath];
    [tri moveToPoint:CGPointMake(c.x - s * 0.92, c.y - s * 0.28)];
    [tri addLineToPoint:CGPointMake(c.x + s * 0.92, c.y - s * 0.28)];
    [tri addLineToPoint:CGPointMake(c.x, c.y + s * 0.78)];
    [tri closePath];
    [color setFill];
    [tri fill];
}

static void ANVStarPath(CGContextRef ctx, CGPoint c, CGFloat s, UIColor *color) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i < 8; i++) {
        CGFloat ang = (CGFloat)i * (CGFloat)M_PI / 4.0;
        CGFloat r = (i % 2 == 0) ? s : s * 0.42;
        CGPoint pt = CGPointMake(c.x + cos(ang) * r, c.y + sin(ang) * r);
        if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
    }
    [p closePath];
    [color setFill];
    [p fill];
}

/// 开枪扫射：枪口闪光 + 弹道流星
- (void)drawGunfire:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    if (side < 10.0) return;
    CGFloat muzzleX = CGRectGetMaxX(rect) - side * 0.12;
    CGFloat muzzleY = CGRectGetMidY(rect) - side * 0.06;
    CGFloat blink = 0.5 + 0.5 * sin(_actionPhase * 18.0);
    UIColor *flash = [UIColor colorWithHue:0.09 saturation:1.0 brightness:1.0 alpha:0.55 + 0.45 * blink];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0 * blink, flash.CGColor);
    CGContextSetFillColorWithColor(ctx, flash.CGColor);
    CGFloat fr = side * (0.10 + 0.06 * blink);
    CGContextFillEllipseInRect(ctx, CGRectMake(muzzleX - fr, muzzleY - fr, fr * 2, fr * 2));
    // 星形枪口焰
    UIBezierPath *star = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat a = (CGFloat)i / 12.0 * 2.0 * (CGFloat)M_PI;
        CGFloat rr = (i % 2 == 0) ? side * 0.16 : side * 0.06;
        CGPoint p = CGPointMake(muzzleX + cos(a) * rr, muzzleY + sin(a) * rr);
        if (i == 0) [star moveToPoint:p]; else [star addLineToPoint:p];
    }
    [star closePath];
    [[UIColor colorWithHue:0.14 saturation:0.9 brightness:1.0 alpha:0.85] setStroke];
    star.lineWidth = 1.1;
    [star stroke];

    // 弹道：三发循环
    for (NSInteger k = 0; k < 3; k++) {
        CGFloat t = fmod(_actionPhase * 1.6 + (CGFloat)k / 3.0, 1.0);
        CGFloat bx = muzzleX + t * side * 2.6;
        CGFloat by = muzzleY - t * side * 0.25;
        CGFloat alpha = (1.0 - t) * 0.9;
        UIColor *bc = [UIColor colorWithHue:0.12 saturation:1.0 brightness:1.0 alpha:alpha];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0, bc.CGColor);
        CGContextSetStrokeColorWithColor(ctx, bc.CGColor);
        CGContextSetLineWidth(ctx, 1.8);
        CGContextMoveToPoint(ctx, bx, by);
        CGContextAddLineToPoint(ctx, bx + side * 0.32, by - side * 0.03);
        CGContextStrokePath(ctx);
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 放烟花：上方随机爆开九色花火 + 拖尾
- (void)drawFireworks:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    if (side < 10.0) return;
    for (NSInteger k = 0; k < 3; k++) {
        CGFloat t = fmod(_actionPhase * 0.5 + (CGFloat)k / 3.0, 1.0);   // 0 -> 1 一轮爆开
        CGFloat cx = CGRectGetMidX(rect) + sin((CGFloat)k * 2.1 + _actionPhase * 0.4) * side * 0.55;
        CGFloat cy = CGRectGetMinY(rect) - side * (0.10 + 0.55 * t);
        CGFloat burst = MIN(1.0, t * 2.2);
        CGFloat fade = t > 0.6 ? MAX(0.0, 1.0 - (t - 0.6) / 0.4) : 1.0;
        NSInteger petals = 14;
        for (NSInteger i = 0; i < petals; i++) {
            CGFloat a = (CGFloat)i / (CGFloat)petals * 2.0 * (CGFloat)M_PI + (CGFloat)k;
            CGFloat r = side * 0.34 * burst * (i % 2 == 0 ? 1.0 : 0.62);
            CGFloat dot = side * 0.045;
            UIColor *col = [UIColor colorWithHue:fmod((CGFloat)i / (CGFloat)petals + (CGFloat)k * 0.3, 1.0)
                                       saturation:1.0 brightness:1.0 alpha:fade];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 7.0, col.CGColor);
            CGContextSetFillColorWithColor(ctx, col.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(cx + cos(a) * r - dot,
                                                       cy + sin(a) * r - dot, dot * 2, dot * 2));
        }
    }
    // 升空拖尾
    CGFloat t0 = fmod(_actionPhase * 0.5, 1.0);
    CGFloat rx = CGRectGetMidX(rect) + sin(_actionPhase * 0.4) * side * 0.55;
    UIColor *trail = [UIColor colorWithHue:0.55 saturation:0.4 brightness:1.0 alpha:0.5];
    CGContextSetShadowWithColor(ctx, CGSizeZero, 6.0, trail.CGColor);
    CGContextSetStrokeColorWithColor(ctx, trail.CGColor);
    CGContextSetLineWidth(ctx, 1.4);
    CGContextMoveToPoint(ctx, rx, CGRectGetMinY(rect) - side * (0.02 + 0.5 * t0));
    CGContextAddLineToPoint(ctx, rx, CGRectGetMaxY(rect) - side * 0.2);
    CGContextStrokePath(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

/// 迪斯科：旋转彩光从宠物上方扫过 + 地面光斑
- (void)drawDisco:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    if (side < 10.0) return;
    CGPoint top = CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect) - side * 0.12);
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat a = _actionPhase * 1.8 + (CGFloat)i * (CGFloat)M_PI_2;
        UIColor *col = [UIColor colorWithHue:fmod((CGFloat)i * 0.24 + _actionPhase * 0.15, 1.0)
                                   saturation:1.0 brightness:1.0 alpha:0.55];
        UIBezierPath *cone = [UIBezierPath bezierPath];
        [cone moveToPoint:top];
        [cone addLineToPoint:CGPointMake(top.x + cos(a - 0.18) * side * 1.6,
                                         top.y + side * 1.7)];
        [cone addLineToPoint:CGPointMake(top.x + cos(a + 0.18) * side * 1.6,
                                         top.y + side * 1.7)];
        [cone closePath];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0, col.CGColor);
        [col setFill];
        [cone fill];
    }
    // 地面光斑
    CGFloat t = fmod(_actionPhase * 0.9, 1.0);
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = CGRectGetMinX(rect) + side * (0.3 + 0.4 * (CGFloat)i)
                    + sin(_actionPhase * 1.4 + (CGFloat)i) * side * 0.25;
        UIColor *c2 = [UIColor colorWithHue:fmod(0.1 + (CGFloat)i * 0.3 + t, 1.0)
                                  saturation:0.9 brightness:1.0 alpha:0.5];
        CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0, c2.CGColor);
        CGContextSetFillColorWithColor(ctx, c2.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x - side * 0.16, CGRectGetMaxY(rect) - side * 0.10,
                                                   side * 0.32, side * 0.12));
    }
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

- (void)drawHeartsAround:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat p = fmod(_actionPhase + (CGFloat)i * 0.9, 2.4) / 2.4;
        CGFloat x = CGRectGetMidX(rect) + sin(_actionPhase * 2.0 + (CGFloat)i) * side * 0.35;
        CGFloat y = CGRectGetMinY(rect) + side * 0.45 - p * side * 0.8;
        ANVFilledHeart(ctx, CGPointMake(x, y), side * 0.08,
                       [UIColor colorWithHue:0.95 saturation:0.7 brightness:1.0 alpha:MAX(0, 1 - p)]);
    }
}

- (void)drawNotesAround:(CGContextRef)ctx rect:(CGRect)rect {
    (void)ctx;
    CGFloat side = CGRectGetHeight(rect);
    UIFont *font = [UIFont systemFontOfSize:MAX(9.0, side * 0.16) weight:UIFontWeightBold];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat p = fmod(_actionPhase * 1.1 + (CGFloat)i * 0.8, 2.2) / 2.2;
        CGFloat x = CGRectGetMidX(rect) + side * 0.45 + sin(_actionPhase * 2.4 + (CGFloat)i) * side * 0.12;
        CGFloat y = CGRectGetMinY(rect) + side * 0.15 - p * side * 0.6;
        [((i % 2 == 0) ? @"♪" : @"♫") drawAtPoint:CGPointMake(x, y)
            withAttributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName:
                                 [UIColor colorWithHue:fmod(0.6 + 0.1 * (CGFloat)i, 1.0)
                                            saturation:0.9 brightness:1.0 alpha:MAX(0, 1 - p)]}];
    }
}

- (void)drawZZZ:(CGContextRef)ctx rect:(CGRect)rect {
    (void)ctx;
    CGFloat side = CGRectGetHeight(rect);
    UIFont *font = [UIFont systemFontOfSize:MAX(9.0, side * 0.18) weight:UIFontWeightHeavy];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat p = fmod(_actionPhase * 0.7 + (CGFloat)i * 0.7, 2.1) / 2.1;
        [@"Z" drawAtPoint:CGPointMake(CGRectGetMidX(rect) + side * (0.42 + p * 0.2),
                                      CGRectGetMinY(rect) + side * 0.08 - p * side * 0.3)
            withAttributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName:
                                 [UIColor colorWithWhite:0.35 alpha:MAX(0, 0.85 - p * 0.7)]}];
    }
}

- (void)drawStarsOrbit:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat ang = _actionPhase * 1.6 + (CGFloat)i * (CGFloat)M_PI / 2.0;
        ANVStarPath(ctx, CGPointMake(CGRectGetMidX(rect) + cos(ang) * side * 0.55,
                                    CGRectGetMidY(rect) + sin(ang) * side * 0.45),
                    side * 0.06,
                    [UIColor colorWithHue:fmod(0.12 + 0.12 * (CGFloat)i, 1.0)
                                saturation:1.0 brightness:1.0 alpha:0.95]);
    }
}

- (void)drawBubblesAround:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetHeight(rect);
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat p = fmod(_actionPhase * 0.9 + (CGFloat)i * 0.55, 2.2) / 2.2;
        CGFloat r = side * (0.04 + 0.02 * (CGFloat)(i % 2));
        CGPoint c = CGPointMake(CGRectGetMidX(rect) + side * 0.5 + sin(_actionPhase * 1.8 + (CGFloat)i) * side * 0.1,
                                CGRectGetMinY(rect) + side * 0.45 - p * side * 0.6);
        UIColor *stroke = [UIColor colorWithHue:fmod(0.55 + 0.08 * (CGFloat)i, 1.0)
                                    saturation:0.75 brightness:1.0 alpha:(1 - p) * 0.9];
        CGContextSetStrokeColorWithColor(ctx, stroke.CGColor);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2, r * 2));
    }
}

@end

#pragma mark - 独立举牌歌词（宠物关掉时用）

@implementation ANVLyricsView {
    CGFloat _phase;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        _textScale = 1.0;
    }
    return self;
}

- (void)setTextScale:(CGFloat)textScale {
    _textScale = MIN(MAX(textScale, 0.6), 1.6);
    [self setNeedsDisplay];
}

- (void)setText:(NSString *)text {
    if ([_text isEqualToString:text]) return;
    _text = [text copy];
    [self setNeedsDisplay];
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGRect board = CGRectInset(rect, 1.0, 1.0);
    ANVDrawFrostedCapsule(ctx, board, 0.75, MIN(11.0, CGRectGetHeight(board) / 2.0), 0.9);

    if (!self.text.length) return;
    ANVDrawRainbowText(self.text, board,
                       MAX(9.0, CGRectGetHeight(rect) * 0.52 * self.textScale),
                       _phase, YES);
}

@end
