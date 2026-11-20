#import <UIKit/UIKit.h>

/// 导航条背景里的真频谱条（12 段），只有音乐播放时才有数据
@interface ANVSpectrumView : UIView
- (void)updateLevels:(const float *)levels count:(NSUInteger)count;
@end
