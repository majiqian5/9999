#import "ANVWidgets.h"

#pragma mark - 宠物

@implementation ANVPetView {
    CGFloat _phase;
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
    }
    return self;
}

- (void)setSizeScale:(CGFloat)sizeScale {
    _sizeScale = MIN(MAX(sizeScale, 0.6), 1.6);
    [self setNeedsDisplay];
}

- (void)setEnergy:(CGFloat)energy {
    _energy = MIN(MAX(energy, 0.0), 1.0);
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat side = MIN(rect.size.width, rect.size.height) * 0.92;
    CGFloat bounce = -fabs(sin(_phase * 3.0)) * 2.6 * (0.4 + _energy);
    CGRect head = CGRectMake(CGRectGetMidX(rect) - side / 2.0,
                             CGRectGetMidY(rect) - side / 2.0 + bounce,
                             side, side);

    // 背后一圈柔光，让它亮起来
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, side * 0.22,
        [UIColor colorWithHue:0.78 saturation:0.8 brightness:1.0 alpha:0.9].CGColor);

    // 耳朵（含粉色内耳）
    for (NSInteger s2 = -1; s2 <= 1; s2 += 2) {
        CGFloat baseX = CGRectGetMidX(head) + s2 * side * 0.24;
        UIBezierPath *ear = [UIBezierPath bezierPath];
        [ear moveToPoint:CGPointMake(baseX - side * 0.15, CGRectGetMinY(head) + side * 0.24)];
        [ear addLineToPoint:CGPointMake(baseX, CGRectGetMinY(head) - side * 0.10)];
        [ear addLineToPoint:CGPointMake(baseX + side * 0.15, CGRectGetMinY(head) + side * 0.24)];
        [ear closePath];
        [[UIColor colorWithHue:0.75 saturation:0.55 brightness:1.0 alpha:0.98] setFill];
        [ear fill];

        UIBezierPath *innerEar = [UIBezierPath bezierPath];
        [innerEar moveToPoint:CGPointMake(baseX - side * 0.075, CGRectGetMinY(head) + side * 0.20)];
        [innerEar addLineToPoint:CGPointMake(baseX, CGRectGetMinY(head) + side * 0.02)];
        [innerEar addLineToPoint:CGPointMake(baseX + side * 0.075, CGRectGetMinY(head) + side * 0.20)];
        [[UIColor colorWithHue:0.94 saturation:0.55 brightness:1.0 alpha:0.95] setFill];
        [innerEar fill];
    }

    // 脸：浅紫到深紫的渐变
    UIBezierPath *face = [UIBezierPath bezierPathWithRoundedRect:head cornerRadius:side * 0.42];
    UIColor *light = [UIColor colorWithHue:0.74 saturation:0.35 brightness:1.0 alpha:1.0];
    UIColor *dark = [UIColor colorWithHue:0.76 saturation:0.65 brightness:0.85 alpha:1.0];
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, face.CGPath);
    CGContextClip(ctx);
    CGGradientRef g = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(),
        (__bridge CFArrayRef)@[(id)light.CGColor, (id)dark.CGColor], NULL);
    CGContextDrawLinearGradient(ctx, g,
                                CGPointMake(CGRectGetMinX(head), CGRectGetMinY(head)),
                                CGPointMake(CGRectGetMaxX(head), CGRectGetMaxY(head)), 0);
    CGGradientRelease(g);
    CGContextRestoreGState(ctx);
    CGContextRestoreGState(ctx);

    [[UIColor colorWithHue:0.74 saturation:0.30 brightness:1.0 alpha:0.95] setStroke];
    face.lineWidth = 1.2;
    [face stroke];

    // 大眼睛：白眼球 + 深色瞳孔 + 两个高光
    CGFloat eyeY = CGRectGetMinY(head) + side * 0.50;
    CGFloat eyeR = side * 0.135;
    CGFloat blink = fmod(_phase, 3.2);
    BOOL closed = (blink > 2.95);
    for (NSInteger s2 = -1; s2 <= 1; s2 += 2) {
        CGFloat eyeX = CGRectGetMidX(head) + s2 * side * 0.19;
        if (closed) {
            UIBezierPath *l = [UIBezierPath bezierPath];
            [l moveToPoint:CGPointMake(eyeX - eyeR, eyeY)];
            [l addLineToPoint:CGPointMake(eyeX + eyeR, eyeY)];
            [[UIColor colorWithHue:0.75 saturation:0.55 brightness:0.55 alpha:1.0] setStroke];
            l.lineWidth = 1.4;
            [l stroke];
            continue;
        }
        [[UIColor colorWithWhite:1.0 alpha:1.0] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - eyeR, eyeY - eyeR, eyeR * 2, eyeR * 2));

        [[UIColor colorWithHue:0.72 saturation:0.75 brightness:0.32 alpha:1.0] setFill];
        CGFloat pr = eyeR * 0.62;
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - pr + eyeR * 0.10,
                                                   eyeY - pr + eyeR * 0.16,
                                                   pr * 2, pr * 2));

        [[UIColor colorWithWhite:1.0 alpha:0.95] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX - eyeR * 0.55, eyeY - eyeR * 0.62,
                                                   eyeR * 0.5, eyeR * 0.5));
        CGContextFillEllipseInRect(ctx, CGRectMake(eyeX + eyeR * 0.10, eyeY + eyeR * 0.18,
                                                   eyeR * 0.26, eyeR * 0.26));
    }

    // 小鼻子 + 嘴
    CGFloat noseY = eyeY + side * 0.17;
    UIBezierPath *nose = [UIBezierPath bezierPath];
    [nose moveToPoint:CGPointMake(CGRectGetMidX(head) - side * 0.045, noseY)];
    [nose addLineToPoint:CGPointMake(CGRectGetMidX(head) + side * 0.045, noseY)];
    [nose addLineToPoint:CGPointMake(CGRectGetMidX(head), noseY + side * 0.05)];
    [nose closePath];
    [[UIColor colorWithHue:0.94 saturation:0.55 brightness:0.95 alpha:1.0] setFill];
    [nose fill];

    UIBezierPath *smile = [UIBezierPath bezierPath];
    [smile moveToPoint:CGPointMake(CGRectGetMidX(head), noseY + side * 0.05)];
    [smile addLineToPoint:CGPointMake(CGRectGetMidX(head), noseY + side * 0.09)];
    [smile addQuadCurveToPoint:CGPointMake(CGRectGetMidX(head) - side * 0.10, noseY + side * 0.12)
                    controlPoint:CGPointMake(CGRectGetMidX(head) - side * 0.06, noseY + side * 0.16)];
    [smile moveToPoint:CGPointMake(CGRectGetMidX(head), noseY + side * 0.09)];
    [smile addQuadCurveToPoint:CGPointMake(CGRectGetMidX(head) + side * 0.10, noseY + side * 0.12)
                    controlPoint:CGPointMake(CGRectGetMidX(head) + side * 0.06, noseY + side * 0.16)];
    [[UIColor colorWithHue:0.75 saturation:0.5 brightness:0.5 alpha:1.0] setStroke];
    smile.lineWidth = 1.2;
    [smile stroke];

    // 腮红
    [[UIColor colorWithHue:0.96 saturation:0.5 brightness:1.0 alpha:0.35] setFill];
    for (NSInteger s2 = -1; s2 <= 1; s2 += 2) {
        CGContextFillEllipseInRect(ctx, CGRectMake(CGRectGetMidX(head) + s2 * side * 0.31 - side * 0.07,
                                                   eyeY + side * 0.14,
                                                   side * 0.14, side * 0.075));
    }

    // 胡须
    [[UIColor colorWithWhite:1.0 alpha:0.5] setStroke];
    for (NSInteger s2 = -1; s2 <= 1; s2 += 2) {
        for (NSInteger k = 0; k < 2; k++) {
            UIBezierPath *w = [UIBezierPath bezierPath];
            CGFloat y = noseY + side * 0.02 + k * side * 0.06;
            [w moveToPoint:CGPointMake(CGRectGetMidX(head) + s2 * side * 0.18, y)];
            [w addLineToPoint:CGPointMake(CGRectGetMidX(head) + s2 * side * 0.42, y - side * 0.04 + k * side * 0.05)];
            w.lineWidth = 0.9;
            [w stroke];
        }
    }
}

