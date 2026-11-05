import Combine
import CoreLocation
import SwiftUI
// 长按结束那枚按钮要的触觉强度与读屏播报（`VolunteerFinishLongPressButton`）。
import UIKit

// MARK: - Volunteer Shared Models

struct VolunteerServiceRecord: Identifiable {
    let order: OrderDetailResponse

    var id: Int64 { order.orderId }
    var sortKey: String { order.createdAt ?? order.plannedStart ?? "" }

    // 这里此前是 `pointsText`，值恒为「+100 积分」——后端从来没有过积分字段，
    // 那个数字是客户端凭 `status == .completed` 现编的，还被念进了下面这条 label。
    // 真实的服务量在「服务成就」页（`VolunteerServiceRecognitionView`），
    // 来自 `GET /api/volunteer/achievements`。
    ///
    /// 姓名走 `unmaskedForSpeech`：这条字符串**只进读屏**，可见那份在行里另有一份。
    var accessibilityLabel: String {
        "时间：\(sortKey.displayDateTime)，盲人：\(order.blindName?.unmaskedForSpeech ?? "")，地点：\(order.startAddress ?? "")，状态：\(order.status.displayName)"
    }
}

// MARK: - Shared Guards and Helpers

extension VolunteerOrderActionGuard {
    static func acceptBlockMessage(
        profile: VolunteerProfileResponse?,
        registrationStatus: VolunteerRegistrationStatus? = nil,
        locationAuthorized: Bool
    ) -> String? {
        if let message = acceptBlockMessage(profile: profile, registrationStatus: registrationStatus) {
            return message
        }
        guard locationAuthorized else {
            return "需要开启定位权限才能接单"
        }
        return nil
    }
}

extension RunOrderStatus {
    var volunteerDescription: String {
        switch self {
        case .pendingMatch:
            return "可接订单"
        // 中性、不归因：志愿者同样不该被告知自己是「第几个候选人」。
        case .pendingIntroCall:
            return "等待与跑者通话确认"
        // 说清**还没到点**，否则志愿者会以为现在就该出发。「请确认」那半句留给动作按钮，
        // 不写进状态名 —— 状态名会出现在列表、卡片、读屏 label 里，那些地方带一个祈使句是噪音。
        case .scheduledConfirmed:
            return "已接单，等出发前确认"
        case .pendingAccept:
            return "已接单，请前往约定地点"
        case .inProgress:
            return "服务进行中"
        case .driverEnRoute:
            return "正在前往约定地点"
        case .driverArrived:
            return "已到达，可开始服务"
        case .completed:
            // 不再说「获得 +100 积分」：后端没有积分字段，那个数字是编的。
            // 但也不能只剩「服务完成」——这是志愿者跑完一趟唯一的正反馈，
            // 把承诺删掉不该连同反馈一起删掉。一句感谢不涉及任何数字，零成本且是真的。
            return "服务完成，感谢你的陪伴"
        case .cancelled:
            return "订单已取消"
        case .rematching:
            return "订单正在重新匹配"
        case .noVolunteer:
            return "暂无志愿者"
        case .unknown:
            return "订单状态有更新，请刷新页面"
        }
    }

    var serviceStageTitle: String {
        switch self {
        // 单独一档：这一态的阶段目标既不是「前往」也不是「等待接单」，是「确认你还去」。
        case .scheduledConfirmed:
            return "确认这次预约"
        case .pendingAccept, .driverEnRoute:
            return "前往出发地点"
        case .driverArrived:
            return "已到达集合地点"
        case .inProgress:
            return "服务进行中"
        case .completed:
            return "行程结算"
        case .cancelled:
            return "订单已取消"
        case .rematching, .noVolunteer:
            return "订单异常"
        case .pendingMatch:
            return "等待接单"
        case .pendingIntroCall:
            return "通话确认"
        case .unknown:
            return "订单状态未知"
        }
    }

    var volunteerServiceDisplayName: String {
        switch self {
        case .pendingAccept:
            return "待出发"
        default:
            return displayName
        }
    }

    var serviceStageSubtitle: String {
        switch self {
        // 🚨 **不写「距开跑还有 X 小时要确认」**：那个提前量是后端配置
        // （`app.order.departure-confirm-window-minutes`），客户端读不到，写死就是编一个数字。
        // 只说清后果（不确认会转给别人），因为那是他真正需要知道的。
        case .scheduledConfirmed:
            return "这次陪跑还没到时间。出发前请确认你还会去，未确认的订单将转给其他陪跑员"
        case .pendingAccept:
            return "请确认当前位置和出发地点，可使用外部地图步行导航"
        case .driverEnRoute:
            return "请按导航前往出发地点，盲人跑者正在等待"
        case .driverArrived:
            return "已到达集合地点，请点击开始服务，服务开始前不能结束订单"
        case .inProgress:
            return "完成本次陪跑后可结束服务"
        case .completed:
            return "感谢你的陪伴"
        case .cancelled:
            return "本次服务已取消"
        case .rematching, .noVolunteer:
            return "本次服务已结束"
        case .pendingMatch:
            return "订单尚未进入服务流程"
        case .pendingIntroCall:
            return "跑者会打电话给你，聊完双方都说合适才算接单"
        case .unknown:
            return "当前状态无法识别，请刷新后再操作"
        }
    }
}

