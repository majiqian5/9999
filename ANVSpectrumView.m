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
    // 彩虹：12 根柱子色相从红渐变到紫
    CGFloat t = (CGFloat)index / (CGFloat)(kANVSpectrumBars - 1);
    CGFloat hue = t * 0.83;              // 0 -> 红, 0.83 -> 紫
    return [UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0];
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
