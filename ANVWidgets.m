#import "ANVWidgets.h"

#pragma mark - 彩虹字

static void ANVDrawRainbowText(NSString *text, CGRect rect, CGFloat fontSize,
                               CGFloat phase, BOOL scrolling) {
    if (!text.length) return;
    UIFont *font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightHeavy];
    NSDictionary *attrs = @{NSFontAttributeName: font};
    CGSize size = [text sizeWithAttributes:attrs];
    CGFloat x = CGRectGetMinX(rect) + 4.0;
    CGFloat y = CGRectGetMidY(rect) - size.height / 2.0;

    if (scrolling) {
        CGFloat span = size.width + CGRectGetWidth(rect);
        CGFloat offset = fmod(phase * 28.0, span);
        x = CGRectGetMinX(rect) + CGRectGetWidth(rect) - offset;
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
}


// 和导航键同一套质感：深色玻璃胶囊 + 顶部高光 + 霓虹描边
static void ANVDrawGlassCapsule(CGContextRef ctx, CGRect rect, CGFloat hue, CGFloat radius) {
    UIBezierPath *cap = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

    // 外发光
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0,
        [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:0.55].CGColor);
    [[UIColor colorWithWhite:0.02 alpha:0.80] setFill];
    [cap fill];
    CGContextRestoreGState(ctx);

    // 玻璃渐变：上亮下暗
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[UIColor colorWithWhite:0.30 alpha:0.70].CGColor,
                        (id)[UIColor colorWithWhite:0.06 alpha:0.85].CGColor,
                        (id)[UIColor colorWithWhite:0.00 alpha:0.90].CGColor];
    CGGradientRef grad = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, cap.CGPath);
    CGContextClip(ctx);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)), 0);
    CGContextRestoreGState(ctx);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);

    // 霓虹边
    [[UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:0.85] setStroke];
    cap.lineWidth = 1.4;
    [cap stroke];
    [[UIColor colorWithWhite:1.0 alpha:0.35] setStroke];
    cap.lineWidth = 0.7;
    [cap stroke];
}

#pragma mark - 宠物（会举牌、会撒娇的小动物）

static UIColor *ANVPetSkin(NSInteger style) {
    if (style == 1) return [UIColor colorWithHue:0.94 saturation:0.18 brightness:1.0 alpha:1.0];
    if (style == 2) return [UIColor colorWithHue:0.09 saturation:0.42 brightness:1.0 alpha:1.0];
    return [UIColor colorWithHue:0.75 saturation:0.45 brightness:1.0 alpha:1.0];
}

static UIColor *ANVPetEdge(NSInteger style) {
    if (style == 1) return [UIColor colorWithHue:0.94 saturation:0.42 brightness:0.98 alpha:1.0];
    if (style == 2) return [UIColor colorWithHue:0.09 saturation:0.62 brightness:0.85 alpha:1.0];
    return [UIColor colorWithHue:0.75 saturation:0.65 brightness:0.85 alpha:1.0];
}

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
        _partnerStyle = 0;
        _action = 0;
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
    _style = MIN(MAX(style, 0), 2);
    [self setNeedsDisplay];
}

- (void)setPartnerStyle:(NSInteger)partnerStyle {
    _partnerStyle = MIN(MAX(partnerStyle, 0), 2);
    [self setNeedsDisplay];
}

- (void)setAction:(NSInteger)action {
    NSInteger clamped = MIN(MAX(action, 0), [ANVPetView actionCount] - 1);
    if (clamped != _action) _actionPhase = 0.0;   // 换动作从头开始播
    _action = clamped;
    [self setNeedsDisplay];
}

+ (NSInteger)actionCount {
    return 17;
}

