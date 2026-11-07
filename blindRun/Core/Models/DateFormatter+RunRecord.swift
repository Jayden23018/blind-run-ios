import Foundation

/// 跑后记录用的两个显示格式器。和 `OrderDisplayHelpers.swift` 里的 `aidRunDisplay*` 同一套 locale 与写法，
/// 单放一个文件只是因为那个文件已超长。
extension DateFormatter {
    /// 「9月20日 周六」，跑后记录列表与详情页用。
    static let aidRunDisplayMonthDayWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    /// 小时补零的钟点「08:00」，跑后记录的时间轴与分段表用。
    ///
    /// 🚩 别和 `OrderDisplayHelpers.swift` 的 `aidRunDisplayClock`（「8:00」）合并：两者输出不同，换哪边都会改界面和播报。
    static let aidRunDisplayClockPadded: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
