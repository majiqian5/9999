#import <UIKit/UIKit.h>
#import "ANVBarController.h"
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
        }
    });
}

%end
