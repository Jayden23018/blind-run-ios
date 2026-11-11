import Foundation

// MARK: - 首页的几张预约与播报（#825）

// 从 `BlindRunnerHomeView.swift` 拆出来：那个文件和类都已到 SwiftLint 上限。

extension BlindRunnerHomeViewModel {
    /// 首页显示的全部预约，最早的在前（`activeOrder` 永远是第一张）。
    var homeOrders: [OrderDetailResponse] {
        BlindHomeUpcomingOrders.merge(active: activeOrder, mine: otherOrders)
    }

    /// 订单页返回时写回（#825）。点开的可能是第 2、3 张：只有同号时才动 `activeOrder`，
    /// 否则会把求助判据换成一张还没开始的单。
    ///
    /// 🔴 **首页还不认识的单要收下，不许丢（#936）。** 约跑提交成功后直接推订单页，首页没有重新加载，
    /// 这张新单既不是 `activeOrder` 也不在 `otherOrders` 里。原来这里两头都对不上就什么都不做，
    /// 盲人从「正在匹配」退回首页只看到「预约新的陪跑」，会以为订单丢了而重复下单。
    /// 首页没有单时它就是最早那张；已有一张时先排进其余几张，下次加载由 `/active` 重新选最早那张。
    func applyOrderDetail(_ updated: OrderDetailResponse) {
        if updated.orderId == activeOrder?.orderId {
            activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            return
        }
        guard homeOrders.contains(where: { $0.orderId == updated.orderId }) else {
            adoptUnknownOrder(updated)
            return
        }
        otherOrders = otherOrders.compactMap { order in
            guard order.orderId == updated.orderId else { return order }
            return updated.status.isActiveForBlindRunner ? updated : nil
        }
    }

    private func adoptUnknownOrder(_ order: OrderDetailResponse) {
        guard order.status.isActiveForBlindRunner else { return }
        guard activeOrder == nil else {
            otherOrders.append(order)
            return
        }
        activeOrder = order
        // 与加载路径同一套登记：WebSocket 推进（`applyRealtimeStatus`）只认登记过的那一单。
        appState?.realtimeCoordinator.registerActiveOrder(order.orderId, status: order.status)
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: order.orderId, status: order.status)
    }

    func handleOrderCreated(_ response: OrderResponse) {
        noteOrderCreated()
        speechService?.resetLastStatus()
        if let status = response.status {
            speechService?.speakStatusChange(status)
        }
    }

    /// 刚下了单（#936）。订单页在拉到详情之前就被退出时，返回不会写回任何东西，
    /// 所以记下来，回到首页时向服务端重新要一次。
    func noteOrderCreated() {
        needsReloadAfterBooking = true
    }

    /// 订单页退出、首页重新在最前面时调用。下过单才重拉；重拉会念一遍首页状态，
    /// 这正是盲人此刻要听的：「订单还在，正在匹配」。
    func reloadAfterBookingIfNeeded() async {
        guard needsReloadAfterBooking else { return }
        needsReloadAfterBooking = false
        await loadActiveOrder()
    }

    /// 拉第 2、3 张。只有 `/active` 给了一张时才拉：它是空的，就不会有别的未完成预约。
    /// 失败不挡首页（最早那张已经在了），但要让人看见、听见：漏掉一张就可能爽约。
    func loadOtherOrders(appState: AppState) async {
        guard let activeOrder else {
            otherOrders = []
            otherOrdersFailed = false
            return
        }
        let orders = appState.orders
        do {
            let page: PagedOrderResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "blind-other-orders"
            ) {
                try await orders.myOrders()
            }
            otherOrders = page.content.filter { $0.orderId != activeOrder.orderId && $0.status.isActiveForBlindRunner }
            otherOrdersFailed = false
        } catch let error as APIError where error.endsSession {
            return
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "blind-other-orders")
            otherOrdersFailed = true
        }
    }


    /// 🔴 **播报里提到的控件名必须与它的 `accessibilityLabel` 逐字一致。**
    ///
    /// 读屏用户是**按标签找控件**的：播报说「可以点击开始约跑」而屏幕上那个按钮叫
    /// 「预约新的陪跑」时，用户会逐个划过去找一个不存在的名字 —— 导航指令当场失效，
    /// 而界面上看不出任何异常。2026-09-16 首页改版时这两句就漏改了一轮。
    ///
    /// 这条抓不成守卫：中文文案漂移的静态匹配实测误报 93%
    /// （`AccessibilityAuditTests` 里 `safetyHubLabel` 那段注释记着同一件事）。
    /// 改按钮标签时自己搜一遍播报文案。
    func speakCurrentStatus(locationDescription: String? = nil) {
        // 最早那张刚走完、还没重新加载时，`activeOrder` 为空而其余几张还在屏幕上，念第一张。
        if let activeOrder = homeOrders.first {
            speechService?.speakBlindRunnerStatusChange(
                activeOrder,
                text: countPrefix + homeAnnouncement(for: activeOrder, locationDescription: locationDescription)
                    + othersFailedSuffix
            )
        } else {
            let locationText = locationDescription.map { "当前位置：\($0)。" } ?? ""
            speechService?.speak("欢迎来到助盲跑。\(locationText)可以点击预约新的陪跑。")
        }
    }


    /// 首页那枚「重复当前状态」。与订单页的 `BlindOrderStatusViewModel.repeatStatus()` 同一档
    /// （`.onDemand`，`状态清单.md` 的「按需播报」）—— 两处是同一个用户动作的两个入口，
    /// 档位分叉的直接后果是：状态推进（`.counterpartAction`）正在播时，首页这一枚会把它
    /// 从半句切断，而订单页那一枚会规规矩矩排队。用户不可能知道自己按的是哪一种。
    func repeatCurrentStatus(locationDescription: String) {
        // 最早那张刚走完、还没重新加载时，`activeOrder` 为空而其余几张还在屏幕上，念第一张。
        if let activeOrder = homeOrders.first {
            speechService?.speak(
                countPrefix + homeAnnouncement(for: activeOrder, locationDescription: locationDescription)
                    + othersFailedSuffix,
                priority: .onDemand
            )
        } else {
            speechService?.speak(
                "当前没有进行中的预约。\(locationDescription)可以点击预约新的陪跑。",
                priority: .onDemand
            )
        }
    }

    /// 「你有 3 张预约。最近一张：」—— 只有一张时为空，播报与改版前逐字相同（#825）。
    private var countPrefix: String {
        BlindHomeUpcomingOrders.countAnnouncement(count: homeOrders.count)
    }

    private var othersFailedSuffix: String {
        otherOrdersFailed ? BlindHomeUpcomingOrders.othersFailedMessage : ""
    }

    private func homeAnnouncement(for order: OrderDetailResponse, locationDescription: String?) -> String {
        let timeText = order.plannedStartForAnnouncement.map { "预约时间：\($0)。" } ?? ""
        let locationText = locationDescription.map { "位置摘要：\($0)。" } ?? ""
        return "\(order.blindRunnerAnnouncement())\(timeText)出发地点：\(order.startAddressForAnnouncement)。\(locationText)"
    }

}
