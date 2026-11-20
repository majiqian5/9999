#import <UIKit/UIKit.h>
#import "ANVBarController.h"
#import "ANVActions.h"
#import "ANVSettings.h"

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    // 等 SpringBoard 主界面起来再挂悬浮条
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            [[ANVBarController sharedInstance] start];
        } @catch (NSException *e) {
            NSLog(@"[AndroNavBar] start failed: %@", e);
            [ANVActions note:[NSString stringWithFormat:@"start exception: %@", e.reason]];
        }
    });
}

%end

%ctor {
    @autoreleasepool {
        [ANVActions note:@"dylib loaded (ctor)"];
        // 不依赖某个 hook 是否被调用：注入后自己起，失败再重试
        for (int i = 0; i < 6; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1.5 + i * 1.5) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                @try {
                    [[ANVBarController sharedInstance] start];
                } @catch (NSException *e) {
                    [ANVActions note:[NSString stringWithFormat:@"retry exception: %@", e.reason]];
                }
            });
        }
    }
}
