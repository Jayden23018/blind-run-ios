import SwiftUI

// MARK: - 恢复：求助还活着时把屏 3b 拉回来

/// 求助**不是**只能从「按下按钮」那条路进屏 3b。至少四条路会让 App 在不知情的情况下
/// 处在一个进行中的求助里：
///
/// 1. **志愿者代触发** —— 盲人自己没按过任何按钮；
/// 2. **冷启动** —— 求助期间 App 被系统回收或用户杀掉；
/// 3. **WS 断线重连** —— 断线那段时间里整条求助可能都发生完了；
/// 4. **点开推送进来** —— 进程可能是刚起来的。
///
/// 这四条的数据侧已经有了：`AppState.catchUpMissedNotifications()` 会先调
/// `refreshActiveEvent()`（仅盲人有该端点权限），而它是「事件 id 与当前状态的唯一权威来源」。
/// **缺的一直是界面侧** —— 恢复出来的状态此前只体现为执行屏底部那一行小字，
/// 而一个正在进行的求助不该只是一行小字。
///
/// 做成 `ViewModifier` 的理由和志愿者那边逐字相同：它能 `@ObservedObject` 持有 coordinator，
/// 而 `AppState.emergencyCoordinator` 是 `let` 不是 `@Published` ——
/// 在页面 body 里 `onChange(of: appState.emergencyCoordinator.activeEvent)`
/// **根本不会触发**（记忆 `nested-observableobject-does-not-republish`）。
struct EmergencyRecoveryPresentation: ViewModifier {
    @ObservedObject var coordinator: EmergencyCoordinator
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.onChange(of: coordinator.activeEvent?.eventID) { eventID in
            // 只在「冒出一个事件」时拉起来。事件消失（撤销 / 客服解除）时**不主动关闭**：
            // 那一刻屏幕上正显示「已撤销」之类的收尾文案，自动关掉等于让用户听不完就被弹走。
            guard eventID != nil else { return }
            isPresented = true
        }
    }
}

extension View {
    func emergencyRecoveryCover(
        coordinator: EmergencyCoordinator,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(EmergencyRecoveryPresentation(coordinator: coordinator, isPresented: isPresented))
    }
}

// MARK: - 屏 3 / 屏 3b · 紧急倒计时与求助已发出

