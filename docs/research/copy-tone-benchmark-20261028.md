# 按钮与说明文字的口吻：外部规范与同类产品怎么写（2026-10-28）

**为什么查**：负责人评价 AidRun 两端文案「大白话、解释性太多、很防御、很小孩化」，要改成成熟产品的口吻（Jayden23018/blind-run-ios#558 第 1 项）。本报告只回答「外面怎么写」，**不评判 AidRun 现有文案**（由另一个 session 审）。
**怎么查的**：规范全部读原文——Apple HIG 用 `developer.apple.com/tutorials/data/design/human-interface-guidelines/*.json` 取正文；Apple 无障碍属性指南取自 Apple 档案库页；Material 3 用内置浏览器读渲染后正文；Ant Design 取自 GitHub 原始 md；微软简体中文指南取自官方 PDF（`pdftotext`）。竞品文案取自仓库已有截图（`docs/ui/reference-screenshots/`，目录被 gitignore，在主 checkout 里）和官方帮助页。查阅日期全部 2026-10-28。已有调研直接引用，没重搜（见末尾「沿用」）。

## 0. 先说限制（别当成已查到）

| 想查的 | 结果 |
|---|---|
| TDesign 文案规范 | **未找到**。官网无文案页（`/design/words` 跳回首页）；仓库 `Tencent/tdesign/docs` 无文案文件；`tdesign-common/naming.md` 只是术语对照。|
| 微信 / 支付宝公开文案规范 | **未找到**一手原文（`developers.weixin.qq.com/miniprogram/design` 需登录态/动态页，搜索只出第三方文章）。|
| Life360、Be My Eyes 帮助页 | 抓取 **403**；只能用截图与 App Store 描述。|
| Uber Assist 帮助页 | 抓取 406/404；只有搜索转述。「Uber 无障碍」一栏因此**没有 App 内按钮原文**。|
| 滴滴无障碍 / 关怀版的司机端、乘客端提示**原文** | **未找到**。只有报道说明三个提示节点（接单、接到乘客、距目的地约 200 米），没有逐字文案。|
| United In Stride、Guiding Eyes 的 App 界面文案 | **未找到**（二者没有可查的专用 App 界面或公开截图）。|
| Noonlight / Life360 的 **App 内**按钮原文 | 只有 Noonlight 帮助页与 App Store 描述；Life360 无。|

⇒ 下面「竞品」一节里，每个产品只记**实际读到的**原文；缺的写「未找到」，不用印象补。

## 1. 外部规范：每份提炼的结论（均读自原文）

引用均 < 15 词；英文原文保留，中文规范直接引。

### 1.1 Apple HIG · Writing
来源：<https://developer.apple.com/design/human-interface-guidelines/writing>（2025-12-16 版加了人称条款）

- **按钮用动词**：「it's almost always best to use a verb」；「just saying "Send" often works better than "Let's do it!"」→ 别卖萌，别写感叹式号召。
- **语气随场景变**：运动达标可以轻快；付款出错、严重情况要「straightforward and direct」。
- **人称**：「Avoid using we altogether」；示例 "We're having trouble loading this content" 改成 "Unable to load content"。所有格 my/your 能省则省（"Favorites" 比 "Your Favorites" 好）；用了就全 App 一致。
- **错误**：「avoid blame」，说清能做什么；"oops!" "uh-oh" 「typically unnecessary and can sound insincere」。
- **空状态**：要给下一步，最好带按钮或链接。
- **一致性**：流程动作用「Get Started / Continue / Next / Done」，选一套保持一致。

### 1.2 Apple HIG · Alerts
来源：<https://developer.apple.com/design/human-interface-guidelines/alerts>

