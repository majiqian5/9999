#import "ANVMusicMonitor.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#define kANVBandCount 12
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
@end

@implementation ANVMusicMonitor

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

- (void)startMicrophone {
    if (self.engine) return;

    // SpringBoard 没有麦克风用途描述，未授权时直接调用会把它杀掉；先检查权限
    AVAudioSessionRecordPermission permission = [AVAudioSession sharedInstance].recordPermission;
    if (permission != AVAudioSessionRecordPermissionGranted) {
        self.micAvailable = NO;
        return;
    }

    @try {
        NSError *error = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers |
                              AVAudioSessionCategoryOptionAllowBluetooth
                        error:&error];
        [session setActive:YES error:&error];

        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *input = engine.inputNode;
        AVAudioFormat *format = [input outputFormatForBus:0];

        self.fftSetup = vDSP_create_fftsetup(log2f(kANVFFTSize), kFFTRadix2);
        self.window = calloc(kANVFFTSize, sizeof(float));
        vDSP_hann_window(self.window, kANVFFTSize, vDSP_HANN_NORM);

        __weak typeof(self) weakSelf = self;
        [input installTapOnBus:0 bufferSize:kANVFFTSize format:format
                         block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf processBuffer:buffer];
        }];
        self.tapInstalled = YES;

        [engine prepare];
        if (![engine startAndReturnError:&error]) {
            self.micAvailable = NO;
            [self teardownEngine];
            return;
        }
        self.engine = engine;
        self.micAvailable = YES;
    } @catch (NSException *e) {
        self.micAvailable = NO;
        [self teardownEngine];
    }
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

#pragma mark - 对外

- (void)stop {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self stopMicrophone];
    self.playing = NO;
}

- (void)fillLevels:(float *)levels count:(NSUInteger)count {
    if (!levels) return;
    NSUInteger n = MIN(count, (NSUInteger)kANVBandCount);
    BOOL playing = self.playing;
    for (NSUInteger i = 0; i < count; i++) {
        levels[i] = (i < n && playing) ? self.levels[i] : 0.0f;
    }
}

@end
