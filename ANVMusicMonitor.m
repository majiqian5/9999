#import "ANVMusicMonitor.h"
#import "ANVActions.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#define kANVBandCount 10
#define kANVFFTSize 1024

typedef void (*MRGetNowPlayingInfoFn)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));

@interface ANVMusicMonitor ()
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign) BOOL micAvailable;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, assign) BOOL tapInstalled;
@property (nonatomic, assign) FFTSetup fftSetup;
@property (nonatomic, assign) float *window;
@property (nonatomic, assign) float *levels;

// AxsEQ 真电平：/var/tmp/AxsEQ/levels.txt 由 mediaserverd 写入
@property (nonatomic, strong) NSTimer *axsTimer;
@property (nonatomic, assign) float axsMinDb;
@property (nonatomic, assign) float axsMaxDb;
@property (nonatomic, assign) BOOL axsAvailable;
@property (nonatomic, assign) BOOL axsRangeLoaded;
@end

@implementation ANVMusicMonitor {
    float _axsLevels[10];
    float _micLevels[10];
    CGFloat _simTime;
    AVAudioEngine *_engine;
    BOOL _tapInstalled;
    FFTSetup _fftSetup;
    float *_window;
    CFTimeInterval _lastChangeAt;   // 电平最后一次明显变化的时间（用来识别"卡住不动"的假数据）
    CGFloat _lastEnergy;
    float _axsPeak;      // 自适应量程的峰值（AxsEQ 数值不落在 range.txt 里时用）
    int _axsScaleMode;   // 0 已归一化 1 按 range.txt 2 自适应
}

+ (instancetype)shared {
    static ANVMusicMonitor *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ANVMusicMonitor alloc] init];
        instance.levels = calloc(kANVBandCount, sizeof(float));
    });
    return instance;
}

- (void)start {
    if (self.pollTimer) return;
    [self startAxsReader];

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.8
                                                      target:self
                                                    selector:@selector(pollPlayback)
                                                    userInfo:nil
                                                     repeats:YES];
    [self pollPlayback];
}

#pragma mark - 播放状态

- (BOOL)springBoardIsPlaying {
    Class mediaClass = objc_getClass("SBMediaController");
    if (!mediaClass || ![mediaClass respondsToSelector:@selector(sharedInstance)]) return NO;
    id controller = [(id)mediaClass performSelector:@selector(sharedInstance)];
    SEL sel = @selector(isPlaying);
    if (![controller respondsToSelector:sel]) return NO;
    BOOL (*fn)(id, SEL) = (BOOL (*)(id, SEL))[controller methodForSelector:sel];
    return fn(controller, sel);
}

- (void)mediaRemoteIsPlaying:(void (^)(BOOL))completion {
    static MRGetNowPlayingInfoFn getInfo = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (handle) getInfo = (MRGetNowPlayingInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    });
    if (!getInfo) {
        completion(NO);
        return;
    }
    getInfo(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(CFDictionaryRef info) {
        BOOL playing = NO;
        if (info) {
            NSDictionary *dict = (__bridge_transfer NSDictionary *)CFRetain(info);
            NSNumber *rate = dict[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
            playing = rate ? (rate.doubleValue > 0.01) : NO;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(playing);
        });
    });
}

- (void)pollPlayback {
    BOOL sbPlaying = [self springBoardIsPlaying];
    [self mediaRemoteIsPlaying:^(BOOL mrPlaying) {
        BOOL playing = sbPlaying || mrPlaying;
        if (playing != self.playing) {
            self.playing = playing;
            if (playing) {
                [self startMicrophone];
            } else {
                [self stopMicrophone];
            }
        } else if (playing) {
            [self ensureMicrophoneRunning];
        }
    }];
}

#pragma mark - 麦克风 / FFT

- (void)setMicEnabled:(BOOL)micEnabled {
    _micEnabled = micEnabled;
    if (micEnabled) {
        [self startMicCapture];
    } else {
        [self stopMicCapture];
    }
}

