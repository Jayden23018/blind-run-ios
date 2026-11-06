# 盲人端少填表：删字段、自动带出、语音代填的可行性（2026-11-06）

## 问题

负责人 2026-11-06 反馈：盲人端要自己逐项填的表单和按钮太多，负担重。
要求：盘点现在要填的地方，调研「尽量少填、用语音代填」能不能做，给出可执行方案。

负责人当轮定的三件事：

- 主线是**先删字段、自动带出，剩下必须填的再加语音**。
- 语音优先用**苹果自带**的识别。苹果自带的做不到时，才把内容送后端大模型。
- 交付到「方案 + 拆好 issue」，批了再开工。

## 一句话结论

能做，而且大部分不用改后端。
17 处文字输入里，App 内带麦克风的只有 4 处，都在约跑表单。
现成的 `VoiceTextField` 用的是苹果的 `SFSpeechRecognizer`，可以直接接到留言、评价、举报、工单和资料页，覆盖到 11 处。
省力最多的是「再约一次」：带出上一单的起点、时长、配速和备注，只剩选时间。
紧急联系人不做语音，继续用系统通讯录：研究里盲人反映 Siri 反复认错人名。

## 一、现状盘点（origin/main `a8d037de`）

方法：先用脚本扫 `blindRun/` 下盲人端目录里的全部输入控件（18 个），再按「首次打开 → 约跑 → 跑完」逐屏核对，最后抽查 3 条。

### 1. 文字输入（17 处）

| 填写点 | 代码 | App 内语音 | 备注 |
|---|---|---|---|
| 登录手机号 | `blindRun/Auth/LoginView.swift:206` | 无 | 数字键盘，可用键盘听写 |
| 验证码 | `blindRun/Auth/LoginView.swift:246` | 无 | 已设 `.oneTimeCode`，短信可自动填 |
| 邀请码 | `blindRun/Role/RoleSelectionView.swift:298` | 无 | 选填，折叠着 |
| 昵称 | `blindRun/Profile/ProfileModule.swift:393` | 无 | #792 改为完全选填 |
| 给陪跑员的引导偏好 | `blindRun/Profile/ProfileModule.swift:463` | 无 | 选填 |
| 特殊需求 | `blindRun/Profile/ProfileModule.swift:480` | 无 | 选填 |
| 紧急联系人姓名 | `blindRun/Profile/EmergencyContactFormView.swift:93` | 无 | 主路径是通讯录选人（#747） |
| 紧急联系人手机号 | `blindRun/Profile/EmergencyContactFormView.swift:103` | 无 | 同上 |
| 自定义关系 | `blindRun/Profile/EmergencyContactRelationship.swift:57` | 无 | 只在选「其他」时出现 |
| 搜索出发地点 | `blindRun/BlindRunner/BlindBookingView+StartPoint.swift:29` | **有** | 识别完自动搜 |
| 出发地点补充描述 | `blindRun/BlindRunner/BlindBookingView+StartPoint.swift:63` | **有** | 语音向导写不进这一项 |
| 路线备注 | `blindRun/BlindRunner/BlindBookingView+StepSections.swift:47` | **有** | 语音向导写不进这一项 |
| 特殊说明 | `blindRun/BlindRunner/BlindBookingView+StepSections.swift:108` | **有** | 向导也能写 |
| 给陪跑员留言 | `blindRun/BlindRunner/RunnerMessage.swift:48` | 无 | 裸 `TextField` |
| 评价内容 | `blindRun/BlindRunner/BlindOrderStatusView+StatusSections.swift:138` | 无 | 裸 `TextEditor`；`SpeechInputField.ratingFeedback`（`blindRun/Voice/SpeechInputService.swift:315`）已定义却没接上 |
| 举报详情 | `blindRun/Shared/UserReportView.swift:117` | 无 | 裸 `TextEditor` |
| 客服工单 | `blindRun/Shared/SupportTicketView.swift:83` | 无 | 裸 `TextEditor` |

扫描到的第 18 个控件是开发用的「API 环境」选择（`blindRun/BlindRunner/BlindRunnerSettingsView.swift:200`），不面向用户，不计入。

### 2. 选择与按钮

- 约跑手动表单共 4 步（`blindRun/BlindRunner/BlindBookingView.swift:67-71`）。第 3 步有时长、配速、路线偏好三个选择器，加导盲犬开关和两个文字框。
- 语音向导（`blindRun/Voice/VoiceOrderWizard*.swift`）能填起点、终点、开始时间、时长、导盲犬、配速、备注。
  **填不到**的是路线偏好、路线备注、出发点补充描述，这三项只能回手动表单。
- 缺紧急联系人时，向导直接降级到手动表单（`VoiceOrderWizard.start()` 里 `fallbackMessage = gate.message`）。
- 资料页的配速、引导方式、视力状况、导盲犬全是点选，没有语音。点选对读屏用户负担不大，不列为重点。

### 3. 已经在减少填写的

