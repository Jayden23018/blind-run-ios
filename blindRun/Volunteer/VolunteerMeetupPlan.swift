import CoreLocation
import Foundation

// MARK: - 陪跑员端「见面安排」的纯判定（#433）
//
// 视觉与文案以视觉稿 v2 为准：`docs/ui/mockups/intro-call-meetup-plan-20261015/index.html`「② 陪跑员端」
// 与「④ 等待、临期与出错」；行为依据 `docs/design/2026-10-15-intro-call-meetup-plan-design.md` §2、§4、§5。
//
// 本文件只放 `(输入) → 值` 的纯逻辑，视图在 `VolunteerMeetupPlanFormView.swift` / `VolunteerIntroCallView.swift`。

// MARK: 表单草稿（V2）

/// V2 正在填的那张单。每个可改项 `nil` = **按原约**，不是「清空」。
struct VolunteerMeetupPlanDraft: Equatable {
    struct Place: Equatable {
        /// 高德 POI 名称。
        let address: String
        /// GCJ-02。来自高德搜索（本来就是 GCJ-02），并且已经过 `BackendCoordinateNormalizer` 那一道单点入口。
        let latitude: Double
        let longitude: Double
    }

    /// 与原约相比改了的项。只有时间、地点算「变更」—— 见面位置与颜色原约里没有，谈不上改。
    enum ChangedItem: Equatable {
        case time
        case place

        var title: String {
            switch self {
            case .time: return "开跑时间"
            case .place: return "集合地点"
            }
        }
    }

    let original: IntroCallOriginalArrangement
    var plannedStart: Date?
    var place: Place?
    var meetSpotNote: String = ""
    var volunteerTopColor: MeetupTopColor?
    var runnerTopColor: MeetupTopColor?

    /// 镜像后端 `app.intro-call.plan-max-relocation-meters`（默认 3000，负责人 2026-10-15 拍板）。
    ///
    /// ⚠️ 与 `AppConstants.Timing.minimumBookingLeadMinutes` 同一性质：后端调整时这里要跟；
    /// 跟不上的那段时间由 422 `INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL` 兜底。
    static let relocationLimitMeters: CLLocationDistance = 3000

    /// 时间选择器的档位（`UIDatePicker.minuteInterval`）。
    static let minuteInterval = 5

    init(original: IntroCallOriginalArrangement) {
        self.original = original
    }

    /// 「修改见面安排」：用上一版预填，陪跑员只改想改的那一项。
    init(original: IntroCallOriginalArrangement, editing plan: IntroCallMeetupPlan?) {
        self.original = original
        guard let plan else { return }
        plannedStart = plan.plannedStartTime
        if let address = plan.startAddress, let lat = plan.startLatitude, let lng = plan.startLongitude {
            place = Place(address: address, latitude: lat, longitude: lng)
        }
        meetSpotNote = plan.meetSpotNote ?? ""
        volunteerTopColor = plan.volunteerTopColor == .unknown ? nil : plan.volunteerTopColor
        runnerTopColor = plan.runnerTopColor == .unknown ? nil : plan.runnerTopColor
    }

    // MARK: 生效值

    var effectiveStart: Date? { plannedStart ?? original.plannedStartTime }

    /// 改了开始时间时**时长默认不变**：结束 = 新开始 + 原时长（与后端「只传开始、按原时长平移」一致）。
    var effectiveEnd: Date? {
        guard let plannedStart, let originalStart = original.plannedStartTime, let originalEnd = original.plannedEndTime else {
            return original.plannedEndTime
        }
        return plannedStart.addingTimeInterval(originalEnd.timeIntervalSince(originalStart))
    }

    var effectiveAddress: String? { place?.address ?? original.startAddress }

    // MARK: 变更

    var timeChanged: Bool {
        guard let plannedStart else { return false }
        return plannedStart != original.plannedStartTime
    }

