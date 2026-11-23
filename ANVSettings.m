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
@property (nonatomic, assign) NSInteger keyBackgroundMode;
@property (nonatomic, assign) BOOL handleEnabled;
@property (nonatomic, assign) CGFloat handleSensitivity;
@property (nonatomic, assign) BOOL spectrumEnabled;
@property (nonatomic, assign) CGFloat spectrumSensitivity;
@property (nonatomic, strong) NSArray<NSNumber *> *slotActions;
@property (nonatomic, assign) NSInteger spectrumStyle;
@property (nonatomic, assign) BOOL positionLocked;
@property (nonatomic, assign) BOOL edgeToEdge;
@property (nonatomic, assign) NSInteger barOrientation;
@property (nonatomic, assign) BOOL petEnabled;
@property (nonatomic, assign) CGFloat petScale;
@property (nonatomic, assign) NSInteger petStyle;
@property (nonatomic, assign) NSInteger petAction;
@property (nonatomic, assign) NSInteger petCount;
@property (nonatomic, assign) NSInteger petSide;
@property (nonatomic, assign) BOOL showOnLockScreen;
@property (nonatomic, assign) BOOL lyricEnabled;
@property (nonatomic, assign) CGFloat lyricScale;
@property (nonatomic, assign) CGFloat bubbleDX;
@property (nonatomic, assign) CGFloat bubbleDY;
@property (nonatomic, assign) CGFloat bubbleW;
@property (nonatomic, assign) CGFloat bubbleH;
@property (nonatomic, assign) CGFloat bubbleAlpha;
@property (nonatomic, assign) CGFloat haloDotScale;
@property (nonatomic, assign) BOOL haloRainbow;
@property (nonatomic, assign) BOOL haloBounce;
@property (nonatomic, assign) BOOL bubbleAutoFit;
@property (nonatomic, assign) CGFloat spectrumWidth;
@property (nonatomic, assign) CGFloat spectrumHeight;
@property (nonatomic, assign) NSInteger spectrumBars;
@property (nonatomic, assign) CGFloat spectrumThickness;
@property (nonatomic, assign) BOOL micSpectrum;
@property (nonatomic, assign) BOOL simulateSpectrum;
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
    id kbm = ANVCopyPref(@"KeyBgMode");
    self.keyBackgroundMode = kbm ? MIN(MAX([kbm integerValue], 0), 2)
                                 : (self.transparentBackground ? 1 : 0);
    id hEn = ANVCopyPref(@"HandleEnabled");
    self.handleEnabled = hEn ? [hEn boolValue] : YES;
    id hSy = ANVCopyPref(@"HandleSensitivity");
    self.handleSensitivity = hSy ? MIN(MAX([hSy doubleValue], 0.3), 2.0) : 1.0;

    id spectrum = ANVCopyPref(@"SpectrumEnabled");
    self.spectrumEnabled = spectrum ? [spectrum boolValue] : NO;

    id sensitivity = ANVCopyPref(@"SpectrumSensitivity");
    CGFloat sens = sensitivity ? [sensitivity doubleValue] : 100.0;
    if (sens > 3.0) sens /= 100.0;
    self.spectrumSensitivity = MAX(0.4, MIN(2.0, sens));

    // 参考图那种“彩色粒子闪光”观感，首次升级时把默认样式切到粒子
    id migratedFlag = ANVCopyPref(@"StyleMigratedV3");
    if (![migratedFlag boolValue]) {
        ANVSetPref(@"StyleMigratedV3", @YES);
        ANVSetPref(@"SpectrumStyle", @7);
    }
    id style = ANVCopyPref(@"SpectrumStyle");
    NSInteger st = style ? [style integerValue] : 0;
    if (st < 0 || st > 17) st = 7;
    self.spectrumStyle = st;

    id mic = ANVCopyPref(@"MicSpectrum");
    self.micSpectrum = mic ? [mic boolValue] : NO;

    id sim = ANVCopyPref(@"SimulateSpectrum");
    self.simulateSpectrum = sim ? [sim boolValue] : YES;

    id locked = ANVCopyPref(@"PositionLocked");
    self.positionLocked = locked ? [locked boolValue] : NO;
    id edge = ANVCopyPref(@"EdgeToEdge");
    self.edgeToEdge = edge ? [edge boolValue] : NO;

    id ori = ANVCopyPref(@"BarOrientation");
    self.barOrientation = ori ? [ori integerValue] : 0;
    id pet = ANVCopyPref(@"PetEnabled");
    self.petEnabled = pet ? [pet boolValue] : YES;
    id pets = ANVCopyPref(@"PetScale");
    self.petScale = pets ? [pets doubleValue] : 1.0;
    id petst = ANVCopyPref(@"PetStyle");
    self.petStyle = petst ? MIN(MAX([petst integerValue], 0), 10) : 0;
    id pcnt = ANVCopyPref(@"PetCount");
    self.petCount = pcnt ? MIN(MAX([pcnt integerValue], 1), 5) : 1;
    id pside = ANVCopyPref(@"PetSide");
    self.petSide = pside ? MIN(MAX([pside integerValue], 0), 2) : 0;
    id pact = ANVCopyPref(@"PetAction");
    self.petAction = pact ? [pact integerValue] : 0;
    id lshow = ANVCopyPref(@"ShowOnLockScreen");
    self.showOnLockScreen = lshow ? [lshow boolValue] : NO;
    id lyr = ANVCopyPref(@"LyricEnabled");
    self.lyricEnabled = lyr ? [lyr boolValue] : NO;
    id bdx = ANVCopyPref(@"BubbleDX");
    self.bubbleDX = bdx ? [bdx doubleValue] : 0.0;
    id bdy = ANVCopyPref(@"BubbleDY");
    self.bubbleDY = bdy ? [bdy doubleValue] : 0.0;
    id bw = ANVCopyPref(@"BubbleW");
    self.bubbleW = bw ? [bw doubleValue] : 120.0;
    id bh = ANVCopyPref(@"BubbleH");
    self.bubbleH = bh ? [bh doubleValue] : 24.0;
    id ba = ANVCopyPref(@"BubbleAlpha");
    self.bubbleAlpha = ba ? [ba doubleValue] : 0.85;
    id baf = ANVCopyPref(@"BubbleAutoFit");
    self.bubbleAutoFit = baf ? [baf boolValue] : YES;
    id hds = ANVCopyPref(@"HaloDotScale");
    self.haloDotScale = hds ? [hds doubleValue] : 1.0;
    id hrw = ANVCopyPref(@"HaloRainbow");
    self.haloRainbow = hrw ? [hrw boolValue] : YES;
    id hbt = ANVCopyPref(@"HaloBounce");
    self.haloBounce = hbt ? [hbt boolValue] : YES;
    // 夹取脏值：旧版本没写入过这些键时会读成 0
    self.bubbleDX = MIN(MAX(self.bubbleDX, -160.0), 160.0);
    self.bubbleDY = MIN(MAX(self.bubbleDY, -80.0), 80.0);
    if (self.bubbleW < 60.0) self.bubbleW = 120.0;
    if (self.bubbleH < 16.0) self.bubbleH = 24.0;
    if (self.bubbleAlpha < 0.15) self.bubbleAlpha = 0.85;
    if (self.haloDotScale < 0.6) self.haloDotScale = 1.0;
    id lyrs = ANVCopyPref(@"LyricScale");
    self.lyricScale = lyrs ? [lyrs doubleValue] : 1.0;

    id sw = ANVCopyPref(@"SpectrumWidth");
    self.spectrumWidth = sw ? [sw doubleValue] : 1.0;
    id sh = ANVCopyPref(@"SpectrumHeight");
    self.spectrumHeight = sh ? [sh doubleValue] : 1.0;
    id sb = ANVCopyPref(@"SpectrumBars");
    self.spectrumBars = sb ? [sb integerValue] : 10;
    id sth = ANVCopyPref(@"SpectrumThickness");
    self.spectrumThickness = sth ? [sth doubleValue] : 0.62;

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
    NSInteger clamped = MAX(0, MIN(27, style));
    ANVSetPref(@"SpectrumStyle", @(clamped));
    self.spectrumStyle = clamped;
}

