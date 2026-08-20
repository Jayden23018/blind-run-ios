> **验证状态（2026-08-03 晚，真机已跑）**
>
> 设备 `mac's iPhone`（xcodebuild UDID `00008140-000161D62112801C`）在线，全量执行完毕：
> - **单测 473 条，0 失败**（`-only-testing:blindRunTests`，59.6s）
> - **UI 测试 33 条，0 失败，1 条恒 skip**（`testCloudBackendBlindRunnerBookingSmoke`，需 Demo 构建通道，544s）
>
> 首跑挂了 9 条，全在 `VoiceOrderWizardTests`，**其中两条是真的行为回归**，已修：
> 1. `bookingViewModel` 是 `weak`，重写时新加的 `guard let bookingViewModel else { return }` 让
>    `parseSingleSlot` / `parseFreeform` 静默返回（原代码用可选链所以不受影响）。改回可选链。
> 2. **API 层失败本该降级到表单，被 `try?` 抹平成了重问。** 恢复 `catch is WizardError → reask` /
>    `catch APIError → fallBack` 的区分。
> 3. **时长取整提示被紧随其后的读回覆盖**，`lastSpokenPrompt` 只剩后一句，「重复一遍」再也念不到取整
>    提示。改为把提示拼进读回同一段（`moveToConfirm(notice:)`）。
>
> 这三条**只有真跑测试才会暴露**，编译和独立脚本都发现不了。
>
> **验证状态（2026-08-04 14:36，真机复跑，含第 2A 节的 `/voice/parse` 改动）**
>
> - **单测 483 条 + UI 33 条，0 失败，首跑即零陈旧断言**（同一台 iPhone 16 Pro，`TEST SUCCEEDED`）
> - 1 条恒 skip 仍是 `testCloudBackendBlindRunnerBookingSmoke`（需 Demo 构建通道），非失败
> - 本轮新增/改写的 14 条用例**逐条核过确已执行并通过**，不是「套件绿了就当它们跑了」
>
> 真机手测（开 VoiceOver 走一遍真实语音）仍未做，见 5.5 —— **自动化测试跑通不等于语音链路可用**：
> 端到端还没有真人对着麦克风说过话，且生产 `AMAP_WEB_KEY` 未配，地点抽取在线上验不了。

## 1. 缺陷修复：语音启动失败必须抵达终局

- [x] 1.1 `SpeechInputService.clearRecognitionStartState(marking:)` 在清空前先取出 `activeField` 与 `completionHandler` 局部引用，送出一次携带 `.error` 的 `SpeechInputCompletion`，再置 nil。幂等由「先取引用再置 nil」保证：第二次调用时两者均已为空。
- [x] 1.2 核对 `handleRecognitionStartupFailure`（`:418`）—— **它没有这个问题**。它走 `stopAudioRecognition(notifyCompletion: true)`，而 `:307` 的守卫是 `(wasListening || reason == .error)`，`.error` 直接放行。音频会话失败、麦克风输入不可用这三条路径本来就能送达完成。**断的只有 `clearRecognitionStartState` 这一条**，覆盖语音授权被拒（`:201`）、麦克风授权被拒（`:211`）、recognizer 不可用（`:335`）。
- [x] 1.3 核对不会双发：`beginRecognition:342` 的预清理是 `notifyCompletion: false, clearHandlers: false`；随后无论走 `clearRecognitionStartState` 还是 `handleRecognitionStartupFailure`，都只会送出一次。
- [x] 1.4 单测 `testAuthorizationDenialDeliversATerminalCompletion` + 测试接缝 `SpeechInputService.denyAuthorizationForTesting()`。**2026-08-04 真机跑通。**
- [x] 1.5 `failRecognitionStartupForTesting`（`:607`）路径经 1.2 核对本就送达完成，既有用例 `testSpeechInputStartupFailureRestoresPlaybackBeforeErrorAnnouncement` 已覆盖其播报顺序。
- [x] 1.6 单测 `testAuthorizationDenialCompletionIsDeliveredOnlyOnce`。**2026-08-04 真机跑通。**
- [x] 1.7 回归 —— **2026-08-04 真机全量跑通（483 单测 + 33 UI，0 失败），没有波及地点搜索、备注、评价等其他 `SpeechInputField` 使用方。** 注意这只覆盖到自动化用例能触达的部分；真人对着麦克风的重复播报要等 5.5 手测。

