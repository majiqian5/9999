#import <Foundation/Foundation.h>

/**
 * 记录 App 的前后台切换顺序，供“返回 / 前进”两个键使用。
 * 通过运行时挂钩 SBApplication -setDisplayed: / -setFrontmost:（存在才挂）来记历史，
 * 挂钩失败时退回读取 SBRecentAppLayouts 的最近任务列表。
 */
@interface ANVHistory : NSObject
+ (instancetype)shared;

+ (void)installHooks;

- (void)record:(NSString *)bundleID;

/// 0.4 秒轮询 SpringBoard 的 _switcherController 拿当前 App，自己记历史
- (void)startTracking;
- (NSString *)frontmostBundleID;

/// 打开失败时清掉“当前 App”标记，避免栈错乱
- (void)invalidateCurrent;
- (void)suppressRecordingFor:(NSTimeInterval)seconds;

- (NSString *)currentBundleID;
- (NSString *)bundleIDForBack;
- (NSString *)bundleIDForForward;

/// 取出并移动历史指针（返回目标 bundleID，已同步更新前进/后退栈）
- (NSString *)moveBack;
- (NSString *)moveForward;
- (void)noteProgrammaticOpen:(NSString *)bundleID;
- (void)noteOpenResult:(NSString *)bundleID success:(BOOL)ok;
@end