- 默认出发地点会预选为起点（`blindRun/BlindRunner/BlindBookingView.swift:327-330`），常用地点本地存最多 10 个（`blindRun/BlindRunner/FavoritePlaceStore.swift:22`）。
- 预约时间默认「最早可约 + 1 分钟」，时长不填按 60 分钟计。
- 语音失败后的表单里有「直接下单」：用当前位置和最早时间成单，要点两次确认。
- 后端已有整句解析 `/api/orders/voice/parse`，请求可带 `current`（上一轮的槽位）做一步修正。

### 4. 缺的

- **没有「再约一次」**。按「再约一次 / 再来一单 / 重复预约 / 上次 / rebook / lastOrder」搜 `blindRun/`，零命中。
- 向导不读 `FavoritePlaceStore`，说「从家出发」认不出常用地点。
- 资料里的默认配速不会带进约跑表单。

## 二、外部证据

来源等级：[高] 官方文档、论文原文、政府原文；[中] 单一可靠来源或社区教程；[低] 转载或厂商自述。

### 研究

- 读屏用户用屏幕键盘打字极慢：两项研究分别测得每分钟 0.66 词和 2.11 词，明眼人超过 20 词。[Azenkot 博士论文《Eyes-Free Input on Mobile Devices》](https://digital.lib.washington.edu/bitstreams/b7fba4e3-b8eb-436e-9f81-54c8787e89ae/download) [高，本轮下载原文核对]
- 同一论文的实验室研究：语音输入速度接近屏幕键盘的 5 倍，8 名盲人中 6 人偏好语音；**但他们平均把 80.3% 的时间花在检查和修改识别结果上**，多数用退格键删掉再重打。同上 [高，原句已核]
- 14 名盲人的 Siri 访谈：有人的联系人姓名被反复认错，重说也没用；有人只用 Siri 发短而简单的消息。[「Siri Talks at You」ASSETS 2018](https://userpages.umbc.edu/~rkuber/pubs/assets2018.pdf) [高]
- 同篇转述：在公共场所，用户对说出隐私信息很谨慎，也担心尴尬。这是转引别人的研究。同上 [中]
- WebAIM 第 10 次读屏用户调查（1,539 份）：「验证码」排第 1 大痛点，「复杂或难用的表单」排第 7（共 12 项）。[WebAIM Screen Reader User Survey #10](https://webaim.org/projects/screenreadersurvey10/) [高]

### 规范

上海市《互联网应用适老化和无障碍设计规范（试行）》（沪经信推〔2021〕209 号附件 4），本轮下载原文核对：[上海市经信委 PDF](https://www.sheitc.sh.gov.cn/cmsres/c8/c85e4ab9fffd4e65a5640b2cd5973862/525f164319b1c6a0a6d3ade45dc2ec88.pdf) [高，地方规范]

- 4.2.4 用户输入（二级）：应通过缓存记录、使用行为和习惯等设置默认值，减少反复输入。
- 5.2.4.2 语音输入（三级）：需要文本输入的输入栏，应提供语音输入的替代方式。
- 5.3.4.3 错误预防（三级）：提交时至少满足一条：可撤回、可检查并纠正、最终提交前有检查确认修改的机制。

工信部《移动互联网应用（APP）适老化通用设计规范》只看到转载，转载里没有「默认值」「语音输入」条款，官方站证书报错打不开。[中国新闻网 2021-04-14 报道](https://www.chinanews.com.cn/cj/2021/04-14/9454293.shtml) [中]

### 平台能力

- App Intents 的 `AppShortcutsProvider` 从 iOS 16.0 起可用，本仓库部署目标 iOS 16 够用。[Apple 文档 JSON](https://developer.apple.com/tutorials/data/documentation/appintents/appshortcutsprovider.json) [高]
  ⇒ 可以加「嘿 Siri，用助盲跑约跑」。中文 Siri 怎么认短语，没查到资料，要真机试。
- 验证码自动填用 `textContentType(.oneTimeCode)`；要绑定域名的那种，短信最后一行要写成 `@域名 #验证码`。[Apple：Enabling AutoFill for domain-bound SMS codes](https://developer.apple.com/documentation/security/enabling-autofill-for-domain-bound-sms-codes) [高]。本仓库已设 `.oneTimeCode`。
- 读屏开着时，在键盘上双指双击可以开关听写（原文：Use a two-finger double tap on the keyboard to start and stop dictation）。[Apple：Use the onscreen keyboard with VoiceOver on iPhone](https://support.apple.com/guide/iphone/use-the-onscreen-keyboard-iph3e2e3d1d/ios) [高]
  ⇒ 不加麦克风按钮，用户也能听写；加按钮的价值在于好找，并且和约跑页的做法一致。
- 阿里云一键登录：不用输手机号和验证码，页面显示脱敏号码，要先勾同意再点登录；失败时用短信验证码兜底。文档没提无障碍。[阿里云号码认证文档](https://help.aliyun.com/document_detail/84540.html) [高]

## 三、共识与争议

**共识**

- 读屏下打字是最慢的输入方式，能不打字就不打字。
- 语音录入快，但改错很费力，所以应该少让人说，说完要念回来确认。
- 默认值和「复用上次」能直接减少输入，规范也明确要求。

**争议**

- **语音还是键盘**：Azenkot 实验里 6/8 偏好语音，但那是写一段话。二手综述（Capti-Speak、W4A 2014 Wizard-of-Oz，只看到摘要）称部分盲人填表时仍偏好键盘，理由是识别不可靠、和别人共处时不便说话。任务不同，现有证据判不出谁对。⇒ 两种都留：麦克风按钮是加的，不替换键盘。
- **人名和号码用不用语音**：通用听写对人名不可靠（ASSETS 2018），但没有中文人名、手机号识别错误率的数据。⇒ 联系人走通讯录，不靠语音。

## 四、方案

按收益和改动量排序。编号对应 issue。

**第一批：不改契约、改动小**

1. 留言、评价、举报详情、客服工单四处改用 `VoiceTextField`（`blindRun/Voice/VoiceTextField.swift`）。评价接现成的 `.ratingFeedback`，另三处在 `SpeechInputField` 加值。识别完把结果念一遍。
2. 资料页的昵称、给陪跑员的话、特殊需求接语音。依赖 #784（资料页改成「点哪行改哪行」）先合，改在它新建的 `BlindProfileTextEditPage.swift` 上。
3. 约跑表单的配速默认取资料里的默认配速。

**第二批：行为有变，先建 OpenSpec 变更**

4. **再约一次**：在跑完的订单和首页加入口，带出上一单的起点、时长、配速、导盲犬和备注，只剩选时间。语音向导支持「和上次一样」：把上一单作为 `current` 传给现有的 `/api/orders/voice/parse`，不改后端。开工前核对订单详情返回这些字段。
5. **约跑第 3 步减项**：路线偏好、路线备注、特殊说明三项合成一个「想跟陪跑员说的话」语音框。契约里这三个字段本来就可选。需要负责人点头。
6. **向导里补紧急联系人**：缺联系人时直接弹系统通讯录，选完回到语音，不降级到手动表单。顺带让向导先在本地 `FavoritePlaceStore` 里匹配「家」「公司」这类常用地点名。

**第三批：探索**

7. **Siri 快捷指令**：「嘿 Siri，用助盲跑约跑」直接打开语音约跑页，先不带参数。先做最小样例在真机上试中文 Siri。

**对照规范的结果**：做完 1、2 后，17 处文字输入里有 App 内语音的从 4 处到 11 处（5.2.4.2）。剩下 6 处是手机号、验证码（短信自动填）、邀请码、联系人姓名和电话（通讯录）、自定义关系，都有非键盘的替代，或很少用到。3、4 对应 4.2.4。语音向导已有读回确认，满足 5.3.4.3。

## 五、被否掉的方案

| 方案 | 为什么不做 |
|---|---|
| 紧急联系人用语音填姓名和电话 | 盲人反映人名反复被认错（ASSETS 2018）；在公共场所念出家人手机号有隐私顾虑；系统通讯录选人更准，#747 已做成主路径 |
| 留言、评价等内容送后端大模型解析 | 负责人定苹果自带优先；这些是自由文字，听写就够，不需要抽取字段 |
| 统一的「一句话填好整页」对话式填表 | 要后端新接口；没找到有盲人参与的对话式填表研究；约跑已经有向导，其余表单字段少 |
| 运营商一键登录 | 要新增第三方 SDK、费用和隐私告知；查不到它对视障用户好不好用；验证码已能自动填。留给负责人以后决定 |

## 六、什么情况下这个方案是错的

- **如果真实盲人用户更常用键盘听写或盲文键盘**，第 1、2 条的麦克风按钮价值不大，只是多一个按钮。验证办法：内测时看麦克风按钮的点按次数，或直接问 3–5 位用户。
- **如果大多数盲人每次约跑的起点、时长都不一样**，「再约一次」省不了多少。验证办法：看内测订单里同一用户相邻两单起点和时长相同的比例。
- **如果中文 Siri 对「用助盲跑约跑」这类短语识别不稳定**，第 7 条应放弃。最小样例在真机试过再决定。
- 第 5 条合并三项后，陪跑员收到的是一段自由文字而不是选项，**如果陪跑员端依赖路线偏好做筛选**，合并会丢信息。开工前要查陪跑员端是否用到 `routePreference`。

## 七、没查到

- 中文语音识别对人名、手机号、地址的错误率。
- 有盲人参与的「对话式填表 vs 普通表单」或大模型填表研究。
- 运营商一键登录对视障用户的可用性评价。
- 滴滴、高德、支付宝关怀模式等「减少填写」做法的原始页面（只有媒体宣传，未打开原文，不列）。
- 工信部适老化规范官方全文。

## 复核触发条件

- 内测数据显示麦克风按钮几乎没人用，或用户反馈更习惯键盘听写。
- Apple 改 `SFSpeechRecognizer` 中文识别或 App Shortcuts 中文短语规则。
- 后端给非约跑表单加解析接口，或负责人改为允许送大模型。
- 出现中文人名、号码语音识别错误率的公开数据。