## 1B. 缺陷修复：2026-08-06 真机手测暴露的三条音频时序缺陷

首次真人对着麦克风走完流程（5.5 的部分执行）报回三件事：读回念到一半被切掉就开始录音；
「改地点」之后没有任何提示音、震动或可听信号说明麦克风重开了；重问一轮后同样无声。
三条根因都在**音频会话与 TTS 的时序**上，全部是自动化用例结构性够不到的地方。

- [x] 1B.1 **读回被截断**。`VoiceOrderWizard.speechSettleTimeout` 写死 8 秒，而读回整单在默认语速下
      要 15~25 秒（该数字就写在同文件 `finishSpeakingOrSkipPrompt` 的注释里）。上限一到就开麦，
      开麦切换音频分类会把正在播的 `AVSpeechSynthesizer` 当场掐断 —— **每一次读回都必被截断**。
      改为按字数推导的 `settleTimeout(forCharacterCount:)`（0.35 秒/字 + 6 秒余量，下限 8、上限 45）。
      上限保留是因为合成器代理丢事件时不能无限等；用户随时可点整屏跳过播报，逃生口不变。
- [x] 1B.2 **同源竞态**：`isSpeaking` 只在 `didStart` 代理里经 `DispatchQueue.main.async` 置 true，
      而 `listen` 紧接着 `speak` 就开始轮询 —— 第一次检查读到的还是 false，等待循环当场放行。
      改为在 `speak(text:)` 入队时同步置位（`markSpeaking(_:)` 统一写入口，与 `stop()` 对称）。
- [x] 1B.3 **起音提示放不出来**。`RecordingCue.begin()` 在 `markRecognitionStarted()` 里发出，
      那时音频分类已经切成 `.record` —— **该分类根本不开输出通道**，那一声用户一次都没听见。
      而对全盲用户它是判断「麦克风开没开」的唯一非视觉信号。分类改为
      `.playAndRecord` + `[.duckOthers, .defaultToSpeaker]`（`defaultToSpeaker` 不能省：
      `.playAndRecord` 默认路由到听筒，提示音会小到等于没有）。
      触觉补 `prepare()` —— 不 prepare 首次触发常被丢，而首次正是最要紧的那次。
      > **这是同一个坑的第二次。** 收音那一端 2026-08-06 早些时候已因完全相同的原因修过
      > （`RecordingCue.end()` 推到会话切回播放之后）并留了断言；起音这一端当时漏了，
      > 因为它没有顺序可调 —— 录音正要开始，没有「之后」。按 `AGENTS.md` 第 1 条落成断言
      > `testRecordingCategoryAllowsPlaybackSoTheStartCueIsAudible`。
- [x] 1B.4 **随 1B.3 引入的回归已堵**：`.record` 不开输出通道时，`VoiceTextField` 那条
      `onAnnouncement → speechService.speak(text:)`（合成器）被系统悄悄吞掉；改成 `.playAndRecord`
      之后它会真的响，而这些通告是在**麦克风已经打开之后**发出的 —— 声音会被自己的麦克风录进去、
      被识别成用户说的话。改为 `speechService.announce(...)`，与 `VoiceOrderWizard` 一致；
      「麦克风开了」由 `RecordingCue` 承担，那本来就是它的职责。
- [x] 1B.4b **第二条随 1B.3 引入的回归**：起音提示现在真的从扬声器出去，而 `.measurement` 模式
      没有回声消除 —— 它会被自己的麦克风录回来，`containsAudibleSpeech` 把它当成「用户开口了」，
      静音判定立刻从首次静音（8 秒）切到尾静音（整句轮 2 秒）。后果是**一个刚听完提示、
      正在组织句子的人还没开口就被掐掉一轮，然后听到一整单默认值的读回** —— 比原缺陷更糟。
      加 0.4 秒 `inputWarmUpWindow`，只挡音量那一路；识别结果那一路不动（提示音转不出字）。
      判定抽成纯函数 `acceptsInputLevelSound(startedAt:now:)` 以便不睡 0.4 秒就能断言。
- [x] 1B.4c **迟到回调**：`speak` 是「先 `stopSpeaking(.immediate)` 再播新的」，旧那条随后回一次
      `didCancel`。不对身份就清 `isSpeaking` 的话，这次迟到的回调会把新那条抹成「没在播」，
      向导当场开麦 —— 同一个截断现象，但变成偶发。加 `currentUtterance` 身份校验。
