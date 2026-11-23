#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define ANV_PREFS_DOMAIN @"com.doubao.andronavbar"

typedef NS_ENUM(NSInteger, ANVKeyAction) {
    ANVKeyActionBack = 0,
    ANVKeyActionHome,
    ANVKeyActionRecents,
    ANVKeyActionForward,
    ANVKeyActionPrevious,
    ANVKeyActionPlay,
    ANVKeyActionPause,
    ANVKeyActionNext,
    ANVKeyActionNone,
};

@interface ANVSettings : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) CGFloat opacity;      // 0.3 ~ 1.0
@property (nonatomic, readonly) CGFloat scale;        // 0.7 ~ 1.5
@property (nonatomic, readonly) CGFloat centerX;      // 0 ~ 1（相对屏幕宽）
@property (nonatomic, readonly) CGFloat centerY;      // 0 ~ 1（相对屏幕高）
@property (nonatomic, readonly) BOOL haptics;
@property (nonatomic, readonly) BOOL autoHideInFullScreen; // 全屏（横屏）时自动淡出
@property (nonatomic, readonly) BOOL transparentBackground;
/// 键背景：0 玻璃 / 1 透明 / 2 全透明
@property (nonatomic, readonly) NSInteger keyBackgroundMode;
/// 隐藏拉手（不可见的拖动条）开关
@property (nonatomic, readonly) BOOL handleEnabled;
/// 拉手灵敏度 0.3~2.0（越大越好拖 / 手指不用走远）
@property (nonatomic, readonly) CGFloat handleSensitivity;
@property (nonatomic, readonly) BOOL spectrumEnabled;
@property (nonatomic, readonly) CGFloat spectrumSensitivity; // 0.5 ~ 2.0
@property (nonatomic, readonly) NSInteger spectrumStyle;  // 0 柱状 1 点阵 2 镜像 3 折线
@property (nonatomic, readonly) BOOL positionLocked;      // 锁住后拖不动
@property (nonatomic, readonly) BOOL edgeToEdge;
@property (nonatomic, readonly) NSInteger barOrientation;  // 0 底部横 / 1 左侧竖 / 2 右侧竖
@property (nonatomic, readonly) BOOL petEnabled;
@property (nonatomic, readonly) CGFloat petScale;
@property (nonatomic, readonly) NSInteger petStyle;      // 0 随机 1 小猫 2 小兔 3 小熊
@property (nonatomic, readonly) NSInteger petAction;
@property (nonatomic, readonly) NSInteger petCount;   // 1~5
@property (nonatomic, readonly) NSInteger petSide;   // 0 左 1 右 2 两边
@property (nonatomic, readonly) BOOL showOnLockScreen;
@property (nonatomic, readonly) BOOL lyricEnabled;
@property (nonatomic, readonly) CGFloat lyricScale;
@property (nonatomic, readonly) CGFloat bubbleDX;       // 气泡左右偏移（点）
@property (nonatomic, readonly) CGFloat bubbleDY;       // 气泡上下偏移（点）
@property (nonatomic, readonly) CGFloat bubbleW;        // 气泡宽
@property (nonatomic, readonly) CGFloat bubbleH;        // 气泡高
@property (nonatomic, readonly) CGFloat bubbleAlpha;    // 气泡背景不透明度
@property (nonatomic, readonly) CGFloat haloDotScale;   // 光环点大小 0.6~2.0
@property (nonatomic, readonly) BOOL haloRainbow;       // 九色彩虹
@property (nonatomic, readonly) BOOL haloBounce;        // 跳动/弹跳
@property (nonatomic, readonly) BOOL bubbleAutoFit;     // 气泡宽度随歌词长度自适应
@property (nonatomic, readonly) CGFloat spectrumWidth;     // 频谱横占比 0.2~1.0
@property (nonatomic, readonly) CGFloat spectrumHeight;    // 频谱高占比 0.2~1.0
@property (nonatomic, readonly) NSInteger spectrumBars;    // 柱子数量 4~24
@property (nonatomic, readonly) CGFloat spectrumThickness; // 柱粗 0.15~1.0          // YES：允许拖到真正的屏幕最底（会压住 Home 指示条）
@property (nonatomic, readonly) BOOL micSpectrum;         // 麦克风频谱（AxsEQ 无数据时用）
@property (nonatomic, readonly) BOOL simulateSpectrum;    // 模拟频谱（数据源坏时的占位动画）

- (void)reload;
- (void)saveCenter:(CGPoint)normalizedPoint;
- (ANVKeyAction)actionForSlot:(NSInteger)slot;   // slot 0~3

- (void)saveScalePercent:(CGFloat)percent;          // 70 ~ 150
- (void)saveSpectrumEnabled:(BOOL)enabled;
- (void)saveSpectrumStyle:(NSInteger)style;
- (void)saveSpectrumSensitivity:(CGFloat)value;
- (void)savePositionLocked:(BOOL)locked;
- (void)saveEdgeToEdge:(BOOL)on;
- (void)saveBarOrientation:(NSInteger)o;
- (void)savePetEnabled:(BOOL)on;
- (void)savePetScale:(CGFloat)v;
- (void)savePetStyle:(NSInteger)v;
- (void)savePetAction:(NSInteger)v;
- (void)savePetCount:(NSInteger)v;
- (void)savePetSide:(NSInteger)v;
- (void)saveShowOnLockScreen:(BOOL)v;
- (void)saveLyricEnabled:(BOOL)on;
- (void)saveLyricScale:(CGFloat)v;
- (void)saveBubbleDX:(CGFloat)v;
- (void)saveBubbleDY:(CGFloat)v;
- (void)saveBubbleW:(CGFloat)v;
- (void)saveBubbleH:(CGFloat)v;
- (void)saveBubbleAlpha:(CGFloat)v;
- (void)saveHaloDotScale:(CGFloat)v;
- (void)saveBubbleAutoFit:(BOOL)v;
- (void)saveTransparentBackground:(BOOL)v;
- (void)saveKeyBackgroundMode:(NSInteger)v;
- (void)saveHandleEnabled:(BOOL)v;
- (void)saveHandleSensitivity:(CGFloat)v;
- (void)saveHaloRainbow:(BOOL)v;
- (void)saveHaloBounce:(BOOL)v;
- (void)saveSpectrumWidth:(CGFloat)v;
- (void)saveSpectrumHeight:(CGFloat)v;
- (void)saveSpectrumBars:(NSInteger)v;
- (void)saveSpectrumThickness:(CGFloat)v;
- (void)saveMicSpectrum:(BOOL)enabled;
- (void)saveSimulateSpectrum:(BOOL)enabled;
- (void)saveAction:(ANVKeyAction)action forSlot:(NSInteger)slot;
@end
