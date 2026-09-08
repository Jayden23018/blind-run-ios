import SwiftUI

// MARK: - Help Script

/// 首次使用引导的一条。
struct BlindHelpTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

/// 首次使用引导的**全部文案**。
///
/// 抽成纯数据而不是写在 View 里：这一页的价值全在文案，而文案写错是会出事的那一类 ——
/// 第 2 条讲的是求助，把降级拨号说成「求助已发出」直接违反 `AGENTS.md` §6
/// （「App 永远不得宣称短信已发出、已送达」）。数据层能被单测逐条钉住，View 不能。
///
/// **只讲这个 App 特有的三件事，不教 VoiceOver。** 能自己把 App 装上的人已经会用读屏了，
/// 教一遍基础手势是在浪费他们的时间；而 Magic Tap 触发求助是我们自己绑的手势，
/// 不教就没有任何人猜得到 —— 这条才是引导存在的理由。
enum BlindFirstRunHelp {
    static let heading = "使用帮助"

    static let intro = "欢迎使用助盲跑。下面说明三件事，随时可以在设置里再听一遍。"

    /// - Parameter leadMinutes: 下单最短提前量。**必须取自 `AppConstants`**，
    ///   写死 30 会在产品松绑提前量的那天变成一句骗人的话。
    static func topics(
        leadMinutes: Int = AppConstants.Timing.minimumBookingLeadMinutes
    ) -> [BlindHelpTopic] {
        [
            BlindHelpTopic(
                id: "booking",
                title: "第一，怎么约跑",
                body: """
                在首页双击「开始约跑」，然后说一句话，比如：明天早上七点，跑四十分钟。\
                系统会把整单念一遍，你说「确认」就下单成功。\
                预约的开始时间要比现在晚 \(leadMinutes) 分钟以上。
                """
            ),
            // 两种模式都要讲，且必须讲清哪一种什么都没发出去。
            // 只讲云端那一半，用户会在没有进行中订单时按下去，以为求助已经发出 —— 那正是
            // `EmergencySafetyCopy.homeCallDialogMessage` 在弹窗里要抢先说明的同一件事。
            // ⚠️ 必须说清是**首页**。Magic Tap 全仓只注册在两处（`BlindRunnerHomeView.swift`
            // 的 `.accessibilityAction(.magicTap)` 与语音下单页），而它沿响应链查找 ——
            // 订单状态页是 push 上去的，够不到首页那个注册点，两指双击会落到系统默认动作
            // （播放音乐）。写「屏幕任意位置」等于教一个在陪跑进行中那一页不生效的手势。
            // 那一页的求助入口是底部常驻区里的按钮，不是手势。
            BlindHelpTopic(
                id: "sos",
                title: "第二，怎么求助",
                body: """
                陪跑进行中的时候，订单页面最下面一直有求助按钮，双击它就能发出求助，再确认一次才会真的发出。\
                首页最下面也一直有求助按钮，在首页还可以用两根手指双击屏幕。\
                但只有陪跑进行中按下去才会真的发出求助；其他时候它只让你选择拨打紧急联系人或者 110，\
                App 不会代你发送求助。
                """
            ),
            BlindHelpTopic(
                id: "repeat",
                title: "第三，怎么重听",
                body: """
                每个页面都有「重复当前状态」按钮，双击它就会把当前的情况重新念一遍。\
                错过播报的时候用它。
                """
            )
        ]
    }

    /// 播报脚本。标题也念 —— 听的人没有视觉分段，靠「第一、第二、第三」才知道走到哪了。
    static func spokenScript(
        leadMinutes: Int = AppConstants.Timing.minimumBookingLeadMinutes
    ) -> String {
        ([intro] + topics(leadMinutes: leadMinutes).map { "\($0.title)。\($0.body)" })
            .joined(separator: " ")
    }
}

// MARK: - Help View

/// 首次使用引导页。首次进盲人首页时自动进入一次，之后从「设置 → 使用帮助」随时回来。
///
/// **为什么不是一次性播报**：一次性 announcement 漏听就再也拿不回来，这正是
/// 「重复当前状态」按钮存在的理由（系统 Speak Screen 读不到 announcement）。
/// 引导是用户最可能漏听的那一段 —— 刚装上、还没进入状态、可能在路上。
struct BlindRunnerHelpView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss

    /// 首次自动进入时为 true：底部是「知道了」，按下去记标志并返回。
    /// 从设置进来时为 false：只有「再听一遍」，返回走系统返回键。
    let isFirstRun: Bool

    private var topics: [BlindHelpTopic] { BlindFirstRunHelp.topics() }

    /// `SpeechService.isSpeaking` 是 `@Published`，`speechService` 又是 `@EnvironmentObject`，
    /// 所以按钮标题会跟着播报状态自动重绘，不需要本地 `@State` 镜像一份。
    private var isSpeaking: Bool { speechService.isSpeaking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(BlindFirstRunHelp.intro)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(BlindFirstRunHelp.intro)

                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        HighContrastText(topic.title, style: .status)
                        HighContrastText(topic.body, style: .body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 标题与正文合成一个焦点：拆开只是让读屏用户多滑三次，
                    // 而标题单独一条（「第一，怎么约跑」）本身不带任何信息。
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(topic.title)。\(topic.body)")
                }

                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            // 与首页同一个理由：iPad 上不限宽的话，把字调大之后仍要横扫整行，换行极易串行。
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(BlindFirstRunHelp.heading)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("blindRunnerHelpScrollView")
        .task { speak() }
    }

    private var actions: some View {
        VStack(spacing: 16) {
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
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .accessibilityLabel(isSpeaking ? "停止播报" : "再听一遍")
                .accessibilityHint(isSpeaking ? "立刻停止当前播报" : "从头重新播报这三条说明")
                .accessibilityIdentifier("blindRunnerHelpRepeatButton")

            if isFirstRun {
                PrimaryButton("知道了") {
                    appState.markBlindFirstRunHelpSeen()
                    dismiss()
                }
                .accessibilityHint("回到首页，之后可以从设置里再听一遍")
                .accessibilityIdentifier("blindRunnerHelpDoneButton")
            }
        }
    }

    private func speak() {
        speechService.speak(text: BlindFirstRunHelp.spokenScript())
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
