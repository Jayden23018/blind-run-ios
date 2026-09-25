import Combine
import CoreLocation
import SwiftUI

// MARK: - 屏 4 · 志愿者陪跑中的同步指标

/// 陪跑进行中，志愿者这一侧看到的「他怎么样了」。
///
/// **为什么这块值得存在**：张梦蝶（2023）§4.2 把「助跑者无法了解视障跑者的状态」列为
/// 这类产品的核心痛点之一，而在此之前志愿者端 `IN_PROGRESS` 只有一张地图和几个流转按钮 ——
/// 盲人那边已经跑了多远、配速多少、位置还通不通，志愿者一概看不到。
///
/// 🚩 **数据来源与盲人端是同一个** `GET /api/orders/{id}/track` 的 `blindStats`。
/// 两端各算一份的话，「你俩看到的公里数不一样」会变成一个没人能复现的投诉。
///
/// ⛔ **设计稿上的「他的电量」这一行没有做** —— 后端没有这个字段。
/// 编一个数字出来比不显示危险得多：志愿者会据此判断「他手机还能撑多久」。
struct VolunteerEscortStatsCard: View {
    /// **自己 `@ObservedObject` 持有**，不通过 `AppState` 读 ——
    /// `AppState.emergencyCoordinator` 是 `let` 不是 `@Published`，嵌套 `ObservableObject`
    /// 的变化不会经由 `AppState` 重新发布（记忆 `nested-observableobject-does-not-republish`）。
    /// 在页面 body 里读它的属性是**读得到值、但不跟着更新**，
    /// 这一页看似能刷新只是因为它恰好每 5 秒轮询一次订单 —— 那是巧合，不重复它。
    @ObservedObject var coordinator: EmergencyCoordinator
    let peerName: String?
    let stats: TrackStats?
    /// 最近一条 `BLIND_LOCATION_UPDATE` 还新不新鲜。过期即 nil（view model 里有过期任务）。
    let isPeerLocationFresh: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var primaryNumberSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title3) private var secondaryNumberSize: CGFloat = 24

    /// 对方的状态。**三档，不是两档。**
    ///
    /// 2026-09-15 code review 抓到的：原实现只有「求助中 / 正常」，志愿者按完
    /// 「我在他身边，去处理」之后这一行立刻变回**「正常」**、圆点变绿 ——
    /// 而他按的那一下只是告诉客服「现场有人了」，求助本身仍然是开的
    /// （同屏另一句话写着「这条求助只有他本人或客服能撤销」）。
    /// 那与屏 5 刻意不写「客服已接入」是同一条红线：**不知道的事不许说**，
    /// 「已经结束」同样是一件我们不知道的事。
    private var peerStatus: (text: String, isAlarming: Bool) {
        guard let alert = coordinator.volunteerAlert else {
            return (EmergencySafetyCopy.volunteerPeerStatusNormal, false)
        }
        // 已确认：不再报警（否则一个**新的**求助会在视觉上被淹没），但也不宣称结束。
        if alert.isAcknowledged {
            return (EmergencySafetyCopy.volunteerPeerStatusAcknowledged, false)
        }
        return (EmergencySafetyCopy.volunteerPeerStatusEmergency, true)
    }

    /// 只给顶部那个小圆点用 —— 它表达的是「现在要不要立刻看一眼」，已确认之后就不要了。
    private var isPeerInEmergency: Bool {
        guard let alert = coordinator.volunteerAlert else { return false }
        return !alert.isAcknowledged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headline
            metricsRow
            statusRows
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background)
        // 粗边框而不是浅色底块 —— 低对比敏感度与管状视力用户看不清浅色块（张梦蝶 §4.2）。
        // 志愿者端主要是明眼人，但低视力志愿者同样存在，而边框对谁都不更差。
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerEscortStatsCard")
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPeerInEmergency ? AppColors.destructive : AppColors.success)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(EmergencySafetyCopy.volunteerEscortHeadline(name: peerName))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        // 上屏那份留掩码星号，念出来这份去掉（见 `String.unmaskedForSpeech`）。
        .accessibilityLabel(
            EmergencySafetyCopy.volunteerEscortHeadline(name: peerName?.unmaskedForSpeech)
        )
    }

    /// 屏幕用跑表体例（`5.26` / `32:18` / `6'08"`），读屏念口语体例。
    /// 两套并存不是重复 —— `6'08"` 读屏会念成「六撇零八引号」。
    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            metric(
                value: stats?.distanceKilometersText,
                label: "公里",
                spokenValue: stats?.distanceText,
                spokenLabel: "已跑",
                size: primaryNumberSize
            )
            metric(
                value: stats?.durationClockText,
                label: "时长",
                spokenValue: stats?.durationText,
                spokenLabel: "时长",
                size: secondaryNumberSize
            )
            metric(
                value: stats?.paceClockText,
                label: "配速",
                spokenValue: stats?.averagePaceText,
                spokenLabel: "配速",
                size: secondaryNumberSize
            )
        }
    }

    private func metric(
        value: String?,
        label: String,
        spokenValue: String?,
        spokenLabel: String,
        size: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? "--")
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundColor(AppColors.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // 拿不到数据时说「正在获取」，不念「杠杠」。刚起跑的头十几秒本来就没有足够的轨迹点，
        // 那是契约里的空态（`OrderTrackResponse.emptyStateText`），不是错误。
        .accessibilityLabel(spokenValue.map { "\(spokenLabel) \($0)" } ?? "\(spokenLabel)，正在获取")
    }

    private var statusRows: some View {
        VStack(spacing: 0) {
            statusRow(
                label: EmergencySafetyCopy.volunteerPeerStatusLabel,
                value: peerStatus.text,
                isAlarming: peerStatus.isAlarming
            )
            Divider()
            statusRow(
                label: EmergencySafetyCopy.volunteerPeerLocationLabel,
                value: isPeerLocationFresh
                    ? EmergencySafetyCopy.volunteerPeerLocationOn
                    : EmergencySafetyCopy.volunteerPeerLocationStale,
                isAlarming: !isPeerLocationFresh
            )
        }
        .padding(.horizontal, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
        )
    }

    private func statusRow(label: String, value: String, isAlarming: Bool) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(AppFonts.body().weight(.semibold))
                // 状态**由文字承担**，颜色只是冗余 —— 色盲用户看不出绿变红，
                // 而「正常 / 求助中」这两个词他一样读得到。
                .foregroundColor(isAlarming ? AppColors.destructive : AppColors.textPrimary)
        }
        .padding(.vertical, 10) // guard:allow small-touch-target 这是一行只读状态，不是可点目标
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(value)")
    }
}