+ (NSString *)titleForAction:(NSInteger)action {
    switch (MIN(MAX(action, 0), 16)) {
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
        default: return @"爱心发射";
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

    CGFloat side = CGRectGetHeight(rect);
    CGFloat E = _energy;
    CGFloat t = _phase;
    CGFloat at = _actionPhase;
    NSInteger act = MIN(MAX(_action, 0), 16);

    CGFloat bob = -fabs(sin(t * 3.0)) * 2.4 * (0.35 + E);
    CGFloat dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0, sy = 1.0;
    BOOL pivotTop = NO;
    BOOL eyeClosed = NO, mouthOpen = NO, blush = NO;
    NSInteger paws = 0;              // 0 无手 1 双手举起 2 单手挥 3 拿花
    BOOL twoPets = (act == 4 || act == 5 || act == 12);

    switch (act) {
        case 1:
            dy -= fabs(sin(t * 4.2)) * side * 0.06 * (0.4 + E);
            break;
        case 2: {                    // 跟歌曲节奏跳舞（频率跟音量走）
            CGFloat beat = sin(t * (5.0 + E * 4.0));
            dx += beat * side * 0.10 * (0.35 + E);
            dy -= fabs(beat) * side * 0.16 * (0.30 + E);
            rot = beat * 0.20;
            sx = 1.0 + fabs(beat) * 0.06;
            sy = 1.0 - fabs(beat) * 0.06;
            mouthOpen = YES;
            blush = YES;
            paws = 1;
            break;
        }
        case 3:                      // 荡秋千：绕顶部吊点大幅摆动
            rot = sin(at * 1.5) * 0.55;
            pivotTop = YES;
            break;
        case 4:                      // 打架：来回冲撞
            dx += sin(at * 8.0) * side * 0.16;
            rot = sin(at * 8.0) * 0.14;
            paws = 1;
            break;
        case 5:                      // 谈恋爱：慢慢靠过去
            dx -= side * 0.10 * (1.0 - cos(at * 1.2)) / 2.0;
            rot = -0.16;
            blush = YES;
            break;
        case 6:                      // 唱歌
            mouthOpen = YES;
            rot = sin(t * 2.0) * 0.05;
            break;
        case 7:                      // 招手
            rot = sin(t * 6.0) * 0.10;
            paws = 2;
            break;
        case 8: {                    // 转圈（横向压扁模拟转身）
            CGFloat s = cos(at * 2.6);
            sx = MAX(0.22, fabs(s));
            break;
        }
        case 9:                      // 睡觉
            eyeClosed = YES;
            sy = 1.0 - (0.5 + 0.5 * sin(t * 1.2)) * 0.04;
            break;
        case 10: {                   // 蹦跳
            CGFloat j = MAX(0.0, sin(at * 4.0));
            dy -= j * side * 0.22;
            sy = 1.0 + j * 0.06;
            break;
        }
        case 11:                     // 甩尾巴
            rot = sin(t * 7.0) * 0.08;
            break;
        case 12:                     // 送花
            dx -= side * 0.06;
            rot = -0.20;
            blush = YES;
            paws = 3;
            break;
        case 13:                     // 打滚
            rot = at * 2.2;
            pivotTop = YES;
            break;
        case 15:                     // 星星环绕
            rot = sin(t * 1.6) * 0.12;
            break;
        case 16:                     // 爱心发射
            dy -= fabs(sin(at * 2.2)) * side * 0.10;
            blush = YES;
            break;
        default:
            break;
    }

    CGFloat baseX = CGRectGetMinX(rect);
    CGRect petRect = CGRectMake(baseX + dx,
                                CGRectGetMaxY(rect) - side * sy + bob + dy,
                                side * sx, side * sy);

    // 秋千的绳子要画在宠物后面
    if (act == 3) {
        [self drawSwingInContext:ctx rect:rect petRect:petRect side:side];
    }

    // 伙伴（打架 / 谈恋爱 / 送花时出场，故意用另一种造型）
    CGRect partnerRect = CGRectZero;
    if (twoPets) {
        CGFloat pd = (act == 4) ? -sin(at * 8.0) * side * 0.14 : 0.0;
        partnerRect = CGRectMake(petRect.origin.x + side * 0.68 + pd,
                                 CGRectGetMinY(petRect), side, side);
        [self drawPetInContext:ctx rect:partnerRect style:(self.partnerStyle + 1) % 3
                      eyeClosed:NO mouthOpen:(act == 5)
                          blush:YES paws:(act == 4 ? 1 : 0) sway:sin(at * 2.0)];
    }

    // 招牌（两只同框时不举牌，免得挤）
    if (!twoPets && self.lyricText.length) {
        CGRect signRect = CGRectMake(CGRectGetMinX(petRect) + side * 0.74,
                                     CGRectGetMinY(petRect) - side * 0.10,
                                     CGRectGetWidth(rect) - (baseX - CGRectGetMinX(rect)) - side * 0.74,
                                     side * 0.52);
        if (CGRectGetWidth(signRect) > 20.0) [self drawSignInContext:ctx rect:signRect];
    }

    CGContextSaveGState(ctx);
    if (rot != 0.0) {
        CGPoint pv = pivotTop ? CGPointMake(CGRectGetMidX(petRect), CGRectGetMinY(petRect))
                              : CGPointMake(CGRectGetMidX(petRect), CGRectGetMaxY(petRect));
        CGContextTranslateCTM(ctx, pv.x, pv.y);
        CGContextRotateCTM(ctx, rot);
        CGContextTranslateCTM(ctx, -pv.x, -pv.y);
    }
    [self drawPetInContext:ctx rect:petRect style:self.style
                 eyeClosed:eyeClosed mouthOpen:mouthOpen blush:blush
                      paws:paws sway:sin(t * 7.0)];
    CGContextRestoreGState(ctx);

    // 气氛装饰
    switch (act) {
        case 2:  [self drawNotesAround:ctx rect:petRect]; break;
        case 3:  [self drawSwingSeat:ctx rect:petRect]; break;
        case 4:  [self drawImpactBetween:ctx a:petRect b:partnerRect]; break;
        case 5:  [self drawHeartsAround:ctx rect:petRect count:3 seed:11]; break;
        case 6:  [self drawNotesAround:ctx rect:petRect]; break;
        case 9:  [self drawZZZ:ctx rect:petRect]; break;
        case 12: [self drawFlowerInContext:ctx rect:petRect]; break;
        case 14: [self drawBubblesAround:ctx rect:petRect]; break;
        case 15: [self drawStarsOrbit:ctx rect:petRect]; break;
        case 16: [self drawHeartsAround:ctx rect:petRect count:5 seed:32]; break;
        default: break;
    }
}

- (void)drawSignInContext:(CGContextRef)ctx rect:(CGRect)rect {
    // 和导航键一样：深色玻璃胶囊 + 霓虹描边，文字还是彩虹滚动
    CGRect board = CGRectInset(rect, 1.0, 1.0);
    board.size.height = MAX(18.0, board.size.height);
    CGFloat radius = MIN(CGRectGetHeight(board) / 2.0, 12.0);
    ANVDrawGlassCapsule(ctx, board, 0.75, radius);

    // 指向宠物的小尖角
    UIBezierPath *tail = [UIBezierPath bezierPath];
    [tail moveToPoint:CGPointMake(CGRectGetMinX(board) + 6.0, CGRectGetMaxY(board) - 2.0)];
    [tail addLineToPoint:CGPointMake(CGRectGetMinX(board) + 2.0, CGRectGetMaxY(board) + radius * 0.8)];
    [tail addLineToPoint:CGPointMake(CGRectGetMinX(board) + 15.0, CGRectGetMaxY(board) - 2.0)];
    [tail closePath];
    [[UIColor colorWithWhite:0.04 alpha:0.80] setFill];
    [tail fill];
    [[UIColor colorWithHue:0.75 saturation:1.0 brightness:1.0 alpha:0.75] setStroke];
    tail.lineWidth = 1.0;
    [tail stroke];

    ANVDrawRainbowText(self.lyricText, board,
                       MAX(8.0, CGRectGetHeight(board) * 0.52 * self.textScale),
                       _phase, YES);
}

- (void)drawPetInContext:(CGContextRef)ctx rect:(CGRect)rect style:(NSInteger)style
               eyeClosed:(BOOL)closed mouthOpen:(BOOL)open blush:(BOOL)blush
                    paws:(NSInteger)paws sway:(CGFloat)sway {
    CGFloat side = rect.size.width;
    if (side < 8.0) return;

    UIColor *skin = ANVPetSkin(style);
    UIColor *edge = ANVPetEdge(style);

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, side * 0.20,
        [UIColor colorWithHue:0.78 saturation:0.9 brightness:1.0 alpha:0.95].CGColor);

    // 耳朵：猫尖耳 / 兔长耳 / 熊圆耳
    for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
        CGFloat baseX = CGRectGetMidX(rect) + sgn * side * 0.25;
        if (style == 1) {
            CGRect ear = CGRectMake(baseX - side * 0.09, CGRectGetMinY(rect) - side * 0.30,
                                    side * 0.18, side * 0.44);
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:ear cornerRadius:side * 0.09];
            [skin setFill]; [p fill];
            UIBezierPath *q = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(ear, side * 0.045, side * 0.06)
                                                            cornerRadius:side * 0.05];
            [[UIColor colorWithHue:0.96 saturation:0.45 brightness:1.0 alpha:0.85] setFill];
            [q fill];
        } else if (style == 2) {
            CGRect ear = CGRectMake(baseX - side * 0.14, CGRectGetMinY(rect) - side * 0.10,
                                    side * 0.28, side * 0.28);
            UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:ear];
            [skin setFill]; [p fill];
            UIBezierPath *q = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(ear, side * 0.07, side * 0.07)];
            [[UIColor colorWithHue:0.08 saturation:0.35 brightness:0.75 alpha:1.0] setFill];
            [q fill];
        } else {
            UIBezierPath *ear = [UIBezierPath bezierPath];
            [ear moveToPoint:CGPointMake(baseX - side * 0.17, CGRectGetMinY(rect) + side * 0.26)];
            [ear addLineToPoint:CGPointMake(baseX, CGRectGetMinY(rect) - side * 0.05)];
            [ear addLineToPoint:CGPointMake(baseX + side * 0.17, CGRectGetMinY(rect) + side * 0.26)];
            [ear closePath];
            [skin setFill]; [ear fill];
        }
    }

    // 脸
    UIBezierPath *face = [UIBezierPath bezierPathWithRoundedRect:rect
                                                       cornerRadius:side * (style == 2 ? 0.5 : 0.40)];
    [skin setFill];
    [face fill];
    CGContextRestoreGState(ctx);

    [edge setStroke];
    face.lineWidth = 1.2;
    [face stroke];

    // 眼睛
    CGFloat eyeY = CGRectGetMidY(rect) - side * 0.02;
    CGFloat eyeR = side * (style == 2 ? 0.12 : 0.15);
    CGFloat blink = fmod(_phase, 3.4);
    for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
        CGFloat eyeX = CGRectGetMidX(rect) + sgn * side * 0.19;
        if (closed || blink > 3.1) {
            UIBezierPath *l = [UIBezierPath bezierPath];
            [l moveToPoint:CGPointMake(eyeX - eyeR, eyeY)];
            [l addQuadCurveToPoint:CGPointMake(eyeX + eyeR, eyeY)
                       controlPoint:CGPointMake(eyeX, eyeY - eyeR * 0.9)];
            [edge setStroke];
            l.lineWidth = 1.6;
            [l stroke];
            continue;
        }
        [[UIColor colorWithWhite:1.0 alpha:1.0] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - eyeR, eyeY - eyeR, eyeR * 2, eyeR * 2));
        [[UIColor colorWithWhite:0.18 alpha:1.0] setFill];
        CGFloat pr = eyeR * 0.62;
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - pr + eyeR * 0.14,
                                                   eyeY - pr + eyeR * 0.20, pr * 2, pr * 2));
        [[UIColor colorWithWhite:1.0 alpha:0.95] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - eyeR * 0.56, eyeY - eyeR * 0.64,
                                                   eyeR * 0.46, eyeR * 0.46));
    }

    // 腮红
    CGFloat blushAlpha = blush ? 0.55 : 0.35;
    [[UIColor colorWithHue:0.96 saturation:0.6 brightness:1.0 alpha:blushAlpha] setFill];
    for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
        CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMidX(rect) + sgn * side * 0.33 - side * 0.08,
                                                   eyeY + side * 0.16, side * 0.16, side * 0.08));
    }

    // 鼻子
    if (style == 0 || style == 2) {
        UIBezierPath *nose = [UIBezierPath bezierPath];
        [nose moveToPoint:CGPointMake(CGRectGetMidX(rect) - side * 0.05, eyeY + side * 0.15)];
        [nose addLineToPoint:CGPointMake(CGRectGetMidX(rect) + side * 0.05, eyeY + side * 0.15)];
        [nose addLineToPoint:CGPointMake(CGRectGetMidX(rect), eyeY + side * 0.20)];
        [nose closePath];
        [[UIColor colorWithHue:0.94 saturation:0.5 brightness:0.9 alpha:1.0] setFill];
        [nose fill];
    } else {
        [[UIColor colorWithHue:0.94 saturation:0.5 brightness:0.9 alpha:0.9] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMidX(rect) - side * 0.025, eyeY + side * 0.14,
                                                   side * 0.05, side * 0.04));
    }

    // 嘴：唱歌 / 说话时张成小 o
    if (open) {
        UIBezierPath *m = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(CGRectGetMidX(rect) - side * 0.055,
                                                                          eyeY + side * 0.235,
                                                                          side * 0.11, side * 0.09)];
        [[UIColor colorWithHue:0.95 saturation:0.6 brightness:0.55 alpha:1.0] setFill];
        [m fill];
    } else {
        UIBezierPath *smile = [UIBezierPath bezierPath];
        [smile moveToPoint:CGPointMake(CGRectGetMidX(rect) - side * 0.08, eyeY + side * 0.24)];
        [smile addQuadCurveToPoint:CGPointMake(CGRectGetMidX(rect) + side * 0.08, eyeY + side * 0.24)
                       controlPoint:CGPointMake(CGRectGetMidX(rect), eyeY + side * 0.31)];
        [edge setStroke];
        smile.lineWidth = 1.4;
        [smile stroke];
    }

    // 胡须只给猫
    if (style == 0) {
        [[UIColor colorWithWhite:1.0 alpha:0.45] setStroke];
        for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
            for (NSInteger k = 0; k < 2; k++) {
                UIBezierPath *w = [UIBezierPath bezierPath];
                CGFloat wy = eyeY + side * 0.17 + k * side * 0.07;
                [w moveToPoint:CGPointMake(CGRectGetMidX(rect) + sgn * side * 0.20, wy)];
                [w addLineToPoint:CGPointMake(CGRectGetMidX(rect) + sgn * side * 0.44, wy - side * 0.03 + k * side * 0.05)];
                w.lineWidth = 0.9;
                [w stroke];
            }
        }
    }

    // 小爪子
    if (paws > 0) {
        CGFloat pawR = side * 0.11;
        CGFloat py = CGRectGetMidY(rect) + side * 0.02;
        if (paws == 1) {
            [[UIColor colorWithWhite:1.0 alpha:0.9] setFill];
            for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
                CGPoint c = CGPointMake(CGRectGetMidX(rect) + sgn * side * 0.44,
                                        py - side * 0.16 - fabs(sway) * side * 0.10);
                CGContextFillEllipseInRect(ctx, CGRectMake(c.x - pawR, c.y - pawR, pawR * 2, pawR * 2));
            }
        } else if (paws == 2) {
            [[UIColor colorWithWhite:1.0 alpha:0.9] setFill];
            CGPoint c = CGPointMake(CGRectGetMidX(rect) + side * 0.44,
                                    py - side * 0.20 - fabs(sway) * side * 0.14);
            CGContextFillEllipseInRect(ctx, CGRectMake(c.x - pawR, c.y - pawR, pawR * 2, pawR * 2));
        } else {
            [[UIColor colorWithWhite:1.0 alpha:0.9] setFill];
            CGPoint c = CGPointMake(CGRectGetMidX(rect) - side * 0.42, py - side * 0.10);
            CGContextFillEllipseInRect(ctx, CGRectMake(c.x - pawR, c.y - pawR, pawR * 2, pawR * 2));
        }
    }
}

