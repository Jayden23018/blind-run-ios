import CoreLocation
import Foundation

// MARK: - 陪跑员订单页 v2 的纯判定
//
// 交付包 `zhumangpao-handoff/02-ios-screens.md`，字段口径以后端对接说明
// `demo/docs/volunteer-order-page-v2-ios-handoff.md` 为准。本文件**不 import SwiftUI**：
// 阶段、头卡文案、求助路由全是 `(订单, 现在) → 值` 的纯函数，用例能穷举。
//
// 与 `VolunteerOrderFlowPresentation` 的分工：那边管**信息行与主按钮**（隐私闸、电话掩码、
// 按状态发哪个动作 —— 50 多条用例钉着），这边只管 v2 新增的头卡与时间判定。

// MARK: 求助路由

/// 陪跑员订单页右上角「求助」按下去去哪（交付包 D1，项目负责人 2026-09-26 拍板全页显示）。
///
/// 与跑者端 `BlindHomeSOSMode.resolve` 同构：云端 SOS **只在 `IN_PROGRESS`**（`AGENTS.md` §6），
/// 其余一律本地拨号，**绝不调 `POST /api/emergency/trigger`**。判据只有 `canVolunteerTriggerEmergency`。
enum VolunteerOrderSOSMode: Equatable {
    /// 现有云端链路（二次确认 → 触发）。
    case cloud
    /// 本地拨号（120 / 110），文案说清「App 不会代你发送求助」。
    case localCall

    static func resolve(status: RunOrderStatus?) -> Self {
        status?.canVolunteerTriggerEmergency == true ? .cloud : .localCall
    }
}

// MARK: 阶段

/// 订单页在哪一格。由服务端状态 + 服务端给的时刻 + 现在推出来，**不存**。
enum VolunteerOrderPhase: Equatable {
    /// `SCHEDULED_CONFIRMED`：先回答「你还去吗」（`confirm-departure`）。
    /// 🚩 与「我出发了」**不是一回事**（`AGENTS.md` §5），交付包的「约好」页没区分这一态。
    case confirmStillGoing
    /// `PENDING_ACCEPT`，还没到 `primaryActionUnlockAt`（或后端没给）：白色次要按钮「我已经出发了」。
    case agreedEarly
    /// `PENDING_ACCEPT`，已到 `primaryActionUnlockAt`：黄色主按钮「我出发了」。
    case agreedSoon
    /// `DRIVER_EN_ROUTE`。`late` **只认 `eta.late`**，客户端不自己拿 delta 判。
    case departed(late: Bool)
    /// `DRIVER_ARRIVED`。`canEndWait` = 已到 `earliestEndWaitAt`。
    case arrived(canEndWait: Bool)
    case completed
    /// `CANCELLED`。结束等待也会落到这一态，但那条路由宿主直接关页，不走这一屏。
    case runnerCancelled

    /// `nil` = 这一态不走 `VolunteerOrderFlowPage`（跑步中有自己的 `VolunteerRunningPage`；邀请、认不出的状态）。
    static func resolve(order: OrderDetailResponse, now: Date) -> Self? {
        switch order.status {
        case .scheduledConfirmed:
            return .confirmStillGoing
        case .pendingAccept:
            guard let unlock = order.primaryActionUnlockAt?.backendTimestamp else { return .agreedEarly }
            return now >= unlock ? .agreedSoon : .agreedEarly
        case .driverEnRoute:
            return .departed(late: order.eta?.late == true)
        case .driverArrived:
            guard let earliest = order.earliestEndWaitAt?.backendTimestamp else { return .arrived(canEndWait: false) }
            return .arrived(canEndWait: now >= earliest)
        case .completed:
            return .completed
        case .cancelled:
            return .runnerCancelled
        case .pendingMatch, .pendingIntroCall, .rematching, .noVolunteer, .inProgress, .unknown:
            return nil
        }
    }

