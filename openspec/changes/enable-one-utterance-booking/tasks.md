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
- [ ] 2A.8 **`missing: ADDRESS` 的歧义未解**：分不出「用户没说地点」和「说了但抽不出」。后者静默用当前位置会把人约到错误起点。已提给后端（handoff 2026-08-04），等他们区分。

## 3. 测试

- [x] 3.1 `testOnlyExplicitAffirmativesAreTreatedAsConfirmation` + `testTrailingParticlesAndPunctuationDoNotBlockConfirmation`。**2026-08-04 真机跑通。**
- [x] 3.2 **2026-08-04 订正**：原文写的 `testNonAffirmativeFallsThroughToGuidedStepsWithoutAnyRequest` 与 `testUnintelligibleConfirmationDoesNotReaskAndDoesNotSubmit` **全仓不存在**，是 `.confirmDefaults` 时期的遗留描述（那时「未命中肯定词 → 落入引导步骤」才是行为）。实际覆盖同一意图的是 `testUnrecognizedConfirmCommandReasksAndNeverSubmits`（认不出即重问、`createdOrder == nil`、不发请求）与 `testEmptyOrUnrelatedTranscriptIsNotConfirmation`。**均已真机跑通。**
- [x] 3.3 `testNegationsContainingAffirmativeWordsAreNotConfirmation`（"不确认""先别确认""确认一下时间""还不能确认"等 13 条）。**2026-08-04 真机跑通。**
- [x] 3.4 ~~默认值不可用时不出现首步~~ **2026-08-06 订正并补齐**。原措辞描述的是已被推翻的 `.confirmDefaults` 形态（先念默认值再逐项追问）——那时默认值不可用，首步自然无意义。现在首步是**整句自由说**，起点缺失恰恰是要用语音补的，把它当阻断条件等于「没有 GPS 就彻底用不了语音」。`VoiceOrderWizard.start()` 里 `gate != .startPoint, gate != .appointmentTime` 两个判断就是这条规则，现由 `testStartProceedsWhenOnlyTheVoiceFilledSlotsAreMissing` 锁住。
  另：任务原文担心的「造不出 `resolvedStartPlace == nil`」早已被解决，`BlindBookingGateTests.testDemoFallbackCoordinateIsNotAcceptedAsStartPoint` 就是这么造的（裸 `LocationService()` + `configureForTesting`），并且它已经覆盖了「演示坐标不得成单」四道断言。
- [x] 3.5 非槽位门槛缺失时 `start()` 返回 false 并播报门槛原因 —— **2026-08-06 补齐**：`testStartIsBlockedByGatesThatVoiceCannotFill`。顺带补了第三条分支 `testStartFallsBackImmediatelyWhenTheSpeechPathIsAlreadyKnownBroken`（语音链路已知不可用时直接交回表单，不走三轮重问）。
  ⚠️ 补之前 `start()` 的三道分支**一条都没被验过** —— 28 条既有用例全部走 `startForTesting(at:)` 绕开了它。
- [x] 3.6 `BlindBookingGateTests` / `blindRunTests` 回归 —— **2026-08-04 全量真机跑通（483 单测 0 失败），1.7 那条「新增回调是否波及其他 `SpeechInputField` 使用方」也随之得到回答：没有波及。**
- [ ] 3.7 UI 测试（Mock 环境）验证首步文案 —— 未写、未跑。

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
  **执行脚本见 `docs/voice-booking-manual-test-20260805.md`**（9 个案例 + 结果表）。其中 C（2 秒尾静音会不会切断中文长句）与 D（8 个确认词够不够用）是 2026-08-05 那两处改动的**唯一验证通道**——单测证明不了它们。E（旁人说话不能下单）是唯一阻断发布的案例。
  ⚠️ 开跑前先用脚本第 1 节的判别法排除「后端 `AMAP_WEB_KEY` 未配」：key 为空时 `AmapGeocodingService` 静默返回 empty，表现成「地点识别不出来」，会被误诊成识别问题。**该 key 的线上状态至今未验证**（curl 预检因限流与白名单不符未打通，详见脚本）。