- (void)startMicCapture {
    if (_engine) return;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (session.recordPermission != AVAudioSessionRecordPermissionGranted) {
        self.micAvailable = NO;
        [ANVActions note:@"mic: 未授权（需要在系统设置里给 SpringBoard 麦克风权限）"];
        return;
    }

    NSError *error = nil;
    @try {
        // MixWithOthers 是关键：不抢音频焦点，音乐继续播
        [session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                              AVAudioSessionCategoryOptionDefaultToSpeaker |
                              AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers
                        error:&error];
        [session setMode:AVAudioSessionModeMeasurement error:&error];
        [session setActive:YES error:&error];

        _fftSetup = vDSP_create_fftsetup(10, kFFTRadix2);
        _window = calloc(1024, sizeof(float));
        vDSP_hann_window(_window, 1024, vDSP_HANN_NORM);

        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *input = engine.inputNode;
        AVAudioFormat *format = [input outputFormatForBus:0];
        __weak typeof(self) weakSelf = self;
        [input installTapOnBus:0 bufferSize:1024 format:format
                         block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            [weakSelf processMicBuffer:buffer];
        }];
        _tapInstalled = YES;
        [engine prepare];
        if (![engine startAndReturnError:&error]) {
            self.micAvailable = NO;
            [self stopMicCapture];
            return;
        }
        _engine = engine;
        self.micAvailable = YES;
        [ANVActions note:@"mic: 采集已启动"];
    } @catch (NSException *e) {
        self.micAvailable = NO;
        [self stopMicCapture];
        [ANVActions note:[NSString stringWithFormat:@"mic: 启动异常 %@", e.reason]];
    }
}

- (void)stopMicCapture {
    @try {
        if (_tapInstalled && _engine) {
            [_engine.inputNode removeTapOnBus:0];
            _tapInstalled = NO;
        }
        [_engine stop];
    } @catch (__unused NSException *e) {}
    _engine = nil;
    if (_fftSetup) { vDSP_destroy_fftsetup(_fftSetup); _fftSetup = NULL; }
    if (_window) { free(_window); _window = NULL; }
    for (NSUInteger i = 0; i < 10; i++) _micLevels[i] = 0;
}

- (void)processMicBuffer:(AVAudioPCMBuffer *)buffer {
    if (!_fftSetup || !buffer.floatChannelData) return;
    float *samples = buffer.floatChannelData[0];
    if (buffer.frameLength < 1024) return;

    static float windowed[1024];
    static float real[512];
    static float imag[512];
    static float magnitudes[512];
    static DSPSplitComplex split;

    vDSP_vmul(samples, 1, _window, 1, windowed, 1, 1024);
    split.realp = real;
    split.imagp = imag;
    vDSP_ctoz((DSPComplex *)windowed, 2, &split, 1, 512);
    vDSP_fft_zrip(_fftSetup, &split, 1, 10, kFFTDirection_Forward);
    split.imagp[0] = 0.0f;
    vDSP_zvabs(&split, 1, magnitudes, 1, 512);

    NSUInteger minBin = 2, maxBin = 200;
    float ratio = powf((float)maxBin / (float)minBin, 1.0f / 10.0f);
    for (NSUInteger band = 0; band < 10; band++) {
        NSUInteger startB = (NSUInteger)(minBin * powf(ratio, band));
        NSUInteger endB = (NSUInteger)(minBin * powf(ratio, band + 1));
        endB = MIN(MAX(endB, startB + 1), 512);
        float sum = 0;
        for (NSUInteger i = startB; i < endB; i++) sum += magnitudes[i];
        float avg = sum / (float)(endB - startB);
        float level = avg > 0.00001f ? log10f(avg * 400.0f + 1.0f) / 2.5f : 0.0f;
        level = MIN(MAX(level, 0.0f), 1.0f);
        float old = _micLevels[band];
        _micLevels[band] = level > old ? level : old * 0.82f + level * 0.18f;
    }
}

- (void)startMicrophone {
    // 曾经用 AVAudioEngine 采麦克风，但它会重新设定全局 AudioSession 类别
    //（PlayAndRecord），直接把正在播放的音乐掐掉。现在频谱只走 AxsEQ 的真实电平，
    // 完全不碰 AudioSession，播放音乐不会再被中断。
    self.micAvailable = NO;
}

- (void)ensureMicrophoneRunning {
    if (!self.engine) {
        [self startMicrophone];
        return;
    }
    if (!self.engine.isRunning) {
        NSError *error = nil;
        [self.engine startAndReturnError:&error];
    }
}

- (void)stopMicrophone {
    [self teardownEngine];
    for (NSUInteger i = 0; i < kANVBandCount; i++) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.levels[i] *= 0.6;
        });
    }
}

- (void)teardownEngine {
    @try {
        if (self.tapInstalled) {
            [self.engine.inputNode removeTapOnBus:0];
            self.tapInstalled = NO;
        }
        [self.engine stop];
    } @catch (__unused NSException *e) {}
    self.engine = nil;
    if (self.fftSetup) {
        vDSP_destroy_fftsetup(self.fftSetup);
        self.fftSetup = NULL;
    }
    if (self.window) {
        free(self.window);
        self.window = NULL;
    }
}