    /// 同名不同点也算改（与 `IntroCallMeetupPlan.changes` 同一条：坐标挪了就要让跑者听到距离）。
    var placeChanged: Bool {
        guard let place else { return false }
        if place.address != original.startAddress?.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        return (distanceFromOriginal ?? 0) >= 1
    }

    var changedItems: [ChangedItem] {
        [timeChanged ? .time : nil, placeChanged ? .place : nil].compactMap { $0 }
    }

    /// 两点都齐才有值。
    var distanceFromOriginal: CLLocationDistance? {
        guard let place, let lat = original.startLatitude, let lng = original.startLongitude else { return nil }
        return CLLocation(latitude: place.latitude, longitude: place.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    // MARK: 主按钮

    /// 视觉稿 V2：改了东西是「提交跑者确认」+ 下面一行「已变更：开跑时间、集合地点」；
    /// 一项没改是「按原约定提交跑者确认」—— 一个字不改、点一下就能提交是主路径。
    var submitButtonTitle: String {
        changedItems.isEmpty ? "按原约定提交跑者确认" : "提交跑者确认"
    }

    var submitButtonCaption: String? {
        changedItems.isEmpty ? nil : "已变更：" + changedItems.map(\.title).joined(separator: "、")
    }

    // MARK: 见面位置

    var meetSpotNoteCount: Int { meetSpotNote.trimmingCharacters(in: .whitespacesAndNewlines).count }

    /// 超过 30 字：界面挡住提交并说明（`IntroCallPlanRequest` 的注释：超长由界面挡、后端兜，**不静默截断**）。
    ///
    /// 🚩 不在输入框的 setter 里截：中文输入法组字时拼音字母也算进长度，27 个字之后打「baoan」
    /// 会被截成「bao」并打断组字 —— 接近上限时最后两个字打不出来。
    var isMeetSpotNoteTooLong: Bool { meetSpotNoteCount > IntroCallMeetupPlan.meetSpotNoteMaxLength }

    // MARK: 时间范围

    /// 最早可选的开跑时间：现在 + 30 分钟 + **本轮通话窗口剩余**，再向上取到 5 分钟一档。
    ///
    /// 多算一个窗口是契约（`APPOINTMENT_TOO_SOON` 的提前量 = 最小提前量 + 窗口剩余分钟）：
    /// 跑者最晚在窗口最后一刻才确认，那时仍要满足 30 分钟。窗口已过或拿不到时只按 30 分钟算。
    static func earliestStart(now: Date, windowEndsAt: Date?, calendar: Calendar = .aidRunBackend) -> Date {
        let windowRemaining = max(0, windowEndsAt?.timeIntervalSince(now) ?? 0)
        let raw = now.addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60) + windowRemaining)
        return roundedUp(raw, calendar: calendar)
    }

