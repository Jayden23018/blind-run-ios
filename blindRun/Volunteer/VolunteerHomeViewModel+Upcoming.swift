import SwiftUI

// MARK: - 接下来要去的单（`PENDING_ACCEPT` / `SCHEDULED_CONFIRMED`）

extension VolunteerHomeViewModel {
    /// 客户端这一侧认哪几个状态算「接下来要去的单」。
    ///
    /// 🚩 **两态都要，缺一个就是一个黑洞。** `SCHEDULED_CONFIRMED` 是还没临期确认的跨天单，
    /// `PENDING_ACCEPT` 是确认完、等着按「我出发了」的那一单 —— 后者此前两个数据源都取不到。
    ///
    /// ⚠️ 这里**不是**「志愿者眼里的活跃订单」那个更宽的白名单
    /// （`RunOrderStatus.isActiveForVolunteer`，含 `DRIVER_EN_ROUTE` 等三态）：
    /// 那三态由后端 `dispatch-summary.activeOrders` 承担，两边重复取会让同一单
    /// 既出现在深蓝卡又出现在「之后还有 N 次」里。
    static let upcomingVolunteerStatuses: Set<RunOrderStatus> = [.scheduledConfirmed, .pendingAccept]

    /// 两条请求的结果合并后落进 `scheduledOrders`。
    ///
    /// 🚨 **失败时不清空已有列表**：预约区块上挂着一个 60 分钟到期的确认动作，
    /// 一次网络抖动把整块抹掉，志愿者就会以为那张单已经没了、不必再管它 ——
    /// 而后端那边计时照走。失败只留一句说明，列表保持上一次的内容。
    ///
    /// 🚩 **两条都失败才算失败。** 一条回来了就按回来的那部分渲染 —— 半份列表
    /// 也比「暂时没有约好的陪跑」诚实，后者是一句**关于事实的断言**。
    ///
    /// ⚠️ 服务端返回的顺序是 `createdAt` 倒序（`OrderController.getMyOrders` 写死的），
    /// 这里按 `plannedStart` 重排成升序：这一块回答的是「下一件事什么时候」，
    /// 不是「我什么时候接的单」。缺 `plannedStart` 的排最后而不是丢掉。
    func applyUpcoming(
        scheduled: Result<PagedOrderResponse, Error>,
        pendingAccept: Result<PagedOrderResponse, Error>
    ) {
        let pages = [scheduled, pendingAccept].compactMap { try? $0.get() }
        if !pages.isEmpty {
            // 同一单**不可能**同时出现在两条响应里（一个订单只有一个状态），
            // 但按 orderId 去一次重是防后端某天放宽 status 语义时悄悄出现两张卡。
            var seen = Set<Int64>()
            scheduledOrders = pages
                .flatMap(\.content)
                .filter { Self.upcomingVolunteerStatuses.contains($0.status) && seen.insert($0.orderId).inserted }
                .sorted { ($0.plannedStart ?? "\u{FFFF}") < ($1.plannedStart ?? "\u{FFFF}") }
        }
        switch (scheduled, pendingAccept) {
        case (.success, _), (_, .success):
            scheduledOrdersMessage = nil
        case (.failure, .failure):
            ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-scheduled-orders")
            // 🚨 **列表空时也要说话。** 早先这里是 `guard !scheduledOrders.isEmpty else { return }`，
            // 于是首次加载失败时既不渲染区块、也不设提示 —— 志愿者看到的与「我没有预约单」
            // 一模一样，而他可能正有一张单在倒计时。判据是「这个失败态下屏幕上会**多**出什么」，
            // 当时的答案是「什么都不多」，那就是静默失败。
            scheduledOrdersMessage = scheduledOrders.isEmpty
                ? "预约列表加载失败，如果你有还没到时间的预约，请下拉刷新再看一次。"
                : "预约列表刷新失败，显示的是上一次的内容。"
        }
    }