- 「be direct, and use a neutral, approachable tone」；别绕、别责备、别淡化严重性。
- 标题要具体，不写 "Error"。按钮「one- or two-word title that describes the result」，用动词；「Avoid explaining alert buttons」。
- 避免默认按钮写 OK（歧义），破坏性操作写具体动词（Erase / Delete）；取消一律叫 Cancel，且不做默认按钮。
- 弹窗别只为告知信息；启动即弹窗要避免。

### 1.3 Apple HIG · Buttons
来源：<https://developer.apple.com/design/human-interface-guidelines/buttons>

- 一个视图里突出按钮「one or two」个；同组并列按钮同尺寸才表示选项对等，要有主次就用不同突出程度。
- 文字标签「a few words」，以动词开头（例 "Add to Cart"）；进行中可换成进行时（"Checking out…"）。
- 主按钮不给破坏性动作，即使它最常用。

### 1.4 Apple · 读屏 label 与 hint（档案库《iOS Accessibility Programming Guide》）
来源：<https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/iPhoneAccessibility/Making_Application_Accessible/Making_Application_Accessible.html>；现行 API 说明 `accessibilityHint`：「brief, localized description of the result of performing an action」。

- **label**：「Very briefly describes the element」，最好一个词；**不含控件类型**（否则读成 "Add button button"）；**不以句号结尾**。
- **hint**：只在 label 看不出结果时才给；「Begins with a verb and omits the subject」，第三人称单数（"Plays the song"，不写祈使 "Play the song"）；以句号结尾；**不写手势名**（"Tap to play" 反例）；不重复控件名；不写控件类型。
- Apple 现行 SwiftUI 文档示例："Purchases the item"、"Downloads the attachment"。
- 注意：档案库页是旧文档，但它是 Apple 对 label/hint 分工写得最细的一份；HIG VoiceOver 页补充一条：label 要「concise」，且装饰图不用描述。

### 1.5 Material 3 · Style guide
来源：<https://m3.material.io/foundations/content-design/style-guide/ux-writing-best-practices> 及同目录 `word-choice`、`grammar-and-punctuation`；对话框 <https://m3.material.io/components/dialogs/guidelines>（仅英文规范，无中文条款）

- **解释后果要中性直接**：「Avoid cautions or warnings that might sound alarming, intimidating, or condescending」；正例要求写清「what will happen」以及怎样撤回；反例「Don't misrepresent consequences or try to influence a user's decision」。
- 人称：用 you/your；同屏**不混用 me/my 与 you**；慎用 I/we（法律同意句除外）。
- 标点：单句标签、提示、对话框正文**不加句号**；感叹号「sparingly」，**空状态与日常任务别用**，留给大成就；按钮和菜单项**不加省略号**。
- 对话框：最多两个动作；两个时一个确认一个取消；确认动作最靠近边缘；单个动作只能是「acknowledgement」；不放第三个「Learn more」类动作（会把人带离对话框）。
- 一律 sentence case（中文无关）。

### 1.6 Ant Design · 文案（含按钮）
来源：<https://github.com/ant-design/ant-design/blob/master/docs/spec/copywriting.zh-CN.md>（按钮：同目录 `buttons.zh-CN.md`；官网渲染页地址本轮未核）

- 立足点：「关注点应该是用户和他们能用你的产品做什么」；以用户为主体写。
- 精简：「省略无用词汇，不重复用户已知事实」。
- 语气：「直接使用「你」、「我」来和用户对话……避免使用「您」」；同句不混用你/我。
- 友好：「多给用户支持与鼓励，不要命令和强迫用户」；出错「专注于解决问题，而不是指责」；表述「不要使用过于绝对的表述」。
- 用词表：「抱歉」只在**系统造成**的结果里用，用户自己造成的不用；「登录」不写「登陆」；「此」比「该」更明确。
- 标点：**按钮和标题不用句号**；输入框下提示、标签、悬停提示单句可省标点；多句要标点；「谨慎使用感叹号」，只在问候或祝贺等场合。
- 按钮：一个按钮区最多一个主按钮；「如果不确定选择哪种按钮，次按钮永远是最安全的选择」；纯图标按钮必须有提示。

