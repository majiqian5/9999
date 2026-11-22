#import <UIKit/UIKit.h>

/// 导航条上的小宠物：一只会跟着音乐点头的猫（纯矢量绘制，不依赖图片）
@interface ANVPetView : UIView
@property (nonatomic, assign) CGFloat sizeScale;   // 0.6~1.6，相对默认尺寸
@property (nonatomic, assign) CGFloat energy;      // 0~1，来自频谱低频
- (void)advancePhase:(CGFloat)delta;
@end

/// 举牌歌词：一块小牌子，上面用彩虹渐变滚字
@interface ANVLyricsView : UIView
@property (nonatomic, assign) CGFloat textScale;   // 0.6~1.6
@property (nonatomic, copy) NSString *text;
- (void)advancePhase:(CGFloat)delta;
@end
