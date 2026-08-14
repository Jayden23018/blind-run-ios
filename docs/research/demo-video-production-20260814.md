# AidRun 演示/宣传视频怎么做：规格、结构、拍摄与本项目专属红线

调研日期：2026-08-14
起因：项目导师要求做一条演示视频，用于内测期对外宣传，做得好可能挂到官网首页作宣传片。
提问方的前置假设：「这跟 App Store 里点进 App 看到的那个预览视频差不多吧？」

---

## 0. 一句话结论

**不一样，而且两者的规则在关键处正好相反 —— 必须做两条片子，不是一条。**

App Store 的 App Preview 受 Apple 审核规格硬约束：15–30 秒、**只能有 App 内画面**、
**明确禁止出现人操作设备的镜头（手指点屏、过肩视角一律不许）**、默认静音播放、
分辨率必须命中枚举值。而官网首页宣传片没有这些约束，且对助盲跑这类产品，
**「盲人和志愿者一起在跑道上」这个镜头才是全片最值钱的一秒 —— 而它在 App Preview 里是违规素材。**

正确做法：拍一条 60–90 秒母版（官网 / 内测分发 / 微信传播用），再从母版**剪出**
一条 ≤30 秒的纯录屏版本上 App Store。素材一次拍齐，剪两个版本。

---

## 1. Apple App Preview 硬规格（逐字取自官方页，2026-08-14 核实）

来源：[App preview specifications — App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/)

| 项 | 官方值 |
|---|---|
| 最大文件体积 | 500MB |
| 最短时长 | 15 Seconds |
| 最长时长 | 30 Seconds |
| 默认封面帧位置 | 5 Seconds |
| 方向 | 竖屏或横屏（macOS / tvOS 只收横屏）|
| 录制与播放的系统要求 | iOS 8 or later |

H.264 编码要求：
- 目标码率 **10–12 Mbps**
- Progressive，**up to High Profile Level 4.0**
- **最大帧率 30 fps**
- **音频必须是立体声**：256kbps AAC，采样率 44.1kHz 或 48kHz，所有轨道必须启用
- 容器扩展名：`.mov` / `.m4v` / `.mp4`

分辨率（iPhone 全部现代尺寸统一）：
- 6.9″ / 6.5″ / 6.3″ / 6.1″ 的 **Accepted resolutions 都是 886 × 1920（竖）或 1920 × 886（横）**
- iPad 13″ / 11″ 是 **1200 × 1600（竖）或 1600 × 1200（横）**
- 未提供对应尺寸时，Apple 用大尺寸的缩放版顶上

数量：**每个本地化语言最多 3 条**预览。

### 内容与创意规则（这条才是关键差异）