    /// 临期确认「我还会去」（`SCHEDULED_CONFIRMED → PENDING_ACCEPT`）。
    ///
    /// 🚩 **成功后必须把他带进服务页，不能只把卡片移除。**
    /// 确认之后订单是 `PENDING_ACCEPT`，**不在「当前订单」里**（后端
    /// `VolunteerService.loadActiveOrders` 的白名单只有陪跑中那三态）；预约区块下一次刷新
    /// 才会把它画成「打开订单页」那张卡（`upcomingVolunteerStatuses`，#457）⇒ 只移除卡片的话，
    /// 他刚确认完要等一轮刷新、再自己点进去，才找得到下一步「我已出发」。
    ///
    /// 复用派单接单后那条既有的导航（`acceptedDispatchOrderId` + `navigationDestination`），
    /// 不另起一套：两者要去的是同一个页面、同一个状态。
    func confirmScheduledDeparture(orderID: Int64) async {
        let order = scheduledOrders.first { $0.orderId == orderID }
        let confirmed = await submitScheduled(
            orderID: orderID,
            successSpeech: "已确认，到时间请按约定前往。"
        ) { orders in
            try await orders.confirmDeparture(orderId: orderID)
            return nil
        }
        guard confirmed else { return }
        // 带上手里这份详情当初值，服务页就不必空着等第一次 GET 回来。
        acceptedDispatchInitialOrder = order?.replacingStatus(with: .pendingAccept)
        acceptedDispatchOrderId = orderID
    }

    /// 预约区块里已确认（`PENDING_ACCEPT`）那张卡的主按钮（#457）：走同一条导航去订单页，
    /// 「我出发了」在那里。不再调 `confirm-departure` —— 这一态它只会 409。
    func openUpcomingOrder(_ order: OrderDetailResponse) {
        acceptedDispatchInitialOrder = order
        acceptedDispatchOrderId = order.orderId
    }

    /// 「我去不了」（走取消端点，订单转 `REMATCHING` 回到派单池）。
    ///
    /// 与确认共用同一条提交路径，**刻意不做得更难** —— 释放做得难只会把 no-show 从
    /// 「提前告知」变成「当天失联」，那对盲人差得多（`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.1）。
    /// 二次确认在 View 上（`confirmationDialog`），因为它不可逆：抢不回同一个盲人。
    func releaseScheduledOrder(orderID: Int64) async {
        // 🚩 **不说「会转给其他志愿者」**：后端 `enterRematching` 在重匹次数达上限时是直接
        // 置 `CANCELLED` 而不是重派（`OrderLifecycleService`），那时这句话就是假的。
        // 只说他自己那一半 —— 那一半永远为真。
        _ = await submitScheduled(orderID: orderID, successSpeech: "已告知系统你无法参加，此订单已解除。") { orders in
            // 「已记一次临时取消」以响应为准（后端 #361）。这条路径没有 WebSocket 抢先播报，直接接在成功那一句后面。
            VolunteerCancelAnnouncement.suffix(for: try await orders.cancel(orderId: orderID))
        }
    }

