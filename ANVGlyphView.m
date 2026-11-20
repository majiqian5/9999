#import "ANVGlyphView.h"

@interface ANVGlyphView ()
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, assign) CGFloat baseLineWidth;
@end

@implementation ANVGlyphView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        _baseLineWidth = 3.2;
        _lineWidth = 3.2;

        _shapeLayer = [CAShapeLayer layer];
        _shapeLayer.fillColor = [UIColor clearColor].CGColor;
        _shapeLayer.lineJoin = kCALineJoinRound;
        _shapeLayer.lineCap = kCALineCapRound;
        _shapeLayer.strokeColor = [UIColor whiteColor].CGColor;
        _shapeLayer.lineWidth = _lineWidth;
        _shapeLayer.shadowOffset = CGSizeZero;
        _shapeLayer.shadowOpacity = 0.95;
        _shapeLayer.shadowRadius = 7.0;
        _shapeLayer.masksToBounds = NO;
        [self.layer addSublayer:_shapeLayer];
    }
    return self;
}

- (void)setKind:(ANVGlyphKind)kind {
    _kind = kind;
    [self setNeedsLayout];
}

- (void)setGlyphColor:(UIColor *)glyphColor {
    _glyphColor = glyphColor;
    _shapeLayer.strokeColor = glyphColor.CGColor;
    _shapeLayer.shadowColor = glyphColor.CGColor;
}

- (void)setLineWidth:(CGFloat)lineWidth {
    _lineWidth = lineWidth;
    _baseLineWidth = lineWidth;
    _shapeLayer.lineWidth = lineWidth;
}

- (void)setGlowHighlighted:(BOOL)highlighted {
    _shapeLayer.lineWidth = highlighted ? _baseLineWidth * 1.35 : _baseLineWidth;
    _shapeLayer.shadowRadius = highlighted ? 12.0 : 7.0;
    _shapeLayer.shadowOpacity = highlighted ? 1.0 : 0.95;
}

- (UIBezierPath *)pathForKind:(ANVGlyphKind)kind inRect:(CGRect)r {
    CGFloat w = r.size.width, h = r.size.height;
    UIBezierPath *p = [UIBezierPath bezierPath];

    switch (kind) {
        case ANVGlyphBack: {
            CGPoint a = CGPointMake(CGRectGetMinX(r) + w * 0.74, CGRectGetMinY(r) + h * 0.14);
            CGPoint b = CGPointMake(CGRectGetMinX(r) + w * 0.24, CGRectGetMidY(r));
            CGPoint c = CGPointMake(CGRectGetMinX(r) + w * 0.74, CGRectGetMinY(r) + h * 0.86);
            [p moveToPoint:a];
            [p addLineToPoint:b];
            [p addLineToPoint:c];
            [p closePath];
            break;
        }
        case ANVGlyphHome: {
            [p addArcWithCenter:CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r))
                          radius:w * 0.30
                      startAngle:0
                        endAngle:M_PI * 2
                       clockwise:YES];
            break;
        }
        case ANVGlyphRecents: {
            CGRect sq = CGRectInset(r, w * 0.24, h * 0.24);
            UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:sq cornerRadius:w * 0.05];
            [p appendPath:rounded];
            break;
        }
        case ANVGlyphForward: {
            CGFloat y = CGRectGetMidY(r);
            // 横线
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.16, y)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.76, y)];
            // 箭头
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.56, y - h * 0.19)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.78, y)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.56, y + h * 0.19)];
            // 箭头前的竖线
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.84, y - h * 0.27)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.84, y + h * 0.27)];
            break;
        }
    }
    return p;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _shapeLayer.frame = self.bounds;
    _shapeLayer.path = [self pathForKind:_kind inRect:self.bounds].CGPath;
}

@end