    /// 最晚可选：现在 + 7 天（镜像 `app.order.max-lead-days`）。
    static func latestStart(now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(AppConstants.Timing.maximumBookingLeadDays * 24 * 3600))
    }

    /// 向上取到 `minuteInterval` 一档、秒归零。选择器只能停在整档上，初值不对齐会让绑定值与显示值不一致。
    static func roundedUp(_ date: Date, calendar: Calendar = .aidRunBackend) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let minute = components.minute ?? 0
        let hasRemainder = (components.second ?? 0) > 0 || minute % minuteInterval != 0
        components.second = 0
        components.minute = minute - minute % minuteInterval
        let floored = calendar.date(from: components) ?? date
        return hasRemainder ? floored.addingTimeInterval(TimeInterval(minuteInterval * 60)) : floored
    }

    // MARK: 本地校验

    /// 时间那一块的就地错误。选择器已经挡住了「太早 / 太远」，这里再兜一次（窗口在走，几分钟前合法的值现在可能已经太早），
    /// 并补上选择器挡不住的夜间窗口（判据是整段，与下单页同一个函数）。
    func timeError(now: Date, windowEndsAt: Date?) -> String? {
        guard timeChanged, let start = plannedStart else { return nil }
        if start < Self.earliestStart(now: now, windowEndsAt: windowEndsAt) - TimeInterval(Self.minuteInterval * 60) {
            return IntroCallMeetupCopy.planStartTooSoon
        }
        if start > Self.latestStart(now: now) {
            return VolunteerMeetupPlanCopy.tooFarAhead
        }
        if let end = effectiveEnd, BlindBookingViewModel.overlapsNightWindow(start: start, end: end) {
            return VolunteerMeetupPlanCopy.nightWindow
        }
        return nil
    }

    /// 地点那一块的就地错误：超出 3 公里调整上限。
    var placeError: String? {
        guard placeChanged, let meters = distanceFromOriginal, meters > Self.relocationLimitMeters else { return nil }
        return VolunteerMeetupPlanCopy.tooFarFromOriginal(meters: meters)
    }

    // MARK: 请求体

    /// 没改的项不发（`nil` = 按原约）。只改开始时间时不发结束时间，后端按原时长平移。
    func request() -> IntroCallPlanRequest {
        IntroCallPlanRequest(
            plannedStart: timeChanged ? plannedStart : nil,
            place: placeChanged ? place.map { IntroCallPlanRequest.Place(address: $0.address, latitude: $0.latitude, longitude: $0.longitude) } : nil,
            meetSpotNote: meetSpotNote,
            volunteerTopColor: volunteerTopColor,
            runnerTopColor: runnerTopColor
        )
    }
}

// MARK: 提交失败落在哪一块

/// 后端拒绝时，错误显示在**对应那一块下面**，已填内容保留（视觉稿 ④「陪跑员提交被拦」）。
enum VolunteerMeetupPlanErrorSlot: Equatable {
    case time
    case place
    /// 表单顶部。
    case general
}

struct VolunteerMeetupPlanSubmitError: Equatable {
    let slot: VolunteerMeetupPlanErrorSlot
    let message: String

    /// - Parameter distanceFromOriginal: 超距时就地拼「距原集合地点 8.4 公里，超出 3 公里调整上限。」
    ///   拿不到距离（原约缺坐标）就退回 `IntroCallMeetupCopy.planTooFarFromOriginal`。
    static func make(for error: Error, distanceFromOriginal: CLLocationDistance?) -> Self {
        let code = (error as? APIError)?.errorCode
        switch code {
        case .appointmentInNightWindow:
            return Self(slot: .time, message: VolunteerMeetupPlanCopy.nightWindow)
        case .appointmentTooSoon:
            return Self(slot: .time, message: IntroCallMeetupCopy.planStartTooSoon)
        case .appointmentTooFar:
            return Self(slot: .time, message: VolunteerMeetupPlanCopy.tooFarAhead)
        case .appointmentTooLong, .introCallPlanTimeUnavailable, .volunteerAlreadyEngaged:
            return Self(slot: .time, message: IntroCallMeetupCopy.planSubmitErrorMessage(for: error))
        case .introCallPlanTooFarFromOriginal:
            let message = distanceFromOriginal.map(VolunteerMeetupPlanCopy.tooFarFromOriginal(meters:))
                ?? IntroCallMeetupCopy.planTooFarFromOriginal
            return Self(slot: .place, message: message)
        default:
            return Self(slot: .general, message: IntroCallMeetupCopy.planSubmitErrorMessage(for: error))
        }
    }
}

// MARK: 等跑者确认的摘要（V3）

