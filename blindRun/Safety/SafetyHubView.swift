import SwiftUI
import UIKit

// MARK: - 求助中心的呈现

/// 把求助中心挂到订单页上的那一层。**做成 `ViewModifier` 而不是一个 `.sheet` 调用，
/// 只为了一件事：先关弹层，再执行选中的动作。**
///
/// 🔴 不这么做的后果是具体的、而且沉默：选「一键求助」会把
/// `emergencyConfirmationAlert` 弹在**被弹层盖住的那一页**上 —— iOS 不会报错，
/// 屏幕上什么都不发生，而用户刚刚按下的是这一层里唯一救命的动作。
/// 「问一句」同理（它自己要起一个语音面板），「播报我的位置」的 TTS 也该在焦点回到
/// 执行屏之后再说，否则读屏正在念弹层里的元素、两句话会撞在一起
/// （记忆 `later-speak-silently-cuts-the-earlier-one`）。
///
/// `ViewModifier` 是这里唯一能存 `@State` 的地方：`View` 的扩展方法存不了状态，
/// 而「等 `onDismiss` 回来再执行」必须有个地方记住待执行的是哪一个。
struct SafetyHubPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let mode: BlindHomeSOSMode
    let primaryContact: EmergencyContactResponse?
    let volunteerPhone: String?
    let locationError: LocationError?
    let offersLiveShare: Bool
    let isLiveSharing: Bool
    let onAnnounceLocation: () -> Void
    let onAskQuestion: () -> Void
    let onToggleLiveShare: () -> Void
    let onLocalCall: () -> Void
    let onTriggerEmergency: () -> Void
    let onTriggerEmergencyImmediately: () -> Void

    @State private var pendingAction: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: runPendingAction) {
            BlindSafetyHubView(
                mode: mode,
                primaryContact: primaryContact,
                volunteerPhone: volunteerPhone,
                locationError: locationError,
                offersLiveShare: offersLiveShare,
                isLiveSharing: isLiveSharing,
                onAnnounceLocation: { dismiss(then: onAnnounceLocation) },
                onAskQuestion: { dismiss(then: onAskQuestion) },
                // 分享也要先关弹层：起分享要先过明示同意那道全屏告知
                // （`RunPlanShareConsentView`），而全屏盖在 sheet 上是 iOS 不报错、
                // 屏幕上什么都不发生的那一类 —— 与「一键求助」同一个坑。
                onToggleLiveShare: { dismiss(then: onToggleLiveShare) },
                onLocalCall: { dismiss(then: onLocalCall) },
                onTriggerEmergency: { dismiss(then: onTriggerEmergency) },
                onTriggerEmergencyImmediately: { dismiss(then: onTriggerEmergencyImmediately) },
                onDismiss: { dismiss(then: nil) }
            )
        }
    }

    private func dismiss(then action: (() -> Void)?) {
        pendingAction = action
        isPresented = false
    }

    private func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }
}

// MARK: - 屏 2 · 求助与安全中心