@end

#pragma mark - 举牌歌词

@implementation ANVLyricsView {
    CGFloat _phase;
    CGFloat _scroll;
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
    _scroll = 0;
    [self setNeedsDisplay];
}

- (void)advancePhase:(CGFloat)delta {
    _phase += delta;
    _scroll += delta * 26.0 * _textScale;      // 慢慢往左滚
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    // 牌子
    CGRect board = CGRectInset(rect, 1.0, 1.0);
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:board
                                                      cornerRadius:MIN(10.0, CGRectGetHeight(board) / 2.0)];
    [[UIColor colorWithWhite:0.05 alpha:0.82] setFill];
    [bg fill];
    [[UIColor colorWithWhite:1.0 alpha:0.18] setStroke];
    bg.lineWidth = 1.0;
    [bg stroke];

    if (!self.text.length) return;

    CGFloat fontSize = MAX(9.0, CGRectGetHeight(rect) * 0.55) * 1.0;
    UIFont *font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightHeavy];
    NSDictionary *attrs = @{NSFontAttributeName: font,
                            NSForegroundColorAttributeName: [UIColor whiteColor]};
    CGSize size = [self.text sizeWithAttributes:attrs];

    CGFloat span = size.width + CGRectGetWidth(rect);
    CGFloat offset = fmod(_scroll, span);
    CGFloat x = CGRectGetWidth(rect) - offset;          // 从右往左滚
    CGFloat y = (CGRectGetHeight(rect) - size.height) / 2.0;

    // 彩虹渐变裁剪到文字
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size.width, size.height), NO, 1.0);
    CFArrayRef colors = (__bridge CFArrayRef)@[
        (id)[UIColor colorWithHue:0.00 saturation:1.0 brightness:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithHue:0.16 saturation:1.0 brightness:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithHue:0.33 saturation:1.0 brightness:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithHue:0.50 saturation:1.0 brightness:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithHue:0.68 saturation:1.0 brightness:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithHue:0.82 saturation:1.0 brightness:1.0 alpha:1.0].CGColor
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(), colors, NULL);
    UIGraphicsEndImageContext();

    // 直接按字符画彩虹（避免渐变裁剪的开销）
    CGFloat cursor = x;
    NSInteger n = self.text.length;
    for (NSInteger i = 0; i < n; i++) {
        NSString *ch = [self.text substringWithRange:NSMakeRange(i, 1)];
        CGFloat t = (CGFloat)i / (CGFloat)MAX(n - 1, 1);
        CGFloat hue = fmod(t * 0.83 + _phase * 0.15, 1.0);
        UIColor *color = [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0];
        CGSize chSize = [ch sizeWithAttributes:attrs];
        [ch drawAtPoint:CGPointMake(cursor, y)
           withAttributes:@{NSFontAttributeName: font,
                            NSForegroundColorAttributeName: color}];
        cursor += chSize.width;
    }
    if (gradient) CGGradientRelease(gradient);
}

@end
