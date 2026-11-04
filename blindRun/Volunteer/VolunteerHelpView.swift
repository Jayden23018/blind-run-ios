import SwiftUI

// MARK: - Help Script

/// 陪跑员使用帮助的一条。
struct VolunteerHelpTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

/// 陪跑员使用帮助的**全部文案**（审计 V-36，#656）。
///
/// 抽成纯数据而不是写在 View 里，理由同盲人端 `BlindFirstRunHelp`：这一页的价值全在文案，
/// 而第三条讲的是求助，把本地拨号说成「求助已发出」直接违反 `AGENTS.md` §6。数据层能被单测逐条钉住。
///
/// **按钮名取自订单页真正在用的常量**，不另写字面量 —— 按钮上的字改了而帮助页没改，
/// 屏幕上没有任何症状，陪跑员却会去找一个不存在的按钮。
enum VolunteerFirstRunHelp {
    static let heading = "使用帮助"

    static let intro = "第一次带跑之前，先看一遍：一单怎么走完，遇到事找哪里。随时可以在「我的」页的「使用帮助」里再看。"

    static let topics: [VolunteerHelpTopic] = [
        VolunteerHelpTopic(
            id: "flow",
            title: "第一，一单怎么走完",
            body: """
            订单页每一步只会出现当前该按的那个主按钮。\
            提前几天约好的单，开跑前要先按「\(VolunteerOrderFlowCopy.confirmDeparture)」，没有确认的单会转给别的陪跑员。\
            出门时按「\(VolunteerOrderFlowCopy.enRoute)」，到了集合点按「\(VolunteerOrderFlowCopy.arrived)」。\
            见到跑者、握好引导绳之后，再按「\(VolunteerOrderFlowCopy.startRun)」。\
            跑完后长按「\(VolunteerFinishLongPress.title)」结束。
            """
        ),
        VolunteerHelpTopic(
            id: "meet",
            title: "第二，找不到对方怎么办",
            body: """
            到了集合点先打电话给跑者，订单页有「\(VolunteerOrderFlowCopy.callRunnerRow)」。\
            一直碰不到面，点「\(VolunteerOrderFlowCopy.cannotFindRunner)」，里面可以拨号，也可以写一条反馈。\
            等满时限后会出现「\(VolunteerOrderFlowCopy.endWaiting)」，\(VolunteerOrderFlowCopy.endWaitingCaption)。
            """
        ),
        // 🔴 红线（AGENTS.md §6）：云端求助只在跑步进行中；其余一律本地拨号，要说清 App 不会代发。
        // 客服工单要说清不是求助入口、不是即时通道；不写「回拨」「已通知」「会有人来」。
        // 求助入口搬位置时这一条必须同轮改，教错位置的代价是陪跑员在最坏的时刻按空。
        VolunteerHelpTopic(
            id: "help",
            title: "第三，出事找哪里",
            body: """
            现在有危险，直接拨打 120 或 110。\
            跑步进行中，订单页右上角的「\(VolunteerRunCopy.navButtonLabel)」里有紧急求助：长按 3 秒会直接发出，轻点会先让你确认一次。\
            只有跑步进行中，求助才会发到云端。其他时候，订单页的求助按钮只让你选择拨打 120、110 或紧急联系人，App 不会代你发送求助。\
            「\(SupportTicketCopy.title)」在「我的」页，用来反馈订单和账号的问题。它不是求助入口，也不是即时通道，不会立刻有人联系你。
            """
        )
    ]
}

// MARK: - 首次自动打开

/// 第一次打开订单页时要不要自动弹出帮助。纯判定，用例能穷举。
///
/// 只在**出发之前**的两态弹：`SCHEDULED_CONFIRMED`、`PENDING_ACCEPT`。出发后、到达后、跑步中不弹 ——
/// 那时他正在赶路或握着绳子，弹一页字是打断；而漏掉的代价有兜底（「我的」页「使用帮助」一直在）。
/// 不挂在「接单成功」上：先通话的那条路接单后立刻进 20 分钟的通话窗口，此时弹页会烧窗口。
enum VolunteerFirstRunHelpPolicy {
    static func shouldAutoOpen(status: RunOrderStatus?, alreadySeen: Bool) -> Bool {
        guard !alreadySeen else { return false }
        switch status {
        case .scheduledConfirmed, .pendingAccept:
            return true
        default:
            return false
        }
    }
}

// MARK: - Help View

/// 陪跑员使用帮助页。
///
/// **不自动朗读。** 盲人端的帮助页会播报，是因为听的人没有别的通道；陪跑员是明眼人，
/// 而订单页自己的状态播报会被一段朗读切断（`SpeechService.speak` 先 stop 再播）。
/// 读屏用户照样能逐条读：每条 topic 合成一个焦点。
struct VolunteerHelpView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 首次自动打开时为 true：底部是「知道了」，按下去记标志并关掉。
    /// 从设置进来时为 false：返回走系统返回键。
    let isFirstRun: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(VolunteerFirstRunHelp.intro)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(VolunteerFirstRunHelp.topics) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        HighContrastText(topic.title, style: .status)
                            .fixedSize(horizontal: false, vertical: true)
                        HighContrastText(topic.body, style: .body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 标题与正文合成一个焦点：标题单独一条本身不带信息。
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(topic.title)。\(topic.body)")
                    .accessibilityIdentifier("volunteerHelpTopic-\(topic.id)")
                }

                if isFirstRun {
                    PrimaryButton("知道了") {
                        appState.markVolunteerFirstRunHelpSeen()
                        dismiss()
                    }
                    .accessibilityHint("关闭，之后可以在「我的」页的「使用帮助」里再看")
                    .accessibilityIdentifier("volunteerHelpDoneButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(VolunteerFirstRunHelp.heading)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("volunteerHelpScrollView")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerHelpView(isFirstRun: true)
            .environmentObject(AppState())
    }
}
#endif