/// 陪跑中那屏底部红块打开的那一层。
///
/// **为什么不是 `confirmationDialog`。** 它此前就是（`blindActiveRunSafetyHubDialog`，已删），
/// 而系统操作表有三样东西给不了，每一样都不是观感问题：
///
/// 1. **按钮不接受长按手势** —— 「紧急求助 · 按住 3 秒」在操作表里做不出来，
///    那条路径是这一层里唯一能跳过二次确认的路径；
/// 2. **遍历顺序由系统定** —— 求助必须是读屏第一个念到的，而操作表按声明顺序从上往下念，
///    把它挪到第一个就等于把最危险的动作放在拇指最容易滑到的地方；
/// 3. **放不下每项的说明小字** —— 「拨打120 / 摔倒、受伤、身体不适」这行小字是
///    「按下去会发生什么」的唯一告知，光看「拨打120」四个字的人不会知道它和 110 的分工。
///
/// 换来的代价是焦点要自己管（`@AccessibilityFocusState` + `.isModal`），见 `body`。
struct BlindSafetyHubView: View {
    /// 底部整条走云端求助还是本地拨号。**由订单状态决定，不由用户选择** ——
    /// 判据与首页/「我的」tab 那条求助条逐字相同（`BlindHomeSOSMode.resolve`），
    /// 理由见 `EmergencySafetyCopy.hubLocalCallNotice`。
    let mode: BlindHomeSOSMode
    let primaryContact: EmergencyContactResponse?
    let volunteerPhone: String?
    /// 定位权限/信号的当前问题。**在这一层顶部说出来，不是等按下求助才说** ——
    /// 云端求助没有新鲜坐标就一个字节都不会发（`EmergencyCoordinator.allowsSubmissionWithoutLocation`），
    /// 而那一刻才告知已经晚了：用户是在「现在要不要按这个红键」这个决定里需要这条事实的。
    let locationError: LocationError?
    /// 这一单此刻能不能开分享链接（`RunOrderStatus.offersRunPlanShare`）。
    let offersLiveShare: Bool
    /// 已经在分享中。那一格的标题随之变成「停止分享实时位置」。
    let isLiveSharing: Bool
    let onAnnounceLocation: () -> Void
    let onAskQuestion: () -> Void
    /// 起 / 停实时分享。**起 / 停由调用方按 `isLiveSharing` 分流**，不在这一层判 ——
    /// 起分享要先过明示同意（`RunPlanShareConsentStep.next`），那是 view 的活。
    let onToggleLiveShare: () -> Void
    /// `.localCall` 档底部那条按下去走的路：本地拨号弹窗，与首页共用同一个构造点。
    let onLocalCall: () -> Void
    /// 轻点「一键求助」：照旧弹 `AGENTS.md` §6 那句逐字锁定的二次确认。
    let onTriggerEmergency: () -> Void
    /// 长按 3 秒 / 自定义无障碍动作：**跳过二次确认**，直接进倒计时。
    let onTriggerEmergencyImmediately: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var emergencyFocused: Bool

    private var tiles: [BlindActiveRunSafetyHubOption] {
        BlindActiveRunSafetyHubOption.tiles(
            volunteerPhone: volunteerPhone,
            primaryContact: primaryContact,
            offersLiveShare: offersLiveShare
        )
    }

    var body: some View {
        // 🚩 SOS **声明在最前面**，视觉上却贴在最底下。
        //
        // 本仓库 2026-08-14 真机实测过四种 `accessibilitySortPriority` 的排法，**全部无效**
        // （`docs/research/swiftui-voiceover-traversal-order-20260814.md`）。真正管用的只有一条：
        // 绘制顺序 = 遍历顺序，所以「读屏第一个念到求助」这件事只能靠声明位置拿到。
        // 上面那层内容用 `.padding(.bottom)` 给它让出位置，两者几何上不重叠。
        ZStack(alignment: .bottom) {
            emergencyButton
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(spacing: 0) {
                dismissButton
                header
                tileGrid
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.bottom, Self.emergencyButtonReservedHeight)
        }
        .background(AppColors.background.ignoresSafeArea())
        // 弹层打开后焦点落在求助上、且被限制在弹层内。`.isModal` 让 VoiceOver 不再往下面的
        // 订单页滑 —— 那一屏此刻在视觉上已经被盖住，能滑到就是「念得到但看不见」。
        .accessibilityAddTraits(.isModal)
        // 🔴 `children: .contain` 不能省。`accessibilityIdentifier` 加在容器上会**向下覆盖**
        // 每个子元素的标识符 —— 本仓库 2026-08-12 在 `OrderRouteReplayView` 上真机实测过：
        // 那一页的按钮和三个统计格全部变成了容器的 id，按子元素 id 的查询永远落空。
        // `guard.mjs` 的 `stale-ui-test-identifier` 查的是「App 侧有没有这个字面量」，
        // 字面量确实在，**那条守卫挡不住这一层**。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindSafetyHub")
        .onAppear { emergencyFocused = true }
    }

    /// 底部红胶囊高度 + 上下留白。上层内容按这个数让位，不靠 `Spacer()` ——
    /// `Spacer()` 在 AX 档下会被内容压成 0，然后两块就叠在一起了。
    private static let emergencyButtonReservedHeight: CGFloat = 132