### 1.7 微软《Chinese (Simplified) Localization Style Guide》
来源：<https://download.microsoft.com/download/1/5/9/159cb91c-b61b-4385-97ca-80ccc7ff1fa0/zho-chn-StyleGuide.pdf> §2.2

- 对用户直接用第二人称「你」：示例「你是否要继续?」「为你的电脑命名」。**该指南正文里仍有个别「您」**（激活向导示例「供您选择」），所以它并没有硬性禁用，但官方示例以「你」为主。
- 出错写法：「密码有误，请再试一次。」——短、不责备、带下一步，「请」只出现在**要用户做事**的那句。
- 完成态：「一切已准备就绪」；另有一条规则：英文俏皮话 "Drum roll..." 译成「请稍等…」，原因是直译「odd for Chinese users」，指南注释说直译对中文用户「odd」，找不到合适译法就不翻——即**不硬凑俏皮**。
- 操作说明短而清楚，给用户做决定所需的信息即可（"tell them only what they need to know"）。
- 感叹号：软件本地化中用半角 `!`，仅在需要时。

## 2. 竞品：读到的原文

> 「口吻特征」是我对原文的标注。图片出处为仓库 `docs/ui/reference-screenshots/<目录>/<序号>.png`（App Store 宣传图，版本以截图为准）。

### 2.1 Be My Eyes（英文，截图 01、03）
| 原文 | 位置 | 口吻特征 |
|---|---|---|
| "I need visual assistance" / 副标题 "Call a company or volunteer" | 首屏两个大按钮之一 | 第一人称**用户视角**短句 + 一行功能副标题；不解释原理 |
| "I'd like to volunteer" / "Share your eyesight" | 同屏第二个按钮 | 同上，副标题是价值而非说明 |
| "Call a volunteer" | 主页整屏大按钮 | **动词 + 宾语，3 词**，无「请」、无感叹号 |
| "My groups" ＞ | 次按钮 | 名词短语，描边（次要）样式 |
| "Visual assistance is just a tap away" | 宣传标题 | 营销语，不在界面按钮里 |

### 2.2 Aira（英文，截图 01、02）
| 原文 | 位置 | 口吻特征 |
|---|---|---|
| "Continue with Apple" / "…Google" / "…Phone Number" / "…Email" | 登录页 4 个按钮 | 统一模式 "Continue with X"，**全 App 一致** |
| "Let's get started. If you don't have an account, we'll create one for you. It's free." | 登录说明 | 3 短句；用 we（这是平台自述，非错误提示） |
| "Call Aira for free with Five Minutes Free" | 首页主按钮 | 动词开头；含促销，信息密度偏高 |
| "Attach Message or Files" / "Browse Access Offers" / "Configure Devices" | 首页次按钮（描边） | **动词开头的 2–3 词**，次级动作描边而非实心 |
| "Your next Five Minutes Free call is available now." | 状态行 | 陈述事实，不加感叹号 |

### 2.3 Lazarillo（英文，截图 01、04）
| 原文 | 位置 | 口吻特征 |
|---|---|---|
| "Welcome, sign in to start exploring." | 登录页标题 | 一句话，动词开头的目标 |
| "Sign in with email" / "…Google" / "…Facebook" / "…Apple" | 登录按钮 | 统一模式 |
| "By continuing, you are indicating that you accept our Terms of Service and Privacy Policy." | 底部小字 | 法务口吻，放在**按钮下方小字**，不占主界面 |
| "Exploration" / "Favourites" / "News" / "Settings" | 标签栏 | 单个名词 |
| 列表行 "Bus Stop" + "587 ft" | 附近交通 | 名称 + 距离，无修饰 |

