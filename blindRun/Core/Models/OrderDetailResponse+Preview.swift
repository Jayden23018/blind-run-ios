#if DEBUG
import Foundation

extension OrderDetailResponse {
    /// SwiftUI Preview 用的订单工厂。
    ///
    /// 存在理由是 `OrderDetailResponse` 的 24 个 `let` 属性**都进了合成的 memberwise init**
    /// —— Swift 只给 `var` 的 Optional 属性补默认 `nil`（这正是 `volunteerId` /
    /// `volunteerName` / `volunteerTotalCompleted` 声明成 `var` 的原因，见那三条的注释）。
    /// 于是每个 Preview 要写 24 个实参，而 Preview 一多就必然复制粘贴，改字段时漏改一处。
    ///
    /// **只在 `#if DEBUG` 里存在**，不会进发布产物。
    ///
    /// ⚠️ **它不是 Mock 的替代品。** Mock 是 `MockAPIClient`，走真实的请求-响应路径并有
    /// 自己的种子数据。分界线是「这条用例验的是什么」：
    ///
    /// - 验**纯展示/文案函数**（相对日期、掩码姓名、经验行）→ 用这个工厂。
    ///   绕 `MockAPIClient` 只会让一条三行的断言背上一整套网络替身。
    ///   `BlindHomeCardCopyTests` 就是这么写的。
    /// - 验**解码、请求、状态流转、轮询** → 必须走 `MockAPIClient`。
    ///   用这个工厂会绕过解码那一步，而「后端换了字段形状」正是该被那一步抓住的。
    static func preview(
        orderId: Int64 = 1,
        status: RunOrderStatus = .pendingMatch,
        startAddress: String? = "深圳湾公园 3 号入口",
        plannedStart: String? = nil,
        volunteerName: String? = nil,
        volunteerTotalCompleted: Int? = nil,
        volunteerPhone: String? = nil,
        createdAt: String? = nil,
        blindName: String? = "李*",
        blindPhone: String? = nil,
        routeNotes: String? = nil,
        specialNotes: String? = nil,
        // ⚠️ `TOTAL_BLIND`，不是 `TOTALLY_BLIND`。原值打错过，而症状是静默的：
        // `VisionLevel(rawValue:)` 认不出来 ⇒ 每个 Preview 的「视力情况」都显示
        // `EscortNeed.confirmInPerson`（「请当面与跑者确认」），看起来像一条正常的兜底。
        visionLevel: String? = "TOTAL_BLIND",
        tetherPreference: String? = nil,
        pacePreference: PacePreference = .noPreference,
        paceMinSecondsPerKm: Int? = nil,
        paceMaxSecondsPerKm: Int? = nil,
        plannedDistanceMeters: Int? = nil
    ) -> OrderDetailResponse {
        var order = OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: startAddress,
            startLatitude: 22.5210,
            startLongitude: 113.9350,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart ?? Self.previewTimestamp(daysFromNow: 1, hour: 7),
            plannedEnd: Self.previewTimestamp(daysFromNow: 1, hour: 8),
            blindName: blindName,
            blindPhone: blindPhone,
            volunteerPhone: volunteerPhone,
            acceptedAt: nil,
            createdAt: createdAt ?? Self.previewTimestamp(daysFromNow: 0, hour: 9),
            expectedDurationMinutes: 40,
            pacePreference: pacePreference,
            routePreference: .parkTrail,
            routeNotes: routeNotes,
            hasGuideDogThisRun: false,
            specialNotes: specialNotes,
            visionLevel: visionLevel,
            tetherPreference: tetherPreference,
            chatPreference: nil
        )
        order.volunteerName = volunteerName
        order.volunteerTotalCompleted = volunteerTotalCompleted
        order.volunteerId = volunteerName == nil ? nil : 9005
        order.paceMinSecondsPerKm = paceMinSecondsPerKm
        order.paceMaxSecondsPerKm = paceMaxSecondsPerKm
        order.plannedDistanceMeters = plannedDistanceMeters
        return order
    }

    /// 派单推送的样本。**和上面那个工厂放在一起**，因为陪跑员端同一屏有两个数据源
    /// （接单前吃派单载荷，接单后吃订单详情），分开放必然只更新其中一份。
    static func previewDispatch(
        orderId: Int64 = 1,
        plannedStart: String? = nil,
        requiresIntroCall: Bool = true,
        hasGuideDog: Bool = true,
        distanceKm: Double? = 3.2,
        paceMinSecondsPerKm: Int? = 390,
        paceMaxSecondsPerKm: Int? = 450,
        plannedDistanceMeters: Int? = 5000
    ) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: orderId,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: 22.5210,
            startLongitude: 113.9350,
            distanceKm: distanceKm,
            plannedStart: plannedStart ?? Self.previewTimestamp(daysFromNow: 1, hour: 7),
            plannedEnd: Self.previewTimestamp(daysFromNow: 1, hour: 8),
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: PacePreference.moderate.rawValue,
            hasGuideDog: hasGuideDog,
            requiresIntroCall: requiresIntroCall,
            paceMinSecondsPerKm: paceMinSecondsPerKm,
            paceMaxSecondsPerKm: paceMaxSecondsPerKm,
            plannedDistanceMeters: plannedDistanceMeters
        )
    }

    /// 后端 `LocalDateTime` 的形状（`yyyy-MM-dd'T'HH:mm:ss`，无时区偏移）。
    ///
    /// 必须按这个形状拼：`blindRunnerShortStartText` 与 `plannedStartForAnnouncement` 都走
    /// `backendTimestamp` 解析，给 ISO-8601 带偏移的串会让 Preview 显示出与真机不同的时间。
    private static func previewTimestamp(daysFromNow: Int, hour: Int) -> String {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        let target = calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: base
        ) ?? base
        return DateFormatter.aidRunBackendLocalDateTime.string(from: target)
    }
}
#endif