    // MARK: 顶部

    /// 顶部居中的文字按钮，**不是右上角的 ✕**。管状视力用户的可视范围是屏幕中间一小块，
    /// 角落里的小图标对他们等于不存在（`AGENTS.md` §1.4 的低视力通道那条）。
    private var dismissButton: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(EmergencySafetyCopy.hubDismissTitle(for: mode))
                    .font(AppFonts.body().weight(.semibold))
            }
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .buttonShapeOutlineIfNeeded(color: AppColors.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityLabel(EmergencySafetyCopy.hubDismissTitle(for: mode))
        .accessibilityHint(EmergencySafetyCopy.hubDismissHint(for: mode))
        .accessibilityIdentifier("blindSafetyHubDismissButton")
    }

    /// 标题 + 两句副文本，合成**一个**焦点。
    ///
    /// 🔴 `hubDialogMessage`（「还没有发送求助」）必须在这一段里被念到。它扛的是
    /// 「我刚按下那个红块，到底发生了什么」——看不见屏幕的人在打开一个叫「求助」的东西之后，
    /// 最需要先知道的是**什么都还没发生**。这条不变式由
    /// `testCloudFailureCallCopyDoesNotDenyTheRunInProgress` 钉着。
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(EmergencySafetyCopy.hubTitle)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
            // 🔴 随 `mode` 变。`.localCall` 那四态没有任何跑步在记录，
            // 而这一段是 `.combine` 合成**一个**元素的 —— 念错这半句，
            // 读屏用户听到的是一句和下面「陪跑还没开始」自相矛盾的话。
            Text(EmergencySafetyCopy.hubSubtitle(for: mode))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
            Text(EmergencySafetyCopy.hubDialogMessage)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            // 🔴 本地拨号档必须在这里说清底部那条只是拨号。不说的话，一个刚在
            // 「出发」态打开这一层的盲人会以为按下去求助就发出去了 ——
            // 而云端求助在那一态根本不可调（`AGENTS.md` §6）。
            if mode == .localCall {
                Text(EmergencySafetyCopy.hubLocalCallNotice)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            if let notice = locationNotice {
                Text(notice)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
            }
            if !tiles.contains(.callPrimaryContact) {
                // 没有唯一主联系人时把原因说出来，与首页那套同一句 —— 不说的话菜单只是
                // 「少一格」，而看不见屏幕的人数不出少了哪一格。
                Text(EmergencySafetyCopy.homeCallNoContactHint)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .readableContentColumn()
        .accessibilityElement(children: .combine)
    }

    /// 定位出问题时那一句。**复用 `locationUnavailable` 的分岔**（权限被关 vs 拿不到 GPS），
    /// 而不是另写一句 —— 两处说的是同一件事，分开写就会慢慢漂成两种说法。
    /// 这里只取「未发出：」之后那半句：求助还没按过，说「求助未发出」是假的。
    private var locationNotice: String? {
        guard let locationError else { return nil }
        let full = EmergencySafetyCopy.locationUnavailable(locationError)
        guard let separator = full.range(of: "：") else { return full }
        return String(full[separator.upperBound...])
    }

    // MARK: 方格

    /// 每格 1.5pt 粗边框，**不用浅色底块**。低对比敏感度与管状视力用户看不清浅色块，
    /// 而边框在任何对比度下都还是一条线（张梦蝶 2023 §4.2）。
    private var tileGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles, id: \.self) { option in
                    // 🚩 identifier **逐条写成字面量**，不走一个返回 String 的 helper ——
                    // `guard.mjs` 的 `stale-ui-test-identifier` 只认
                    // `accessibilityIdentifier("字面量")`，算出来的它看不见，于是 UI 测试
                    // 引用这些 id 时会被判成「App 侧不存在」。而那条守卫正是本仓库
                    // 唯一挡得住 identifier 漂移的东西（CI 跑不了 XCTest）。
                    // 穷举 switch 顺带保证新增一项时编译器逼你给它一个 id。
                    switch option {
                    case .contactVolunteer:
                        tile(option).accessibilityIdentifier("blindSafetyHubContactVolunteer")
                    case .announceLocation:
                        tile(option).accessibilityIdentifier("blindSafetyHubAnnounceLocation")
                    case .askQuestion:
                        tile(option).accessibilityIdentifier("blindSafetyHubAskQuestion")
                    case .callPrimaryContact:
                        tile(option).accessibilityIdentifier("blindSafetyHubCallContact")
                    case .callMedical:
                        tile(option).accessibilityIdentifier("blindSafetyHubCallMedical")
                    case .callPolice:
                        tile(option).accessibilityIdentifier("blindSafetyHubCallPolice")
                    case .shareLiveLocation:
                        // 一个 id 管起 / 停两种标题。UI 测试断的是「这一格在不在」，
                        // 而中文文案漂移在本仓库拦不住（误报 93%，见记忆
                        // `merged-prs-whose-tests-never-ran`）—— 别在用例里抄标题字面量。
                        tile(option).accessibilityIdentifier("blindSafetyHubShareLiveLocation")
                    case .triggerEmergency:
                        // `tiles` 已经把它滤掉了，这里只为穷举完整。
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 20)
            .readableContentColumn()
        }
    }

    /// AX 档掉到一列。两列在 AX5 下每格只剩不到 150pt，标题会被挤成三四行、
    /// 小字直接叠在一起 —— 这一屏的读者正是最可能开大字的那群人。
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private func tile(_ option: BlindActiveRunSafetyHubOption) -> some View {
        let title = option.title(contactName: primaryContact?.name, isLiveSharing: isLiveSharing)
        let subtitle = EmergencySafetyCopy.hubTileSubtitle(
            option,
            contactName: primaryContact?.name,
            isLiveSharing: isLiveSharing
        )
        return Button {
            perform(option)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 26, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFonts.body().weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            // 盲人端的触达下限是 64pt 不是 Apple 的 44pt（`guard.mjs` 的 `small-touch-target`）。
            .frame(minHeight: 104)
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    /// 拨号一律经 `EmergencyDialer`：它只取数字位，掩码串（`138****1234`）会被拼成空号，
    /// 而空号在界面上看不出任何异常。`guard.mjs` 的 `raw-open-url` 会拦住绕开它的写法。
    private func perform(_ option: BlindActiveRunSafetyHubOption) {
        switch option {
        case .contactVolunteer:
            dial(volunteerPhone)
        case .announceLocation:
            onAnnounceLocation()
        case .askQuestion:
            onAskQuestion()
        case .callPrimaryContact:
            dial(primaryContact?.phone)
        case .callMedical:
            dial(EmergencyDialer.medicalNumber)
        case .callPolice:
            dial(EmergencyDialer.policeNumber)
        case .shareLiveLocation:
            onToggleLiveShare()
        case .triggerEmergency:
            // 方格里没有这一项（`tiles` 已经滤掉），留着只为穷举完整 —— 真进来了也不该
            // 静默吞掉，走轻点那条（有二次确认）比什么都不做安全。
            onTriggerEmergency()
        }
    }

    private func dial(_ rawNumber: String?) {
        guard let url = EmergencyDialer.telURL(for: rawNumber) else { return }
        EmergencyDialer.dial(url)
        onDismiss()
    }

    // MARK: 底部求助

    /// 底部整条。**两档不是同一个组件，也不该是** ——
    ///
    /// - `.cloudTrigger`：`EmergencySOSLongPressButton`，轻点走二次确认、长按 3 秒进倒计时。
    /// - `.localCall`：一枚普通按钮，按下去只弹本地拨号弹窗。**刻意不接长按手势** ——
    ///   长按那条路的全部意义是「跳过二次确认直接发出求助」，而这一档发不出任何东西。
    ///   留着它等于让一个按住 3 秒的人以为自己发出了求助。
    ///
    /// 标题「紧急呼叫」不是「一键求助」：后四个字在本 App 里专指云端那条链路
    /// （`EmergencySafetyCopy.homeCallTitle` 的注释里写着为什么这两个词不能混）。
    @ViewBuilder
    private var emergencyButton: some View {
        switch mode {
        case .cloudTrigger:
            EmergencySOSLongPressButton(
                onTap: onTriggerEmergency,
                onLongPress: onTriggerEmergencyImmediately
            )
            .accessibilityFocused($emergencyFocused)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .readableContentColumn()
        case .localCall:
            PrimaryButton(
                EmergencySafetyCopy.homeCallTitle,
                isDestructive: true,
                action: onLocalCall
            )
            .accessibilityLabel(EmergencySafetyCopy.homeCallAccessibilityLabel)
            .accessibilityHint(EmergencySafetyCopy.homeCallAccessibilityHint)
            .accessibilityIdentifier("blindSafetyHubLocalCall")
            .accessibilityFocused($emergencyFocused)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .readableContentColumn()
        }
    }
}

// MARK: - 长按 3 秒的求助键

/// 轻点与长按后果不同的那一枚按钮。屏 1 底部那块和屏 2 底部这条都用它的判据。
///
/// **只做「长按一次」，不做「持续按住」。** Noonlight 的持续按住在跑动中几乎按不住
/// （手在摆动、屏幕在颠），而这个 App 的用户正在跑步。
enum SafetyLongPress {
    /// 3 秒。与副标题里印的数字是同一个常量 —— 分开写就会有一天对不上，
    /// 而对不上的表现是「说好按 3 秒，按了 3 秒没反应」。
    static let duration: TimeInterval = 3

    /// 按下过程中的震动节奏：按住越久震得越重，让看不见屏幕的人知道**进度**。
    ///
    /// 做成可单测的纯数据，理由与 `BlindActiveRunSafetyHubOption.options` 同源：
    /// 这是「用户凭什么知道自己按够了没」的唯一依据，而手势本身在单测里够不着。
    /// 每一拍必须**严格落在 `duration` 之前**：踩在 3.0 上那一拍会和触发同时发生，
    /// 用户听到的是「一下重震」而不是「渐强到触发」。
    static let hapticRamp: [(elapsed: TimeInterval, intensity: CGFloat)] = [
        (0.0, 0.35),
        (1.0, 0.6),
        (2.0, 0.85),
        (2.6, 1.0),
    ]
}

/// 「轻点走一条路、长按 3 秒走另一条」这套手势的**唯一实现**。
///
/// 屏 1 的贴边红块和屏 2 的红胶囊都用它。2026-09-15 code review 抓到这两处原本各写一份，
/// 于是屏 1 那块 —— **全 App 唯一印着「长按 3 秒」四个字的地方** —— 反而没有接上渐强震动，
/// 而那是「用户凭什么知道自己按够了没」的唯一依据。
///
/// 🔴 **`didFireLongPress` 这个标志位不是防御性代码。** `.onLongPressGesture` 与
/// `.simultaneousGesture(TapGesture())` 并存时，长按满 3 秒抬手会不会**再**触发一次 tap，
/// SwiftUI 没有任何公开约定（`TapGesture` 对按压时长没有文档化的上限）。真会触发的话后果是静默的：
/// 屏 1 上 alert 与 sheet 会在同一次交互里都要求呈现、iOS 丢掉其中一个；屏 2 上后到的 tap
/// 会把长按刚设好的待执行动作覆盖掉，于是**长按 3 秒完全等价于轻点**，倒计时那条路径消失。
/// 与其去真机上验一个没有约定的行为，不如让实现不依赖它。
///
/// ⛔ 不用 `Button`：`Button` 把长按当成「取消这次点击」吃掉，两个手势挂在同一个
/// `Button` 上时长按那条永远拿不到。
struct SafetyLongPressGesture: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void
    /// 按住过程中的视觉反馈。屏 2 的胶囊用它变淡，屏 1 的贴边红块不需要（它没有形状变化的余地）。
    var onPressingChanged: (Bool) -> Void = { _ in }

    @State private var didFireLongPress = false
    @State private var rampTasks: [DispatchWorkItem] = []

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onLongPressGesture(
                minimumDuration: SafetyLongPress.duration,
                perform: {
                    cancelRamp()
                    didFireLongPress = true
                    onPressingChanged(false)
                    onLongPress()
                },
                onPressingChanged: { pressing in
                    onPressingChanged(pressing)
                    if pressing {
                        // **只在按下那一刻清标志**，不在抬手时清 —— 抬手与 tap 的先后
                        // 同样没有约定，在抬手时清等于把这道保险抹掉。
                        didFireLongPress = false
                        startRamp()
                    } else {
                        cancelRamp()
                    }
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard !didFireLongPress else { return }
                    onTap()
                }
            )
            .onDisappear(perform: cancelRamp)
    }

    private func startRamp() {
        cancelRamp()
        rampTasks = SafetyLongPress.hapticRamp.map { step in
            let work = DispatchWorkItem {
                // 不 `prepare()` 的话首次触发常被系统丢掉 —— 而首次正是最要紧的那次：
                // 用户刚按下去，还不知道这块红的认不认长按。
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred(intensity: step.intensity)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + step.elapsed, execute: work)
            return work
        }
    }

    private func cancelRamp() {
        rampTasks.forEach { $0.cancel() }
        rampTasks = []
    }
}