/// V3 那张摘要卡。改过的项标「已变更」，**不显示跑者听没听、同不同意**。
struct VolunteerMeetupPlanSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
        let isChanged: Bool
        let accessibilityLabel: String
    }

    let rows: [Row]
    /// 头卡小标题用的生效时间与地点（「明天 7:30 · 朝阳公园东门」）。
    let start: Date?
    let address: String?

    static func make(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let changes = plan.changes(from: original)
        let start = plan.plannedStartTime ?? original.plannedStartTime
        let end = plan.plannedEndTime ?? (plan.plannedStartTime == nil ? original.plannedEndTime : shiftedEnd(plan: plan, original: original))
        let address = plan.startAddress ?? original.startAddress
        var rows: [Row] = []

        if let start {
            let value = VolunteerMeetupPlanCopy.timeRange(start: start, end: end, now: now, calendar: calendar)
            let spoken = VolunteerMeetupPlanCopy.spokenTimeRange(start: start, end: end, now: now, calendar: calendar)
            rows.append(Row(
                id: "time", label: "开跑时间", value: value, isChanged: changes.timeChanged,
                accessibilityLabel: ["开跑时间", changes.timeChanged ? "已变更" : nil, spoken].compactMap { $0 }.joined(separator: "，")
            ))
        }
        if let address {
            let value = [address, plan.meetSpotNote].compactMap { $0 }.joined(separator: " · ")
            rows.append(Row(
                id: "place", label: "集合地点", value: value, isChanged: changes.placeChanged,
                accessibilityLabel: ["集合地点", changes.placeChanged ? "已变更" : nil, value.replacingOccurrences(of: " · ", with: "，")]
                    .compactMap { $0 }.joined(separator: "，")
            ))
        } else if let note = plan.meetSpotNote {
            rows.append(Row(id: "place", label: "具体见面位置", value: note, isChanged: false, accessibilityLabel: "具体见面位置，\(note)"))
        }
        if plan.volunteerTopColor != nil || plan.runnerTopColor != nil {
            let mine = VolunteerMeetupPlanCopy.colorName(plan.volunteerTopColor)
            let runner = VolunteerMeetupPlanCopy.colorName(plan.runnerTopColor)
            rows.append(Row(
                id: "colors", label: "上衣颜色", value: "本人 \(mine) · 跑者 \(runner)", isChanged: false,
                accessibilityLabel: "上衣颜色，本人\(mine)，跑者\(runner)"
            ))
        }
        return Self(rows: rows, start: start, address: address)
    }

    /// 后端只平移了开始、没回结束时间时，按原时长补出来（展示用，不发回去）。
    private static func shiftedEnd(plan: IntroCallMeetupPlan, original: IntroCallOriginalArrangement) -> Date? {
        guard let start = plan.plannedStartTime, let os = original.plannedStartTime, let oe = original.plannedEndTime else { return nil }
        return start.addingTimeInterval(oe.timeIntervalSince(os))
    }
}

// MARK: 文案

/// V2 表单与 V3 摘要的界面文案。逐字取视觉稿 v2。
enum VolunteerMeetupPlanCopy {
    static let navigationTitle = "见面安排"
    static let cancel = "取消"
    static let intro = "请填写通话中商定的见面安排。跑者确认后即完成约定；未变更的项目无需修改。"
    static let changedTag = "已变更"
    static let editButton = "修改"
    static let restoreTimeButton = "恢复原定时间"
    static let restorePlaceButton = "恢复原定地点"
    static let timeLabel = "开跑时间"
    static let placeLabel = "集合地点"
    static let meetSpotLabel = "具体见面位置"
    static let meetSpotPlaceholder = "例如：南门保安亭左侧"
    static let volunteerColorLabel = "本人上衣颜色"
    static let runnerColorLabel = "跑者上衣颜色（通话中确认）"
    static let unconfirmedColor = "未确认"
    static let meetSpotTooLong = "具体见面位置最多 \(IntroCallMeetupPlan.meetSpotNoteMaxLength) 个字，请删减。"
    static let greetingReminder = "见面时请主动上前，并告知跑者你的姓氏。"
    static let placeSearchTitle = "选择集合地点"
    static let placeSearchPrompt = "搜索地点名称"
    static let placeSearchButton = "搜索"
    static let placeSearchFailed = "暂时搜不到地点，请换个关键词或稍后再试。"
    static let placeCoordinateInvalid = "这个地点没有可用的位置信息，请换一个。"

