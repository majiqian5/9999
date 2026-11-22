#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ANVSpectrumStyle) {
    ANVSpectrumStyleBars = 0,   // 霓虹柱状
    ANVSpectrumStyleDots,       // 点阵
    ANVSpectrumStyleMirror,     // 上下镜像
    ANVSpectrumStyleLine,       // 折线波形
    ANVSpectrumStyleMarquee,    // 跑马灯：一个亮点左右来回跑
    ANVSpectrumStyleStream,     // 流水灯：光带单向循环流动
    ANVSpectrumStylePulse,      // 呼吸波形：正弦起伏扫过
    ANVSpectrumStyleParticles,  // 七色彩虹粒子左右冲撞
    ANVSpectrumStyleDoubleCollide, // 双向对冲：两边粒子同时撞向中间
    ANVSpectrumStyleSpiral,     // 螺旋点阵
    ANVSpectrumStyleRipple,     // 涟漪圆环
    ANVSpectrumStyleWaterfall,  // 瀑布下落
    ANVSpectrumStyleHalo,       // 光环旋转
    ANVSpectrumStyleStrobe,     // 随机闪烁星点
    ANVSpectrumStyleBounceBall, // 弹跳小球
    ANVSpectrumStyleBraid,      // 交织斜线
    ANVSpectrumStyleHeartbeat,  // 心电图
    ANVSpectrumStyleRainStreak, // 七色雨丝
};

/// 导航条背景里的真频谱（10 段真实电平，可插值成 4~24 根柱子）
@interface ANVSpectrumView : UIView
@property (nonatomic, assign) ANVSpectrumStyle style;
/// 跑马灯/流水灯/呼吸都需要时间相位，由外部 tick 推进
@property (nonatomic, assign) CGFloat phase;

/// 柱子数量 4~24
@property (nonatomic, assign) NSInteger barCount;
/// 频谱横向占条宽的比例 0.2~1.0
@property (nonatomic, assign) CGFloat widthRatio;
/// 频谱纵向占条高的比例 0.2~1.0
@property (nonatomic, assign) CGFloat heightRatio;
/// 单根柱子的粗细（占每个槽位的比例）0.15~1.0
@property (nonatomic, assign) CGFloat thickness;

/// 光环（旋转光环样式）专用：点大小倍数 / 九色彩虹 / 跳动
@property (nonatomic, assign) CGFloat haloDotScale;
@property (nonatomic, assign) BOOL haloRainbow;
@property (nonatomic, assign) BOOL haloBounce;

- (void)advancePhase:(CGFloat)delta;
- (void)updateLevels:(const float *)levels count:(NSUInteger)count;
@end
