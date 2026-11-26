#import <Foundation/Foundation.h>

/**
 * 音乐状态 + 真频谱采集。
 *
 * - 播放状态：先读 SpringBoard 的 SBMediaController.isPlaying，失败再用
 *   MediaRemote 的 MRMediaRemoteGetNowPlayingInfo 读 PlaybackRate。
 * - 频谱：AVAudioEngine 麦克风采集 + Accelerate FFT，按对数分 12 个频段，
 *   只有检测到正在播放时才开采集，暂停/停止立刻关掉麦克风。
 */
@interface ANVMusicMonitor : NSObject
+ (instancetype)shared;

- (void)start;
- (void)stop;

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readonly) BOOL micAvailable;

/// 取出 0~1 的频段能量，count 最多 10
- (void)fillLevels:(float *)levels count:(NSUInteger)count;

/// AxsEQ 的真实电平（mediaserverd 的 PCM 峰值）：是否已经读到数据
@property (nonatomic, readonly) BOOL axsAvailable;
/// 当前数据源说明（给设置列表显示用）：AxsEQ 真电平 / 麦克风 / 模拟动画 / 无信号
- (NSString *)sourceLabel;
/// 最近一次电平均值（0~1），设置列表里显示用
- (CGFloat)currentEnergy;
/// 麦克风频谱开关（AxsEQ 输出 nan 时的备用数据源）
@property (nonatomic, assign) BOOL micEnabled;
@property (nonatomic, assign) BOOL simulateEnabled;
@end