    var ropeState: RopeState {
        switch self {
        case .confirmStillGoing, .agreedEarly, .agreedSoon: return .agreed
        case .departed: return .departed(progress: 0.1)
        case .arrived: return .arrived
        case .completed: return .together
        case .runnerCancelled: return .cancelled(after: .agreed)
        }
    }
}

// MARK: 时间文案

enum VolunteerOrderTimeCopy {
    /// 「6:35」。
    static func clock(_ date: Date) -> String {
        DateFormatter.aidRunDisplayClock.string(from: date)
    }

    /// 「明天早上」「今天下午」「周六早上」（交付包 02 ②：由客户端按开始时间和当前日期生成）。
    static func dayPart(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "今天"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "明天"
        } else {
            let weekday = calendar.component(.weekday, from: date)
            day = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1]
        }
        let hour = calendar.component(.hour, from: date)
        let part: String
        switch hour {
        case ..<11: part = "早上"
        case ..<13: part = "中午"
        case ..<18: part = "下午"
        default: part = "晚上"
        }
        return day + part
    }

    /// 向上取整的分钟数。「还差 30 秒」算 1 分钟 —— 说「0 分钟后出发」是错的。
    static func minutesUntil(_ date: Date, now: Date) -> Int {
        Int((date.timeIntervalSince(now) / 60).rounded(.up))
    }
}

// MARK: 头卡

/// 头卡里要画的全部东西。视图只按它渲染。
struct VolunteerOrderHero: Equatable {
    /// 头卡底色（交付包 v2 C01）。视图按它取 `AppColors.Flow.state*`，这里只管「是哪一种」。
    /// 跑者取消与其他终止状态用约好的藏青；跑步中 / 暂停不走这个页面（V4）。
    enum Style: Equatable { case light, agreed, departed, arrived, done }

    var style: Style = .agreed
    var rope: RopeState
    /// 小标题「已约好 · 明天早上」。
    var eyebrow: String
    /// 主角数字「6:35」「15」「8」。`nil` = 这一态用 `headline` 当主角。
    var number: String?
    var numberSize: FlowV2Fonts.Hero = FlowV2Fonts.heroM
    /// 数字后的单位「出发」「分钟后出发」「分钟后到」。
    var unit: String?
    /// 没有数字时的主角句「李*就在附近」「你和李*第 4 次一起跑」。屏幕上保留掩码。
    var headline: String?
    /// 主角句的读屏版（去掉掩码星号）。
    var headlineSpoken: String?
    /// 快迟到 / 过了建议出发时间：主角数字换金色（交付包 ③b）。
    var isGold = false
    /// 副文，每行一句。
    var lines: [String] = []
    /// 「李*已到集合点附近」胶囊。`nil` = 不出现、不留空位。
    var presence: String?
    /// 头卡下方的暖色提醒条（快迟到）。
    var notice: String?
    /// 出发中追加到绳子读屏标签里的「还有 N 分钟到」。
    var remainingMinutes: Int?

    /// 头卡正文合成一个读屏元素（绳子另算一个）。
    var accessibilityLabel: String {
        var parts = [eyebrow]
        if let number { parts.append([number, unit].compactMap { $0 }.joined()) }
        if let headline { parts.append(headlineSpoken ?? headline) }
        // 副文里也有掩码姓名（「在 3 号入口见李*」），读屏不念星号。
        parts.append(contentsOf: lines.map(\.unmaskedForSpeech))
        if let presence { parts.append(presence.unmaskedForSpeech) }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }
}

