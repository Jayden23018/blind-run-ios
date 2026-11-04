import SwiftUI

/// 下单入口的开放范围闸门（#667）。表单和语音下单都从这里进。
///
/// 暂不接受预约（`launchScope.acceptingOrders == false`）时**不实例化下单页**：表单不出现，
/// 语音向导的自动启动（下单页 `onAppear`）也就无从发生 —— 这时 `/parse` 只会反复追问地点。
/// 只显示并播报后端那句 `areaHint`，出口只有「返回首页」：换地点、换时间都没用，不引导。
///
/// 每次进入都重读一次规则参数（开放范围按账号下发、随运营调整）。本账号已有数据时先放行、后台重读；
/// 还没有任何数据时最多等 `maxCheckWaitNanoseconds`，读失败或等不到就放行 —— 能不能下单以 `POST /api/orders` 为准，
/// 后端兜底。不无限等：转圈不出声，看不见屏幕的人对着它干等十几秒（请求超时）就是「点了没反应」。
/// 下单被 `ORDER_SERVICE_NOT_OPEN` 拒时，`AppState.noteBookingServiceNotOpen` 让这里当场换成告知页。
struct BlindBookingLaunchScopeGate<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    let onLeave: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var didCheck = false
    @AccessibilityFocusState private var focusesNotice: Bool

    var body: some View {
        Group {
            switch BookingLaunchAvailability(appState.ruleParamsResponse?.launchScope) {
            case .closed(let notice):
                closedNotice(notice)
            case .open:
                if didCheck || appState.ruleParamsResponse != nil {
                    content()
                } else {
                    ProgressView(LaunchScopeCopy.checking)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.background)
                        .accessibilityIdentifier("blindBookingLaunchScopeChecking")
                }
            }
        }
        .task {
            // 读本身不随等待取消：晚到的结果照样写进 AppState，暂未开放时闸门随之换成告知页。
            let refresh = Task { await appState.loadRuleParamsIfNeeded(force: true) }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await refresh.value }
                group.addTask { try? await Task.sleep(nanoseconds: launchScopeMaxCheckWaitNanoseconds) }
                await group.next()
                group.cancelAll()
            }
            didCheck = true
        }
    }

    private func closedNotice(_ notice: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(notice)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("blindBookingClosedNotice")
                    .accessibilityFocused($focusesNotice)

                PrimaryButton(LaunchScopeCopy.backHome) {
                    speechService.stop()
                    onLeave()
                }
                .accessibilityHint("回到首页，现在还不能预约")
                .accessibilityIdentifier("blindBookingClosedBackHome")

                Button("重复当前状态") {
                    speechService.speak(notice)
                }
                .buttonStyle(OutlineSecondaryButtonStyle())
                .accessibilityHint("再次朗读现在为什么不能预约")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle("创建预约")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // 换成告知页的那一刻念一遍（含提交后被拒的那一次），同一句不重复念。
        // 读屏焦点同时搬到这句上：提交后被拒时，原先聚焦的提交按钮已随下单页一起销毁。
        .task(id: notice) {
            focusesNotice = true
            speechService.speak(notice)
        }
    }
}

/// 本账号还没有规则数据时，进入下单页前最多等多久（2 秒）。
private let launchScopeMaxCheckWaitNanoseconds: UInt64 = 2_000_000_000
