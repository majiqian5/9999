#import <Foundation/Foundation.h>
#import "ANVGlyphView.h"

@interface ANVActions : NSObject

+ (void)note:(NSString *)message;
/// 执行某个键的动作，返回是否成功
+ (BOOL)performGlyph:(ANVGlyphKind)kind;

/// 启动时把可用私有 API 写进 /var/mobile/andronavbar.log，方便排错
+ (void)logEnvironment;

/// 音乐控制（MediaRemote，失败时退回 SBMediaController）
+ (BOOL)mediaPlay;
+ (BOOL)mediaPause;
+ (BOOL)mediaNext;
+ (BOOL)mediaPrevious;

+ (BOOL)openBundleID:(NSString *)bundleID;
+ (BOOL)goHome;
+ (BOOL)toggleAppSwitcher;
+ (NSString *)frontmostBundleID;
/// 最近打开过的 App bundleID 列表（最新的在前）
+ (NSArray<NSString *> *)recentBundleIDs;
/// 本次开机自己跟踪到的访问历史
+ (NSArray<NSString *> *)historyBundleIDs;
@end
