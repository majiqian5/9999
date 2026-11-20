# AndroNavBar

安卓风格霓虹四键导航条，挂在 SpringBoard 上，全系统悬浮（主屏、App 内都能用）。

- 蓝色三角：返回（回到上一个使用的 App）
- 绿色圆圈：主屏幕
- 粉色方块：后台 / 多任务
- 黄色箭头：前进（回到刚才离开的那个 App）

包名 `com.doubao.andronavbar`，rootless（`/var/jb`），arm64 + arm64e，iOS 15–16。

### 1.1.0 新增

- **背景全透明**：去掉毛玻璃和底色，只留四个霓虹图标（设置里可切回毛玻璃）。
- **图标可更换**：把 PNG 放进 `/var/jb/Library/Application Support/AndroNavBar/icons/`，命名 `slot0.png` ~ `slot3.png`，respring 生效；不放就用内置矢量图标。
- **大小自定义**：设置里“图标大小”70% ~ 150%。
- **功能键可选**：四个位子各自可设为 返回 / 主屏幕 / 后台 / 前进 / 无动作。
- **真频谱**：播放音乐时用麦克风采集 + Accelerate FFT，12 段对数频段，快起慢落；暂停/停止立刻关麦克风，频谱归零。

## 用 GitHub Actions 编译（推荐）

仓库里已经放好 `.github/workflows/build.yml`，跑在 `macos-15`，用官方 Theos + 官方 SDK 编译，arm64e 的 ABI 是正确的（Linux 版 Theos 那套 `incompatible arm64e ABI` 问题不会出现）。

1. 新建一个 GitHub 仓库，把 `AndroNavBar/` 里除 `packages/`、`.theos/` 之外的文件全部推上去：

```bash
cd AndroNavBar
git init
git add .
git commit -m "AndroNavBar 1.0.0"
git branch -M main
git remote add origin git@github.com:<你的用户名>/AndroNavBar.git
git push -u origin main
```

2. 打开仓库的 **Actions** 页，等 `Build AndroNavBar` 跑完（首次约 3–5 分钟）。
3. 在该次运行页面底部的 **Artifacts** 下载 `AndroNavBar-rootless-deb`，解压就是 `com.doubao.andronavbar_1.0.0_iphoneos-arm64.deb`。
4. 之后想发版，打个 tag 就会自动上传到 Releases：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

想在本地 macOS 上编也一样：`make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless`。

## 文件结构

```
AndroNavBar/
├── Makefile                  # Theos 工程（rootless）
├── control                   # deb 元信息
├── AndroNavBar.plist         # 只注入 com.apple.springboard
├── Tweak.xm                  # SpringBoard 启动后拉起导航条
├── ANVBarController.h/.m     # 悬浮窗 + 毛玻璃条 + 按钮 + 拖拽/长按
├── ANVGlyphView.h/.m         # 四个霓虹矢量图标（CAShapeLayer 描边 + 发光）
├── ANVActions.h/.m           # 四个功能的具体实现
├── ANVHistory.h/.m           # App 前后台历史栈（返回/前进用）
├── ANVSettings.h/.m          # 读配置 / 保存位置
├── layout/Library/PreferenceLoader/Preferences/AndroNavBar.plist  # 设置页
├── icons/                    # 4 个 240×240 透明底图标（可替换）
└── preview.png
```

## 编译

