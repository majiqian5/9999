#import "ANVSettings.h"

static id ANVCopyPref(NSString *key) {
    id value = nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)ANV_PREFS_DOMAIN);
    CFPropertyListRef ref = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       (__bridge CFStringRef)ANV_PREFS_DOMAIN);
    if (ref) {
        value = (__bridge_transfer id)ref;
    }
    if (!value) {
        // rootless 兜底：直接读 /var/jb 下的 plist
        NSString *path = [@"/var/jb/var/mobile/Library/Preferences" stringByAppendingPathComponent:
                          [ANV_PREFS_DOMAIN stringByAppendingPathExtension:@"plist"]];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        value = dict[key];
    }
    return value;
}

static void ANVSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)ANV_PREFS_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)ANV_PREFS_DOMAIN);
}

@interface ANVSettings ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) CGFloat opacity;
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, assign) CGFloat centerX;
@property (nonatomic, assign) CGFloat centerY;
@property (nonatomic, assign) BOOL haptics;
@property (nonatomic, assign) BOOL autoHideInFullScreen;
@end

@implementation ANVSettings

+ (instancetype)shared {
    static ANVSettings *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ANVSettings alloc] init];
        [instance reload];
    });
    return instance;
}

- (void)reload {
    id enabled = ANVCopyPref(@"Enabled");
    self.enabled = enabled ? [enabled boolValue] : YES;

    id opacity = ANVCopyPref(@"Opacity");
    CGFloat op = opacity ? [opacity doubleValue] : 100.0;
    if (op > 1.0) op /= 100.0;                 // 设置面板里是 0~100
    self.opacity = MAX(0.25, MIN(1.0, op));

    id scale = ANVCopyPref(@"Scale");
    CGFloat sc = scale ? [scale doubleValue] : 100.0;
    if (sc > 2.0) sc /= 100.0;                 // 设置面板里是 70~130
    self.scale = MAX(0.6, MIN(1.5, sc));

    id cx = ANVCopyPref(@"CenterX");
    id cy = ANVCopyPref(@"CenterY");
    self.centerX = cx ? [cx doubleValue] : 0.5;
    self.centerY = cy ? [cy doubleValue] : 0.86;

    id haptics = ANVCopyPref(@"Haptics");
    self.haptics = haptics ? [haptics boolValue] : YES;

    id autoHide = ANVCopyPref(@"AutoHideInFullScreen");
    self.autoHideInFullScreen = autoHide ? [autoHide boolValue] : YES;
}

- (void)saveCenter:(CGPoint)normalizedPoint {
    self.centerX = normalizedPoint.x;
    self.centerY = normalizedPoint.y;
    ANVSetPref(@"CenterX", @(normalizedPoint.x));
    ANVSetPref(@"CenterY", @(normalizedPoint.y));
}

@end