// MARK: - 屏 5 的呈现

/// 把屏 5 挂到志愿者服务页上。
///
/// **做成 `ViewModifier` 只为一件事**：它能 `@ObservedObject` 持有 coordinator，
/// 而 `AppState.emergencyCoordinator` 是 `let` 不是 `@Published` ——
/// 在页面 body 里直接读 `appState.emergencyCoordinator.volunteerAlert`
/// **读得到值但不会跟着更新**，表现就是告警来了这一屏不弹
/// （记忆 `nested-observableobject-does-not-republish`）。
///
/// 呈现条件是「有未确认的告警」。`set` 是空实现且**刻意如此**：这一屏没有关闭路径，
/// 它只在告警被确认（`isAcknowledged`）或被本人 / 客服结束（`volunteerAlert` 置 nil）时消失。
/// `fullScreenCover` 本来就不能下滑关掉，所以不存在「用户划走了但状态没变」这种不一致。
struct VolunteerEmergencyAlertPresentation: ViewModifier {
    @ObservedObject var coordinator: EmergencyCoordinator
    let peerName: String?
    let peerPhone: String?
    let deviceCoordinate: CLLocationCoordinate2D?
    let isAcknowledging: Bool
    let reverseGeocode: (CLLocationCoordinate2D) async -> String?
    let serverAddress: (Int64) async -> OrderLocationAddressResponse?
    let onAcknowledge: (Int64) -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(
            isPresented: Binding(
                get: { coordinator.volunteerAlert.map { !$0.isAcknowledged } ?? false },
                set: { _ in }
            )
        ) {
            if let alert = coordinator.volunteerAlert {
                VolunteerEmergencyAlertView(
                    alert: alert,
                    peerName: peerName,
                    peerPhone: peerPhone,
                    deviceCoordinate: deviceCoordinate,
                    isAcknowledging: isAcknowledging,
                    onAcknowledge: { onAcknowledge(alert.eventID) },
                    reverseGeocode: reverseGeocode,
                    serverAddress: serverAddress
                )
            }
        }
    }
}