#pragma mark - 动作装饰

- (void)drawHeartsAround:(CGContextRef)ctx rect:(CGRect)rect count:(NSInteger)count seed:(NSInteger)seed {
    CGFloat side = CGRectGetWidth(rect);
    CGFloat at = _actionPhase;
    for (NSInteger i = 0; i < count; i++) {
        CGFloat off = (CGFloat)i * 1.1 + (CGFloat)seed * 0.2;
        CGFloat p = fmod(at + off, 2.4) / 2.4;          // 0~1 的生命周期
        CGFloat alpha = 1.0 - p;
        CGFloat x = CGRectGetMidX(rect) + sin(at * 2.0 + (CGFloat)i) * side * (0.18 + 0.06 * i);
        CGFloat y = CGRectGetMinY(rect) + side * 0.30 - p * side * 0.75;
        CGFloat s = side * 0.09 * (1.0 + 0.2 * (CGFloat)i);
        ANVFilledHeart(ctx, CGPointMake(x, y), s,
                       [UIColor colorWithHue:0.95 saturation:0.7 brightness:1.0 alpha:MAX(0.0, alpha)]);
    }
}

- (void)drawNotesAround:(CGContextRef)ctx rect:(CGRect)rect {
    (void)ctx;
    CGFloat side = CGRectGetWidth(rect);
    CGFloat at = _actionPhase;
    UIFont *font = [UIFont systemFontOfSize:MAX(9.0, side * 0.18) weight:UIFontWeightBold];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat p = fmod(at * 1.1 + (CGFloat)i * 0.8, 2.2) / 2.2;
        CGFloat x = CGRectGetMidX(rect) + side * 0.30 + sin(at * 2.4 + (CGFloat)i) * side * 0.10;
        CGFloat y = CGRectGetMinY(rect) + side * 0.10 - p * side * 0.55;
        NSString *note = (i % 2 == 0) ? @"♪" : @"♫";
        [note drawAtPoint:CGPointMake(x, y)
            withAttributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName:
                                 [UIColor colorWithHue:fmod(0.6 + 0.1 * (CGFloat)i, 1.0)
                                            saturation:0.9 brightness:1.0
                                                alpha:MAX(0.0, 1.0 - p)]}];
    }
}

