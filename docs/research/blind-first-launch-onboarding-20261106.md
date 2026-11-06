# 盲人端首次打开到能约跑：别家怎么做，我们还差什么（2026-11-06）

## 问题

负责人 2026-11-06 反馈：盲人端一打开，没有资料就必须先填个人资料才能进首页，而且没有退出的机会。
要求：调研其他盲人 App 首启流程和 Apple 的做法，判断流程对不对，改流程或 UI 要先出可视图批准。

## 一句话结论

**强制先填资料的那道门 main 上已经没有了**（PR #783 / issue #781，2026-11-05 合入），负责人看到的是旧版本。
现在的顺序与别家和 Apple 的口径一致。负责人随后决定昵称完全可选（#789）：约跑前只要求紧急联系人。

## 一、现状（origin/main `f1697475`）

| 步骤 | 页面 | 能不能跳过 | 代码 |
|---|---|---|---|
| 1 | 首启隐私同意 | 不能（PIPL 第 14 条要主动同意，登录页也收手机号） | `blindRun/ContentView.swift`（`PrivacyConsentGateView`） |
| 2 | 手机号 + 验证码登录 | 不能（账号是派单与求助的前提） | `blindRun/Auth/LoginView.swift`，验证码框已是 `.oneTimeCode` |
| 3 | 选身份（视障跑者 / 陪跑员） | 不能（后端按角色建空资料） | `blindRun/Role/RoleSelectionView.swift` |
| 4 | 首页，自动推一次「使用帮助」四张卡 | 能，返回键即可 | `BlindRunnerHomeView.swift`（`didSeeBlindFirstRunHelp`） |
| 用到时 | 通知权限：有第一张订单时问 | 能 | `PushPermissionPrompt.swift`（#521） |
| 用到时 | 位置说明页再弹系统定位框：约跑时问 | 能，拒绝后可手动搜地点 | `BlindBookingTrackConsentGate`（#776） |
| 用到时 | 昵称、紧急联系人：约跑页顶部「约跑前还差 N 项」 | 不约跑就不用填 | `BlindBookingMissingSetupCard.swift`（#781） |

后端口径（读 `blind-run-backend` origin/main）：

- 选身份时 `RoleController` 自动建空的 `BlindProfile`，所以新用户 `GET /api/blind/profile` 不会 404。
- `PUT /api/blind/profile` 的 `name` 自 #926 起可选。
- `POST /api/orders` 只在服务端校验紧急联系人（403 `EMERGENCY_CONTACT_REQUIRED`），不校验昵称。
- 求助短信取 `User.name`，为空时退成「未知用户」（`EmergencyContactNotifier.java:320-321`、`:531`）。
  ⇒ 昵称一旦可选，这里必须由后端兜底（见第四节第 3 条，blind-run-backend#929）。

## 二、同类 App（来源等级：官 = 官方页，评 = 用户评测或第三方指南，摘 = 搜索摘要转述）