### 2.4 Seeing AI（英文，截图 01、04）
| 原文 | 位置 | 口吻特征 |
|---|---|---|
| "People" / "Recognize friends. Describe faces and expressions." | 频道说明 | 名词标题 + 两个**祈使动词短句**，每句 3–4 词 |
| "Documents" / "Read printed pages using audio cues to align." | 频道说明 | 同上，说明的是**怎么用**而非「我们会…」 |

### 2.5 GoodMaps（英文，截图 01）
| 原文 | 位置 | 口吻特征 |
|---|---|---|
| "Turn by turn directions" | 宣传标题 | 名词短语 |
| "Straight 12 feet" / "Slight right and continue 5 feet" | 导航卡 | **方向 + 数字**，不用「请」、不用语气词；这是读屏/语音播报的范式 |

### 2.6 安全类
| 产品 | 原文（来源） | 口吻特征 |
|---|---|---|
| Noonlight | "If you don't enter in your PIN, an alarm is triggered" / "False alarm? No worries, you can always cancel…"（<https://help.noonlight.com/en/articles/2114600>） | 前一句**陈述机制**；后一句 "No worries" 偏口语安抚——这一句**不要学**（见规则 12） |
| Noonlight App Store | "Press and hold the button whenever you feel uneasy." / "In danger? Simply release the button…"（<https://apps.apple.com/us/app/noonlight-feel-protected-24-7/id716262008>） | 步骤式祈使句；"Simply" 是低龄化信号 |
| Apple Watch 跌倒检测 | "To call emergency services, drag the Emergency Call slider in the alert." / "If you don't want to call emergency services, tap Cancel."（<https://support.apple.com/en-us/108896>） | **按钮名原样引用、不加引号**；一条一个动作；不安慰、不吓人 |
| Apple 紧急 SOS | "Call with Hold and Release" / "Call with 5 Button Presses"（设置项）（<https://support.apple.com/guide/personal-safety/use-emergency-sos-ips4f0cd709b/web>） | 设置项用**动词短语**，后面一句说结果 |
| Google Personal Safety（见 <https://support.google.com/android/answer/9319337>） | "Anyone who picks up your phone can find your lock screen message…" | 警示写**事实与后果**，没有「小心」「千万」 |

### 2.7 出行陪同类
- **Uber Assist**：未取得原文（见 §0）。
- **滴滴无障碍**：公开报道只说明三个提示节点，**未找到逐字文案**（<https://paper.people.com.cn/mszk/pc/content/202505/26/content_30077183.html> 为人民网报道，非界面原文）。
- 滴滴「报警页」警示语 "谎报警情，依法追责" 在 `volunteer-sos-button-placement-20260819.md` 已被否决，不作正例。
- **United In Stride / Guiding Eyes**：未找到 App 界面文案。

## 3. 规则表：AidRun 文案规则（14 条）

「依据」一栏：规范条款 = §1 对应小节；竞品原文 = §2。推论（我从原文推出、原文没逐字说）一律标 **[推论]**。