- (void)drawZZZ:(CGContextRef)ctx rect:(CGRect)rect {
    (void)ctx;
    CGFloat side = CGRectGetWidth(rect);
    CGFloat at = _actionPhase;
    UIFont *font = [UIFont systemFontOfSize:MAX(9.0, side * 0.20) weight:UIFontWeightHeavy];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat p = fmod(at * 0.7 + (CGFloat)i * 0.7, 2.1) / 2.1;
        CGPoint pt = CGPointMake(CGRectGetMidX(rect) + side * (0.30 + p * 0.24),
                                 CGRectGetMinY(rect) + side * 0.04 - p * side * 0.30);
        [@"Z" drawAtPoint:pt
            withAttributes:@{NSFontAttributeName: font,
                             NSForegroundColorAttributeName:
                                 [UIColor colorWithWhite:1.0 - p alpha:MAX(0.0, 0.85 - p * 0.7)]}];
    }
}

- (void)drawStarsOrbit:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetWidth(rect);
    CGFloat at = _actionPhase;
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat ang = at * 1.6 + (CGFloat)i * (CGFloat)M_PI / 2.0;
        CGPoint c = CGPointMake(CGRectGetMidX(rect) + cos(ang) * side * 0.62,
                                CGRectGetMidY(rect) + sin(ang) * side * 0.52);
        ANVStarPath(ctx, c, side * 0.075, [UIColor colorWithHue:fmod(0.12 + 0.12 * (CGFloat)i, 1.0)
                                                    saturation:1.0 brightness:1.0 alpha:0.95]);
    }
}

