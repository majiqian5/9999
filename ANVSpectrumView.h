#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ANVSpectrumStyle) {
    ANVSpectrumStyleBars = 0,   // 霓虹柱状
    ANVSpectrumStyleDots,       // 点阵
    ANVSpectrumStyleMirror,     // 上下镜像
    ANVSpectrumStyleLine,       // 折线波形
};

/// 导航条背景里的真频谱（10 段，对应 AxsEQ 的真实电平）
@interface ANVSpectrumView : UIView
@property (nonatomic, assign) ANVSpectrumStyle style;
- (void)updateLevels:(const float *)levels count:(NSUInteger)count;
@end
