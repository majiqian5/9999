#import <UIKit/UIKit.h>

/// 卡片式后台（Android 风格叠卡）：由 4 键条里的「后台」键唤出
@interface ANVRecents : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isShowing) BOOL showing;

/// 在宿主视图里弹出/收起卡片后台；host 一般是导航条所在的全屏窗口
- (void)toggleInHost:(UIView *)host;
- (void)dismiss;

@end