extension View {
    func volunteerEmergencyAlertCover(
        coordinator: EmergencyCoordinator,
        peerName: String?,
        peerPhone: String?,
        deviceCoordinate: CLLocationCoordinate2D?,
        isAcknowledging: Bool,
        reverseGeocode: @escaping (CLLocationCoordinate2D) async -> String?,
        serverAddress: @escaping (Int64) async -> OrderLocationAddressResponse?,
        onAcknowledge: @escaping (Int64) -> Void
    ) -> some View {
        modifier(
            VolunteerEmergencyAlertPresentation(
                coordinator: coordinator,
                peerName: peerName,
                peerPhone: peerPhone,
                deviceCoordinate: deviceCoordinate,
                isAcknowledging: isAcknowledging,
                reverseGeocode: reverseGeocode,
                serverAddress: serverAddress,
                onAcknowledge: onAcknowledge
            )
        )
    }
}

// MARK: - 屏 5 · 收到紧急求助

/// 志愿者端收到 `EMERGENCY_VOLUNTEER_ALERT` 时盖满整屏的强提醒。
///
/// **为什么是 `fullScreenCover` 而不是一条横幅**：在此之前它是底部面板上方一条
/// `EmergencyStatusNotice` + 一个按钮，而那一刻志愿者多半正看着地图导航、或者根本没在看屏幕。
/// 一条和其他提示长得一样的横幅，在「被陪同者刚刚按下求助」这件事上是不成比例的。
///
/// 🔴 **没有关闭按钮，这是刻意的。** 后端对志愿者的 `action=FALSE_ALARM` 恒 403
/// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS` —— 一对一陪跑里志愿者可能就是威胁来源，
/// 撤销权只在受助者本人和客服手里。给一个「关掉」按钮等于在客户端造一个后端拒绝的能力。
/// 这一屏只会在志愿者按下「我在他身边」之后，或求助被本人 / 客服结束之后消失。
struct VolunteerEmergencyAlertView: View {
    let alert: VolunteerEmergencyAlert
    let peerName: String?
    /// 全号。**只进 `tel:`，不上屏、不进 `accessibilityLabel`**（`AGENTS.md` §8）——
    /// VoiceOver 是外放的，念全号等于把盲人的号码广播给周围所有人。
    let peerPhone: String?
    /// 志愿者本机位置，用来算「距你多远」。拿不到就不显示距离，不猜。
    let deviceCoordinate: CLLocationCoordinate2D?
    let isAcknowledging: Bool
    let onAcknowledge: () -> Void
    /// 逆地理。传进来而不是从环境里取 —— 这个视图在两处被呈现，
    /// 而环境值漏注入的表现是「地址永远解析不出来」，不报错。
    let reverseGeocode: (CLLocationCoordinate2D) async -> String?
    /// `GET /api/orders/{id}/location/address`（盲人的位置）。告警没带坐标（冷启动恢复出来的
    /// 那条恒没有）或本机逆地理失败时的兜底，后端 #387 ①。
    let serverAddress: (Int64) async -> OrderLocationAddressResponse?

    /// 逆地理解析出来的地名。nil = 还没解析出来或解析失败。
    @State private var resolvedPlace: String?
    @State private var didResolvePlace = false
    @State private var elapsedSeconds = 0