| 产品 | 首启顺序 | 进首页前必填 | 紧急联系人 | 来源 |
|---|---|---|---|---|
| Be My Eyes | 选盲人或志愿者 → 登录方式 → 邮箱验证 → 语言 → 麦克风/相机/通知 | 角色、账号、语言 | 没有这个字段 | 官 [Getting Started](https://support.bemyeyes.com/hc/en-us/articles/360005536558-Getting-Started-with-Be-My-Eyes) |
| Aira Explorer | 登录（含手机号 + 4 位码）→ 确认姓名 → 语言 → 首页呼叫 | 账号、姓名、语言 | 没有 | 评 [Surrey 郡上手指南 2025-05](https://www.surreycc.gov.uk/__data/assets/pdf_file/0018/446031/Getting-Started-with-Aira-Explorer-v1-30052025_112717.pdf) |
| Seeing AI | 打开即用，引导提示只弹一次 | App Store 页未提账号 | 没有 | 官 [App Store](https://apps.apple.com/us/app/seeing-ai/id999062298) |
| Lazarillo | 必须注册 → 蓝牙/通知/定位连弹 → 首次教程 | 账号（邮箱注册要姓名） | 没有 | 官 [iOS 手册 2021](https://lazarillo.app/wp-content/uploads/2021/05/IOS-USER-MANUAL-ENGLISH.pdf) |
| NaviLens | 接受条款 + 简短导览，打开即扫码 | 无账号 | 没有 | 官 [Intercity Transit](https://intercitytransit.com/how-to-ride/navilens) |
| Life360 | 注册 10 步，最后一步右上角 Skip | 手机号、姓名等 | 不在注册里，之后单独设 | 官 [Create Account](https://support.life360.com/hc/en-us/articles/23053525850519-Create-a-Life360-Account) |
| Noonlight | 注册 4 项 | 未列明 | 在「个人资料」里加，从通讯录选 | 官 [Emergency contact](https://help.noonlight.com/en/articles/2141854-can-i-add-an-emergency-contact-to-my-profile) |
| Uber | — | — | 「信任联系人」在设置里增删，0–5 人 | 摘 |

**查到的产品里，没有一家在进首页前强制填紧急联系人。**

未找到：Envision、GoodMaps、Oko、VoiceVista、小艾帮帮的首启流程；国内「保益」「点明」没有搜到。
全部来自文档与评测，没有实机走过。「问用户是否用读屏」「读屏专用跳过按钮」没有任何产品的官方说明。

## 三、Apple 与 WCAG 原文

| 来源 | 原句 | 对我们的意思 |
|---|---|---|
| HIG Onboarding | "Postpone nonessential setup flows or customization steps." | 非必需的设置往后放 —— #783 的依据 |
| HIG Onboarding | "If you let people skip the tutorial … don't present it again on subsequent launches, but make sure it's easy for people to find" | 使用帮助只自动推一次，之后在设置里能找到（现状如此） |
| HIG Managing accounts | "Delay sign-in for as long as possible." | 我们的登录是派单前提，属核心功能，可以放前面 |
| 审核指南 5.1.1(v) | "Apps may not require users to enter personal information to function, except when directly relevant to the core functionality" | 紧急联系人只在约跑时要，约跑是核心功能且带线下安全风险 |
| 审核指南 5.1.1(x) | "Apps may request basic contact information (such as name and email address) so long as the request is optional for the user, features and services are not conditional on providing the information" | 昵称**不能**挡在进 App 前；约跑时要它，必须说清用途（家属短信、陪跑员称呼） |
| HIG Accessibility | "Break up multistep workflows so people can focus on a single interaction per screen." | 补昵称该是一屏一件事，不该落到十几行的资料页 |
| WCAG 2.2 3.3.7 Redundant Entry | "Information previously entered … is either: auto-populated, or available for the user to select." | 补完回约跑页，已填的地点、时间不能丢（#783 已做） |
| Apple 健康 App 入门 | "If you don't supply all of the requested information, you can add it later on the Health Details screen." | Apple 自己的资料收集也允许以后补 |

链接：[Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) ·
[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts) ·
[审核指南](https://developer.apple.com/app-store/review/guidelines/) ·
[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) ·
[WCAG 2.2](https://www.w3.org/TR/WCAG22/) ·
[健康 App 入门](https://support.apple.com/guide/iphone/get-started-with-health-iph08022b194/ios)。
WCAG 与 HIG Accessibility 都没有「首次流程必须可跳过」的条款（未找到）。

## 四、决策

1. **不加新的引导页、不加「稍后再说」按钮**：门已经拆了，没有东西需要跳过。再加一层就是过度防御。
2. **前三步（隐私同意、登录、选身份）保留**：都是法律或派单的前提，与 Be My Eyes、Aira 的顺序一致。
3. **紧急联系人保持「约跑时才要」**：它是后端下单的硬门槛，也是盲人线下陪跑的安全前提。
4. **昵称完全可选，约跑也不要求**（负责人 2026-11-06 原话「昵称也改成可选」，iOS #789）。依据 5.1.1(x)。
   没昵称时两处要后端兜底，由 blind-run-backend#929 做，iOS 那个 PR 等它先合：
   - 求助短信称呼不能是「未知用户」，改为家属认得出的兜底（如手机尾号）。
   - 跑者姓名字段 null 目前表示「已注销」，陪跑员跑后记录会误报对方已注销。

被否掉的：

- 「首启问一句是否用读屏，分两套流程」—— 没有任何产品这样做的一手证据，且 iOS 能直接读 `UIAccessibility.isVoiceOverRunning`。
- 「约跑前补昵称直达单输入框页」（本报告初稿的拟改方案）—— 昵称不再是门槛，这一行整个去掉，直达页不需要了。

## 复核触发条件

后端把求助短信的称呼改成不依赖 `User.name`（例如改用手机尾号）；Apple 改 5.1.1(x) 或 HIG Onboarding；
上线后数据显示新用户卡在「约跑前还差 N 项」；拿到 Be My Eyes / Aira 实机首启录屏且与上表矛盾。