- [x] 1B.5 单测：`testRecordingCategoryAllowsPlaybackSoTheStartCueIsAudible`（断言分类常量而非替身的
      调用序列 —— `configureRecordingCategory()` 不带参数，只记录「调过了」的替身对这条缺陷全盲，
      这正是它当初没被测出来的原因）、`testSettleTimeoutOutlastsAFullReadback` /
      `KeepsTheOldFloorForShortPrompts` / `IsCappedSoALostDelegateCannotHangTheMicrophone`、
      `testInputLevelSoundIsIgnoredDuringTheStartCueWarmUp`、
      `testSpeakMarksSpeakingSynchronouslySoTheWizardDoesNotOpenTheMicTooEarly`、
      `testStaleUtteranceCallbackDoesNotClearTheSpeakingFlag`。
- [x] 1B.6 真机批跑回归：见 5.7。
- [ ] 1B.7 **真机复测这三条**（只能人耳验，见 5.5 的补充案例 J/K/L）：读回念完整不被切；
      起音提示在外放与戴耳机下都听得见；重问一轮后能再次听到起音提示。

## 2. 语音向导：整句说完 → 读回整单 → 确认或定点修改

> **2026-08-04 订正**：本节此前整节描述的是 `.confirmDefaults`（先念默认值让用户确认、不确认再逐项追问），
> 且全部标着 `[x]`。**实现从来不是那个形态**，落地的是 `.freeform`（用户先说一整句、抽出多少算多少、
> 再读回整单）。文档与实现对不上这件事，我们刚在 handoff 里批评过后端同类问题，所以按实现改正本节。
> 差异原因：`.confirmDefaults` 的默认值对首次下单的用户几乎总是错的（起点=当前位置、时间=系统默认），
> 让人先听一遍必错的默认值再逐项改，比直接说一句慢。

- [x] 2.1 `VoiceOrderWizard.Step` 的第一个 case 是 `freeform`；`SpeechInputField` 对应 `voiceOrderFreeform`（`isAllowlisted` 只判断是否已知 case，新增即自动允许）。
- [x] 2.2 `voiceOrderFreeform` 单独放宽静默超时（首句 8 秒、尾静默 2 秒，`SpeechInputService.swift:547-561`）—— 说一整句本来就比说一个词久，用字段听写的 3 秒会在人说到一半时截断。
  **2026-08-05 下调**：原取 15/12 秒，调过了头。自发语音停顿的第三个峰在 1500ms，2 秒盖住它还留 500ms 余量；而 12 秒超过 Nielsen 的 10 秒注意力上限、是 Dialogflow no-speech 默认值的 2.4 倍 —— 看不见屏幕的人对着毫无反应的麦克风等 12 秒，判定的是「死机」不是「系统在等我」。显式结束通道（整块内容区可点 + Magic Tap）一直在，不依赖纯静音兜底。
- [x] 2.3 `VoiceOrderWizard.isAffirmative(_:)`：整串匹配肯定词，剥句尾语气词与标点，不做包含匹配。刻意不收「嗯」（犹豫填充词）。已附 `ponytail:` 注释写明天花板与升级路径。
  **2026-08-05 收窄 19 → 8 条**：移出「好 / 好的 / 行 / 可以 / 对 / 是 / 没错 / 同意 / 确定 / 提交 / 下单」。依据是 2018 Portland 事故（Amazon 官方复盘：助手问 "[名字], right?"，背景对话里的 "right" 满足确认，私人录音被发出），中文这几个字与 "right" 同构，而陪跑场景里志愿者可能就站在旁边说话。保留「确认」是因为读回念的就是「说『确认』就下单」，白名单必须与系统教的话一致。这次收窄是决策 2「两个方向代价不对称」的自然结论 —— 原来的 19 条与该决策不一致。