- (void)saveSpectrumSensitivity:(CGFloat)value {
    CGFloat clamped = MAX(0.4, MIN(2.0, value));
    ANVSetPref(@"SpectrumSensitivity", @(lround(clamped * 100.0)));
    self.spectrumSensitivity = clamped;
}

- (void)saveMicSpectrum:(BOOL)enabled {
    ANVSetPref(@"MicSpectrum", @(enabled));
    self.micSpectrum = enabled;
}

- (void)saveSimulateSpectrum:(BOOL)enabled {
    ANVSetPref(@"SimulateSpectrum", @(enabled));
    self.simulateSpectrum = enabled;
}

- (void)saveBarOrientation:(NSInteger)o {
    self.barOrientation = MIN(MAX(o, 0), 2);
    ANVSetPref(@"BarOrientation", @(self.barOrientation));
}

- (void)savePetEnabled:(BOOL)on {
    self.petEnabled = on;
    ANVSetPref(@"PetEnabled", @(on));
}

- (void)savePetSide:(NSInteger)v {
    self.petSide = MIN(MAX(v, 0), 2);
    ANVSetPref(@"PetSide", @(self.petSide));
}

- (void)savePetCount:(NSInteger)v {
    self.petCount = MIN(MAX(v, 1), 5);
    ANVSetPref(@"PetCount", @(self.petCount));
}