extension VolunteerOrderHero {
    /// - Parameters:
    ///   - direction: 汇合页的方位描述（「右前方」），由宿主带滞回算好；`nil` = 拿不到朝向或跑者位置。
    ///   - distanceText: 出发中、还没有 ETA 时的兜底（本机到集合点的距离）。
    static func make(
        order: OrderDetailResponse,
        phase: VolunteerOrderPhase,
        now: Date,
        direction: String? = nil,
        distanceText: String? = nil
    ) -> Self {
        let name = order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName
        let spokenName = order.blindNameForSpeech
        let place = order.startAddress?.nilIfBlank ?? VolunteerOrderFlowCopy.meetingPointUnknown
        let start = order.plannedStart?.backendTimestamp

        switch phase {
        case .confirmStillGoing:
            return Self(
                rope: .agreed,
                eyebrow: "已约好" + (start.map { " · " + VolunteerOrderTimeCopy.dayPart($0, now: now) } ?? ""),
                number: start.map(VolunteerOrderTimeCopy.clock),
                unit: start == nil ? nil : "开跑",
                headline: start == nil ? VolunteerOrderFlowCopy.bookedSubtitle : nil,
                lines: [VolunteerOrderFlowCopy.scheduledSubtitle]
            )

        case .agreedEarly, .agreedSoon:
            return agreed(order: order, phase: phase, now: now, name: name, place: place, start: start)

        case .departed(let late):
            let rope = RopeState.departed(progress: order.eta?.progress ?? 0.1)
            guard let eta = order.eta, let minutes = eta.remainingMinutes else {
                // 出发后还没上报过位置：后端不给 ETA，**不编数字**。
                return Self(
                    style: .departed,
                    rope: rope,
                    eyebrow: "正在赶去 · 骑车",
                    headline: VolunteerOrderFlowCopy.departedTitle,
                    lines: [distanceText].compactMap { $0 },
                    presence: presence(order: order, name: name)
                )
            }
            let arrive = eta.arriveAt?.backendTimestamp.map(VolunteerOrderTimeCopy.clock)
            let delta = eta.deltaVsStartMinutes ?? 0
            let line: String
            if late {
                line = "\(arrive ?? "稍后") 左右到，比约定晚约 \(max(delta, 1)) 分钟"
            } else if delta < 0 {
                line = "预计 \(arrive ?? "按时") 到，比约定早 \(-delta) 分钟"
            } else {
                line = "预计 \(arrive ?? "按时") 到，刚好赶上"
            }
            return Self(
                style: .departed,
                rope: rope,
                eyebrow: "正在赶去 · 骑车",
                number: "\(minutes)",
                numberSize: FlowV2Fonts.heroXL,
                unit: "分钟后到",
                isGold: late,
                lines: [line],
                presence: presence(order: order, name: name),
                notice: late ? "已自动告诉\(name)你会晚到约 \(max(delta, 1)) 分钟" : nil,
                remainingMinutes: minutes
            )

        case .arrived(let canEndWait):
            let bucket = order.meet?.distanceBucket ?? .unknown
            let copy = MeetBucketCopy.make(bucket: bucket, farKm: order.meet?.farDistanceKm, direction: direction)
            return Self(
                style: .arrived,
                rope: .arrived,
                eyebrow: canEndWait ? "等待时间已满" : "已到集合点",
                headline: copy.title(name),
                headlineSpoken: copy.title(spokenName),
                lines: [copy.subtitle]
            )

        case .completed:
            let count = order.completedTogetherCount
            let title: (String) -> String = { who in
                switch count {
                case .some(1): return "你和\(who)第一次一起跑"
                case .some(let n) where n > 1: return "你和\(who)第 \(n) 次一起跑"
                // `nil` = 后端没下发；`0` 在已完成的单上不该出现（本单已计入）。都不编数字。
                default: return "你和\(who)跑完了"
                }
            }
            let distance = (order.actualDistanceMeters ?? 0) > 0
                ? String(format: "%.2f 公里", Double(order.actualDistanceMeters ?? 0) / 1000) : nil
            let duration = (order.actualDurationSeconds ?? 0) > 0
                ? VolunteerOrderFlowCopy.spokenDuration(seconds: order.actualDurationSeconds ?? 0) : nil
            // 交付包 D11：**不显示配速**（不暗示「表现」）。
            let summary = [distance, duration, order.startAddress?.nilIfBlank].compactMap { $0 }.joined(separator: " · ")
            return Self(
                style: .done,
                rope: .together,
                eyebrow: VolunteerOrderFlowCopy.completedTitle,
                headline: title(name),
                headlineSpoken: title(spokenName),
                lines: summary.isEmpty ? [] : [summary]
            )

        case .runnerCancelled:
            return Self(
                rope: .cancelled(after: .agreed),
                eyebrow: "已取消",
                headline: VolunteerOrderFlowCopy.runnerCancelledTitle(name: name),
                headlineSpoken: VolunteerOrderFlowCopy.runnerCancelledTitle(name: spokenName),
                lines: [VolunteerOrderFlowCopy.runnerCancelledSubtitle]
            )
        }
    }