extension View {
    /// 轻点与长按后果不同的那套手势。见 `SafetyLongPressGesture`。
    func safetyLongPress(
        onTap: @escaping () -> Void,
        onLongPress: @escaping () -> Void,
        onPressingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(
            SafetyLongPressGesture(
                onTap: onTap,
                onLongPress: onLongPress,
                onPressingChanged: onPressingChanged
            )
        )
    }
}

/// 红胶囊。**轻点 = 走二次确认，长按 3 秒 = 跳过确认直接进倒计时。**
///
/// 🔴 两条路径后果不同，所以副标题必须把长按说出来 —— 见 `EmergencySafetyCopy.hubEntrySubtitle`
/// 与 `hubTriggerSubtitle`。不说的话，一个不知道自己在长按的人会以为按钮坏了（没弹确认框），
/// 而倒计时在他反应过来之前就走完了。
struct EmergencySOSLongPressButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void
    /// 求助正在路上（定位中 / 发送中）时不接受新的触发。
    var isEnabled = true

    @State private var isPressing = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // `sos` 那个符号要 iOS 16.1，部署目标是 16.0 —— 见
                // `BlindActiveRunSafetyHubOption.symbolName` 的注释。
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityHidden(true)
                Text(EmergencySafetyCopy.title)
                    .font(.title3.weight(.bold))
            }
            Text(EmergencySafetyCopy.hubTriggerSubtitle)
                .font(AppFonts.caption().weight(.semibold))
                .opacity(0.9)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 84)
        .background(
            Capsule().fill(AppColors.destructive.opacity(isPressing ? 0.75 : 1))
        )
        .clipShape(Capsule())
        // 轻点走二次确认、长按 3 秒跳过它。两条路径与渐强震动的实现都在
        // `SafetyLongPressGesture` 里 —— 屏 1 那块贴边红块用的是同一份。
        .safetyLongPress(
            onTap: onTap,
            onLongPress: onLongPress,
            onPressingChanged: { isPressing = $0 }
        )
        // 见屏 1 那块红块上的同一段注释：`.disabled()` 是 SwiftUI 里唯一能让读屏
        // 念出「不可用」的写法，静默 `guard` 做不到。
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(EmergencySafetyCopy.title)
        .accessibilityHint(EmergencySafetyCopy.hubTriggerAccessibilityHint)
        // 读屏用户走这条：VoiceOver 下的「双击并按住」不稳定，而自定义动作是两步刻意操作。
        // 它按长按算 —— 见 `EmergencySafetyCopy.emergencyAccessibilityActionName` 的注释。
        .accessibilityAction(named: Text(EmergencySafetyCopy.emergencyAccessibilityActionName)) {
            onLongPress()
        }
        .accessibilityIdentifier("blindSafetyHubTriggerEmergency")
    }
}