    /// 警报最长响这么久。够把人从导航 / 口袋里叫出来，又不至于盖掉他随后要打的电话。
    static let sirenDuration: TimeInterval = 15

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    locationCard
                    callButton
                    acknowledgeBlock
                }
                .padding(20)
                .readableContentColumn()
            }
        }
        // 整圈红色粗边框。与屏 3 同一个形状 —— 两端看到「紧急」时，屏幕的样子是一致的。
        .overlay(
            Rectangle()
                .strokeBorder(AppColors.destructive, lineWidth: 3)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerEmergencyAlert")
        .onReceive(ticker) { _ in
            elapsedSeconds = Int(Date().timeIntervalSince(alert.receivedAt))
        }
        .task {
            // 警报音 + 震动。志愿者多半没在看屏幕，全屏本身传达不了任何东西。
            // 先把「多久之前」算准再说。只靠 ticker 每秒更新的话，这一屏出现的第一秒
            // 恒显示「0 秒前」—— 而冷启动恢复时那条告警可能是几十秒前的，
            // 「刚刚发生」和「我漏看了很久」对志愿者是两种完全不同的判断。
            elapsedSeconds = Int(Date().timeIntervalSince(alert.receivedAt))
            EmergencyAlarm.startSiren()
            EmergencyHaptics.countdownTick()
            // 🔴 **响够就停，不无限循环。** 这一屏刻意没有关闭按钮（撤销权不在志愿者手里），
            // 而 `acknowledgeEmergency` 连续失败时告警不会消失 —— 无限循环的警报会把
            // 志愿者困在一段**关不掉也静不了**的声音里，而他此刻多半正需要打电话。
            // 警报的作用是「叫住他」，叫到了就该让位。
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.sirenDuration * 1_000_000_000))
                EmergencyAlarm.stopSiren()
            }
            await resolvePlaceIfPossible()
        }
        .onDisappear { EmergencyAlarm.stopSiren() }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(spacing: 10) {
            // 三条冗余线索里的第二条（第一条是整圈边框，第三条是标题文字本身）——
            // 紧急状态不能只靠红色，色盲用户看不出来。
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(AppColors.destructive)
                .accessibilityHidden(true)
            Text(EmergencySafetyCopy.volunteerAlertTitle(name: peerName))
                .font(.title.weight(.bold))
                .foregroundColor(AppColors.destructive)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(EmergencySafetyCopy.volunteerAlertElapsed(seconds: elapsedSeconds))
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            // ⛔ 这里**没有**设计稿上那句「客服已接入」—— 志愿者端无从知道，
            // 见 `EmergencySafetyCopy` 里 `volunteerAlertLocationUnknown` 上方那段注释。
            Text(EmergencySafetyCopy.volunteerAlertNoDismissNotice)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 位置

    /// 地址 + 「距你多远」。
    ///
    /// 🔴 **距离用分档不用精确值**（`DistanceCalculator.proximityBand`）。这是两台手机
    /// 各自 GPS 读数之差，城市里单台误差就可达十几米。印「距你约 8 米」会让志愿者
    /// 以为对方就在手边、抬头没看见就开始怀疑数据，而真正该做的是往那个方向找。
    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(AppColors.destructive)
                    .accessibilityHidden(true)
                Text(placeText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let distance = distanceText {
                Text(distance)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel([placeText, distanceText].compactMap { $0 }.joined(separator: "，"))
    }

    /// 拿不到就说拿不到，**不编**。这一句会被志愿者转述给 110 —— 一个猜出来的地名
    /// 比没有地名危险得多（与 `EmergencySafetyCopy.locationAnnouncement` 同一条理由）。
    private var placeText: String {
        if let resolvedPlace { return resolvedPlace }
        return didResolvePlace
            ? EmergencySafetyCopy.volunteerAlertLocationUnknown
            : EmergencySafetyCopy.volunteerAlertLocationResolving
    }

    private var distanceText: String? {
        alert.distanceText(from: deviceCoordinate)
    }

    private func resolvePlaceIfPossible() async {
        if let peer = alert.coordinate {
            resolvedPlace = await reverseGeocode(peer.coordinate)
        }
        if resolvedPlace == nil, let orderID = alert.orderID, let response = await serverAddress(orderID) {
            resolvedPlace = EmergencySafetyCopy.volunteerAlertPlace(server: response)
        }
        didResolvePlace = true
    }

    // MARK: 动作

    /// 次要动作：直接打给他。
    ///
    /// 号码经 `EmergencyDialer.telURL`（拦掩码串 + 只取数字位）—— 掩码串若不拦会拼成 `tel://1381234`，
    /// 而空号在界面上看不出任何异常（2026-08-11 的真实缺陷）。
    @ViewBuilder
    private var callButton: some View {
        if let url = EmergencyDialer.telURL(for: peerPhone) {
            Button {
                EmergencyDialer.dial(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill").accessibilityHidden(true)
                    Text(EmergencySafetyCopy.volunteerAlertCallTitle(name: peerName))
                        .font(AppFonts.body().weight(.semibold))
                }
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .overlay(
                    Capsule().strokeBorder(AppColors.textPrimary.opacity(0.85), lineWidth: 1.5)
                )
            }
            // 号码本身**不进这里**：VoiceOver 外放，念全号等于把盲人的号码广播出去。
            // 姓名去掉掩码星号，否则念成「张星号」。
            .accessibilityLabel(
                EmergencySafetyCopy.volunteerAlertCallTitle(name: peerName?.unmaskedForSpeech)
            )
            .accessibilityIdentifier("volunteerEmergencyAlertCall")
        }
    }

    private var acknowledgeBlock: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                EmergencySafetyCopy.volunteerAlertAcknowledgeTitle,
                isDestructive: true,
                isLoading: isAcknowledging,
                action: onAcknowledge
            )
            .accessibilityHint(EmergencySafetyCopy.volunteerAlertAcknowledgeHint)
            .accessibilityIdentifier("volunteerEmergencyAlertAcknowledge")
            Text(EmergencySafetyCopy.volunteerAlertAcknowledgeFootnote)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