    private static func agreed(
        order: OrderDetailResponse,
        phase: VolunteerOrderPhase,
        now: Date,
        name: String,
        place: String,
        start: Date?
    ) -> Self {
        let eyebrow = "已约好" + (start.map { " · " + VolunteerOrderTimeCopy.dayPart($0, now: now) } ?? "")
        let startClock = start.map(VolunteerOrderTimeCopy.clock)
        // 🚩 四个时刻字段同进同出：陪跑员从没上报过位置时全是 `nil` —— **不编出发时刻**。
        guard let depart = order.suggestedDepartAt?.backendTimestamp else {
            return Self(
                rope: .agreed,
                eyebrow: eyebrow,
                number: startClock,
                unit: startClock == nil ? nil : "开跑",
                headline: startClock == nil ? VolunteerOrderFlowCopy.bookedSubtitle : nil,
                lines: ["在\(place)见\(name)"]
            )
        }
        let departClock = VolunteerOrderTimeCopy.clock(depart)
        let travel = order.travelMinutes.map { "骑车约 \($0) 分钟" }

        if phase == .agreedSoon {
            let minutes = VolunteerOrderTimeCopy.minutesUntil(depart, now: now)
            let line = [departClock + " 出发", travel.map { $0 + "到" + place }].compactMap { $0 }.joined(separator: "，")
            if minutes > 0 {
                return Self(
                    rope: .agreed, eyebrow: eyebrow,
                    number: "\(minutes)", numberSize: FlowV2Fonts.heroL, unit: "分钟后出发",
                    lines: [line]
                )
            }
            let overdue = -minutes
            return Self(
                rope: .agreed, eyebrow: eyebrow,
                headline: overdue == 0 ? "现在出发" : "已过建议出发时间 \(overdue) 分钟",
                isGold: overdue > 0,
                lines: [line]
            )
        }

        var lines = [
            [travel, startClock.map { "\($0) 在\(place)见\(name)" }].compactMap { $0 }.joined(separator: "，")
        ]
        // 交付包 00 §二：提醒时间 = 建议出发前 5 分钟，**取后端的 `departReminderAt`**，不按画板的 6:25。
        if let reminder = order.departReminderAt?.backendTimestamp {
            lines.append("\(VolunteerOrderTimeCopy.clock(reminder)) 会提醒你出发")
        }
        return Self(
            rope: .agreed, eyebrow: eyebrow,
            number: departClock, numberSize: FlowV2Fonts.heroM, unit: "出发",
            lines: lines.filter { !$0.isEmpty }
        )
    }

    /// 只在后端明确说「在」时出现（`runnerAtMeetingPoint == true`）。`false` 与 `nil` 都不出现。
    private static func presence(order: OrderDetailResponse, name: String) -> String? {
        order.runnerAtMeetingPoint == true ? "\(name)已到集合点附近" : nil
    }

    /// 邀请态（派单推送）。白色头卡、虚线绳子。
    static func make(invite presentation: VolunteerOrderFlowPresentation) -> Self {
        Self(
            style: .light,
            rope: .invited,
            eyebrow: VolunteerOrderFlowCopy.inviteTitleFallback,
            number: presentation.title,
            numberSize: FlowV2Fonts.heroS,
            lines: presentation.subtitle.isEmpty ? [] : [presentation.subtitle]
        )
    }
}

// MARK: 汇合距离档位的文案（交付包 02 ④ 表）

