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
        createdAt: String? = nil
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
            blindName: "李*",
            blindPhone: nil,
            volunteerPhone: volunteerPhone,
            acceptedAt: nil,
            createdAt: createdAt ?? Self.previewTimestamp(daysFromNow: 0, hour: 9),
            expectedDurationMinutes: 40,
            pacePreference: .noPreference,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: false,
            specialNotes: nil,
            visionLevel: "TOTALLY_BLIND",
            tetherPreference: nil,
            chatPreference: nil
        )
        order.volunteerName = volunteerName
        order.volunteerTotalCompleted = volunteerTotalCompleted
        order.volunteerId = volunteerName == nil ? nil : 9005
        return order
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