    /// 视觉稿 ④ 原话。夜间窗口的判据是整段（与下单同一条）。
    static let nightWindow = "行程时段不得与 22:00–05:00 重叠，请调整时间。"
    /// 不写死「7 天」以外的理由同 `ErrorCode.appointmentTooFar`：选择器已按 7 天挡，这句只在竞态里出现。
    static let tooFarAhead = "这个日期太远了，请改到近一些的日子。"

    /// 视觉稿 ④：「距原集合地点 8.4 公里，超出 3 公里调整上限。」实际距离走 `DistanceCalculator.formattedDistance`
    /// （与「距原地点约 800 米」同一套舍入）；上限是配置值，按整公里说。
    static func tooFarFromOriginal(meters: CLLocationDistance) -> String {
        "距原集合地点 \(DistanceCalculator.formattedDistance(meters))，超出 \(relocationLimitKilometers) 公里调整上限。"
    }

    /// 「3」。
    static var relocationLimitKilometers: String {
        String(format: "%g", VolunteerMeetupPlanDraft.relocationLimitMeters / 1000)
    }

    /// 「原定 7:00 – 8:00」。
    static func originalTimeLine(start: Date?, end: Date?) -> String? {
        guard let start else { return nil }
        return "原定 " + clockRange(start: start, end: end)
    }

    /// 「原定 朝阳公园南门 · 距原地点约 800 米（调整上限 3 公里）」。
    static func originalPlaceLine(address: String?, distance: CLLocationDistance?) -> String? {
        guard let address = address?.nilIfBlank else { return nil }
        guard let distance, distance >= 10 else { return "原定 \(address)" }
        return "原定 \(address) · 距原地点约 \(DistanceCalculator.formattedDistance(distance))（调整上限 \(relocationLimitKilometers) 公里）"
    }

    /// 「明天 7:30 – 8:30」。
    static func timeRange(start: Date, end: Date?, now: Date, calendar: Calendar = .current) -> String {
        "\(IntroCallMeetupCopy.spokenDay(start, now: now, calendar: calendar)) " + clockRange(start: start, end: end)
    }

    /// 读屏版「明天 7 点 30 到 8 点 30」。
    static func spokenTimeRange(start: Date, end: Date?, now: Date, calendar: Calendar = .current) -> String {
        let day = IntroCallMeetupCopy.spokenDay(start, now: now, calendar: calendar)
        let from = IntroCallMeetupCopy.spokenClock(start, calendar: calendar)
        guard let end else { return "\(day) \(from)" }
        return "\(day) \(from) 到 \(IntroCallMeetupCopy.spokenClock(end, calendar: calendar))"
    }

    static func clockRange(start: Date, end: Date?) -> String {
        let clock = DateFormatter.aidRunDisplayClock
        guard let end else { return clock.string(from: start) }
        return "\(clock.string(from: start)) – \(clock.string(from: end))"
    }

    /// 「红色」；没填或认不出是「未确认」。
    static func colorName(_ color: MeetupTopColor?) -> String {
        color?.spokenName ?? unconfirmedColor
    }

    /// 色块上的单字（「红」）。
    static func colorShortName(_ color: MeetupTopColor) -> String {
        String((color.spokenName ?? unconfirmedColor).prefix(1))
    }
}

extension MeetupTopColor {
    /// 陪跑员表单里可选的十种颜色，**排除 `.unknown`**（它是本地兜底值，不是能选的颜色）。
    /// 照 `MeetupTopColor` 注释的约定手写，不遵循 `CaseIterable`。
    static let selectableColors: [MeetupTopColor] = [
        .black, .white, .gray, .red, .orange, .yellow, .green, .blue, .purple, .pink,
    ]
}