- [x] 2.4 `.confirm` 轮命中肯定词 → `submitConfirmedBooking()` 调 `bookingViewModel.submit()`，结果经 `@Published createdOrder` 交回视图，视图用 `onReceive` 走既有 `onOrderCreated` 出口，跳转逻辑仍只有一份。
- [x] 2.5 `.confirm` 轮的 `command(for:)` 认「改地点 / 改时间 / 改时长」三条定点修改出路与「再说一遍」；认不出即不推进也不提交。
- [x] 2.6 读回由 `confirmPrompt(for:)` 三段拼装：**用户原话 + 整单 + 两条出路**。缺一不可 —— 没有原话分不清是自己说错还是系统听错；没有整单不知道默认值补了什么；没有出路，看不见屏幕的人不会自己发现还能说「改时间」。
- [x] 2.7 `SpeechInputService.isSpeechPathUnavailable` 新增（启动阶段失败时置真，成功起听时复位）；`start()` 见其为真即 `fallBack` 并播报，不进重问循环。
- [x] 2.8 `BlindBookingView.onChange(of: voiceWizard.step)` 的步骤→表单段落映射覆盖 `.freeform` 与 `.confirm`：向导念的就是确认页的内容，中途切回手动时看到的和刚听到的是同一件事。
- [x] 2.9 `voiceOrderSection` 无需改动：`isRunning` 在首步为真，故 `lastSpokenPrompt` 可见；`repeatCurrentPrompt()` 走 `lastSpokenPrompt ?? step.prompt`，首步直接可用。
- [x] 2.10 **演示坐标已阻断**。~~`LocationService.isUsingDemoFallback` 只是 `currentLocation == nil`，没有 DEBUG 门禁……表单路径只播报不阻断，需产品决定是否阻断提交。~~
  **2026-08-06 复核订正**：这条描述在写下时就已被实现推翻，只是没人回头核。实情是——
  `LocationService.isDemoLocationForcedForTesting` **有 `#if DEBUG` 门禁**（`LocationService.swift:74-80`），
  Release 构建下恒为 false；`BlindBookingView.allowsDemoFallbackAsStartPoint`（`:394-397`）只在 Mock 环境或
  DEBUG UI 测试强开时为真；关键闸口是 `resolvedStartPlace` 的 `guard`（`:358`）——生产下 `currentLocation == nil`
  即返回 nil，于是 `firstMissingGate == .startPoint`、`canSubmit == false`，
  `makeCreateOrderRequest()`（`:614-615`）再挡一道。**表单和语音走的是同一道闸，都提交不出北京坐标的单。**
  `isUsingDemoFallback` / `effectiveLocation` 的行为描述本身是准确的，错在没看到调用侧已不再无条件消费它们。
  ~~⚠️ 但这条红线目前没有任何自动化守卫（见 3.4），下一个人仍可能把它改回去。~~
  **这句也是错的**（同日写下、同日推翻）：守卫一直都在 ——
  `BlindBookingGateTests.testDemoFallbackCoordinateIsNotAcceptedAsStartPoint`
  逐条断言 `resolvedStartPlace == nil`、`firstMissingGate == .startPoint`、`canSubmit == false`、
  `makeCreateOrderRequest() == nil`。写那句话时没去查用例，只看了 3.4 的「用例未写」就下了结论，
  而 3.4 说的根本是另一件事（首步出不出现）。**这正是本变更里第四次同类错误：拿一份陈旧描述当现状。**

- [x] 2.11 **录音起止的非视觉提示**（`RecordingCue`，`SpeechInputService.swift`）：起音系统音 1113 + `.light` impact，收音 1114 + `.success` notification，对应 `specs/blind-runner-voice-first-experience/spec.md:79-87`。收音提示**必须在音频会话切回播放之后**才响 —— 录音会话下放系统音会被路由到录音链路，用户可能根本听不见。
  ⚠️ **本条此前没有任务项也没有守卫**，结果实现完整却被三份文档集体误判成「尚未实现」（2026-08-06 订正）。**2026-08-06 补齐守卫**：`RecordingCue` 加 DEBUG 观察接缝；起听成功的状态转换抽成共同出口 `markRecognitionStarted()`，生产路径与测试替身共用（替身此前少做四件事，起音提示丢了在测试里根本看不见）；四条用例锁起音、收音、**收音的顺序**、以及「从没起听成功过不得有任何提示音」。

## 2A. 整句解析改走 `/api/orders/voice/parse`（2026-08-04）