来源：[App Previews — Apple Developer](https://developer.apple.com/app-store/app-previews/)

- **「App previews must show only content within the app itself. Don't film people
  interacting with a device, such as an over-the-shoulder angle or fingers tapping the screen.」**
  → 真人镜头、手指点屏、过肩视角，**全部禁止**。
- 允许加图形元素与转场；演示交互可以加「touch hotspots」这类示意图形。
- 文字要易读、停留够久；**禁止时令性表述**（"new for spring"、具体日期）；**禁止出现价格**。
- **「By default, app previews play with the sound muted」** —— 默认静音播放，所以要靠字幕补上下文。
- 建议用同一条配乐贯穿全片；用画外音则必须用好设备、在无噪环境录。
- 建议叙事连贯：第一条讲整体体验，后续条目讲附加功能。

> ⚠️ 对 AidRun 的直接后果：这个 App 的核心价值是**听觉的**（VoiceOver 遍历、TTS 播报、语音下单），
> 而 App Preview **默认静音**。静音状态下，一段「用户说话 → App 播报 → 下单成功」的录屏，
> 在观众眼里就是「一个人对着不动的屏幕发呆 20 秒」。**语音内容必须视觉化成字幕/文字卡**，否则这条预览等于空白。

---

## 2. 官网首页宣传片：另一套完全不同的技术要求

来源：[Design TLC](https://designtlc.com/how-to-optimize-a-silent-background-video-for-your-websites-hero-area/) ·
[Mux](https://www.mux.com/articles/add-background-video-website-hls-performance) ·
[Mintec](https://mintec.co/blog/video-lcp-hero-performance-2026/)

- 标签属性固定组合：`autoplay muted loop playsinline`。缺 `playsinline` 时 Safari 会全屏打开，自动播放失效。
- 体积预算：**桌面 ≤ 4MB，移动 ≤ 2MB**；码率 1–2 Mbps；720p 通常够用，正片位置用 1080p，别上 4K。
- 帧率 24–30 fps；循环片长 10–30 秒。
- **把音轨整个删掉**（不是静音）—— 空音轨仍占容器开销，且某些浏览器会因此拒绝自动播放。
  ⚠️ **这一条与 Apple「必须有立体声音轨」正好相反**，两个版本不能共用同一个导出文件。
- `moov atom` 必须前置（`-movflags +faststart`），否则首帧要等整段下载完。
- LCP 问题：`<video autoplay>` 会抢占关键资源带宽。**poster 图才应该是 LCP 元素，视频是渐进增强。**
- WCAG 2.2.2 要求用户**能手动停止**自动播放的视频。

---

## 3. 片长与结构（有数据支撑的部分）

来源：[Vidico](https://vidico.com/news/best-product-demo-video-examples/) ·
[ngram](https://www.ngram.com/blog/demo-video-length) · [Demosmith](https://demosmith.ai/blog/how-long-should-demo-video-be)

- **长度由投放位置决定，不由功能数量决定**：社交流 15–30 秒 / 官网首页 60–90 秒 / 产品详情页 90 秒–3 分钟。
- Vidyard 基准数据：**1 分钟以内完播率 65%**，20 分钟以上只有 20%；60 秒后完播率陡降。
- 观众在**前 10–15 秒**决定要不要继续看 —— 没勾住，后面多长都不重要。
- 节奏比长度更重要：同为 3 分钟，快剪留存 60% vs 慢节奏 35%。
- 脚本字数换算：**约 150 字/分钟**。60 秒片子 ≈ 150 字旁白（中文可略少，中文语速慢于英文）。
- 通用骨架：**Hook → Problem → Solution → Proof → CTA**。
- 最常见的失败开场：10 秒 logo 动画 + 「大家好，欢迎了解 XX」。**把最亮的那一下放最前面。**
- 功能只讲 **2–3 个**，跑通**一条完整流程**，不要做功能巡礼。
- ⚠️ 一条被反复点名的失败模式：**demo 跑在产品前面**（demo that oversells）——
  结果不是转化问题而是流失问题。对 AidRun 尤其致命，因为承诺的是**人身安全**。

---

## 4. 拍摄通道：这个仓库的特殊约束

### 4.1 只能真机录，模拟器路线不存在
高德 SDK 没有 arm64-sim slice，模拟器通道永久不可用（`AGENTS.md` §11）。录屏必须在真机
（`111` 或 `iPad Pro (2)`）上做。这不是选择题。

### 4.2 音频是本片最大的技术风险，必须先试拍验证
来源：[Apple Developer Forums 775675](https://developer.apple.com/forums/thread/775675) ·
[AppleVis](https://www.applevis.com/forum/ios-ipados/screen-recording-includes-voiceover-sound)

- iOS 14 起，系统录屏**默认会录到 VoiceOver 声音**（属于设备内部音频）。
- **但有一个直接命中本项目的已知缺陷**：有开发者报告 `AVAudioEngine` 开启 voice processing 后，
  系统内置录屏在该模式活跃期间**整段没有音频**，Apple 的回复是需要工程团队调查。
  AidRun 的语音下单走 `Speech` 框架 + 麦克风会话 —— **正好落在这个风险面上**。
- 其他已知坑：戴耳机时录不到设备音频；音频被路由到听筒；开了麦克风开关后麦克风电平盖过 VoiceOver；
  麦克风开关**重启后会重置**。
- ⇒ **动手前先拍 15 秒试片**：录一段「按住说话 → 识别 → 播报确认」，导出到 Files/Photos 回放，
  确认这段有没有声音。**不要等剪辑时才发现整条素材是哑的。**
  （本仓库已有教训：记忆 `audio-correctness-needs-real-ears-not-code-reading` ——
  音频正确性只能人耳验，代码看着全对也可能一声不响。）

### 4.3 备选通道：QuickTime 有线录制
来源：[Apple Support](https://support.apple.com/guide/quicktime-player/record-a-movie-qtp356b55534/mac)

USB 连 Mac → QuickTime Player → 文件 > 新建影片录制 → 展开选项，
**Camera 和 Microphone 都要选 iPhone**（只选 Camera 会录成 Mac 的麦克风）。
- macOS Tahoe 26 起可选 SDR（H.264，兼容性最好）或 HDR（HEVC）——**选 SDR**。
- ⚠️ Tahoe 已知缺陷：接外置多通道 USB 声卡时，系统录制 API 只录左声道。用内置通道可避开。

### 4.4 转码到 Apple 规格
录屏出来是 2796×1290 之类的设备分辨率，**不是** Apple 收的 886×1920，必须转：

```bash
ffmpeg -i raw.mov -vf "scale=886:1920:flags=lanczos" -r 30 \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 11M \
  -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart appstore-preview.mp4
```

官网 hero 版（注意 `-an` 删音轨，与上面相反）：

```bash
ffmpeg -i master.mov -an -vf "scale=-2:1080" -c:v libx264 -crf 28 -preset slow \
  -pix_fmt yuv420p -movflags +faststart web-hero.mp4
```

（1290/2796 = 0.4614，886/1920 = 0.4615，比例吻合，直接 scale 不会拉伸变形。）

---

## 5. 视频本身必须是无障碍的（一个助盲产品在这条上没有借口）

来源：[Section508.gov](https://www.section508.gov/create/synchronized-media/) ·
[3Play Media](https://www.3playmedia.com/blog/wcag-2-0-requirements-for-video-captioning-and-audio-description/)

- WCAG **1.2.2（A 级）**：所有带音频的预录视频必须有**同步字幕**。
- WCAG **1.2.3（A 级）**：音频描述**或**完整文字替代二选一；
  **1.2.5（AA 级）**：**音频描述是必须的**。ADA / EAA 场景一般以 AA 为目标。
- 字幕 ≠ subtitle：字幕要含说话人标识与非语音音效（「手机震动」「脚步声」）。
- **自动生成字幕不够用**，必须人工校对。
- 播放器本身也要可访问：要有可见的字幕开关、能纯键盘操作。
- 附带好处：字幕让人在静音状态下也能看懂（正好对上 App Preview 默认静音）；
  文字稿能被搜索引擎索引。

实操最低配：**硬字幕烧进画面**（防止平台丢字幕轨）+ 官网页面上放一份**完整文字稿**
+ 旁白里把关键视觉信息说出来（等于内嵌音频描述）。

---

## 6. 表达伦理：拍盲人用户最容易翻车的地方

来源：[Forbes — How To Avoid "Inspiration Porn"](https://www.forbes.com/sites/andrewpulrang/2019/11/29/how-to-avoid-inspiration-porn/) ·
[The Drum](https://www.thedrum.com/news/avoid-charity-or-inspiration-porn-how-better-represent-disability-ads) ·
[GADIM](https://gadim.org/best-practices-for-entertainment-media/) ·
[NDRN 同意书模板](https://www.ndrn.org/consent-form/)

- **避免 inspiration porn**（Stella Young 提出的概念）：把残障者仅仅因为残障就塑造成励志符号，
  实质是物化。Nielsen 的说法是「以残障者的真实经验为代价去激励非残障观众」。
  **一个可用的自检**：把「盲人」这个设定拿掉，这还是个故事吗？不是的话，就别这么讲。
- **真实出镜**（authentic casting）：残障角色由残障者本人出演；做不到就至少请残障顾问在场。
- 常见失败：**请了残障演员，成片本身却不可访问**（没字幕、没音频描述）。
- **知情同意对盲人要改形式**：不要求在看不见的纸上签字 ——
  **口头宣读 + 录像/录音记录同意过程**是被认可的做法；可由见证人签署确认已准确解释并被理解。
- 同意的**范围和撤回权**同样重要：说清将来用途（宣传/教学/培训）；
  **成片在公开前给本人过目确认**；给出撤回渠道。
- 即使不拍脸也可能被识别 —— 体貌特征、住所/单位背景、环境音都会暴露身份。
- 让残障用户自己说，不要替他说。

---

## 7. AidRun 专属红线（违反的代价比代码 bug 大，因为它挂在官网上）

| # | 红线 | 依据 |
|---|---|---|
| 1 | **绝不能出现「已通知家属」「联系人已收到短信」「已送达」这类说法**（旁白、字幕、演示画面一律） | `AGENTS.md` §6：`EMERGENCY_CONTACT_NOTIFIED` 推送时短信一次都没试过发，失败也不回告盲人。字符串「联系人已收到短信」在发布产物中被守卫拦。视频不是代码，守卫拦不到 —— **只能靠人**。 |
| 2 | 首页那条常驻求助条，**非 `IN_PROGRESS` 时是本地拨号，不走云端**。演示它就必须说清「App 不会代你发送求助」 | `AGENTS.md` §6 / `BlindHomeSOSMode.resolve` |
| 3 | 不得出现真实手机号、真实住址、真实定位坐标、真实身份信息。演示账号数据全部脱敏 | `docs/test-accounts.md`；隐私常识 |
| 4 | 字幕/旁白里的**状态词必须与 App 内一致**，别自己造词。禁用遗留词汇：`已提交`/`已联系`/`匹配中`/`已接受`/`已到达` | `AGENTS.md` §5，`guard.mjs` 拦的是代码，视频靠人 |
| 5 | **只演示内测版真的有的功能**。积分商城是占位页（`docs/05-page-specs.md:812`），轨迹总结、实时同行位置要确认当期状态再决定拍不拍 | 「demo 不能跑在产品前面」；本产品承诺的是人身安全 |
| 6 | 下单起始时间距今必须 ≥30 分钟，**没有「现在就跑」**。脚本别写成即时叫车 | `AGENTS.md` §5，`EnvironmentConfig.minimumBookingLeadMinutes = 30` |

---

## 8. 建议方案（可直接执行）

### 母版：75 秒，官网 / 内测分发 / 微信传播

| 时间 | 画面 | 声音 / 字幕 |
|---|---|---|
| 0–8s | 实拍：清晨跑道，盲人独自站在路边，手里是白手杖 | 无旁白，环境音。字幕：「想跑步，但一个人不敢出门。」（**Hook = 问题，不是 logo**）|
| 8–18s | 实拍转录屏：手指按住屏幕说话 → 屏幕上语音气泡出现 | 真实语音「明天早上八点，去奥体中心跑步」+ **大号字幕同步**（静音也看得懂）|
| 18–30s | 录屏：确认页 → 下单成功 → 状态卡从 `PENDING_MATCH` 变 `PENDING_ACCEPT` | TTS 播报原声 + 字幕。**一个决策点都不跳过**，展示的就是「少即是安全」|
| 30–45s | 实拍：志愿者到场，两人握绳，起跑 | 志愿者一句真实同期声。字幕带上「志愿者需实名认证」这类信任要素 |
| 45–58s | 分屏：左跑步实拍，右手机上的服务中页 / 安全提示 | 旁白讲**安全机制**（不夸大：说「记录求助事件并同步客服」，**不说**「已通知家属」）|
| 58–68s | 实拍：跑完，两人击掌；录屏切完成页 | 盲人用户本人一句话（比任何旁白都强）|
| 68–75s | 定版：Logo + 一句话定位 + 内测入口 | CTA 只留一个 |

旁白控制在 **150–180 字**。

### App Store 版：约 27 秒，从母版重剪

- **删掉全部真人镜头**（Apple 硬规定），只留 18–30s 那段录屏，补足到 15–30 秒。
- 全程**加大号字幕**（默认静音）。
- 封面帧（默认取第 5 秒）挑一个信息量最大的画面，别落在转场中间。
- 导出 886×1920 / 30fps / H.264 High L4.0 / AAC 立体声 256kbps。

### 拍摄清单（一次拍齐，别补拍）

- [ ] 器材：手机拍实拍够用，**但一定要外接麦**（风声毁片率最高）；三脚架；跑道选清晨光线
- [ ] 出镜同意：**口头 + 录像**记录，讲清用途与撤回方式，成片给本人过目
- [ ] 录屏前：手机设静音勿扰、隐藏顶部通知、电量拉满、状态栏干净
- [ ] **先拍 15 秒音频试片并回放确认**（见 §4.2）
- [ ] 同一流程录 3 遍以上，留剪辑余地
- [ ] 实拍多拍空镜（脚步、手握绳的特写、路面）—— 剪辑时救命的都是这些

### 工具

录屏用 iOS 内置或 QuickTime 有线；剪辑用剪映专业版（中文字幕效率最高）或 DaVinci Resolve 免费版；
转码用 ffmpeg（命令见 §4.4）。**不要**为这件事买软件。

---

## 9. 没查到 / 未核实的部分

- 微信朋友圈、视频号对视频时长与体积的当前上限：搜索通道是 US-only，没拿到可靠的中文一手来源。
  投放前自己在客户端实测一遍。
- 国内官网视频托管（自建 CDN vs 腾讯云点播）的成本与合规要求：不在本轮范围。
- 本项目内测版当期到底哪些功能可演示（轨迹总结、实时同行位置的完成度）：需对着
  `openspec/changes/` 未归档变更逐条确认，属于产品判断不是调研。

---

## 复核触发条件

- Apple 更新 App Preview 规格页（新机型分辨率、时长、编码要求变化）
- Apple 放宽/收紧「不得拍摄人操作设备」这条内容规则
- WCAG 更新 1.2.x 系列对字幕与音频描述的等级要求
- AidRun 的 SOS 文案红线（`AGENTS.md` §6）变化，或后端短信链路改为可确认送达
- 官网技术栈变化导致 hero video 的体积/格式预算变化