    /// 两个动作共用的提交路径。返回**这次提交是不是真的成功了**（调用方据此决定要不要导航）。
    ///
    /// 成功与 409 都从列表移除：两种情况下这一单都不再是「待你确认的预约」。
    ///
    /// `operation` 返回接在 `successSpeech` 后面的一句（`nil` / 空串 = 不接），
    /// 用于只有响应才知道的事 —— 目前只有「已记一次临时取消」。
    private func submitScheduled(
        orderID: Int64,
        successSpeech: String,
        operation: @escaping @MainActor (any OrderServing) async throws -> String?
    ) async -> Bool {
        guard submittingScheduledOrderID == nil, let appState else { return false }
        submittingScheduledOrderID = orderID
        scheduledOrdersMessage = nil
        defer { submittingScheduledOrderID = nil }
        do {
            let followUp = try await operation(appState.orders) ?? ""
            scheduledOrders.removeAll { $0.orderId == orderID }
            scheduledOrdersChangedLocallyAt = Date()
            speechService?.speak(successSpeech + followUp)
            return true
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return false }
            // 409 `ORDER_STATUS_NOT_ALLOWED`：订单已经不在 `SCHEDULED_CONFIRMED` 上了。
            //
            // 🚨 **不许断言是哪一种。** 至少三种成因，客户端一个都分不出：
            // 闸门已经把它退回重新匹配、盲人取消了、以及**上一次其实已经提交成功**
            // （请求到了服务端、响应在回来的路上丢了，用户以为没成功又点了一次）。
            // 早先这里写死「这一单已经转给其他志愿者了」——在第三种情况下那是句假话，
            // 而且紧跟着把卡片删掉，他从此在首页上再也看不到一张仍在自己名下的单。
            // 现在这句话对三种成因**都为真**，且给出的下一步（不用再确认）也都对。
            if case .serverError(let response) = error, response.errorCode == .invalidOrderStatus {
                scheduledOrders.removeAll { $0.orderId == orderID }
                scheduledOrdersChangedLocallyAt = Date()
                let message = "此订单的状态已经变了，不用再确认。可以到「近期服务」里看它现在怎么样。"
                scheduledOrdersMessage = message
                speechService?.speakError(message)
                return false
            }
            scheduledOrdersMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return false
        } catch {
            let message = "操作没有成功，请重试。"
            scheduledOrdersMessage = message
            speechService?.speakError(message)
            return false
        }
    }

    /// 派单摘要带回来的 `upcomingOrders`（#471）：直接当预约列表，省掉两条 `orders/mine`。
    ///
    /// 🚨 **只进 `scheduledOrders`，不进 `activeOrder`、不调 `registerActiveOrder`**：这两态不共享实时位置，
    /// 注册进位置协同会让安全网空转（契约原话）。`nil` 不走这里 —— 那是「服务端没取到」，由 `startAuxiliaryLoad` 回落。
    func applyUpcoming(fromSummary upcoming: [VolunteerDispatchSummaryActiveOrder]) {
        var seen = Set<Int64>()
        scheduledOrders = upcoming
            .map(\.orderDetail)
            .filter { Self.upcomingVolunteerStatuses.contains($0.status) && seen.insert($0.orderId).inserted }
            .sorted { ($0.plannedStart ?? "\u{FFFF}") < ($1.plannedStart ?? "\u{FFFF}") }
        scheduledOrdersMessage = nil
    }

    /// 回落路径：摘要的 `upcomingOrders` 是 `nil`（或摘要没拉到）时，按状态各拉一次。
    func fetchUpcomingOrderLists(
        _ orders: any OrderServing
    ) async -> (scheduled: Result<PagedOrderResponse, Error>, pendingAccept: Result<PagedOrderResponse, Error>) {
        // 一次只能问一个状态（`OrderServing.volunteerOrders(status:)` 的注释），所以是两条请求，彼此并行。
        async let scheduledResult: Result<PagedOrderResponse, Error> = Self.fetchResult {
            try await HomeLoadCoordinator.run(timeout: self.loadTimeout, operationName: "volunteer-scheduled-orders") {
                try await orders.volunteerOrders(status: .scheduledConfirmed)
            }
        }
        // 🔴 **`PENDING_ACCEPT` 这一条是 2026-09-18 补的，它此前是个黑洞。**
        // 陪跑员谈成之后点「确认我还会去」，订单 `SCHEDULED_CONFIRMED → PENDING_ACCEPT`，
        // 而那一态**两个数据源都不含它**：预约列表按 `SCHEDULED_CONFIRMED` 拉，
        // `dispatch-summary.activeOrders` 的后端白名单也没有它（#471 之前的摘要也没有 `upcomingOrders`）。
        // 真机表现是「刚接下的那一单，一退出订单页就从自己的 App 里消失了」。
        async let pendingAcceptResult: Result<PagedOrderResponse, Error> = Self.fetchResult {
            try await HomeLoadCoordinator.run(timeout: self.loadTimeout, operationName: "volunteer-pending-accept-orders") {
                try await orders.volunteerOrders(status: .pendingAccept)
            }
        }
        return await (scheduledResult, pendingAcceptResult)
    }
}
