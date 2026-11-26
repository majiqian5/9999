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
    ANVSpectrumStyleHelix,        // 双螺旋
    ANVSpectrumStyleBurst,        // 音柱爆点
    ANVSpectrumStyleNeonWave,     // 霓虹波浪
    ANVSpectrumStyleSpokes,       // 旋转射线
    ANVSpectrumStylePulseRing,    // 脉冲光环
    ANVSpectrumStyleMeteor,       // 横向流星
    ANVSpectrumStyleWings,        // 对称羽翼
    ANVSpectrumStylePlasma,       // 等离子云
    ANVSpectrumStyleLaserGrid,    // 激光矩阵
    ANVSpectrumStyleBeatBeam,     // 心跳光带
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
/// 光环旋律动作：0 呼吸 / 1 摇摆 / 2 浮动 / 3 波浪 / 4 双环 / 5 全开 / 6 螺旋 / 7 爆闪 / 8 雨刷
@property (nonatomic, assign) NSInteger haloMotion;

/// 强拍回调：检测到一次"咚"就回调一次（主线程），外面拿它做触感反馈
@property (nonatomic, copy) void (^onBeat)(CGFloat energy);

- (void)advancePhase:(CGFloat)delta;
- (void)updateLevels:(const float *)levels count:(NSUInteger)count;
@end