/// 按下求助之后的那一整屏。**两态共用一个视图**：倒计时（屏 3）与求助已发出（屏 3b）。
///
/// 合成一个而不是两个，是因为它们对用户是**同一件事的两个阶段**，而底部那一格必须
/// 始终在同一个位置（`取消` → `撤销求助`）。拆成两个全屏视图的话，中间会有一次
/// 呈现切换 —— VoiceOver 会重新播报整屏、焦点回到第一个元素，而那一刻用户正等着听
/// 「发出去了没有」。
///
/// 🔴 **紧急状态不能只靠红色**（色盲用户）。这一屏同时给三样：整圈 3pt 粗边框、
/// 警示图标、以及标题文字本身。三样都**无条件**存在，不看
/// `accessibilityDifferentiateWithoutColor` —— 那个环境值只有用户主动打开才为真，
/// 而红绿色觉异常的人多数不知道 iOS 有这个开关。
struct EmergencyCountdownView: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    /// 主紧急联系人。屏 3b 的拨号项与首页那套同一个来源。
    let primaryContact: EmergencyContactResponse?
    let onCancelCountdown: () -> Void
    /// 撤销自己已经发出的求助（`PUT /api/emergency/{id}/cancel`）。**只有本人和客服有这个权力。**
    let onCancelOwnEmergency: () async -> Void
    /// 发送失败之后由**用户**决定要不要再发一次。
    let onRetry: () -> Void
    let onClose: () -> Void

    @State private var showCancelOwnConfirmation = false
    @State private var isCancelling = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    dismissButton
                    header
                    if coordinator.state.isCountingDown {
                        countdownRing
                    }
                    pendingEffects
                    if let message = coordinator.state.message {
                        Text(message)
                            .font(AppFonts.body())
                            .foregroundColor(
                                coordinator.state.isFailure ? AppColors.destructive : AppColors.textPrimary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    callOutButtons
                    bottomAction
                }
                .padding(20)
                .readableContentColumn()
            }
        }
        // 整圈 3pt 粗边框 —— 三条冗余线索里唯一一条在余光里也能看见的。
        .overlay(
            Rectangle()
                .strokeBorder(AppColors.destructive, lineWidth: 3)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        )
        // `children: .contain` 不能省，理由见 `BlindSafetyHubView.body` 上那段注释。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindEmergencyCountdown")
        .confirmationDialog(
            EmergencySafetyCopy.cancelButtonTitleForOwner,
            isPresented: $showCancelOwnConfirmation
        ) {
            Button(EmergencySafetyCopy.cancelButtonTitleForOwner, role: .destructive) {
                Task {
                    isCancelling = true
                    await onCancelOwnEmergency()
                    isCancelling = false
                }
            }
            Button("保持求助", role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.cancelOwnerConfirmation)
        }
        // 警报音是这一屏起的，收尾也必须在这一屏 —— 忘了关的表现是
        // 「求助已经撤销了，警报还在响」。
        .onDisappear { EmergencyAlarm.stopAll() }
    }

    // MARK: 顶部

    /// 🔴 **求助发出之后必须还能离开这一屏。**
    ///
    /// 2026-09-15 code review 抓到的：`activeEvent != nil` 时底部那一格是「撤销求助」，
    /// 而这是 `fullScreenCover`（下滑关不掉）—— 于是唯一的退出路径变成
    /// **撤销一条真实的求助**。事件在 `CS_HANDLING` 期间可以持续很久，
    /// 而盲人这段时间里完全可能想回去听「重复当前状态」、或者打给身边的陪跑志愿者。
    ///
    /// 位置与形态照抄屏 2 的收起按钮：顶部居中的文字按钮，**不是角落 ✕** ——
    /// 管状视力用户的可视范围是屏幕中间一小块，角落里的小图标对他们等于不存在。
    ///
    /// 倒计时那三秒里不给这个口子：那一刻屏幕上只该有一个动作（取消），
    /// 多一个「返回」会让「往下摸到底就是取消」这条位置记忆失效。
    @ViewBuilder
    private var dismissButton: some View {
        if !coordinator.state.isCountingDown {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                    Text("返回跑步")
                        .font(AppFonts.body().weight(.semibold))
                }
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .buttonShapeOutlineIfNeeded(color: AppColors.textPrimary)
            }
            .accessibilityLabel("返回跑步")
            .accessibilityHint("回到跑步页面。求助仍然有效，不会被撤销。")
            .accessibilityIdentifier("blindEmergencyCountdownClose")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(AppColors.destructive)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.bold))
                .foregroundColor(AppColors.destructive)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(title)
    }

    /// 判定在 `EmergencySafetyCopy.screenTitle(for:hasActiveEvent:)` —— 穷举 switch 的纯函数，
    /// 被 `EmergencySOSTests` 逐状态钉住。这里只负责把它显示出来。
    private var title: String {
        EmergencySafetyCopy.screenTitle(
            for: coordinator.state,
            hasActiveEvent: coordinator.activeEvent != nil
        )
    }

    // MARK: 倒计时圆环

    /// 居中大圆环 + 数字。**它是给看得见的人的**：真正承载倒计时的是每秒一次的
    /// 声音（`EmergencyAlarm.countdownTick`）、震动（`EmergencyHaptics`）和播报。
    ///
    /// 数字本身 `accessibilityHidden` —— 读屏已经在每秒念一遍完整那句
    /// 「还有 N 秒，现在取消还来得及」，让它再念一个光秃秃的「2」只会打断那句话
    /// （记忆 `later-speak-silently-cuts-the-earlier-one`：谁后说谁赢）。
    private var countdownRing: some View {
        Text("\(secondsRemaining)")
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 96 : 120, weight: .bold).monospacedDigit())
            .foregroundColor(AppColors.destructive)
            .frame(width: 180, height: 180)
            .overlay(Circle().strokeBorder(AppColors.destructive, lineWidth: 6))
            .accessibilityHidden(true)
    }

    private var secondsRemaining: Int {
        if case .countingDown(let seconds) = coordinator.state { return seconds }
        return 0
    }

    // MARK: 即将发生的事

    /// 倒计时里列的是「即将发生什么」。
    ///
    /// 🔴 **求助发出之后这一段就撤掉，不改成打勾的完成态。** 打勾等于宣称那三件事做成了，
    /// 而 App 无从知道：短信是事务提交后异步发的、失败也从不回告盲人（`AGENTS.md` §6）。
    /// 发出之后该说什么由 `coordinator.state.message` 说了算 —— 那条链路上的每一句
    /// 都是被 `EmergencySOSTests` 逐句验过时态的。
    @ViewBuilder
    private var pendingEffects: some View {
        if coordinator.state.isCountingDown {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(EmergencySafetyCopy.countdownPendingEffects, id: \.self) { effect in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "arrow.right")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(AppColors.destructive)
                            .accessibilityHidden(true)
                        Text(effect)
                            .font(AppFonts.body())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("接下来会：" + EmergencySafetyCopy.countdownPendingEffects.joined(separator: "，"))
        }
    }

    // MARK: 拨号

    /// 120 与 110。**倒计时期间不显示** —— 那三秒里屏幕上只该有一个动作（取消），
    /// 多两个按钮会让「往下摸到底就是取消」这条位置记忆失效。
    ///
    /// 🔴 **只调起系统拨号，不自动拨出。** 自动拨号会把一个还在判断情况的人直接接进接警台。
    @ViewBuilder
    private var callOutButtons: some View {
        if !coordinator.state.isCountingDown {
            VStack(spacing: 12) {
                if let url = EmergencyDialer.telURL(for: EmergencyDialer.medicalNumber) {
                    PrimaryButton(EmergencySafetyCopy.homeCallMedicalTitle, isDestructive: true) {
                        EmergencyDialer.dial(url)
                    }
                    .accessibilityHint(EmergencySafetyCopy.sentCallMedicalHint)
                    .accessibilityIdentifier("blindEmergencySentCallMedical")
                }
                if let url = EmergencyDialer.telURL(for: EmergencyDialer.policeNumber) {
                    PrimaryButton(EmergencySafetyCopy.homeCallPoliceTitle, isDestructive: true) {
                        EmergencyDialer.dial(url)
                    }
                    .accessibilityHint(EmergencySafetyCopy.sentCallPoliceHint)
                    .accessibilityIdentifier("blindEmergencySentCallPolice")
                }
                if let contact = primaryContact,
                   let url = EmergencyDialer.telURL(for: contact.phone) {
                    PrimaryButton(EmergencySafetyCopy.homeCallContactTitle(name: contact.name)) {
                        EmergencyDialer.dial(url)
                    }
                    .accessibilityIdentifier("blindEmergencySentCallContact")
                }

                // 🔴 **重试排在 120 / 110 后面，这个顺序本身就是要求的一半。**
                // prompt 要的是「倒计时结束仍未发出时，显示明确提示和拨打 120 入口」——
                // 一个摔在路边的人最该先够到的是急救电话，不是再赌一次网络。
                //
                // ⛔ **没有做成自动重试。** 后端 `POST /api/emergency/trigger` 没有幂等 key，
                // 自动重发要么建出第二个事件、要么撞 60 秒冷却回 429 —— 而 429 的文案是
                // 「请稍后再试」，会把一个**已经生效**的求助说成被拒绝。
                // 「刚才那条到底发出去没有」改由只读的 `refreshActiveEvent()` 对账
                // （`EmergencyCoordinator.reconcile(after:)`），不靠重发去试。
                if coordinator.state.isFailure, coordinator.activeEvent == nil {
                    PrimaryButton(EmergencySafetyCopy.retrySendTitle, action: onRetry)
                        .accessibilityHint(EmergencySafetyCopy.retrySendAccessibilityHint)
                        .accessibilityIdentifier("blindEmergencyRetrySend")
                }
            }
        }
    }

    // MARK: 底部固定动作

    /// 底部**永远是一个动作，位置不变**：倒计时是「取消」，发出之后是「撤销求助」，
    /// 都没有时是「返回跑步」。盲人靠的是「往下摸到底的那一个」这条位置记忆。
    @ViewBuilder
    private var bottomAction: some View {
        if coordinator.state.isCountingDown {
            PrimaryButton(EmergencySafetyCopy.countdownCancelTitle, action: onCancelCountdown)
                .accessibilityHint(EmergencySafetyCopy.countdownCancelAccessibilityHint)
                .accessibilityIdentifier("blindEmergencyCountdownCancel")
        } else if coordinator.activeEvent != nil {
            PrimaryButton(
                EmergencySafetyCopy.cancelButtonTitleForOwner,
                isLoading: isCancelling
            ) {
                showCancelOwnConfirmation = true
            }
            .accessibilityHint("误触时撤销本次求助，需要确认")
            .accessibilityIdentifier("blindEmergencyCancelOwn")
        }
        // 没有倒计时、也没有活动事件时**底部不放任何东西** —— 退出走顶部那个
        // 「返回跑步」（`dismissButton`）。此前这里再放一个同名按钮，
        // 等于同一个动作在一屏上有两个位置，而位置记忆恰恰经不起这个。
    }
}
