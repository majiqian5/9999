#import "ANVGlyphView.h"

/**
 * 四个图标全部用 CGContext 直接画（不用 CAShapeLayer）。
 * 之前用 CAShapeLayer 的版本在部分环境下路径不刷新，导致图标空白；
 * 改成 drawRect 后，只要视图被布局就一定画得出来。
 */
@implementation ANVGlyphView {
    BOOL _highlighted;
    UIImage *_image;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.clipsToBounds = NO;
        _lineWidth = 3.2;
        _glyphColor = [UIColor whiteColor];
    }
    return self;
}

#pragma mark - 属性

- (void)setKind:(ANVGlyphKind)kind {
    _kind = kind;
    [self setNeedsDisplay];
}

- (void)setGlyphColor:(UIColor *)glyphColor {
    _glyphColor = glyphColor ?: [UIColor whiteColor];
    [self setNeedsDisplay];
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = MAX(1.0, lineWidth);
    [self setNeedsDisplay];
}

- (void)setGlowHighlighted:(BOOL)highlighted {
    _highlighted = highlighted;
    [self setNeedsDisplay];
}

- (void)setGlyphImage:(UIImage *)image {
    _image = image;
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

#pragma mark - 路径

- (UIBezierPath *)pathForKind:(ANVGlyphKind)kind inRect:(CGRect)r {
    CGFloat side = MIN(r.size.width, r.size.height) * 0.74;
    CGRect box = CGRectMake(CGRectGetMidX(r) - side / 2.0,
                            CGRectGetMidY(r) - side / 2.0,
                            side, side);
    CGFloat w = box.size.width, h = box.size.height;
    CGFloat minX = CGRectGetMinX(box), minY = CGRectGetMinY(box);
    UIBezierPath *p = [UIBezierPath bezierPath];

    switch (kind) {
        case ANVGlyphBack: {
            CGPoint a = CGPointMake(minX + w * 0.96, minY + h * 0.04);
            CGPoint b = CGPointMake(minX + w * 0.04, minY + h * 0.50);
            CGPoint c = CGPointMake(minX + w * 0.96, minY + h * 0.96);
            [p moveToPoint:a];
            [p addLineToPoint:b];
            [p addLineToPoint:c];
            [p closePath];
            break;
        }
        case ANVGlyphHome: {
            [p addArcWithCenter:CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box))
                          radius:side / 2.0 * 0.96
                      startAngle:0
                        endAngle:M_PI * 2
                       clockwise:YES];
            break;
        }
        case ANVGlyphRecents: {
            UIBezierPath *sq = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:side * 0.10];
            [p appendPath:sq];
            break;
        }
        case ANVGlyphForward: {
            CGFloat y = CGRectGetMidY(box);
            [p moveToPoint:CGPointMake(minX + w * 0.03, y)];
            [p addLineToPoint:CGPointMake(minX + w * 0.62, y)];
            [p moveToPoint:CGPointMake(minX + w * 0.50, y - h * 0.22)];
            [p addLineToPoint:CGPointMake(minX + w * 0.80, y)];
            [p addLineToPoint:CGPointMake(minX + w * 0.50, y + h * 0.22)];
            [p moveToPoint:CGPointMake(minX + w * 0.92, y - h * 0.36)];
            [p addLineToPoint:CGPointMake(minX + w * 0.92, y + h * 0.36)];
            break;
        }
    }
    return p;
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    UIColor *color = self.glyphColor ?: [UIColor whiteColor];
    CGFloat lw = _highlighted ? _lineWidth * 1.35 : _lineWidth;

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero,
                                _highlighted ? 12.0 : 7.0,
                                [color colorWithAlphaComponent:0.95].CGColor);

    if (_image) {
        CGFloat inset = MIN(rect.size.width, rect.size.height) * 0.06;
        CGRect imageRect = CGRectInset(rect, inset, inset);
        [_image drawInRect:imageRect blendMode:kCGBlendModeNormal alpha:1.0];
        CGContextRestoreGState(ctx);
        return;
    }

    UIBezierPath *path = [self pathForKind:_kind inRect:rect];
    if (!path || path.isEmpty) { CGContextRestoreGState(ctx); return; }

    path.lineWidth = lw;
    path.lineJoinStyle = kCGLineJoinRound;
    path.lineCapStyle = kCGLineCapRound;

    if (_kind == ANVGlyphBack) {
        // 三角是实心的，跟参考图一致
        [color setFill];
        [path fill];
    }
    [color setStroke];
    [path stroke];

    CGContextRestoreGState(ctx);
}

@end
