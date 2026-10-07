# 盲人端重设计补充调研：Seeing AI / 苹果自带 App / 跑步 App 播报 / ADA Inclusivity（2026-10-07）

**定位**：补 [`blind-runner-ui-reference-study-20260915.md`](./blind-runner-ui-reference-study-20260915.md) 没覆盖的四块。
那份已研究的 Be My Eyes / BeMyGuide / Sense / Strava / NRC / adidas 界面**不重做**，其结论
（Strava/NRC/adidas 无障碍不及格 ⇒ 只借视觉与情绪语言，不借交互模式）本轮照用。

**方法**：子代理（sonnet）联网检索，主会话未逐条复抓。每条标「原文」或「转述」；标「二手」的是
非官方来源或年代较旧，**不能单独作为设计依据**。核实日期一律 2026-10-07。

## 1. Seeing AI（Microsoft）

- 旧版功能叫「频道」，VoiceOver 下右划到频道调节条，上划 / 下划切换；AFB 原文 "Swipe up or down to get to a specific channel"。<https://www.afb.org/aw/19/9/15059>
- 2025 更新改成三个标签：Read（短文本 + 文档 + 手写）/ Describe（场景 + 人物）/ More；More 页内仍上下划切换、不需双击激活。转述。<https://www.henshaws.org.uk/hints-and-tips/seeing-ai-the-2025-update/>
- **声音编码距离**：Product 条码越近音越连续；Find My Things 蜂鸣越近越快；亮度检测光越多音越高。转述，同上。
- 短文本频道持续扫描、发现文字就自动读。转述，AFB。
- 震动反馈、朗读顺序细节：**未找到**。

## 2. 苹果自带 App

- 健身 / Watch：三环 Move / Exercise / Stand（轮椅用户 Stand → Roll）。转述。<https://support.apple.com/guide/watch/track-daily-activity-apd3bf6d85a6/watchos>
- VoiceOver 把三环读成一句「Moving, 50%, exercising, 27%, standing, 75%」——**二手**（AppleVis 博文，watchOS 3 时代，现行读法未核）。<https://www.applevis.com/blog/opinion-how-not-work-out-apple-watch>
- 体能训练 Voice Feedback：每英里一报（例 "Mile two, pace 6 minute 30 seconds"），合环 / 达标也报，**经耳机播放并压低音乐而非打断**。转述。<https://9to5mac.com/2021/07/19/watchos-8-siri-on-apple-watch-voice-feedback-workout/>
- 地图：锁屏、自动锁屏、切到别的 App 时继续播报方向。转述，iOS 13/14 时代指南。<https://support.apple.com/en-asia/guide/iphone/iph87085d3a/13.0/ios>
- 天气：地图叠加层 VoiceOver 可读，手指拖动听到周边城市温度与降水——**二手**（2023 个人博客）。<https://theideaplace.net/apple-adds-overlay-data-to-accessibility-info-in-weather-app/>
- Audio Graphs：转子出现「音频图表」，上下划选 Describe chart / Play Audio Graph / Chart Details。转述（Kodeco 教程，苹果官方页抓取失败）。
- 结束体能训练的 VoiceOver 确认步骤、Maps 转弯措辞、天气小时预报读法：**未找到**。

## 3. 跑步 App 的语音播报与锁屏

- Strava：可设开始 / 停止 / 暂停播报；分段播报仅跑步，每半公里或每公里。转述。<https://support.strava.com/en-us/articles/15402180-how-do-i-enable-audio-announcements-on-strava>
- Strava 锁屏实时活动（iOS 16.1+）**固定**显示用时、距离、配速，不可选。转述。<https://support.strava.com/en-us/articles/15401559-strava-live-activities-on-ios>
- NRC 原文 "choose from time, distance, or pace updates; you can also choose their frequency"。<https://www.nike.com/help/a/nrc-settings>；具体频率选项与锁屏内容**未找到**。

## 4. Apple Design Awards「Inclusivity」（2022 设立）

| 年 | 获奖 | 入围 |
|---|---|---|
| 2022 | Procreate（震颤 / 动作过滤、辅助触控菜单、音频反馈、色盲设置）；Wylde Flowers | Letter Rooms、Navi、Noted.、tint. |
| 2023 | Universe（Dynamic Type 与 VoiceOver 出色）；stitch.（色盲 / 低视力 / 动作敏感选项） | Anne、Passenger Assistance、Ancient Board Game Collection、Finding Hannah |
| 2024 | **oko**（用触觉 + 声音告知行人信号灯状态，VoiceOver / Dynamic Type 完整）；Crayola Adventures | Complete Anatomy 2024、Tiimo、Unpacking、quadline |
| 2025 | Speechify | **Train Fitness**（凭 Watch 与 AirPods 运动数据记训练，**不需要看屏幕**，有轮椅模式）、Evolve；游戏 Art of Fauna、Land of Livia（面向盲人与低视力） |
| 2026 | Guitar Wiz（语音指导、不依赖颜色）；游戏 Pine Hearts | Hearing Buddy、Structured、Sago Mini Jinja's Garden、Civilization VII |

来源：<https://developer.apple.com/design/awards/2022/> 至 `/2025/`；2026 来自 <https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/>。均为转述。

## 5. 对本 App 的取舍

| 借什么 | 来自 | 为什么适合看不见屏幕的跑者 | 本轮采不采 |
|---|---|---|---|
| 同一事实同时走语音 + 震动 + 声音三通道 | oko | 戴耳机、路口嘈杂时一条失效另一条顶上 | **采**：开始 / 汇合 / 求助发出 / 结束四个时刻三通道齐发 |
| 整个跑步过程不需要看屏幕 | Train Fitness | 跑动中屏幕是不可用的 | **采**：跑步中屏幕只留「听当前状态」与求助，删节奏按钮 |
| 固定间隔播报 + 事件播报 | Strava / Watch | 跑者不用伸手要数据 | 已有（每公里），本轮不改间隔 |
| 播报压低背景音而不是打断 | Watch Voice Feedback | 跑者常开音乐 / 导航 | 待核现状（`SystemSpeechAudioSession`），不在本轮 |
| 锁屏卡固定少量字段 | Strava | 低视力瞄一眼就够 | 已有（锁屏实时活动），不改 |
| 声音编码远近 | Seeing AI | 汇合时不用念数字 | **不采**：需要可信的双方实时距离，`DRIVER_ARRIVED` 后端不给跑者方向数据（`docs/ui/mockups/INDEX.md` 盲人端行偏差） |
| 上下划切换功能 | Seeing AI | 单手、不需精确点击 | **不采**：本 App 每屏只有一个主动作，没有可切换的「频道」 |
| 图表给文字摘要 | Audio Graphs | 配速曲线可听 | 不在本轮 7 屏范围（属跑后记录） |