- [x] 2A.1 `ParseVoiceOrderResponse` + `VoiceOrderMissingSlot`（带 `unknown` 兜底）；请求体复用 `ResolveAddressRequest`（spec 明说两端点请求体一致）。`missing`/`needReask`/`ttsText` 在 spec 里是 required，客户端一律放宽成可选。
- [x] 2A.2 `parseFreeform` 由**两路并发 `parse-slot`** 改为**一次 `/voice/parse`**；删除常闭开关 `resolvesPlaceFromFullUtterance` —— 后端已改成先抽地名 span 再查高德，整句里说的起点第一次可用。
- [x] 2A.3 `missing` / `needReask` / 后端 `ttsText` 在整句轮一个都不消费：`missing` 等价于「这几项保持默认值」，后端的 `ttsText` 在 `missing` 非空时是**追问**文案，播它等于把人拉回重问。后端 2026-08-04 确认这个用法，并说明他们拼不出整单读回。
- [x] 2A.4 `.freeform` 提问改成邀请把地点也说进去（「明天早上八点从人民广场出发跑一个小时」）。
- [x] 2A.5 `disambiguationRequest(transcript:)` 抽出坐标取值：只认 `.gcj02Backend` 真实采样，**演示坐标绝不进消歧请求**（会把人约到另一座城市）。两个解析端点共用这一份，红线只留一个出处。
- [x] 2A.6 整句轮补上时长取整播报（`durationRoundingNotice`），与定点修改轮共用同一句 —— 此前整句轮是静默取整，而静默取整对听不见屏幕的人就是篡改。
- [x] 2A.7 `MockAPIClient.handleVoiceParseOrder`；地点匹配与 `handleVoiceResolveAddress` 共用 `matchedVoicePlace`，Mock 不许比线上松。
- [x] 2A.8 **`missing: ADDRESS` 的歧义已解**（2026-08-20 复核确认，后端 N48 就是这条请求的落地）。
      分法**不是**再加一道客户端拦截，而是既有的三段机制，判据一律看**结构**（有没有坐标）
      而不是 `addressUnresolved` 那个标志位 —— 同一事实有两个来源时只信结构
      （`ResolvedPlace.isUnresolved` 上那句注释）：
      1. 用户说的地名**保留**在槽位里，绝不被当前位置顶掉（`confirmRoundSnapshot` 只在响应里
         一个地名都没有时才补起点，判据是 `address` 而不是坐标）；
      2. 读回把它念出来并明说没定位到（起点走 `startAddressUnresolvedNotice`，
         终点走 `endPointSummary` 的 `isUnresolved` 分支「这个地点没能定位到，志愿者会看到这个名字」）
         —— 后端允许「有地址无坐标」，所以**照样带名下单**，志愿者看到的是那个地名；
      3. 下一轮后端继续报 `missing:[ADDRESS]`，走确认轮那条 `unchanged + missing` 分支
         播它的定向追问（含具体地名，本地拼不出来），并计入重问上限。
      > ⚠️ **2026-08-20 走过一次弯路，记在这里免得再来一遍**：曾按「后端红线说绝不能落回当前位置」
      > 又加了一层 `startAddressNeedsReask`，拦在读回之前直接追问。那是**误读** ——
      > 既有实现本来就没有静默落回，而新加的那层会打断上面第 1 条的槽位回传，
      > 也与终点的「带名下单」直接矛盾（新文案说「先不设终点」，而终点其实带上了）。
      > 已整体 revert（PR #55 → revert）。判据看结构、不看标志位这条，是这次的教训。

## 3. 测试