- (void)processBuffer:(AVAudioPCMBuffer *)buffer {
    if (!self.fftSetup || !buffer.floatChannelData) return;

    float *samples = buffer.floatChannelData[0];
    vDSP_Length length = MIN(buffer.frameLength, kANVFFTSize);
    if (length < kANVFFTSize) return;

    static float windowed[kANVFFTSize];
    static float real[kANVFFTSize / 2];
    static float imag[kANVFFTSize / 2];
    static float magnitudes[kANVFFTSize / 2];
    static DSPSplitComplex split;

    vDSP_vmul(samples, 1, self.window, 1, windowed, 1, kANVFFTSize);

    split.realp = real;
    split.imagp = imag;
    vDSP_ctoz((DSPComplex *)windowed, 2, &split, 1, kANVFFTSize / 2);
    vDSP_fft_zrip(self.fftSetup, &split, 1, log2f(kANVFFTSize), kFFTDirection_Forward);
    split.imagp[0] = 0.0f;
    vDSP_zvabs(&split, 1, magnitudes, 1, kANVFFTSize / 2);

    // 对数分频，2 ~ 200 bin
    NSUInteger minBin = 2, maxBin = 200;
    float ratio = powf((float)maxBin / minBin, 1.0f / kANVBandCount);
    for (NSUInteger band = 0; band < kANVBandCount; band++) {
        NSUInteger start = (NSUInteger)(minBin * powf(ratio, band));
        NSUInteger end = (NSUInteger)(minBin * powf(ratio, band + 1));
        end = MIN(MAX(end, start + 1), kANVFFTSize / 2);

        float sum = 0;
        for (NSUInteger i = start; i < end; i++) sum += magnitudes[i];
        float avg = sum / (float)(end - start);

        // 压成 0~1，dB 感
        float level = 0;
        if (avg > 0.00001f) {
            level = log10f(avg * 400.0f + 1.0f) / 2.5f;
        }
        level = MIN(MAX(level, 0.0f), 1.0f);

        // 快起慢落，像真实电平表
        float old = self.levels[band];
        self.levels[band] = level > old ? level : old * 0.82f + level * 0.18f;
    }
}

#pragma mark - AxsEQ 真实电平

