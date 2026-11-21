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
@property (nonatomic, assign) BOOL transparentBackground;
@property (nonatomic, assign) BOOL spectrumEnabled;
@property (nonatomic, assign) CGFloat spectrumSensitivity;
@property (nonatomic, strong) NSArray<NSNumber *> *slotActions;
@property (nonatomic, assign) NSInteger spectrumStyle;
@property (nonatomic, assign) BOOL positionLocked;
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

    // 老版本单指拖动容易在列表里误拖，升级后强制归位一次
    id migrated = ANVCopyPref(@"PositionMigratedV2");
    if (!migrated) {
        self.centerX = 0.5;
        self.centerY = 0.86;
        ANVSetPref(@"CenterX", @(0.5));
        ANVSetPref(@"CenterY", @(0.86));
        ANVSetPref(@"PositionMigratedV2", @YES);
    } else {
        self.centerX = cx ? [cx doubleValue] : 0.5;
        self.centerY = cy ? [cy doubleValue] : 0.86;
    }

    id haptics = ANVCopyPref(@"Haptics");
    self.haptics = haptics ? [haptics boolValue] : YES;

    id autoHide = ANVCopyPref(@"AutoHideInFullScreen");
    self.autoHideInFullScreen = autoHide ? [autoHide boolValue] : YES;

    id transparent = ANVCopyPref(@"TransparentBackground");
    self.transparentBackground = transparent ? [transparent boolValue] : YES;

    id spectrum = ANVCopyPref(@"SpectrumEnabled");
    self.spectrumEnabled = spectrum ? [spectrum boolValue] : NO;

    id sensitivity = ANVCopyPref(@"SpectrumSensitivity");
    CGFloat sens = sensitivity ? [sensitivity doubleValue] : 100.0;
    if (sens > 3.0) sens /= 100.0;
    self.spectrumSensitivity = MAX(0.4, MIN(2.0, sens));

    id style = ANVCopyPref(@"SpectrumStyle");
    NSInteger st = style ? [style integerValue] : 0;
    if (st < 0 || st > 6) st = 0;
    self.spectrumStyle = st;

    id locked = ANVCopyPref(@"PositionLocked");
    self.positionLocked = locked ? [locked boolValue] : NO;

    NSInteger defaults[4] = {ANVKeyActionBack, ANVKeyActionHome, ANVKeyActionRecents, ANVKeyActionForward};
    NSMutableArray *actions = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger slot = 0; slot < 4; slot++) {
        NSString *key = [NSString stringWithFormat:@"Action%ld", (long)slot];
        id value = ANVCopyPref(key);
        NSInteger action = value ? [value integerValue] : defaults[slot];
        if (action < ANVKeyActionBack || action > ANVKeyActionNone) action = defaults[slot];
        [actions addObject:@(action)];
    }
    self.slotActions = actions;
}

- (void)saveScalePercent:(CGFloat)percent {
    CGFloat clamped = MAX(70.0, MIN(150.0, percent));
    ANVSetPref(@"Scale", @(clamped));
    self.scale = clamped / 100.0;
}

- (void)saveSpectrumStyle:(NSInteger)style {
    NSInteger clamped = MAX(0, MIN(6, style));
    ANVSetPref(@"SpectrumStyle", @(clamped));
    self.spectrumStyle = clamped;
}

- (void)saveSpectrumSensitivity:(CGFloat)value {
    CGFloat clamped = MAX(0.4, MIN(2.0, value));
    ANVSetPref(@"SpectrumSensitivity", @(lround(clamped * 100.0)));
    self.spectrumSensitivity = clamped;
}

- (void)savePositionLocked:(BOOL)locked {
    ANVSetPref(@"PositionLocked", @(locked));
    self.positionLocked = locked;
}

- (void)saveSpectrumEnabled:(BOOL)enabled {
    ANVSetPref(@"SpectrumEnabled", @(enabled));
    self.spectrumEnabled = enabled;
}

- (void)saveAction:(ANVKeyAction)action forSlot:(NSInteger)slot {
    if (slot < 0 || slot > 3) return;
    NSMutableArray *actions = [[self slotActions] mutableCopy] ?: [NSMutableArray array];
    while (actions.count < 4) [actions addObject:@(slot == 1 ? 1 : slot)];
    actions[slot] = @((NSInteger)action);
    ANVSetPref([NSString stringWithFormat:@"Action%ld", (long)slot], @((NSInteger)action));
    self.slotActions = actions;
}

- (ANVKeyAction)actionForSlot:(NSInteger)slot {
    if (slot < 0 || slot >= (NSInteger)self.slotActions.count) return ANVKeyActionNone;
    return (ANVKeyAction)[self.slotActions[slot] integerValue];
}

- (void)saveCenter:(CGPoint)normalizedPoint {
    self.centerX = normalizedPoint.x;
    self.centerY = normalizedPoint.y;
    ANVSetPref(@"CenterX", @(normalizedPoint.x));
    ANVSetPref(@"CenterY", @(normalizedPoint.y));
}

@end
