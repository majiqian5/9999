#import "ANVSpectrumView.h"

#define kANVSpectrumBars 12

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
    // 青 -> 粉 -> 黄，跟四个图标同一套霓虹色
    CGFloat t = (CGFloat)index / (CGFloat)(kANVSpectrumBars - 1);
    if (t < 0.5) {
        CGFloat k = t * 2.0;
        return [UIColor colorWithRed:0.31 + 0.69 * k
                               green:0.76 - 0.52 * k
                                blue:1.00 - 0.50 * k
                               alpha:1.0];
    }
    CGFloat k = (t - 0.5) * 2.0;
    return [UIColor colorWithRed:1.0
                           green:0.24 + 0.54 * k
                            blue:0.50 - 0.24 * k
                           alpha:1.0];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat barWidth = 3.0;
    CGFloat gap = 2.5;
    CGFloat totalWidth = kANVSpectrumBars * barWidth + (kANVSpectrumBars - 1) * gap;
    CGFloat startX = (CGRectGetWidth(rect) - totalWidth) / 2.0;
    CGFloat maxHeight = CGRectGetHeight(rect);
    CGFloat baseY = CGRectGetMaxY(rect);

    for (NSInteger i = 0; i < kANVSpectrumBars; i++) {
        CGFloat level = MAX(_levels[i], 0.04f);
        CGFloat height = MAX(2.0, maxHeight * level);
        CGRect barRect = CGRectMake(startX + i * (barWidth + gap),
                                    baseY - height,
                                    barWidth,
                                    height);

        UIColor *color = [self colorForBar:i];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 5.0, color.CGColor);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                            cornerRadius:barWidth / 2.0];
        [path fill];
    }
}

@end