- (void)loadAxsRange {
    if (self.axsRangeLoaded) return;
    self.axsMinDb = -42.0f;
    self.axsMaxDb = 6.0f;
    NSString *rangePath = @"/var/tmp/AxsEQ/range.txt";
    NSString *text = [NSString stringWithContentsOfFile:rangePath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (text.length) {
        NSScanner *scanner = [NSScanner scannerWithString:text];
        float lo = 0, hi = 0;
        if ([scanner scanFloat:&lo] && [scanner scanFloat:&hi] && hi > lo) {
            self.axsMinDb = lo;
            self.axsMaxDb = hi;
        }
    }
    self.axsRangeLoaded = YES;
    [ANVActions note:[NSString stringWithFormat:@"axs range %.1f..%.1f dB",
                      self.axsMinDb, self.axsMaxDb]];
}

- (void)startAxsReader {
    if (self.axsTimer) return;
    [self loadAxsRange];
    [ANVActions note:@"axs: reader started"];
    self.axsTimer = [NSTimer timerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *timer) {
        [self pollAxsLevels];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.axsTimer forMode:NSRunLoopCommonModes];
}

- (void)pollAxsLevels {
    NSString *path = @"/var/tmp/AxsEQ/levels.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    static BOOL loggedFirstTick = NO;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!loggedFirstTick) {
        loggedFirstTick = YES;
        [ANVActions note:[NSString stringWithFormat:@"axs: first tick attrs=%@ readable=%d",
                          attrs ? attrs[NSFileSize] : @"nil",
                          (int)(attrs != nil)]];
    }
    if (!attrs) {
        static int missingLogs = 0;
        if (missingLogs < 2) {
            missingLogs++;
            [ANVActions note:@"axs levels.txt missing (/var/tmp/AxsEQ/levels.txt)"];
        }
        for (NSUInteger i = 0; i < kANVBandCount; i++) _axsLevels[i] *= 0.7f;
        self.axsAvailable = NO;
        return;
    }

    static int readLogs = 0;
    NSDate *modified = attrs[NSFileModificationDate];
    double age = modified ? -[modified timeIntervalSinceNow] : 999.0;

    static NSTimeInterval lastEmptyLog = 0;
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (!text.length) {
        NSTimeInterval nowE = [NSDate date].timeIntervalSince1970;
        if (nowE - lastEmptyLog > 5.0) {
            lastEmptyLog = nowE;
            NSNumber *size = attrs[NSFileSize];
            [ANVActions note:[NSString stringWithFormat:
                @"axs: levels.txt 存在但内容为空 size=%@ age=%.1f（AxsEQ 还没写数，先跑 axs_on）",
                size, age]];
        }
        return;
    }

    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    float values[10] = {0};
    NSUInteger found = 0;
    for (NSString *part in parts) {
        if (!part.length) continue;
        if ([part.uppercaseString isEqualToString:@"AXS"]) continue;
        double v = part.doubleValue;
        if (found < 10) values[found++] = (float)v;
        if (found >= 10) break;
    }
    // AxsEQ 有时会写出一串 nan（它自己的算法在除零/未初始化时崩了），
    // 直接当 0 处理，否则整张频谱会被 NaN 渲染成空白
    BOOL allNaN = YES;
    for (NSUInteger i = 0; i < found; i++) {
        if (isnan(values[i]) || isinf(values[i])) values[i] = self.axsMinDb;
        else allNaN = NO;
    }
    if (allNaN && found > 0) {
        static NSTimeInterval lastNaNLog = 0;
        NSTimeInterval nowN = [NSDate date].timeIntervalSince1970;
        if (nowN - lastNaNLog > 5.0) {
            lastNaNLog = nowN;
            [ANVActions note:@"axs: levels.txt 全是 nan（AxsEQ 采样失效，不是插件问题）"];
        }
        for (NSUInteger i = 0; i < kANVBandCount; i++) _axsLevels[i] *= 0.7f;
        return;
    }

    if (found < 4) {
        if (readLogs < 3) {
            readLogs++;
            [ANVActions note:[NSString stringWithFormat:@"axs parse failed n=%lu text=%@",
                              (unsigned long)found, [text substringToIndex:MIN(text.length, 60u)]]];
        }
        return;
    }
    if (!self.axsAvailable) {
        [ANVActions note:[NSString stringWithFormat:@"axs online n=%lu v0=%.2f age=%.2f",
                          (unsigned long)found, values[0], age]];
    }
    self.axsAvailable = YES;

    // 超过 0.6 秒没更新（暂停/停止播放）就当静音，柱子立刻落下去
    BOOL fresh = (age < 0.6);
    float range = MAX(1.0f, self.axsMaxDb - self.axsMinDb);

    // 关键：AxsEQ v1.8.2 写出来的数（实测 6..40）根本不在 range.txt 的 -42..6 量程里。
    // 按 range 夹会得到 (40+42)/48 > 1 → 10 根柱子全部顶满，看起来就是一条静止的平线。
    // 所以先判断标度，不对就自动换一套。
    float mx = -99999.f, mn = 99999.f;
    for (NSUInteger i = 0; i < found; i++) {
        mx = MAX(mx, values[i]);
        mn = MIN(mn, values[i]);
    }
    if (_axsScaleMode <= 0) {
        if (mx <= 1.6f) {
            _axsScaleMode = 1;   // 已经是 0..1 归一化值
        } else if (mx <= self.axsMaxDb + 2.0f && mn >= self.axsMinDb - 8.0f) {
            _axsScaleMode = 2;   // 老老实实按 range.txt
        } else {
            _axsScaleMode = 3;   // 未知标度，自适应
        }
        [ANVActions note:[NSString stringWithFormat:
            @"axs scale=%d (min=%.2f max=%.2f range=%.1f..%.1f)",
            _axsScaleMode, mn, mx, self.axsMinDb, self.axsMaxDb]];
    }

    if (_axsScaleMode == 3) {
        // 自适应：峰值缓降，留 15% 底噪余量，音乐起伏就明显了
        _axsPeak = MAX(_axsPeak * 0.985f, mx);
        _axsPeak = MIN(MAX(_axsPeak, 16.0f), 120.0f);
    }

    static int traceTicks = 0;
    for (NSUInteger i = 0; i < kANVBandCount; i++) {
        float db = i < found ? values[i] : self.axsMinDb;
        float target;
        if (_axsScaleMode == 1) {
            target = db;
        } else if (_axsScaleMode == 2) {
            target = (db - self.axsMinDb) / range;
        } else {
            target = (db - _axsPeak * 0.15f) / (_axsPeak * 0.85f);
        }
        target = fresh ? MIN(MAX(target, 0.0f), 1.0f) : 0.0f;

        float old = _axsLevels[i];
        _axsLevels[i] = target > old ? target : old * 0.86f + target * 0.14f;
    }

    // 电平一直不动 = 数据源卡住了（音乐停了但 mediaserverd 还在写同一个值，或者写死了）
    CGFloat energyNow = 0.0;
    for (NSUInteger i = 0; i < kANVBandCount; i++) energyNow += _axsLevels[i];
    energyNow /= (CGFloat)kANVBandCount;
    if (fabs(energyNow - _lastEnergy) > 0.01) {
        _lastEnergy = energyNow;
        _lastChangeAt = [NSDate date].timeIntervalSince1970;
    }

    if (++traceTicks % 40 == 0) {
        [ANVActions note:[NSString stringWithFormat:
            @"axs trace mode=%d peak=%.1f b0=%.2f b4=%.2f b9=%.2f fresh=%d",
            _axsScaleMode, _axsPeak, _axsLevels[0], _axsLevels[4], _axsLevels[9], (int)fresh]];
    }
}

