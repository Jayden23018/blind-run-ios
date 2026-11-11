import Foundation

// 约跑的模型类型。原来与旧四步表单 `BlindBookingView` 同文件；#810 删掉表单界面后，
// 这些类型仍被 `BlindBookingViewModel`、`BlindMatchFirstBookingView` 和 `VoiceOrderWizard` 用到，所以单独留下。
// 语音下单的逻辑保留（负责人 2026-11-06：界面先删，以后可能按需加回）。

// MARK: - Booking Option Types

enum BookingDurationOption: Int, CaseIterable, Identifiable {
    case none = 0
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "不填写"
        case .fifteen: return "15 分钟"
        case .thirty: return "30 分钟"
        case .fortyFive: return "45 分钟"
        case .sixty: return "1 小时"
        case .ninety: return "1.5 小时"
        case .oneTwenty: return "2 小时"
        }
    }

    var minutes: Int? {
        rawValue == 0 ? nil : rawValue
    }
}

/// 预约时间过不了的三种原因。文案集中在这里，是为了让「提示行 / 步骤阻断语 / 语音摘要」
/// 三处说的是同一句话 —— 它们此前各写各的，其中两处把 30 分钟硬编码进了句子。
enum BookingTimeProblem: Equatable {
    case tooSoon
    case tooFar
    case nightWindow

    var message: String {
        switch self {
        case .tooSoon:
            // 数字取自常量，与 `minimumAppointmentTime` 同源 —— 写死会在后端调整提前量时变成假话。
            return "当前选择的时间太近了，请改到 \(AppConstants.Timing.minimumBookingLeadMinutes) 分钟以后。"
        case .tooFar:
            return "最多只能约 \(AppConstants.Timing.maximumBookingLeadDays) 天以内的时间，请改到近一些的日子。"
        case .nightWindow:
            // 🚨 必须说清判据是**整段**。只说「这个时间不能约」的话，21 点出发的用户会认为
            // 自己没碰到 22 点，把开始时间往前挪一点再试 —— 而真正越界的是结束时间。
            //
            // 时刻从常量取（同 `.tooSoon` / `.tooFar`），不写死在句子里：后端改窗口时
            // 写死的那两个数会变成骗人的话，而这条与本文件早就写着的
            // 「写死 30 会在后端调整提前量时变成一句骗人的话」是同一条理由。
            // 念「晚上10点 / 早上5点」而不是 `22:00` / `05:00`：这段要过 TTS，
            // 念钟点比念数字冒号稳，所以只取小时数、自己拼成钟点。
            let start = AppConstants.Timing.nightWindowStartHour
            let end = AppConstants.Timing.nightWindowEndHour
            return "晚上\(start - 12)点到次日早上\(end)点不安排陪跑，"
                + "请改到白天，或缩短时长在晚上\(start - 12)点前结束。"
        }
    }
}

struct BookingReviewItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

// MARK: - Booking Gate

/// `POST /api/orders` 的硬门槛，枚举顺序即「第一个可操作的缺失项」的播报顺序。
///
/// 服务端门槛的唯一真源是 `OrderCreationService.createOrder`：无紧急联系人 → 403 `EMERGENCY_CONTACT_REQUIRED`。
/// 2026-11-05 起不再校验实名（#767，后端 blind-run-backend#924）。
/// 2026-11-06 起昵称不再是门槛（#789）：App Store 审核指南 5.1.1(x) 要求姓名类信息可选、
/// 功能不以它为条件。没昵称时求助短信与陪跑员端的称呼由后端兜底（blind-run-backend#929）。
///
/// ⚠️ **定位权限被拒不在这里，这是刻意的。** 2026-08-18 之前它是第四道门槛，拒绝定位后
/// 整个出发地点区块被权限提示顶掉（搜索框、常用地点、语音输入全不渲染），`canSubmit` 恒 false ——
/// 也就是关掉定位等于 App 的核心功能不可用。Apple 审核指南 **5.1.1(iv)** 举的例子与这个场景
/// 逐字吻合：拒绝定位后应当提供手动输入地址的替代路径。高德 POI 搜索本来就不需要定位权限
/// （`searchPlaces` 只依赖 `placeSearchProvider`），那条替代路径一直存在，只是被这道门槛藏起来了。
///
/// 拿掉门槛**不等于**当作没事：定位关着会真的降级两件事（陪跑中志愿者看不到实时位置、
/// 云端求助拿不到坐标会发不出去，见 `EmergencyCoordinator.allowsSubmissionWithoutLocation`），
/// 所以改成**可听可见的降级告知**而不是拦截 —— `BlindBookingViewModel.locationDegradationNotice(isDenied:)`。
/// 志愿者侧的「无定位不接单」没有动：那一侧的实时位置是服务本体，不是可替代的输入。
enum BlindBookingGate: Equatable {
    case emergencyContacts
    case startPoint
    case appointmentTime

    static func firstMissing(
        hasValidEmergencyContacts: Bool,
        hasStartPoint: Bool,
        isAppointmentTimeValid: Bool
    ) -> BlindBookingGate? {
        if !hasValidEmergencyContacts { return .emergencyContacts }
        if !hasStartPoint { return .startPoint }
        if !isAppointmentTimeValid { return .appointmentTime }
        return nil
    }

    /// 要去别的页面补的项（现在只有紧急联系人）。补它的入口是约跑前的门页（#805，`BlindBookingEmergencyContactGate`）。
    static let setupGates: [BlindBookingGate] = [.emergencyContacts]

    /// 这句话是不是上面某一项的缺失说明。补齐回来时据它撤掉留在屏幕上的旧句子。
    static func isSetupMessage(_ text: String) -> Bool {
        setupGates.contains { $0.message == text }
    }

    /// 展示与朗读共用的缺失说明。
    var message: String {
        switch self {
        case .emergencyContacts:
            // 正常路径到不了这里：缺联系人时点「预约新的陪跑」先进门页（#805，`BlindBookingEmergencyContactGate`）。
            // 只在门页放行后又不齐时兜底，所以指回门页的入口，不指「本页」（约跑页上没有补的入口）。
            return "约跑前还要设好紧急联系人：至少 1 位，并设其中 1 位为主联系人。请返回首页，再点「预约新的陪跑」去设。"
        case .startPoint:
            return "请选择出发地点。"
        case .appointmentTime:
            // 只是兜底：要说「具体哪里不行」走 `BlindBookingViewModel.message(for:)`，它读 `appointmentTimeProblem`。
            return "预约时间需至少在 \(AppConstants.Timing.minimumBookingLeadMinutes) 分钟后。"
        }
    }
}
