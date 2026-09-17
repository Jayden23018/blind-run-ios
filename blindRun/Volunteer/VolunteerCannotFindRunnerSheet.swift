import SwiftUI

// MARK: - 汇合态的「找不到对方」

/// 设计稿在汇合那一屏画了一行「找不到对方 ›」，但**没有给这一层的内容** ——
/// 下面这几句是本轮补的，措辞已经项目负责人过目（2026-09-17）。
///
/// 三条都要能当场做，不写「保持耐心」这类没有动作的话：
/// 盲人看不见挥手、看不见对方的衣服颜色，唯一能收敛两个人位置的办法就是出声。
///
/// **不调任何端点。** 契约里没有「我找不到他」这个动作 —— 通话磨合期那条
/// `POST /intro-call/unreachable` 是接单前用的，这一刻早就过了那个窗口。
struct VolunteerCannotFindRunnerSheet<Ticket: View>: View {
    /// 这一单有没有能拨通的号码。`false` 时拨号按钮不出现 ——
    /// 摆一个按下去无事发生的按钮，比直说「没有号码」更糟。
    let canCall: Bool
    let onCall: () -> Void
    /// 「上报问题」那一层**由这一层自己弹**，不是回调给上一层换 `activeSheet`。
    /// 同一个视图上「关掉一个 sheet 的同一帧再开另一个」在 SwiftUI 里会丢掉后一个 ——
    /// 表现正好是本仓库最怕的那种：点了没反应。
    @ViewBuilder let ticket: () -> Ticket

    @Environment(\.dismiss) private var dismiss
    @State private var showsTicket = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(VolunteerOrderFlowCopy.cannotFindRunner)
                    .font(AppFonts.title())
                    .accessibilityAddTraits(.isHeader)

                ForEach(VolunteerCannotFindRunnerCopy.advice, id: \.self) { line in
                    Text(line)
                        .font(AppFonts.body())
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canCall {
                    FlowActionButton(
                        VolunteerOrderFlowCopy.callRunnerRow,
                        systemImage: "phone.fill",
                        style: .primary,
                        accessibilityLabel: VolunteerOrderFlowCopy.callRunner,
                        accessibilityHint: "系统会先弹出拨号确认，确认后才会拨出"
                    ) {
                        // 先拨号再关页：反过来写会让系统的拨号确认赶上这一层的收起动画。
                        onCall()
                        dismiss()
                    }
                    .accessibilityIdentifier("volunteerCannotFindCall")
                } else {
                    Text(VolunteerCannotFindRunnerCopy.noPhoneNotice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(SupportTicketCopy.title) { showsTicket = true }
                    .font(AppFonts.body())
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                    .accessibilityHint("提交一条事后反馈，不会立刻有人联系你")
                    .accessibilityIdentifier("volunteerCannotFindReportIssue")
            }
            .padding(24)
            .readableContentColumn()
        }
        .sheet(isPresented: $showsTicket) { ticket() }
    }

}

/// 这一层的文案。**放在泛型类型外面**：Swift 不允许泛型类型有 static 存储属性，
/// 而这个视图必须是泛型（它要接一个由上一层装配好的「上报问题」页）。
/// 顺带也让用例够得着 —— 视图里的 private 常量测不到。
enum VolunteerCannotFindRunnerCopy {
    static let advice = [
        "先打电话给跑者，说清你现在站在哪个出入口。",
        "跑者看不见你挥手，在电话里出声、喊他一声，比找他更快。",
        "站在原地别动，让他朝你的声音走过来。"
    ]

    /// 🔴 号码为空时**说清楚是什么状况**，不要静默少一个按钮。
    static let noPhoneNotice = "这一单没有可以拨打的号码。如果一直碰不到面，先上报问题。"
}

#if DEBUG
#Preview("找不到对方") {
    VolunteerCannotFindRunnerSheet(canCall: true, onCall: {}, ticket: { EmptyView() })
}

#Preview("找不到对方 · 没有号码") {
    VolunteerCannotFindRunnerSheet(canCall: false, onCall: {}, ticket: { EmptyView() })
}
#endif
