import Foundation

extension VolunteerAvailabilityScheduleEditing {
    /// 列表行上屏的日期串：「仅 11月4日（周三）」→「仅 11月4日 (周三)」，收尾换成半角「)」。读屏标签与数据不经过这里。
    ///
    /// 为什么不再补窄空格（`displayText`）：11月4日（周三）补了也被真机审计判「放大字号可能被裁」——
    /// 行尾的窄空格被排版吃掉，字的框恰好贴着「）」的右缘（框宽 140.7 = 字宽）。#673。
    static func rowDayText(_ text: String) -> String {
        guard text.hasSuffix("）"), let open = text.lastIndex(of: "（") else { return text }
        return String(text[..<open]) + " (" + String(text[text.index(after: open)...].dropLast()) + ")"
    }
}
