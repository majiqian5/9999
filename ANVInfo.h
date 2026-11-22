#import <Foundation/Foundation.h>

/// 无歌词时气泡的「信息轮播」：时间 / 天气 / 农历 / 最近的节气或节日倒计时
@interface ANVInfo : NSObject

/// 可用信息条目（顺序随机但有内容变化），每调用一次内部自增游标
+ (NSString *)nextInfoLineWithWeather:(NSDictionary *)weather;

/// 最近的节气或节日：@"中秋 · 还有 3 天"
+ (NSString *)festivalLine;
/// 农历：@"农历七月十二"
+ (NSString *)lunarLine;
/// 时间：@"周日 17:15"
+ (NSString *)timeLine;

@end