- (void)drawBubblesAround:(CGContextRef)ctx rect:(CGRect)rect {
    CGFloat side = CGRectGetWidth(rect);
    CGFloat at = _actionPhase;
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat p = fmod(at * 0.9 + (CGFloat)i * 0.55, 2.2) / 2.2;
        CGFloat r = side * (0.05 + 0.03 * (CGFloat)(i % 2));
        CGPoint c = CGPointMake(CGRectGetMidX(rect) + side * 0.34 + sin(at * 1.8 + (CGFloat)i) * side * 0.08,
                                CGRectGetMinY(rect) + side * 0.42 - p * side * 0.65);
        UIColor *stroke = [UIColor colorWithHue:fmod(0.55 + 0.08 * (CGFloat)i, 1.0)
                                    saturation:0.75 brightness:1.0 alpha:(1.0 - p) * 0.9];
        CGContextSetStrokeColorWithColor(ctx, stroke.CGColor);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, r * 2, r * 2));
    }
}

- (void)drawSwingInContext:(CGContextRef)ctx rect:(CGRect)rect petRect:(CGRect)petRect side:(CGFloat)side {
    CGPoint anchor = CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect) - side * 0.10);
    CGPoint seat = CGPointMake(CGRectGetMidX(petRect), CGRectGetMinY(petRect) + side * 0.10);

    [[UIColor colorWithWhite:1.0 alpha:0.35] setStroke];
    for (NSInteger sgn = -1; sgn <= 1; sgn += 2) {
        UIBezierPath *rope = [UIBezierPath bezierPath];
        [rope moveToPoint:anchor];
        [rope addLineToPoint:CGPointMake(seat.x + sgn * side * 0.28, seat.y)];
        rope.lineWidth = 1.1;
        [rope stroke];
    }
}