| # | 场景 | 规则 | 正例 | 反例 | 依据 |
|---|---|---|---|---|---|
| 1 | 主按钮 | **动词 + 宾语，2–4 个汉字起、不超过 6 字**；写结果，不写「确定」「好的」「知道啦」。一屏一个主按钮，全宽、64pt。 | 「叫陪跑员」「开始跑步」 | 「好的」「我知道了」「让我们开始吧」 | Apple Buttons「a few words…verb」；Apple Alerts「describes the result」「Avoid OK」；Be My Eyes "Call a volunteer"；Ant「一个按钮区最多一个主按钮」|
| 2 | 次按钮 | **名词或动词短语，描边/文字样式，同宽竖排**；拿不准就用次按钮；次按钮文案不比主按钮长。 | 「查看订单」「稍后再说」 | 把次按钮写成长句；两个按钮都用实心 | Ant「次按钮永远是最安全的选择」；Apple Buttons「prominent…one or two」；Aira "Browse Access Offers" 描边 |
| 3 | 读屏 label | **一个词或极短短语；不含「按钮」二字；不以句号结尾**；和屏上可见文字一致。 | label「叫陪跑员」 | 「叫陪跑员按钮」「点击这里叫陪跑员。」 | Apple 档案库 labels「Does not include the type」「Does not end with a period」；HIG VoiceOver「concise」|
| 4 | 读屏 hint | **只在 label 看不出结果时给；动词开头、说结果、不写手势**；中文以句号结尾。 | 「向附近陪跑员发出邀请。」 | 「双击可以叫陪跑员」「点击后会…」 | Apple 档案库 hints「Begins with a verb」「Does not include the name of the action or gesture」；**[推论]** 中文版去掉「点按/双击」 |
| 5 | 错误提示 | **一句说发生了什么，一句说下一步**；不道歉用户自己造成的，系统问题才用「抱歉」；不责备、不叹气；别写「Error」式空标题。 | 「验证码有误，请重新输入。」 | 「哎呀，出错啦！」「您输入的验证码不对哦」 | Apple Writing「avoid blame」「oops!…insincere」；Ant「抱歉」只用于系统造成；微软「密码有误，请再试一次。」|
| 6 | 确认弹窗 | **标题具体到动作，按钮 = 动词，最多两个动作，取消叫「取消」**；破坏性动词写具体（「删除」「取消订单」）；**不解释按钮**；不做 OK/「确定」。 | 「取消这次订单？」+「取消订单」/「返回」 | 「是否确定要这样做呢？」+「确定」/「再想想」 | Apple Alerts「Avoid explaining alert buttons」「Always use "Cancel"」；Material 对话框最多两个动作 |
| 7 | 后果说明 | **一句中性事实，说清「会怎样」和「怎么撤回」**，不用「千万」「务必」「小心」，不渲染风险。 | 「取消后，陪跑员将不再收到这次邀请。」 | 「温馨提醒：取消后可能会让志愿者很失望哦」 | Material「Avoid cautions…alarming, intimidating, or condescending」，正例「what will happen」+ 怎样撤回|
| 8 | 空状态 | **一句说明 + 一个动作**；不用感叹号，不夸奖，不卖萌。 | 「暂无订单。」+「叫陪跑员」 | 「这里空空如也呢～快去下单吧！」 | Apple Writing 空状态「provide clear next steps」；Material「Avoid using exclamation marks for empty states」|
| 9 | 安全 / 求助警示 | **只写事实与可做的动作；不安慰（「别担心」）、不吓唬、不教育**。红线文案**逐字锁定，不套本表**（见 §4）。 | 「无法获取位置。可手动输入集合点。」 | 「别怕，我们一直陪着你～」「请务必谨慎使用！」 | Apple Writing「straightforward and direct, reflecting the seriousness」；Apple Alerts「masking the severity」；Apple Watch / Google 帮助页写法；Noonlight "No worries" 不学 |
| 10 | 首次引导 | **每屏一件事；标题 ≤ 一句；正文 ≤ 两句；按钮用统一流程词「继续」「完成」**；不写「欢迎来到…大家庭」。 | 「继续」…「完成」 | 「让我们开始一段美好旅程吧！」 | Apple Writing 流程「Get Started / Continue / Done…be consistent」；Aira "Let's get started" 之后立刻给动作 |
| 11 | 人称与称呼 | **用「你」，不用「您」**；少用「我们」（App 不是人）；能省的「你的」「我的」就省；同一屏不混「我」和「你」。 | 「订单已确认」 | 「您的订单已经为您确认啦」 | Ant「避免使用「您」」；微软示例以「你」为主；Apple「Avoid using we」「use possessive pronouns sparingly」；Material 不混 me/you |
| 12 | 语气词与感叹号 | **不用「啦 / 哦 / 呢 / 吧 / ～」和感叹号**；成功态用陈述句。唯一例外：真正的成就或问候，且每屏最多一个。 | 「已完成。」 | 「搞定啦！」「欢迎回来哦～」 | Apple「too cute or clever」「oops!」；Material「sparingly…not for common tasks」；Ant「谨慎使用感叹号」；微软 "Drum roll…" 不硬译 |
| 13 | 标点与长度 | **按钮、标题、单句标签不加句号；多句说明加；读屏 hint 加句号**。省略号只表示进行中，不放按钮上。 | 按钮「继续」；说明「订单已确认。陪跑员将来电。」 | 按钮「继续。」「继续…」 | Ant「按钮和标题」不使用句号；Material「Skip periods」「Don't use ellipses in buttons」；Apple 档案库 hint 以句号结尾 |
| 14 | 说明文字放哪里 | **按钮上只放动词；一句话说明放副标题；操作结果放 hint；原理和政策放帮助页**。屏上同一信息不重复三遍。 | 按钮「叫陪跑员」+ 副标题「预计 5 分钟内联系你」 | 按钮下一段 80 字解释 | Be My Eyes 副标题一行 "Call a company or volunteer"；Lazarillo 法务句放底部小字；Ant「不重复用户已知事实」；Apple Alerts「Avoid explaining alert buttons」|

