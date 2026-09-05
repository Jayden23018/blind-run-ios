import Foundation
@testable import blindRun

/// 下单时间用例的共享时刻。
///
/// 🚨 **存在的唯一理由：`Date().addingTimeInterval(31 * 60)` 不再是「一个合法的预约时间」。**
///
/// 2026-09-05 后端 N134 加了夜间禁跑窗口 `[22:00, 05:00)`，客户端跟着在
/// `BlindBookingViewModel.appointmentTimeProblem` 上挡住它。于是「现在 + 31 分钟」
/// 在晚上 21:29 之后、凌晨 5 点之前**是不合法的** —— 用它构造「合法预约」的用例
/// 会白天全绿、夜里集体变红，而提交那一刻多半是白天，没人看得见。
///
/// 这个坑在另一条尚未合并的分支上被记过一次（N134 那批错误码，PR #103）：那边的应对是
/// **Mock 不镜像夜间校验**，理由是本仓多条用例按 `Date() + 45 分钟` 下单，镜像之后
/// 会白天全绿、晚上集体变红。客户端这一侧挡不掉（产品要求挡在选择器上），
/// 所以改成给用例一条显然正确的路。
/// ⚠️ 那段注释目前**不在本分支上**，别去 `MockAPIClient+Order.swift` 里找。
///
/// **写新用例时**：要「一个合法的预约时间」就用 `daytime()`；
/// 要「一个不合法的时间」照旧用相对时间（那一侧不受挂钟影响，太近就是太近）。
enum BookingTimeFixture {

    /// 一个必然合法的预约时刻：**下一个白天的 10:00**。
    ///
    /// 同时满足三条：≥ 最小提前量（`minimumBookingLeadMinutes`）、
    /// ≤ 最远提前天数（`maximumBookingLeadDays`）、整段行程避开夜间窗口
    /// （10:00 + 默认时长 60 分钟 = 11:00，离 22:00 还很远）。
    ///
    /// 取 10:00 而不是当天某个偏移：偏移会随跑用例的时刻漂进夜里，而固定钟点不会。
    static func daytime(from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let minimumLead = TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60)
        let earliest = reference.addingTimeInterval(minimumLead)
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: reference),
                  let slot = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)
            else { continue }
            if slot > earliest { return slot }
        }
        // 走不到：0/1/2 天里必有一个 10:00 晚于「现在 + 30 分钟」。
        // 真走到了说明日历算错了，这时返回一个仍然合法的值好过让用例在别处离奇失败。
        return calendar.date(byAdding: .day, value: 1, to: earliest) ?? earliest
    }
}