#pragma mark - 模拟频谱（占位动画，不是真实电平）

- (void)fillSimulatedLevels:(float *)levels count:(NSUInteger)count {
    static float sim[10];
    static NSTimeInterval lastSim = 0;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    CGFloat dt = lastSim > 0 ? (CGFloat)(now - lastSim) : 0.05;
    lastSim = now;
    dt = MIN(MAX(dt, 0.01), 0.20);
    _simTime += dt;

    for (NSUInteger i = 0; i < 10; i++) {
        CGFloat t = _simTime;
        // 低频高一点、高频低一点，再叠两个不同速率的正弦，看起来像鼓点和旋律
        CGFloat base = 0.55 - (CGFloat)i * 0.035;
        CGFloat w1 = 0.5 + 0.5 * sin(t * (1.7 + i * 0.13) + i * 0.9);
        CGFloat w2 = 0.5 + 0.5 * sin(t * (0.6 + i * 0.05) + i * 1.7);
        CGFloat target = base * (0.35 + 0.45 * w1 + 0.35 * w2);
        target = MIN(MAX(target, 0.02), 1.0);
        sim[i] = sim[i] * 0.85f + (float)target * 0.15f;
        if (i < count) levels[i] = sim[i];
    }
    for (NSUInteger i = 10; i < count; i++) levels[i] = 0.0f;
}

#pragma mark - 对外

- (void)stop {
    [self.axsTimer invalidate];
    self.axsTimer = nil;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self stopMicrophone];
    self.playing = NO;
}

- (NSString *)sourceLabel {
    NSTimeInterval nowL = [NSDate date].timeIntervalSince1970;
    if (self.axsAvailable) {
        if (_lastChangeAt <= 0 || nowL - _lastChangeAt > 1.5) return @"AxsEQ 卡住";
        return @"AxsEQ 真电平";
    }
    if (self.micAvailable && self.micEnabled) return @"麦克风";
    if (self.simulateEnabled) return @"模拟动画";
    return @"无信号";
}

- (CGFloat)currentEnergy {
    CGFloat sum = 0.0;
    for (NSUInteger i = 0; i < kANVBandCount; i++) sum += _axsLevels[i];
    return sum / (CGFloat)kANVBandCount;
}

- (void)fillLevels:(float *)levels count:(NSUInteger)count {
    if (!levels) return;
    NSUInteger n = MIN(count, (NSUInteger)kANVBandCount);

    // 优先用 AxsEQ 的真实电平（文件新鲜度已代表"正在播放"），没有它才退回麦克风 FFT
    if (self.axsAvailable) {
        // 电平 1.5 秒没有任何变化 → 判定为数据源卡死（不是真电平），直接给 0，
        // 否则音乐一停、文件还在原地循环写同一个值，光环就会一直转个不停
        NSTimeInterval nowL = [NSDate date].timeIntervalSince1970;
        BOOL stuck = (_lastChangeAt <= 0 || nowL - _lastChangeAt > 1.5);
        if (stuck) {
            for (NSUInteger i = 0; i < count; i++) levels[i] = 0.0f;
            return;
        }
        for (NSUInteger i = 0; i < count; i++) {
            levels[i] = (i < kANVBandCount) ? _axsLevels[i] : 0.0f;
        }
        return;
    }
    if (self.micAvailable && self.micEnabled) {
        for (NSUInteger i = 0; i < count; i++) {
            levels[i] = (i < n) ? _micLevels[i] : 0.0f;
        }
        return;
    }

    // 数据源都不可用时的占位动画（明确不是真实电平）
    if (self.simulateEnabled) {
        [self fillSimulatedLevels:levels count:count];
        return;
    }

    for (NSUInteger i = 0; i < count; i++) levels[i] = 0.0f;
}

@end