- (void)drawSwingSeat:(CGContextRef)ctx rect:(CGRect)petRect {
    (void)ctx;
    CGFloat side = CGRectGetWidth(petRect);
    CGRect seat = CGRectMake(CGRectGetMidX(petRect) - side * 0.32,
                             CGRectGetMinY(petRect) + side * 0.10, side * 0.64, side * 0.08);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:seat cornerRadius:side * 0.04];
    [[UIColor colorWithHue:0.55 saturation:0.6 brightness:1.0 alpha:0.55] setFill];
    [p fill];
}

- (void)drawImpactBetween:(CGContextRef)ctx a:(CGRect)a b:(CGRect)b {
    if (CGRectIsEmpty(b)) return;
    CGFloat mid = (CGRectGetMidX(a) + CGRectGetMaxX(b)) / 2.0;
    CGPoint c = CGPointMake(mid, CGRectGetMidY(a) - CGRectGetHeight(a) * 0.10);
    CGFloat s = CGRectGetHeight(a) * 0.16;
    CGFloat pulse = 0.6 + 0.4 * fabs(sin(_actionPhase * 8.0));
    ANVStarPath(ctx, c, s * pulse, [UIColor colorWithHue:0.13 saturation:1.0 brightness:1.0 alpha:0.95]);
    ANVStarPath(ctx, c, s * pulse * 0.55, [UIColor colorWithWhite:1.0 alpha:0.9]);
}