struct MeetBucketCopy: Equatable {
    /// 标题带姓名，屏幕用掩码、读屏用去星版，所以是函数。
    let titleTemplate: Template
    let subtitle: String

    enum Template: Equatable {
        case beside, near, notYet, unknown
    }

    func title(_ name: String) -> String {
        switch titleTemplate {
        case .beside: return "\(name)就在你身边"
        case .near: return "\(name)就在附近"
        case .notYet: return "\(name)还没到集合点"
        case .unknown: return "暂时看不到\(name)的位置"
        }
    }

    /// - Parameter direction: 「右前方」。`nil` 时只说距离档位，**不编方位**。
    static func make(bucket: DistanceBucket, farKm: Double?, direction: String?) -> Self {
        func within(_ range: String) -> String {
            direction.map { "在你\($0)，\(range)" } ?? range
        }
        switch bucket {
        case .within10: return Self(titleTemplate: .beside, subtitle: within("10 米以内"))
        case .within50: return Self(titleTemplate: .near, subtitle: within("大约 50 米以内"))
        case .within100: return Self(titleTemplate: .near, subtitle: within("大约 100 米以内"))
        case .far:
            let km = farKm.map { String(format: "%.1f", $0) }
            return Self(titleTemplate: .notYet, subtitle: km.map { "对方的手机在 \($0) 公里外" } ?? "对方离集合点还比较远")
        case .unknown:
            return Self(titleTemplate: .unknown, subtitle: "可以让对方的手机响起来，或者打电话")
        }
    }

    /// 方位盘画不画扇形：只有三个「附近」档位才有意义（交付包 02：`FAR` / `UNKNOWN` 隐藏）。
    static func showsDirection(for bucket: DistanceBucket) -> Bool {
        switch bucket {
        case .within10, .within50, .within100: return true
        case .far, .unknown: return false
        }
    }
}

// MARK: 汇合页方位（交付包 02 ④、03 §三）

/// 跑者在你哪一边。本机坐标是 WGS-84、跑者坐标是后端 GCJ-02 —— **先把本机转过去再算方位角**，
/// 否则两套坐标差出的几百米会让近距离的方位整个指反。
struct MeetDirection: Equatable {
    /// 相对角度 = 方位角 − 朝向，(−180, 180]，右为正。
    let relativeDegrees: Double
    /// 带滞回的描述（「右前方」）。
    let sector: DirectionSector
    let sectorWidth: Double

    /// `nil` = 不画扇形、不说方位：`FAR` / `UNKNOWN`、拿不到朝向、本机或跑者位置缺一个。
    static func make(
        device: CLLocationCoordinate2D?,
        runner: LocatedCoordinate?,
        runnerAccuracyMeters: Double?,
        heading: Double?,
        bucket: DistanceBucket,
        previous: DirectionSector?
    ) -> Self? {
        guard MeetBucketCopy.showsDirection(for: bucket),
              let device, let runner, let heading,
              let here = BackendCoordinateNormalizer.normalize(
                LocatedCoordinate(coordinate: device, system: .wgs84Device)
              ),
              let there = BackendCoordinateNormalizer.normalize(runner) else { return nil }
        let bearing = DirectionSector.bearing(from: here.coordinate, to: there.coordinate)
        let relative = DirectionSector.normalized(bearing - heading)
        let distance = CLLocation(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
            .distance(from: CLLocation(latitude: there.coordinate.latitude, longitude: there.coordinate.longitude))
        return Self(
            relativeDegrees: relative,
            sector: DirectionSector.describe(relativeDegrees: relative, previous: previous),
            // 精度未知按 0 算 ⇒ 落在最小宽度 60°。
            sectorWidth: DirectionDialGeometry.sectorWidth(
                accuracyMeters: runnerAccuracyMeters ?? 0,
                distanceMeters: distance
            )
        )
    }

    /// 读屏播报的最小间隔（交付包 03 §三，沿用 v3）。
    static let announcementInterval: TimeInterval = 3
}
