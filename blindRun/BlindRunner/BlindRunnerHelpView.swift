import SwiftUI

// MARK: - Help Script

/// 首次使用引导的一条。
struct BlindHelpTopic: Identifiable, Equatable {
    let id: String
    /// 卡片上的标题（「怎么约跑」）。播报时前面再加序号（「第一，怎么约跑」），见 `spokenScript`。
    let title: String
    let body: String
}

/// 首次使用引导的**全部文案**。
///
/// 抽成纯数据而不是写在 View 里：这一页的价值全在文案，而文案写错是会出事的那一类 ——
/// 第 2 条讲的是求助，把降级拨号说成「求助已发出」直接违反 `AGENTS.md` §6
/// （「App 永远不得宣称短信已发出、已送达」）。数据层能被单测逐条钉住，View 不能。
///
/// **只讲这个 App 特有的三件事，外加一条系统 SOS（#657 B-12），不教 VoiceOver。** 能自己把 App 装上的人已经会用读屏了，
/// 教一遍基础手势是在浪费他们的时间；而 Magic Tap 触发求助是我们自己绑的手势，
/// 不教就没有任何人猜得到 —— 这条才是引导存在的理由。
///
/// 2026-11-05 改成四张卡（#753，定稿 `docs/ui/mockups/blind-help-20261105/`）：
/// 标题去掉「第一，」这类序号（卡片本身就分开了），正文删掉重复的句子，意思不变。
enum BlindFirstRunHelp {
    static let heading = "使用帮助"

    /// 大标题下面那行灰字。
    static let intro = "四件事。随时可以回到这里再听一遍。"

    /// 播报开头。屏幕上没有这句：页面有大标题，听的人没有。
    static let spokenGreeting = "欢迎使用助盲跑。"

    /// 播报时标题前的序号。听的人没有视觉分段，靠「第一、第二……」才知道走到哪了。
    static let spokenOrdinals = ["第一", "第二", "第三", "第四", "第五", "第六"]

    /// - Parameter leadMinutes: 下单最短提前量。**必须取自 `AppConstants`**，
    ///   写死 30 会在产品松绑提前量的那天变成一句骗人的话。
    static func topics(
        leadMinutes: Int = AppConstants.Timing.minimumBookingLeadMinutes
    ) -> [BlindHelpTopic] {
        [
            // 定稿删掉了提前量那一句，这里保留：它不是重复的句子，删了用户会照引导下单然后被拒。
            BlindHelpTopic(
                id: "booking",
                title: "怎么约跑",
                body: """
                在首页双击「预约新的陪跑」，说一句话，比如：明天早上七点，跑四十分钟。\
                系统把整单念一遍，你说「确认」就下单。\
                开始时间要比现在晚 \(leadMinutes) 分钟以上。
                """
            ),
            // 两种模式都要讲，且必须讲清哪一种什么都没发出去。
            // 只讲云端那一半，用户会在没有进行中订单时按下去，以为求助已经发出 —— 那正是
            // `EmergencySafetyCopy.homeCallDialogMessage` 在弹窗里要抢先说明的同一件事。
            //
            // 🔴 **紧急入口搬位置时这一条必须同轮改**（2026-09-16、2026-10-30、2026-11-05 各改过一次）。
            // 教错紧急入口的位置，代价是**盲人在最坏的时刻按空** ——
            // 而这是 App 亲口教出来的肌肉记忆，比界面上少一个按钮严重得多。
            // 2026-11-05（#753）：#744 删掉了「我的」里的「紧急呼叫」那一行，这里不再提它。
            //
            // ⚠️ Magic Tap 注册在 `BlindRunnerTabView.swift` 的 TabView 上，
            // 它沿响应链查找 ⇒ 标签页里都生效，但**订单状态页是 push 上去的、够不到**
            // （那一页的求助入口是底部常驻区里的按钮，不是手势）。所以这里点名页面
            // 而不是「屏幕任意位置」—— 后者等于教一个在陪跑进行中那一页不生效的手势。
            // 非 `IN_PROGRESS` 时这个手势只弹本地拨号（`BlindHomeSOSMode.resolve`），所以说「可以拨打」。
            BlindHelpTopic(
                id: "sos",
                title: "怎么求助",
                body: """
                陪跑进行中，订单页最下面一直有求助按钮，双击后再确认一次才会发出。\
                其他时候，在首页、记录、我的这三页，用两根手指双击屏幕，\
                可以拨打紧急联系人、120 或 110，App 不会代你发送求助。
                """
            ),
            // 「首页那个在哪」保留：说清它在哪比说「每页都有」有用 —— 后者听起来像「到处都是」，
            // 实际是「你得先找到它」。
            BlindHelpTopic(
                id: "repeat",
                title: "怎么重听",
                body: """
                每页都有「重复当前状态」，双击就把当前情况再念一遍。\
                首页那个在「你好」这一行的右边。
                """
            ),
            // 手机在臂包里、手不方便碰屏幕时，唯一不用解锁、不用找按钮的求助路径是 iPhone 自带的紧急 SOS。
            // 锁屏卡片按设计不放求助按钮，就是把这条路交给系统 —— 但原来 App 里没有一处教过（#657 B-12）。
            //
            // 🔴 按法只写苹果支持文档写明的两种（support.apple.com/104992，2026-11-04 核实）：
            // 同时按住侧边按钮和任一音量按钮；「按五次」要先在设置里打开。
            // 🔴 必须说清这是系统的、不经过助盲跑 —— 与第二条同一条红线：App 不会代你发送求助。
            BlindHelpTopic(
                id: "systemSOS",
                title: "手不方便时怎么求助",
                body: """
                手机放在臂包里、不方便操作屏幕的时候，可以用 iPhone 自带的紧急 SOS：\
                同时按住侧边按钮和任意一个音量按钮不放，倒计时结束后手机会直接拨打急救电话。\
                也可以在系统「设置」的「紧急 SOS」里打开「按五次」，之后连按侧边按钮五次就能拨打。\
                这是 iPhone 系统的功能，不经过助盲跑，App 不会代你发送求助。
                """
            )
        ]
    }