### 使用说明（给改写建议的人）

- 「2–4 汉字起、≤ 6 字」是**我从英文 "a few words" / "one- or two-word" 推到中文的经验值**，不是任一规范的原话；用来判断「明显太长」，不是硬门槛。
- 「不用语气词」的依据是 Apple/Ant/Material 对「cute / 过于友好」的反复否定；**没有一份规范逐字列出「啦哦呢吧」**，这条是**从原则推出的具体化**。微软 zh-CN 示例也没出现这些词。
- 竞品里**没有找到**中文原文，故中文示例都是写法示意，**不是**某产品的原文。

## 4. 与 AidRun 红线冲突的地方（只记冲突，不给改法）

| 规范条款 | 红线（AGENTS.md） | 冲突在哪 |
|---|---|---|
| Material「Avoid cautions or warnings that might sound alarming」；Apple「be direct…neutral」 | §6 求助二次确认句**逐字锁定**：「是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。」 | 规范倾向更短更中性；这一句已含后果说明，属**允许的例外**，不动。 |
| Apple「Avoid explaining alert buttons」；Apple/Ant「少用我们」 | §6「App 不会代你发送求助」必须在降级文案里说清 | 这句是对用户**能力边界**的陈述，不是解释按钮；规范无冲突，但改写时不得因「精简」删掉。 |
| 「不安慰、只陈述事实」（规则 9） | §6「App 永远不得宣称短信已发出、已送达、联系人已被通知」，要用进行时文案 | 方向一致：只写进行中的事实。**改写不得出现「已通知」类措辞**。 |
| Ant/Apple「不加感叹号」 | 无 | 无冲突。 |

## 5. 沿用的已有调研（未重搜）

- `sos-sent-screen-patterns-20261022.md`：安全类动作结构、取消方式；本报告 §2.6 补的是**文案口吻**，不是版式。
- `help-screen-autoread-and-policy-20260907.md`：Apple VoiceOver 评估标准「Labels should be concise」。
- `blind-voice-booking-ia-20260805.md` / `blind-runner-redesign-references-20261007.md` / `blind-ui-visual-benchmark-20260808.md`：版式与减法方向，无冲突。

## 6. 复核触发条件

- Apple 更新 HIG Writing / Alerts / Buttons 或 `accessibilityHint` 说明。
- Material 3 的 content-design 页改动；Ant Design 文案规范改版。
- 拿到 TDesign / 微信 / 支付宝 / 滴滴 / Be My Eyes / Uber 的**界面原文**，与本表结论矛盾。
- 主会话审完 AidRun 现有文案后，发现规则表有对不上的场景。
