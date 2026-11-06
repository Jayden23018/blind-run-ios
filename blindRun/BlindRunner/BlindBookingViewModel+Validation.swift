import Foundation

extension BlindBookingViewModel {
    var minimumAppointmentTime: Date {
        Date().addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60))
    }

    /// 选择器的上界。后端 2026-09-05 起对 `plannedStartTime` 有了 7 天上限
    /// （422 `APPOINTMENT_TOO_FAR`），在此之前**只有下限没有上限**，能选到几个月后再被拒。
    var maximumAppointmentTime: Date {
        Date().addingTimeInterval(TimeInterval(AppConstants.Timing.maximumBookingLeadDays * 24 * 3600))
    }

    /// 默认预约时间：最早可约时刻再加 1 分钟，免得一设下去就踩线。
    var seedAppointmentTime: Date {
        minimumAppointmentTime.addingTimeInterval(60)
    }

    /// 默认值只比下限多 1 分钟，而合法性按**实时**的 `Date()` 判，停留久了就变成「太近」。
    /// 进页时（`configure`）过期的值重新取最早可约时刻；用户或语音给的、仍然合法的时间不动。
    func reseedAppointmentTimeIfExpired() {
        if appointmentTime < minimumAppointmentTime {
            appointmentTime = seedAppointmentTime
        }
    }

    var isAppointmentTimeValid: Bool {
        appointmentTimeProblem == nil
    }

    /// 当前这个时间选择过不了哪一道，`nil` = 都过得了。
    ///
    /// 抽成一个枚举而不是三个 Bool：`message(for:)` 与 `appointmentSummary` 都要说出**具体哪里不行**，
    /// 散着写就会漂 —— 旧表单的两处提示曾经手抄「30 分钟」，而另一处是从常量取的。
    ///
    /// 顺序即优先级：太近 → 太远 → 夜间。先说时间点本身的问题，再说整段的问题。
    var appointmentTimeProblem: BookingTimeProblem? {
        // 时段单（#806）：时段由 `BookingSlotPlanner` 只列合法的（已过提前量、不碰夜间），不再用表单那个选择器的值判。
        if flexibleSlot != nil { return nil }
        if appointmentTime < minimumAppointmentTime { return .tooSoon }
        if appointmentTime > maximumAppointmentTime { return .tooFar }
        if Self.overlapsNightWindow(start: appointmentTime, end: plannedEndDate) { return .nightWindow }
        return nil
    }

    /// 整段行程与夜间禁跑窗口 `[22:00, 05:00)` 有没有交集。
    ///
    /// 🚩 **判据是整段不是开始时刻**，与后端 `OrderCreationService.overlapsNightWindow` 同构：
    /// `21:00–22:30` 拒（尾巴进了夜间）、`21:00–22:00` 放行（恰好 22:00 结束不算重叠）、
    /// `05:00–06:00` 放行（恰好 05:00 开始不算重叠）、`次日 04:00–06:00` 拒。
    /// 半开区间的判据 `start < windowEnd && end > windowStart` 就是「恰好相接不算」的来源。
    ///
    /// 扫 `-1...1` 三天：一段最长 5 小时的行程只可能撞上「当天那扇」或「前一天那扇
    /// （它延伸到今天 05:00）」，`+1` 是多余但无害的保险。
    ///
    /// `nonisolated static` + 显式 `calendar` 是为了能被单测直接驱动：它是纯函数，
    /// 不碰任何 view model 状态，挂在 `@MainActor` 上只会逼调用方跑主线程。
    ///
    /// 默认日历取北京时间（`Calendar.aidRunBackend`）而不是设备日历：后端按北京时间的钟点判，
    /// 设备在别的时区时用本地钟点判会差整数小时（#236 同根因）。
    nonisolated static func overlapsNightWindow(start: Date, end: Date, calendar: Calendar = .aidRunBackend) -> Bool {
        guard end > start else { return false }
        let startHour = AppConstants.Timing.nightWindowStartHour
        let endHour = AppConstants.Timing.nightWindowEndHour
        let windowHours = (24 - startHour) + endHour
        for dayOffset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start),
                  let windowStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
                  let windowEnd = calendar.date(byAdding: .hour, value: windowHours, to: windowStart)
            else { continue }
            if start < windowEnd && end > windowStart { return true }
        }
        return false
    }

    /// 下单前第一个未通过的门槛；nil 表示全部通过。
    var firstMissingGate: BlindBookingGate? {
        BlindBookingGate.firstMissing(
            hasValidEmergencyContacts: appState?.hasValidEmergencyContacts ?? true,
            hasStartPoint: resolvedStartPlace != nil,
            isAppointmentTimeValid: isAppointmentTimeValid
        )
    }

    /// 某道门槛现在该对用户说的话。
    ///
    /// `.appointmentTime` 门槛背后有三种原因（太近 / 超过 7 天 / 撞夜间窗口），`BlindBookingGate.message`
    /// 是个无状态枚举，只能说其中一种；所以凡是把门槛念给用户的地方都走这里，
    /// 时间门槛读 `appointmentTimeProblem`，说出具体哪里不行（#424）。
    func message(for gate: BlindBookingGate) -> String {
        guard gate == .appointmentTime, let problem = appointmentTimeProblem else { return gate.message }
        return problem.message
    }

    var canSubmit: Bool {
        !isSubmitting && firstMissingGate == nil
    }
}
