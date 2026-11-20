#import <Foundation/Foundation.h>

@interface ANVBarController : NSObject
+ (instancetype)sharedInstance;
- (void)start;
- (void)stop;
@end
