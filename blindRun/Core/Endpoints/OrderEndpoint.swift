//
//  OrderEndpoint.swift
//  blindRun
//
//  订单片用到的全部端点。形状照 `AuthEndpoint`。
//

import Foundation

/// 订单片（下单 · 状态流转 · 通话磨合 · 评价 · 行程分享 · 派单）的全部端点。
///
/// **一个 case 一条完整字面量路径**，不许拼接 —— `scripts/validate-spec-coverage.mjs`
/// 只认字符串字面量，拼出来的路径它扫不到，于是这条端点就再也不会跟后端契约对撞。
/// 带参数的写成插值（`"/api/orders/\(orderId)"`），脚本会归一成 `{param}`。
///
/// 两族端点**不在这里重写路径**，转发给它们原有的枚举：
/// `KeepWaitingEndpoint`（`OrderDisplayHelpers.swift`）与 `IntroCallEndpoint`
/// （`IntroCallModels.swift`）本来就是为了让路径可被静态扫描才写成枚举的。
/// 在这里抄第二遍等于制造一个必然过期的第二源 —— 那两个文件里的注释写的就是这条理由。
/// 这里只补它们缺的那一半：HTTP 方法。
enum OrderEndpoint {
    // 下单与查询
    case create
    case mine
    /// 盲人端冷启动 / 断线重连的活跃订单恢复。**与 `.mine` 不是一回事** ——
    /// 那条是分页历史列表，靠客户端 filter + sort 猜哪条还活着；这条由服务端判。
    case active
    case detail(orderId: Int64)

    // 状态流转（`POST /api/orders/{orderId}/{action}`，见 AGENTS.md §5）
    case cancel(orderId: Int64)
    case respond(orderId: Int64)
    case enRoute(orderId: Int64)
    case arrived(orderId: Int64)
    case startService(orderId: Int64)
    case finish(orderId: Int64)

    /// 跨天预约单的临期闸门：志愿者表示「我还会去」，`SCHEDULED_CONFIRMED → PENDING_ACCEPT`。
    ///
    /// 🚩 **与 `enRoute` 不是一回事，别合并**（后端 `api_spec.yaml` 的 operation description 逐字写着）：
    /// 这一步只回答「你还去吗」，人可能还在家里；`/en-route` 是真的动身了、开始双向推位置了。
    /// 合并会让位置互推提前几小时打开，而那期间双方并不需要找到对方。
    case confirmDeparture(orderId: Int64)

    // 评价与状态记录
    case review(orderId: Int64)
    case reviews(orderId: Int64)
    case statusLogs(orderId: Int64)

    // 行程实时分享
    case startLiveShare(orderId: Int64)
    case stopLiveShare(orderId: Int64)

    // 陪跑途中的位置兜底（盲人侧读志愿者位置）
    case volunteerLocation

    // 志愿者派单
    case dispatchSummary
    case dispatchStatus

    /// 延长等待窗口。两条前置状态互斥的端点由 `RunOrderStatus.keepWaitingEndpoint` 选。
    case keepWaiting(KeepWaitingEndpoint, orderId: Int64)

    /// 接单前通话磨合的四条端点。角色不对称由 `IntroCallEndpoint` 的注释说明。
    case introCall(IntroCallEndpoint, orderId: Int64)

    var request: EndpointRequest {
        switch self {
        case .create:
            return EndpointRequest(.post, "/api/orders")
        case .mine:
            return EndpointRequest(.get, "/api/orders/mine")
        case .active:
            return EndpointRequest(.get, "/api/orders/active")
        case .detail(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)")
        case .cancel(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/cancel")
        case .respond(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/respond")
        case .enRoute(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/en-route")
        case .arrived(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/arrived")
        case .startService(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/start-service")
        case .finish(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/finish")
        case .confirmDeparture(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/confirm-departure")
        case .review(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/review")
        case .reviews(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)/reviews")
        case .statusLogs(let orderId):
            return EndpointRequest(.get, "/api/orders/\(orderId)/status-logs")
        case .startLiveShare(let orderId):
            return EndpointRequest(.post, "/api/orders/\(orderId)/share")
        case .stopLiveShare(let orderId):
            return EndpointRequest(.delete, "/api/orders/\(orderId)/share")
        case .volunteerLocation:
            return EndpointRequest(.get, "/api/blind/volunteer-location")
        case .dispatchSummary:
            return EndpointRequest(.get, "/api/volunteer/dispatch-summary")
        case .dispatchStatus:
            return EndpointRequest(.put, "/api/volunteer/dispatch-status")
        case .keepWaiting(let endpoint, let orderId):
            // ⚠️ 这两条都是 `PUT`，与其余走 `POST` 的状态流转端点不同族。
            return EndpointRequest(.put, endpoint.path(orderId: orderId))
        case .introCall(let endpoint, let orderId):
            let path = endpoint.path(orderId: orderId)
            switch endpoint {
            case .view:
                return EndpointRequest(.get, path)
            case .decision, .unreachable, .notifyIncoming:
                return EndpointRequest(.post, path)
            }
        }
    }
}