/// 订单页兜底那一屏显示什么（`VolunteerInServiceView.fallbackContent`）。
enum VolunteerOrderFallback: Equatable {
    case loading
    case message(title: String, message: String)

    static let loadingTitle = "正在获取订单状态..."

    /// `status == nil` = 手上还没有订单。有订单时不看 `errorMessage`：那是某次操作的失败，不是这一屏的内容。
    static func resolve(status: RunOrderStatus?, errorMessage: String?) -> Self {
        if let status {
            return .message(title: status.serviceStageTitle, message: status.serviceStageSubtitle)
        }
        guard let errorMessage else { return .loading }
        // 轮询没有停（`startPolling` 的循环不看成败），所以「会自动重试」是真的。
        return .message(title: errorMessage, message: "页面会自动重试，也可以先返回")
    }
}

func orderCoordinate(_ order: OrderDetailResponse) -> CLLocationCoordinate2D? {
    guard let lat = order.startLatitude, let lng = order.startLongitude else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

func externalNavigationRequest(
    for order: OrderDetailResponse,
    currentLocation: CLLocationCoordinate2D?,
    locationAuthorized: Bool
) -> ExternalMapNavigationRequest? {
    guard let destination = orderCoordinate(order) else { return nil }
    return ExternalMapNavigationRequest(
        originCoordinate: locationAuthorized ? currentLocation : nil,
        originName: "我的位置",
        destinationCoordinate: destination,
        destinationName: (order.startAddress?.nilIfBlank ?? "出发地点")
    )
}

// MARK: - Order Detail

enum VolunteerOrderActionError: Error {
    case timedOut
}

enum VolunteerOrderTransitionState: Equatable {
    case idle
    case submitting(target: RunOrderStatus)
    case awaitingConfirmation(target: RunOrderStatus)
    case confirmationDelayed(target: RunOrderStatus)
    case failed(message: String)

    var targetStatus: RunOrderStatus? {
        switch self {
        case .submitting(let target),
             .awaitingConfirmation(let target),
             .confirmationDelayed(let target):
            return target
        case .idle, .failed:
            return nil
        }
    }

    var blocksDuplicateSubmission: Bool {
        switch self {
        case .submitting, .awaitingConfirmation, .confirmationDelayed:
            return true
        case .idle, .failed:
            return false
        }
    }

    var message: String? {
        switch self {
        case .idle, .submitting, .failed:
            return nil
        case .awaitingConfirmation:
            return "操作已提交，状态待确认。页面其他功能仍可使用。"
        case .confirmationDelayed:
            return "状态确认延迟，请稍后点击“重新确认状态”。请勿重复提交同一操作。"
        }
    }
}

extension RunOrderStatus {
    func satisfiesVolunteerTransition(target: RunOrderStatus) -> Bool {
        if self == target { return true }
        switch target {
        case .pendingAccept:
            return [.driverEnRoute, .driverArrived, .inProgress, .completed].contains(self)
        case .driverEnRoute:
            return [.driverArrived, .inProgress, .completed].contains(self)
        case .driverArrived:
            return [.inProgress, .completed].contains(self)
        case .inProgress:
            return self == .completed
        case .rematching:
            return [.cancelled, .noVolunteer].contains(self)
        case .completed:
            return false
        case .pendingMatch, .cancelled, .noVolunteer:
            return false
        // 通话磨合不是志愿者的状态机动作（它由双方表态驱动），永远不会是这里的目标状态。
        case .pendingIntroCall:
            return false
        // 同理：确认出发的**目标**是 `.pendingAccept`，没有任何志愿者动作以这一态为目标。
        // （它是接单那一刻由后端按「距开跑多远」决定的，客户端不驱动。）
        case .scheduledConfirmed:
            return false
        // `.unknown` 只可能来自解码兜底，永远不会是志愿者操作的目标状态。
        case .unknown:
            return false
        }
    }
}

func withVolunteerOrderActionDeadline<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @concurrent @Sendable () async throws -> T
) async throws -> T {
    do {
        return try await HomeLoadCoordinator.run(
            timeout: TimeInterval(nanoseconds) / 1_000_000_000,
            operationName: "volunteer-order-transition",
            operation: operation
        )
    } catch HomeLoadCoordinatorError.timedOut {
        throw VolunteerOrderActionError.timedOut
    }
}