- [x] 3.1 `testOnlyExplicitAffirmativesAreTreatedAsConfirmation` + `testTrailingParticlesAndPunctuationDoNotBlockConfirmation`。**2026-08-04 真机跑通。**
- [x] 3.2 **2026-08-04 订正**：原文写的 `testNonAffirmativeFallsThroughToGuidedStepsWithoutAnyRequest` 与 `testUnintelligibleConfirmationDoesNotReaskAndDoesNotSubmit` **全仓不存在**，是 `.confirmDefaults` 时期的遗留描述（那时「未命中肯定词 → 落入引导步骤」才是行为）。实际覆盖同一意图的是 `testUnrecognizedConfirmCommandReasksAndNeverSubmits`（认不出即重问、`createdOrder == nil`、不发请求）与 `testEmptyOrUnrelatedTranscriptIsNotConfirmation`。**均已真机跑通。**
- [x] 3.3 `testNegationsContainingAffirmativeWordsAreNotConfirmation`（"不确认""先别确认""确认一下时间""还不能确认"等 13 条）。**2026-08-04 真机跑通。**
- [x] 3.4 ~~默认值不可用时不出现首步~~ **2026-08-06 订正并补齐**。原措辞描述的是已被推翻的 `.confirmDefaults` 形态（先念默认值再逐项追问）——那时默认值不可用，首步自然无意义。现在首步是**整句自由说**，起点缺失恰恰是要用语音补的，把它当阻断条件等于「没有 GPS 就彻底用不了语音」。`VoiceOrderWizard.start()` 里 `gate != .startPoint, gate != .appointmentTime` 两个判断就是这条规则，现由 `testStartProceedsWhenOnlyTheVoiceFilledSlotsAreMissing` 锁住。
  另：任务原文担心的「造不出 `resolvedStartPlace == nil`」早已被解决，`BlindBookingGateTests.testDemoFallbackCoordinateIsNotAcceptedAsStartPoint` 就是这么造的（裸 `LocationService()` + `configureForTesting`），并且它已经覆盖了「演示坐标不得成单」四道断言。
- [x] 3.5 非槽位门槛缺失时 `start()` 返回 false 并播报门槛原因 —— **2026-08-06 补齐**：`testStartIsBlockedByGatesThatVoiceCannotFill`。顺带补了第三条分支 `testStartFallsBackImmediatelyWhenTheSpeechPathIsAlreadyKnownBroken`（语音链路已知不可用时直接交回表单，不走三轮重问）。
  ⚠️ 补之前 `start()` 的三道分支**一条都没被验过** —— 28 条既有用例全部走 `startForTesting(at:)` 绕开了它。
- [x] 3.6 `BlindBookingGateTests` / `blindRunTests` 回归 —— **2026-08-04 全量真机跑通（483 单测 0 失败），1.7 那条「新增回调是否波及其他 `SpeechInputField` 使用方」也随之得到回答：没有波及。**
- [x] 3.7 UI 测试（Mock 环境）—— **2026-08-08 补齐并真机跑通**：`AccessibilityAuditTests.testVoiceStageRendersNoFormControls`，断言语音态里搜索框 / 补充描述框 / 搜索按钮 / 辅助地图 / 表单说明文字一个都不存在，且「改用表单」这个逃生口在。
  ⚠️ 原措辞「验证首步文案」写不出可靠断言：首步文案是 TTS 播的，屏幕上那份是 `lastSpokenPrompt` 的镜像，断言它等于断言一个字符串常量等于它自己。改成断言**结构**（语音态里表单不存在），那才是自动化能抓、人眼容易漏的东西。
  ⚠️ 真机跑 UI 测试拿不到语音识别授权时 `start()` 会直接降级到表单态，语音态在自动化里根本走不到 —— 加了接缝 `AIDRUN_UI_TEST_FORCE_VOICE_STAGE`（只调既有的 `startForTesting(at:)`，不碰麦克风、不伪造解析结果）。

## 6. 预约页收成语音态 / 表单态二选一（2026-08-08）

- [x] 6.1 `BlindBookingView.body` 从「header + 语音区 + 进度条 + 四步表单」四块并排改成 `if voiceWizard.isRunning { voiceStage } else { formStage }`。
- [x] 6.2 `voiceStatusBlock` 取代原来挂在 `body` 上的整屏点击 `.overlay`。原实现在 `isParsing` 时把整层撤掉，那几秒屏幕上没有任何东西说「正在识别」；现在元素恒在，只有可点性与 `.isButton` 随状态变。VoiceOver 只给一个焦点：`label` 是现在能做什么，`value` 是刚念的那句话。
- [x] 6.3 读回轮加 `voiceOrderRecap`：一行「一个名字 + 一个值」，不带「出发地点：」这类前缀（视觉对标 §1 规则 4）。时间只在 `didCaptureStartTime` 为真时显示具体时刻 —— 屏幕这一份不能把 2026-08-06 修过的「不许念用户没说过的时刻」退回去。
- [x] 6.4 底栏 `voiceControls` 从并排改全宽竖排（视觉对标 §1 规则 3；横排也是本项目 UI 测试假失败的常见来源）。
- [x] 6.5 **缺陷修复**：`.onChange(of: voiceWizard.step)` 首次进入不触发（`step` 初值即 `.freeform`，`start()` 是同值赋值，SwiftUI 的 `onChange` 只在新旧值不等时触发），表单因此停在第 1 步。三个启动点收敛到 `startVoiceWizard()`，成功时显式同步到 `.review`。
  ⚠️ 这个缺陷的可见症状正是本轮的起点：`startsWithVoice: true` 进来时屏幕渲染的是 `locationSection`（搜索框 + 麦克风 + 辅助地图），而不是设计里的确认步。
