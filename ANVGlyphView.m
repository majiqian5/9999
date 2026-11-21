#import "ANVGlyphView.h"

@interface ANVGlyphView ()
@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) UIImageView *imageView;
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

        _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.userInteractionEnabled = NO;
        _imageView.hidden = YES;
        [self addSubview:_imageView];

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
    // 统一成同一视觉外接框：四种图标占同样的大小，看起来才像一套
    CGFloat side = MIN(r.size.width, r.size.height) * 0.62;
    CGRect box = CGRectMake(CGRectGetMidX(r) - side / 2.0,
                            CGRectGetMidY(r) - side / 2.0,
                            side, side);
    CGFloat w = box.size.width, h = box.size.height;
    r = box;
    UIBezierPath *p = [UIBezierPath bezierPath];

    switch (kind) {
        case ANVGlyphBack: {
            CGPoint a = CGPointMake(CGRectGetMinX(r) + w * 0.97, CGRectGetMinY(r) + h * 0.02);
            CGPoint b = CGPointMake(CGRectGetMinX(r) + w * 0.03, CGRectGetMidY(r));
            CGPoint c = CGPointMake(CGRectGetMinX(r) + w * 0.97, CGRectGetMinY(r) + h * 0.98);
            [p moveToPoint:a];
            [p addLineToPoint:b];
            [p addLineToPoint:c];
            [p closePath];
            break;
        }
        case ANVGlyphHome: {
            [p addArcWithCenter:CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r))
                          radius:w * 0.5
                      startAngle:0
                        endAngle:M_PI * 2
                       clockwise:YES];
            break;
        }
        case ANVGlyphRecents: {
            CGRect sq = r;
            UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:sq cornerRadius:w * 0.12];
            [p appendPath:rounded];
            break;
        }
        case ANVGlyphForward: {
            CGFloat y = CGRectGetMidY(r);
            // 横线
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.02, y)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.72, y)];
            // 箭头
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.58, y - h * 0.24)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.88, y)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.58, y + h * 0.24)];
            // 箭头后的竖线（跟参考图一致）
            [p moveToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.93, y - h * 0.34)];
            [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + w * 0.93, y + h * 0.34)];
            break;
        }
    }
    return p;
}

- (void)setGlyphImage:(UIImage *)image {
    self.imageView.image = image;
    self.imageView.hidden = (image == nil);
    self.shapeLayer.hidden = (image != nil);
    if (image) {
        self.imageView.layer.shadowColor = self.glyphColor.CGColor;
        self.imageView.layer.shadowOffset = CGSizeZero;
        self.imageView.layer.shadowRadius = 7.0;
        self.imageView.layer.shadowOpacity = 0.9;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _shapeLayer.frame = self.bounds;
    _shapeLayer.path = [self pathForKind:_kind inRect:self.bounds].CGPath;

    CGFloat inset = 3.0;
    _imageView.frame = CGRectInset(self.bounds, inset, inset);
}

@end