    /// 播报时念的标题：「第一，怎么约跑」。
    static func spokenTitle(_ title: String, at index: Int) -> String {
        guard spokenOrdinals.indices.contains(index) else { return title }
        return "\(spokenOrdinals[index])，\(title)"
    }

    /// 播报脚本。标题也念，并带序号。
    static func spokenScript(
        leadMinutes: Int = AppConstants.Timing.minimumBookingLeadMinutes
    ) -> String {
        let parts = topics(leadMinutes: leadMinutes).enumerated().map { index, topic in
            "\(spokenTitle(topic.title, at: index))。\(topic.body)"
        }
        return ([spokenGreeting + intro] + parts).joined(separator: " ")
    }
}

// MARK: - Help View

/// 首次使用引导页。首次进盲人首页时自动进入一次，之后从「我的 → 使用帮助」随时回来。
///
/// **为什么不是一次性播报**：一次性 announcement 漏听就再也拿不回来，这正是
/// 「重复当前状态」按钮存在的理由（系统 Speak Screen 读不到 announcement）。
/// 引导是用户最可能漏听的那一段 —— 刚装上、还没进入状态、可能在路上。
///
/// 版式（#753）：灰底，四段各一张白卡，卡左上彩色图标 + 标题，下面正文；按钮固定在底部。
/// 不拆「列表 → 详情」两层：对读屏用户多一次进出，四段话放一页更省事。
struct BlindRunnerHelpView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss

    /// 首次自动进入时为 true：底部多一个「知道了」，按下去记标志并返回。
    /// 从「我的」进来时为 false：只有「再听一遍」，返回走系统返回键。
    let isFirstRun: Bool

    private var topics: [BlindHelpTopic] { BlindFirstRunHelp.topics() }

    /// `SpeechService.isSpeaking` 是 `@Published`，`speechService` 又是 `@EnvironmentObject`，
    /// 所以按钮标题会跟着播报状态自动重绘，不需要本地 `@State` 镜像一份。
    private var isSpeaking: Bool { speechService.isSpeaking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(BlindFirstRunHelp.intro)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    // 这一条在 2026-09-16 之前就被 `.textClipped` 审计点名过，直接加在 `Text` 上有效。
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                ForEach(topics) { topic in
                    BlindHelpTopicCard(topic: topic)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            // 与首页同一个理由：iPad 上不限宽的话，把字调大之后仍要横扫整行，换行极易串行。
            .readableContentColumn()
        }
        .accessibilityIdentifier("blindRunnerHelpScrollView")
        .background(AppColors.Flow.page.ignoresSafeArea())
        // 固定在底部：读到第几张卡都点得到「再听一遍」。挂在这一页上，不挂 NavigationStack 外层
        // （记忆 `opaque-bottom-bar-fakes-contrast-failure`）。
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .navigationTitle(BlindFirstRunHelp.heading)
        .navigationBarTitleDisplayMode(.large)
        // 二级页藏标签栏（同 `BlindBookingView`，记忆 tab-bar-clips-the-last-line-of-secondary-pages）：
        // 首次自动进来时，悬浮标签栏正好压在「知道了」上，点下去落到「星火」「记录」，
        // 引导没记「已看过」就被带走了（2026-10-05 真机截图）。返回箭头始终在，不丢出口。
        .toolbar(.hidden, for: .tabBar)
        .task { speak() }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            // 这一页的「重复当前状态」。名字换成「再听一遍」是因为这一页没有「状态」，
            // 只有一段说明 —— 用同一个词反而让人以为它会念订单情况。
            //
            // 播报中变成「停止播报」：整段脚本 40–60 秒，而 WCAG 2.2 SC 1.4.2 Audio Control
            // （**Level A**）要求自动播放超过 3 秒必须给出暂停或停止的手段，且系统音量键不算数。
            // 做成同一个按钮的两态而不是新增一个控件 —— 引导页多一个焦点，读屏用户就要多滑一次，
            // 而这两个动作互斥（在播才需要停，没播才需要重听），天然是一个开关。
            // 标识符保持 `blindRunnerHelpRepeatButton` 不变：UI 用例按 id 找它。
            Button(isSpeaking ? "停止播报" : "再听一遍") {
                if isSpeaking {
                    speechService.stop()
                } else {
                    speak()
                }
            }
                .buttonStyle(OutlineSecondaryButtonStyle())
                .accessibilityLabel(isSpeaking ? "停止播报" : "再听一遍")
                .accessibilityHint(isSpeaking ? "立刻停止当前播报" : "从头重新播报这几条说明")
                .accessibilityIdentifier("blindRunnerHelpRepeatButton")

            if isFirstRun {
                PrimaryButton("知道了") {
                    appState.markBlindFirstRunHelpSeen()
                    dismiss()
                }
                .accessibilityHint("回到首页，之后可以在「我的」里再听一遍")
                .accessibilityIdentifier("blindRunnerHelpDoneButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .readableContentColumn()
        .background(AppColors.Flow.page.ignoresSafeArea(edges: .bottom))
        // 贴底的按钮栏：审计要知道它在哪，滚到它后面的卡片才不会误判对比度（`AccessibilityAuditTests+Audit`）。
        // 先 `.contain` 再挂 id，否则会盖掉子按钮的 id（记忆 `accessibility-identifier-overwrites-children`）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindRunnerHelpBottomBar")
    }

    private func speak() {
        speechService.speak(text: BlindFirstRunHelp.spokenScript())
    }
}

// MARK: - Topic Card

/// 一张白卡：左上彩色图标 + 标题，下面正文。读屏把标题和正文合成一个焦点。
private struct BlindHelpTopicCard: View {
    let topic: BlindHelpTopic

    /// 图标方块边长，跟着字号放大（只是图形，不是字）。
    @ScaledMetric(relativeTo: .headline) private var iconSide: CGFloat = 32

    var body: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon
                    Text(topic.title)
                        .font(.headline.weight(.bold)) // 同 `SettingsTileLabel`：.headline 的中文半粗在真机上偏细
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HighContrastText(topic.body, style: .body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `fixedSize` 保留（防真实截断），但**它清不掉 `.textClipped` 审计在合成元素上的点名** ——
        // 2026-09-16 真机三跑实测：审计量的是 `.combine` 合成元素的几何对它那条很长的 label，
        // `fixedSize` 改不了合成元素的报告几何（`docs/review/ui-test-red-triage-20260927.md` 第 6 条，判为误报）。
        // 别为它拆掉 `.combine`：每条变两个焦点，读屏用户多滑四次，而标题单独一条本身不带信息。
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title)。\(topic.body)")
        .accessibilityIdentifier("blindRunnerHelpTopic_\(topic.id)")
    }

    /// 图标只是装饰，读屏不念。底色纯色压白色图形，亮暗两档同值（同 `SettingsTileLabel`），
    /// 取 `AppColors` 已有的色值：主色蓝、求助红、陪伴时长天青、次级文字灰。
    private var icon: some View {
        Image(systemName: Self.symbol(for: topic.id))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .frame(width: iconSide, height: iconSide)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: UIColor(rgb: Self.rgb(for: topic.id))))
            )
            .accessibilityHidden(true)
    }

    static func symbol(for id: String) -> String {
        switch id {
        case "booking": return "calendar"
        case "sos": return "phone.fill"
        case "repeat": return "speaker.wave.2.fill"
        case "systemSOS": return "iphone"
        default: return "questionmark"
        }
    }

    static func rgb(for id: String) -> UInt32 {
        switch id {
        case "booking": return 0x0058C7 // `AppColors.primary` 亮色值
        case "sos": return 0xC81E14 // `AppColors.destructive` 亮色值
        case "repeat": return AppColors.VolunteerHome.durationTealTone.light
        default: return 0x5C5C61 // `AppColors.textSecondary` 亮色值
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindRunnerHelpView(isFirstRun: true)
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
