#import <Foundation/Foundation.h>
#import "ANVGlyphView.h"

@interface ANVActions : NSObject
/// 执行某个键的动作，返回是否成功
+ (BOOL)performGlyph:(ANVGlyphKind)kind;

+ (BOOL)openBundleID:(NSString *)bundleID;
+ (BOOL)goHome;
+ (BOOL)toggleAppSwitcher;
+ (NSString *)frontmostBundleID;
@end
