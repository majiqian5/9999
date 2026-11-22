#import <UIKit/UIKit.h>

/// 导航条上的小宠物：纯矢量绘制（小猫 / 小兔 / 小熊），会跳舞、打架、谈恋爱……
@interface ANVPetView : UIView
@property (nonatomic, assign) CGFloat sizeScale;   // 0.6~1.6，相对默认尺寸
@property (nonatomic, assign) CGFloat energy;      // 0~1，来自频谱低频
/// 举牌上的字（宠物自己把牌子举起来）
@property (nonatomic, copy) NSString *lyricText;
@property (nonatomic, assign) CGFloat textScale;
/// 宠物造型：0 蓝团子 1 电气狐 2 樱花猫 3 企鹅 4 小幽灵
@property (nonatomic, assign) NSInteger style;
/// 同时显示几只：1~5
@property (nonatomic, assign) NSInteger petCount;
/// 动作：0 发呆 1 点头 2 跳舞 3 荡秋千 4 打架 5 谈恋爱 6 唱歌 7 招手 8 转圈
///       9 睡觉 10 蹦跳 11 甩尾巴 12 送花 13 打滚 14 吹泡泡 15 星星环绕 16 爱心发射
@property (nonatomic, assign) NSInteger action;
/// 伙伴造型（打架 / 谈恋爱时出现的第二只）
@property (nonatomic, assign) NSInteger partnerStyle;
- (void)advancePhase:(CGFloat)delta;
+ (NSString *)titleForAction:(NSInteger)action;
+ (NSInteger)actionCount;
+ (NSString *)titleForStyle:(NSInteger)style;
@end

/// 举牌歌词：一块小牌子，上面用彩虹渐变滚字
@interface ANVLyricsView : UIView
@property (nonatomic, assign) CGFloat textScale;   // 0.6~1.6
@property (nonatomic, copy) NSString *text;
- (void)advancePhase:(CGFloat)delta;
@end