```bash
export THEOS=/path/to/theos
cd AndroNavBar
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

产物在 `packages/com.doubao.andronavbar_1.0.0_iphoneos-arm64.deb`。

## 安装

```bash
# 传进手机后
dpkg -i com.doubao.andronavbar_1.0.0_iphoneos-arm64.deb
killall -9 SpringBoard
```

Sileo / Zebra 直接打开 deb 安装也可以。卸载：`dpkg -r com.doubao.andronavbar`。

## 使用

- **单指拖动整条**：移动位置，松手记忆（写入 `com.doubao.andronavbar` 的 `CenterX/CenterY`）。
- 长按整条 0.65 秒：淡出 5 秒，方便看视频/打游戏，之后自动回来。
- 长按整条 2.6 秒：位置重置回底部居中。
- 点键有轻微放大 + 发光加强 + 震动（可在设置里关）。
- 首次运行到 1.0.1 会自动把旧版本误拖的位置归位一次（`PositionMigratedV2` 标记）。

### 频谱权限（重要）

`AVAudioSession` 采集麦克风时，SpringBoard 的 Info.plist 没有麦克风用途描述，未授权直接调用会被系统杀掉。代码里先检查 `recordPermission`，**没授权就不启动录音**，所以不会因为频谱崩 SpringBoard，但频谱也不会动。开启步骤：

1. 用 AppData（或 TCC 工具）给 `SpringBoard` 打开麦克风权限；
2. 设置里打开“启用频谱”；
3. 注销重进，播放音乐，频谱才会跟节奏跳。

注意：采的是环境声（不是 App 的数字输出），所以手机静音/音量极低时频谱会很小，这是正常的。

设置项（设置 App → AndroNavBar）：启用、震动、不透明度、大小。改完注销生效。

## 四个动作怎么实现的

| 键 | 主路径 | 兜底 |
|---|---|---|
| 返回 | 历史栈上一条 → `LSApplicationWorkspace openApplicationWithBundleID:` | 栈空时打开多任务 |
| 主屏 | `UIApplication _simulateHomeButtonPressWithCompletion:`（iOS 15+）→ `_simulateHomeButtonPress`（老系统） | 多任务控制器 dismiss 到 `homeScreenAppLayout` → `SBUIController` 老方法 |
| 后台 | `toggleSwitcherNoninteractivelyWithSource:` | `toggleMainSwitcherNoninteractivelyWithSource:animated:`（iOS 15/16）→ `toggleSwitcherNoninteractively` → `activateSwitcherNoninteractively` |
| 前进 | 前进栈 → 打开对应 App | 无动作 + 警告震动 |

> iOS 15 移除了 `_simulateHomeButtonPress` 的简单版本，直接调用会崩 SpringBoard；所以优先用带 completion 的新方法，并对每个 selector 先 `respondsToSelector` 再调用。

历史记录：运行时检测 `SBApplication` 是否存在 `setDisplayed:` / `setFrontmost:`，存在才用 `MSHookMessageEx` 挂钩；不存在就直接读 `SBRecentAppLayouts._recentsFromPrefs`，不会因为方法不存在而崩。

## 自定义

- 颜色：`ANVBarController.m` 里 `ANVColorForGlyph()` 改 RGB。
- 线条粗细：创建 `ANVGlyphView` 时的 `lineWidth`。
- 图标形状：`ANVGlyphView.m` 的 `-pathForKind:inRect:`，归一化坐标，改点即可。
- 想用图片素材：把 `icons/icon_*.png` 放进 `layout/.../AndroNavBar/`，再把按钮改成 `setImage:`。

## 排错：看日志

启动时会把探测到的私有 API 写法、每次按键走的分支写到 `/var/mobile/andronavbar.log`：

```bash
cat /var/mobile/andronavbar.log
```

正常应该能看到 `probe begin` 段落里 `homePressCompletion=1` 或 `toggleMain=1`，以及每次点击的 `performGlyph N -> 1`。哪个键是 `-> 0` 或 `FAILED`，就说明那条私有 API 在你这版系统上不存在。

## 已知风险（务必看）

1. **arm64e 警告**：Linux 版 Theos 链接时会报 `incompatible arm64e ABI`，产物里 arm64e slice 是打出来了，但个别系统上可能注入失败。若装完没反应，用 macOS + 官方 Theos 重新编一次 arm64e（代码无需改）。
2. **返回的语义**：iOS 没有全局“上一页”，所以这里返回 = 回上一个 App。要在 App 内部返回上一页，只能各 App 自己做（或用 SquidGesture 之类手势插件）。
3. **选择器随版本**：`handleHomeButtonSinglePress`、`_dismissSwitcher...` 属于私有 API，iOS 16.5.1 上按上面顺序逐级降级；如果某个版本全失败，用 `Logos` 抓一下 `SBMainSwitcherViewController` 的方法列表，把名字补进 `ANVActions.m` 的候选数组即可。
4. 装完若进安全模式：先 `dpkg -r com.doubao.andronavbar` 再 respring。
