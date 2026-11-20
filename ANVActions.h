#import <Foundation/Foundation.h>
#import "ANVGlyphView.h"

@interface ANVActions : NSObject

+ (void)note:(NSString *)message;
/// 执行某个键的动作，返回是否成功
+ (BOOL)performGlyph:(ANVGlyphKind)kind;

/// 启动时把可用私有 API 写进 /var/mobile/andronavbar.log，方便排错
+ (void)logEnvironment;

+ (BOOL)openBundleID:(NSString *)bundleID;
+ (BOOL)goHome;
+ (BOOL)toggleAppSwitcher;
+ (NSString *)frontmostBundleID;
@end
