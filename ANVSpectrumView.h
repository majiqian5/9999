#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ANVSpectrumStyle) {
    ANVSpectrumStyleBars = 0,   // 霓虹柱状
    ANVSpectrumStyleDots,       // 点阵
    ANVSpectrumStyleMirror,     // 上下镜像
    ANVSpectrumStyleLine,       // 折线波形
    ANVSpectrumStyleMarquee,    // 跑马灯：一个亮点左右来回跑
    ANVSpectrumStyleStream,     // 流水灯：光带单向循环流动
    ANVSpectrumStylePulse,      // 呼吸波形：正弦起伏扫过
};

/// 导航条背景里的真频谱（10 段，对应 AxsEQ 的真实电平）
@interface ANVSpectrumView : UIView
@property (nonatomic, assign) ANVSpectrumStyle style;
/// 跑马灯/流水灯/呼吸都需要时间相位，由外部 tick 推进
@property (nonatomic, assign) CGFloat phase;
- (void)advancePhase:(CGFloat)delta;
- (void)updateLevels:(const float *)levels count:(NSUInteger)count;
@end