- (void)savePetAction:(NSInteger)v {
    self.petAction = MIN(MAX(v, 0), 17);
    ANVSetPref(@"PetAction", @(self.petAction));
}

- (void)saveShowOnLockScreen:(BOOL)v {
    self.showOnLockScreen = v;
    ANVSetPref(@"ShowOnLockScreen", @(v));
}

- (void)savePetStyle:(NSInteger)v {
    self.petStyle = MIN(MAX(v, 0), 10);
    ANVSetPref(@"PetStyle", @(self.petStyle));
}

- (void)savePetScale:(CGFloat)v {
    self.petScale = MIN(MAX(v, 0.6), 1.6);
    ANVSetPref(@"PetScale", @(self.petScale));
}

- (void)saveLyricEnabled:(BOOL)on {
    self.lyricEnabled = on;
    ANVSetPref(@"LyricEnabled", @(on));
}

- (void)saveBubbleDX:(CGFloat)v { self.bubbleDX = MIN(MAX(v, -160.0), 160.0); ANVSetPref(@"BubbleDX", @(self.bubbleDX)); }
- (void)saveBubbleDY:(CGFloat)v { self.bubbleDY = MIN(MAX(v, -80.0), 80.0); ANVSetPref(@"BubbleDY", @(self.bubbleDY)); }
- (void)saveBubbleW:(CGFloat)v { self.bubbleW = MIN(MAX(v, 60.0), 360.0); ANVSetPref(@"BubbleW", @(self.bubbleW)); }
- (void)saveBubbleH:(CGFloat)v { self.bubbleH = MIN(MAX(v, 16.0), 44.0); ANVSetPref(@"BubbleH", @(self.bubbleH)); }
- (void)saveBubbleAlpha:(CGFloat)v { self.bubbleAlpha = MIN(MAX(v, 0.15), 1.0); ANVSetPref(@"BubbleAlpha", @(self.bubbleAlpha)); }
- (void)saveTransparentBackground:(BOOL)v { self.transparentBackground = v; ANVSetPref(@"TransparentBackground", @(v)); }

- (void)saveHandleEnabled:(BOOL)v { self.handleEnabled = v; ANVSetPref(@"HandleEnabled", @(v)); }

- (void)saveHandleSensitivity:(CGFloat)v {
    self.handleSensitivity = MIN(MAX(v, 0.3), 2.0);
    ANVSetPref(@"HandleSensitivity", @(self.handleSensitivity));
}

- (void)saveKeyBackgroundMode:(NSInteger)v {
    self.keyBackgroundMode = MIN(MAX(v, 0), 2);
    self.transparentBackground = (self.keyBackgroundMode != 0);
    ANVSetPref(@"KeyBgMode", @(self.keyBackgroundMode));
    ANVSetPref(@"TransparentBackground", @(self.transparentBackground));
}

- (void)saveBubbleAutoFit:(BOOL)v { self.bubbleAutoFit = v; ANVSetPref(@"BubbleAutoFit", @(v)); }

- (void)saveHaloDotScale:(CGFloat)v { self.haloDotScale = MIN(MAX(v, 0.6), 2.0); ANVSetPref(@"HaloDotScale", @(self.haloDotScale)); }
- (void)saveHaloRainbow:(BOOL)v { self.haloRainbow = v; ANVSetPref(@"HaloRainbow", @(v)); }
- (void)saveHaloBounce:(BOOL)v { self.haloBounce = v; ANVSetPref(@"HaloBounce", @(v)); }

- (void)saveLyricScale:(CGFloat)v {
    self.lyricScale = MIN(MAX(v, 0.6), 1.6);
    ANVSetPref(@"LyricScale", @(self.lyricScale));
}

- (void)saveSpectrumWidth:(CGFloat)v {
    self.spectrumWidth = MIN(MAX(v, 0.2), 1.0);
    ANVSetPref(@"SpectrumWidth", @(self.spectrumWidth));
}

- (void)saveSpectrumHeight:(CGFloat)v {
    self.spectrumHeight = MIN(MAX(v, 0.2), 1.0);
    ANVSetPref(@"SpectrumHeight", @(self.spectrumHeight));
}

- (void)saveSpectrumBars:(NSInteger)v {
    self.spectrumBars = MIN(MAX(v, 4), 24);
    ANVSetPref(@"SpectrumBars", @(self.spectrumBars));
}

- (void)saveSpectrumThickness:(CGFloat)v {
    self.spectrumThickness = MIN(MAX(v, 0.15), 1.0);
    ANVSetPref(@"SpectrumThickness", @(self.spectrumThickness));
}

- (void)saveEdgeToEdge:(BOOL)on {
    self.edgeToEdge = on;
    ANVSetPref(@"EdgeToEdge", @(on));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.doubao.andronavbar.reload"
                                                        object:nil];
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