- (void)drawFlowerInContext:(CGContextRef)ctx rect:(CGRect)petRect {
    CGFloat side = CGRectGetWidth(petRect);
    CGPoint c = CGPointMake(CGRectGetMidX(petRect) - side * 0.46, CGRectGetMidY(petRect) - side * 0.30);
    CGFloat r = side * 0.10;
    for (NSInteger i = 0; i < 5; i++) {
        CGFloat ang = (CGFloat)i * 2.0 * (CGFloat)M_PI / 5.0 + _actionPhase * 0.6;
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithHue:0.96 saturation:0.60 brightness:1.0 alpha:1.0].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(c.x + cos(ang) * r * 0.9 - r * 0.6,
                                                   c.y + sin(ang) * r * 0.9 - r * 0.6,
                                                   r * 1.2, r * 1.2));
    }
    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithHue:0.14 saturation:1.0 brightness:1.0 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - r * 0.45, c.y - r * 0.45, r * 0.9, r * 0.9));
    UIBezierPath *stem = [UIBezierPath bezierPath];
    [stem moveToPoint:CGPointMake(c.x, c.y + r * 0.4)];
    [stem addLineToPoint:CGPointMake(c.x, c.y + r * 2.0)];
    [[UIColor colorWithHue:0.33 saturation:0.7 brightness:0.8 alpha:1.0] setStroke];
    stem.lineWidth = 1.4;
    [stem stroke];
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
    ANVDrawGlassCapsule(ctx, board, 0.75, MIN(12.0, CGRectGetHeight(board) / 2.0));

    if (!self.text.length) return;
    ANVDrawRainbowText(self.text, board,
                       MAX(9.0, CGRectGetHeight(rect) * 0.55 * self.textScale),
                       _phase, YES);
}

@end