- [x] 6.6 零输入下单：`fallbackMessage != nil && firstMissingGate == nil` 时在表单顶部给两步按钮。演示坐标不需要单独判 —— 正式通道里 `resolvedStartPlace` 拿不到真实定位就是 nil，`.startPoint` 那道门槛已经挡住了。
- [x] 6.9 **`/code-review` 抓到的一条 HIGH，已修**：`isZeroInputConfirming` 这个 `@State` 只在两个按钮里赋值、没有任何复位，活得比它的前提久。路径：点「不用填，直接下单」进第二步 → 改点「用语音重新说一次」→ 这一轮语音又失败 → 页面切回表单态时**直接露出真提交的按钮**，而用户这一轮既没点过 offer、也没听到「确认就再点一次」那句整单播报 —— 两步确认的全部理由就是那句播报，没听到等于一步提交。
  修在两处，缺一不可：`startVoiceWizard()` 里显式复位（盖重启语音那条 —— 那条路上 `isZeroInputOfferAvailable` 一直是 true，`fallBack` 换的是消息内容不是有无，`onChange` 抓不到），以及 `.onChange(of: isZeroInputOfferAvailable)` 在前提消失时复位（盖门槛中途变化那条，例如去系统设置关掉定位再打开）。
- [x] 6.7 既有 UI 用例适配：
  - `blindRunUITests.createBookingAndAssertMatching` 不再写死「第 1 步 → 第 2 步 → 第 3 步 → 提交」。落在哪一步由麦克风授权决定，写死步数在授权成功的设备上必挂，且挂的原因与下单链路无关。
  - `AccessibilityAuditTests.testBlindBookingPassesAccessibilityAudit` 改成等语音态或表单态任一标志元素。**基线实测这条本来就在报 `XCTAssertTrue failed - 下单页没起来`** —— 它只等表单态才有的 `blindBookingVoiceOrderButton`，而这台设备的麦克风授权是给过的。
- [x] 6.8 真机验证（2026-08-08，iPhone 16 Pro）：
  - `blindRunTests/VoiceOrderWizardTests` + `blindRunTests/BlindBookingGateTests` → passed=62 failed=0
  - `blindRunTests/blindRunTests` → passed=278 failed=0
  - `blindRunUITests/blindRunUITests/testMockBlindRunnerBookingSmoke` → passed=1 failed=0
  - `blindRunUITests/AccessibilityAuditTests` → passed=4 failed=2，两条失败是先于本轮存在的静态审计红灯（对比度 + Dynamic Type，见 `docs/research/blind-ui-visual-benchmark-20260808.md` §5）。**基线对照实测**：改动前预约页那条报 4 条报警 + 1 条断言失败，改动后降到 2 条报警、断言失败消失。
  - 未全量：本轮没碰 `SystemSpeechAudioSession` / `APIClient` / `AppState`，按 `AGENTS.md`「跑多大范围」只跑覆盖面内的 suite。

## 4. 文档

