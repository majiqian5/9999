#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ANVGlyphKind) {
    ANVGlyphBack = 0,      // 蓝色三角：返回上一个使用的 App
    ANVGlyphHome,          // 绿色圆圈：回主屏幕
    ANVGlyphRecents,       // 粉色方块：多任务 / 后台
    ANVGlyphForward,       // 黄色箭头：前进到刚才离开的 App
};

@interface ANVGlyphView : UIView
@property (nonatomic, assign) ANVGlyphKind kind;
@property (nonatomic, strong) UIColor *glyphColor;
@property (nonatomic, assign) CGFloat lineWidth;
- (void)setGlowHighlighted:(BOOL)highlighted;
@end
