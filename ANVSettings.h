#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define ANV_PREFS_DOMAIN @"com.doubao.andronavbar"

@interface ANVSettings : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) CGFloat opacity;      // 0.3 ~ 1.0
@property (nonatomic, readonly) CGFloat scale;        // 0.7 ~ 1.3
@property (nonatomic, readonly) CGFloat centerX;      // 0 ~ 1（相对屏幕宽）
@property (nonatomic, readonly) CGFloat centerY;      // 0 ~ 1（相对屏幕高）
@property (nonatomic, readonly) BOOL haptics;
@property (nonatomic, readonly) BOOL autoHideInFullScreen; // 全屏（横屏）时自动淡出

- (void)reload;
- (void)saveCenter:(CGPoint)normalizedPoint;
@end