- [x] 4.1 `docs/05-page-specs.md` 创建预约页：「语音下单：一次说完 → 读回整单 → 确认或定点修改」小节（2026-08-04 随第 2 节一并从「第 0 轮：复核默认值」订正过来，并补上 `/voice/parse` 与 `missing: ADDRESS` 的已知缺口）。
- [x] 4.2 `docs/09-accessibility-and-voice-guidelines.md`：必播报节点补读回整单的三段式、**时长取整必须说出来**、以及语音不可用时的降级播报（同日订正掉原来那条「第 0 轮默认值复核」）。
- [x] 4.3 `AGENTS.md` 无需改动：本变更不触及 SOS 章节，也不改下单门槛顺序。
- [x] 4.5 `docs/05-page-specs.md` 设置页：补法律条款入口（`GET /api/misc/legal-links` 免鉴权、只拉一次、失败静默、两条落点都可点且有内容）—— 这是同日 `validate-spec-coverage.mjs` 抓到「该端点前端从未请求过、入口也不存在」之后补的。
- [-] 4.4 `docs/07-api-contract.openapi.yaml` —— **不适用**。契约唯一来源是后端仓库 `demo/docs/api_spec.yaml`（`AGENTS.md` 第 7 节），且本变更不触碰任何端点。
- [x] 4.6 **2026-08-05 订正 `specs/blind-runner-voice-first-experience/spec.md`**：`Scenario: Start place is
      not extracted from the full utterance` 与实现**方向相反** —— spec 要求「不从整句抽地点、不把整句送
      address-resolution」，而 2A.2 已改成一次 `/voice/parse` 抽三槽位、`resolvesPlaceFromFullUtterance` 已删。
      同一 Scenario 里「两路并发 parse-slot」也是旧形态。已改写为 `Scenario: Start place is extracted from
      the full utterance`，并把 `missing: ADDRESS` 的歧义兜底（读回念出实际起点）写进 spec。
      **这是本变更第三次文档/spec 与实现反向漂移**（前两次见第 2 节 2026-08-04 订正），
      `openspec validate --strict` 只查结构不查语义、三次都没抓到，已按 `AGENTS.md` 第 1 条写入项目记忆。

## 5. 验收

- [x] 5.1 `openspec validate enable-one-utterance-booking --strict --no-interactive` 通过。
- [x] 5.2 `node scripts/validate-docs.mjs` 通过（文档改动后复跑）。
- [x] 5.3 `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing` → `TEST BUILD SUCCEEDED`。注意这是**无签名编译**；带签名的 `build-for-testing` 需 `-allowProvisioningUpdates DEVELOPMENT_TEAM=ZW39BS8NXT`。
- [x] 5.6 独立 Swift 脚本实跑（设备离线时的替代信号，非 XCTest）：
  - `/tmp/clearstate_check.swift` —— 一次性送达、幂等、无会话时不送、**回调内重启新会话不被随后的清空覆盖**（这一条证明「先取引用再置 nil 最后回调」的顺序是重入安全的）。ALL PASS。
  - `/tmp/affirmative_check.swift` —— 19 条白名单 + 语气词剥离 + 13 条含肯定词的否定 + 填充词与边界。ALL PASS。
    ⚠️ 这是当时那一版的记录，**已被 2026-08-05 的收窄取代**（19 → 8 条，见 2.3）。现行断言在 `blindRunTests/VoiceOrderWizardTests.swift`，以那里为准。
- [x] 5.4 真机批跑单测 + UI 测试 —— **2026-08-04 14:36 执行完毕：`TEST SUCCEEDED`，483 单测 + 33 UI、0 失败、1 恒 skip。** 命令：
  ```
  xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun \
    -destination 'platform=iOS,id=<设备 id>' \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=ZW39BS8NXT
  ```
  全量约 10 分钟，会超 Bash 600s 上限，需自行重定向到日志文件。
- [ ] 5.5 真机手测（开 VoiceOver）：说肯定词完成一次真实下单；说「修改」落入逐项流程；**拒绝麦克风权限后进入语音下单，确认只播报一次原因就落到表单、不再连问三轮**。
  **2026-08-06 首次部分执行，报回三条缺陷（读回被截断 / 起音提示放不出来 / 重问后无信号），已修，见第 1B 节。**
  修完新增手测案例 **J（读回念完整）、K（重问后仍可感知）、L（外放与耳机都听得见）**，
  与 A 一起构成「音频只能人耳验」的那一组 —— 全部待复测，本条继续挂着。
  **执行脚本见 `docs/voice-booking-manual-test-20260805.md`**（12 个案例 + 结果表）。其中 C（2 秒尾静音会不会切断中文长句）与 D（8 个确认词够不够用）是 2026-08-05 那两处改动的**唯一验证通道**——单测证明不了它们。E（旁人说话不能下单）是唯一阻断发布的案例。
  ⚠️ 开跑前先用脚本第 1 节的判别法排除「后端 `AMAP_WEB_KEY` 未配」：key 为空时 `AmapGeocodingService` 静默返回 empty，表现成「地点识别不出来」，会被误诊成识别问题。**该 key 的线上状态至今未验证**（curl 预检因限流与白名单不符未打通，详见脚本）。
