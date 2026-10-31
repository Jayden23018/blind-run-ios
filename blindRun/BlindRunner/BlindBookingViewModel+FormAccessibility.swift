import Foundation

/// 下单表单的读屏可用性（#295）。走查清单与修复对照在 issue 评论与 PR 描述里。
///
/// 放在扩展文件里是因为 `BlindBookingView.swift` 已超长（SwiftLint 棘轮只许变短）。
extension BlindBookingViewModel {

    /// 出发地点卡上显示的那一行。屏幕与读屏 label 共用，免得地址还没拿到时
    /// 屏幕写「正在获取当前位置」、读屏念「出发地点，」（空值）。（走查 B1）
    var startPointDisplayText: String {
        resolvedStartLocationDescription.nilIfBlank ?? "正在获取当前位置"
    }

    /// 默认预约时间：最早可约时刻再加 1 分钟，免得一设下去就踩线。
    var seedAppointmentTime: Date {
        minimumAppointmentTime.addingTimeInterval(60)
    }

    /// 默认值只比下限多 1 分钟，而合法性按**实时**的 `Date()` 判 —— 页面停留超过约 1 分钟它就变成「太近」。
    /// 读屏用户在第 1 步搜地点、选地点通常要好几分钟，走到第 2 步看到的是红字加灰掉的下一步，
    /// 还得马上去操作日期选择器。所以每次**进入**第 2 步时，过期的值重新取最早可约时刻。
    /// 用户自己选的、仍然合法的时间不会被动到。（走查 C2）
    func reseedAppointmentTimeIfExpired() {
        if appointmentTime < minimumAppointmentTime {
            appointmentTime = seedAppointmentTime
        }
    }

    /// 给「日期 / 时刻」两行可调节控件用：读屏上下滑一次移动一格。（走查 C1）
    /// 夹在 `[最早可约 + 1 分钟, 最远 - 1 分钟]` 里，与 `DatePicker` 的 `in:` 同一区间；
    /// 夜间窗口夹不出来，仍由 `appointmentTimeProblem` 报。
    ///
    /// 按天步进越界时**原地不动**，不夹：夹到边界会把时刻也一起改掉（明天 07:00 退一天变成今天 15:42），
    /// 而用户以为只动了日期。按刻步进越界时夹到边界 —— 那正是用户要的「尽量早 / 尽量晚」。
    func shiftAppointment(byMinutes minutes: Int) {
        let shifted = appointmentTime.addingTimeInterval(TimeInterval(minutes * 60))
        let lower = seedAppointmentTime
        let upper = maximumAppointmentTime.addingTimeInterval(-60)
        if abs(minutes) >= Self.minutesPerDay, shifted < lower || shifted > upper { return }
        appointmentTime = min(max(shifted, lower), upper)
    }

    static let minutesPerDay = 24 * 60

    /// 表单的提交入口：先告知「正在提交」再提交。（走查 D1）
    /// 点击到服务端返回之间只有按钮里一个转圈，读屏用户无从得知点击是否生效。
    /// 语音向导自己有播报节奏，直接调 `submit()`，不走这里。
    func submitAnnouncingProgress() async -> OrderResponse? {
        if canSubmit {
            speechService?.announce("正在提交预约。")
        }
        return await submit()
    }
}
