## Context

- `WSAppNotification.eventType` 是 `String`，未知取值不会解码失败；`routeNotification` 对不在生命周期表里的 eventType 一律入队并由 `ContentView` 朗读 `speechText`。所以迟到 / 快捷消息四类已经走得通，只缺测试钉住。
- `RUNNER_RING` 的信封多一个 `until`（后端 `LocalDateTime`，无时区，可能带小数秒）；`ring-runner` 响应写明「受理时刻 + 10 秒」。
- 全 App 只有 `.playback` 一个常驻音频分类（启动时配好），静音拨杆下照常出声；后台模式只有 `location` + `remote-notification`，**没有 `audio`**。
- 盲人端根是 `BlindRunnerTabView`，TabView 上挂着 magic tap = 求助。

## Goals / Non-Goals

**Goals:** 前台收到响铃就响、到点停、一碰就停；四类朗读有测试；两个自由文本字段有录入入口。

**Non-Goals:** APNs 推送与锁屏（#213）；强行把系统音量拉满（没有公开 API，`MPVolumeView` 滑块写值属于绕过，且未经用户同意改系统音量）；为响铃新增后台 `audio` 模式；蓝牙耳机连接时强制走扬声器（`.playback` 分类不允许 override 输出端口）。

## Decisions

1. **响铃时长按服务端时钟算**：`until − timestamp`（两者都是服务端时间），夹到 `(0, 30]` 秒，从收到那一刻起计。不用 `until − 本机 now`，因为本机时钟偏几秒就能把 10 秒吃光。`timestamp` 解析不出时退回 `until − now`。时长 ≤ 0 或缺 `until` → 不响，回落到普通通知朗读一次。
2. **去重在两层**：协调器按 `messageId` 丢弃重复的 `RUNNER_RING`；控制器再按 id 与 `endsAt > now` 挡住 `@Published` 重新订阅时回放的旧值。新 id 直接替换（重新计时）。
3. **先念后响**：朗读 `ttsText` 后等合成器说完（最多 4 秒，且不超过 `endsAt`）再起铃声。同时起的话 1.5 kHz 的铃声会盖住那句话。代价：10 秒窗口里铃声少 2–3 秒，但那句朗读本身也是外放的声音，照样能帮陪跑员找人。
4. **专用提示音**：`ToneSynthesizer` 合成下行「叮咚」1568/1244.5 Hz + 0.6 秒静音，循环。频率避开全 App 已用的 587–1318.5 各组（求助警报 740/988 不得复用）。播放器创建后常驻，不释放（`finishedPlaying:` 崩溃的教训）。
5. **遮罩挂在 `BlindRunnerTabView`**，用 `HostedContainersAccessibilityHider` 把背后的 UIKit 容器对读屏藏起来；遮罩本身挂 `.magicTap` / `.escape` 动作，抢在 TabView 的求助手势之前。
6. **留言入口**：信息卡「集合地点」与最后一行之间加一行，只在四个可写状态出现；点开是表单页（`TextField` + 保存 + 清空）。保存成功就地把 `order.messageToVolunteer` 换成响应值，不等下一轮轮询。
7. **长度按 UTF-16 计**，与 `SupportTicketRequest.length(of:)` 同口径（后端 `@Size` 数的是 Java `String.length()`）。

## Risks / Trade-offs

- [App 在后台时 `AVAudioPlayer` 起不来声] → 不加 `audio` 后台模式；后台靠 #213 的 APNs（`time-sensitive` + 声音）。PR 里写明，真机验证时一并试。
- [连着骨传导耳机时铃声只在耳机里] → 公开 API 无解，写进 PR 风险项，等产品判断。
- [音量是否「够大」] → 只能真机人耳验（记忆 `audio-correctness-needs-real-ears-not-code-reading`）。
- [WS 与 APNs 前台同时到，朗读两遍] → 已有行为（`PushNotificationsManager.willPresent` 对所有推送都念），属于 #213 范围。
