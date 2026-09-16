import XCTest
@testable import blindRun

/// 首页深蓝订单卡那几句文案的判定。
///
/// 全是纯函数，所以能在这一层钉死 —— 而它们的错误形态**都是静默的**：
/// 相对日期错一天、掩码星号被念出来、经验数字凭空出现，屏幕上都不会报任何错。
final class BlindHomeCardCopyTests: XCTestCase {

    /// 固定时区的日历。**不能用 `.current`**：CI 与两台真机的时区一旦不同，
    /// 「明天 7:00」会在其中一处变成「今天 7:00」，而那种红看着完全像代码错了。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)!
    }

    // MARK: - 相对日期

    /// 相对日期做到后天，再往后退回绝对日期。
    ///
    /// ⚠️ 取值刻意**跨午夜**：`now` 是 23:30、目标是次日 01:00，两者只差 90 分钟。
    /// 按时刻差算会判成「今天」，按日初差算才是「明天」。随手取 `now=09:00`、
    /// 目标次日 07:00 那种值，两种实现都会给出「明天」—— 用例分辨不出对错。
    func testShortStartTextUsesRelativeDaysAcrossMidnight() {
        let now = date("2026-09-16 23:30:00")
        let cases: [(planned: String, expected: String)] = [
            ("2026-09-16T23:50:00", "今天 23:50"),
            ("2026-09-17T01:00:00", "明天 1:00"),
            ("2026-09-17T07:00:00", "明天 7:00"),
            ("2026-09-18T07:00:00", "后天 7:00"),
            ("2026-09-19T07:00:00", "9月19日 7:00"),
        ]
        for (planned, expected) in cases {
            let order = OrderDetailResponse.preview(plannedStart: planned)
            XCTAssertEqual(
                order.blindRunnerShortStartText(now: now, calendar: calendar),
                expected,
                "plannedStart=\(planned) 时应显示「\(expected)」"
            )
        }
    }

    /// 跨月与跨年都要走绝对日期分支，且**不带年份** —— 预约最远 7 天，跨年只在 12 月末成立。
    func testShortStartTextFallsBackToAnAbsoluteDateAcrossMonthAndYearBoundaries() {
        XCTAssertEqual(
            OrderDetailResponse.preview(plannedStart: "2026-10-01T06:00:00")
                .blindRunnerShortStartText(now: date("2026-09-28 10:00:00"), calendar: calendar),
            "10月1日 6:00"
        )
        XCTAssertEqual(
            OrderDetailResponse.preview(plannedStart: "2027-01-02T06:00:00")
                .blindRunnerShortStartText(now: date("2026-12-30 10:00:00"), calendar: calendar),
            "1月2日 6:00"
        )
    }

    /// 已过去的时间**不说「昨天」**：那一态只出现在已结束或异常的单上，
    /// 相对日期会让人以为还有事要做。
    func testShortStartTextNeverSaysYesterday() {
        let text = OrderDetailResponse.preview(plannedStart: "2026-09-15T07:00:00")
            .blindRunnerShortStartText(now: date("2026-09-16 10:00:00"), calendar: calendar)
        XCTAssertEqual(text, "9月15日 7:00")
        XCTAssertFalse(text?.contains("昨天") ?? false)
    }

    /// 时间拿不到时返回 `nil`，由调用方决定摆什么 —— **不返回「--:--」这类占位**。
    /// 52pt 大字的位置被一个没有信息的东西占住，比少一行更糟。
    func testShortStartTextReturnsNilWhenThereIsNoPlannedStart() {
        XCTAssertNil(
            OrderDetailResponse.preview(plannedStart: "")
                .blindRunnerShortStartText(now: date("2026-09-16 10:00:00"), calendar: calendar)
        )
        XCTAssertNil(
            OrderDetailResponse.preview(plannedStart: "not-a-timestamp")
                .blindRunnerShortStartText(now: date("2026-09-16 10:00:00"), calendar: calendar)
        )
    }

    // MARK: - 掩码姓名

    /// 后端姓名**始终带掩码星号**（`张*`）。读屏是外放的，原样交给它会念出「张星号」。
    ///
    /// 这条同时是那个修法的验红：把实现换回 `volunteerName` 原串，`contains("*")` 立刻成立。
    func testSpokenVolunteerNameDropsTheMaskAsterisk() {
        XCTAssertEqual(OrderDetailResponse.preview(volunteerName: "张*").volunteerNameForSpeech, "张")
        XCTAssertEqual(OrderDetailResponse.preview(volunteerName: "欧阳**").volunteerNameForSpeech, "欧阳")
        // 全角星号也要吃掉 —— 后端换一次掩码字符就会漏过半角那一条。
        XCTAssertEqual(OrderDetailResponse.preview(volunteerName: "李＊").volunteerNameForSpeech, "李")

        for name in ["张*", "欧阳**", "李＊"] {
            XCTAssertFalse(
                OrderDetailResponse.preview(volunteerName: name).volunteerNameForSpeech.contains("*"),
                "朗读文本里还留着掩码星号，VoiceOver 会念出「星号」"
            )
        }
    }

    /// 没有姓名时回退到既有常量，不另造第二个占位词。
    func testSpokenVolunteerNameFallsBackToTheSharedPlaceholder() {
        XCTAssertEqual(
            OrderDetailResponse.preview(volunteerName: nil).volunteerNameForSpeech,
            PartnerStreakCopy.unknownVolunteerName
        )
        XCTAssertEqual(
            OrderDetailResponse.preview(volunteerName: "  ").volunteerNameForSpeech,
            PartnerStreakCopy.unknownVolunteerName
        )
        // 只有星号的情况：去掉星号就空了，同样要回退而不是给出空串。
        XCTAssertEqual(
            OrderDetailResponse.preview(volunteerName: "**").volunteerNameForSpeech,
            PartnerStreakCopy.unknownVolunteerName
        )
    }

    /// 🔴 **视觉上仍然显示掩码**。去掉星号只发生在朗读通道 ——
    /// 屏幕上去掉会让人以为拿到了全名，而拨号那条路从来不经过姓名。
    func testTheMaskStaysOnScreenEvenThoughItIsDroppedForSpeech() {
        let order = OrderDetailResponse.preview(volunteerName: "张*")
        XCTAssertEqual(order.volunteerName, "张*", "渲染用的原串不许被改写")
        XCTAssertNotEqual(order.volunteerName, order.volunteerNameForSpeech, "两条通道取值必须不同")
    }

    // MARK: - 陪跑经验

    /// 只说后端真的发了的那一项。
    ///
    /// 设计稿要的是「陪跑 32 次，引导绳经验 2 年」，而后端只有前半句 ——
    /// 后半句与「已认证」在契约里 0 命中。**这条用例挡的是「填一个默认值」**：
    /// 给盲人印一个凭空生成的经验数字，正是他决定要不要把自己交给陌生人时唯一的依据。
    func testExperienceTextOnlyStatesWhatTheBackendActuallySent() {
        XCTAssertEqual(
            OrderDetailResponse.preview(volunteerName: "张*", volunteerTotalCompleted: 32)
                .volunteerExperienceText,
            "陪跑 32 次"
        )
        XCTAssertNil(
            OrderDetailResponse.preview(volunteerName: "张*", volunteerTotalCompleted: nil)
                .volunteerExperienceText,
            "字段缺失时必须整段不显示，不许填默认值"
        )
        // 0 次也不显示：「陪跑 0 次」对一个刚通过资质审核的志愿者是误导性的负面标签，
        // 而 nil 与 0 在这里的用户含义是同一个 ——「还没有可展示的经验」。
        XCTAssertNil(
            OrderDetailResponse.preview(volunteerName: "张*", volunteerTotalCompleted: 0)
                .volunteerExperienceText
        )
        // 不得出现「引导绳」「已认证」—— 后端没有这两个字段。
        let text = OrderDetailResponse.preview(volunteerName: "张*", volunteerTotalCompleted: 32)
            .volunteerExperienceText ?? ""
        XCTAssertFalse(text.contains("引导绳"), "引导绳经验年数后端没有这个字段，不许凭空显示")
        XCTAssertFalse(text.contains("认证"), "陪跑员认证状态不在订单详情里，不许凭空显示")
    }

    // MARK: - 状态轮询不许弄丢新字段

    /// `replacingStatus` 漏带字段的后果是**静默消失**：每 5 秒一次轮询之后卡片上少一行字，
    /// 没有任何报错，也没有空位。终点三项与 `volunteerId` 都栽过同一个跟头
    /// （`testReplacingStatusKeepsTheEndLocation` 是那次的钉子）。
    func testReplacingStatusKeepsTheVolunteerExperience() {
        let order = OrderDetailResponse.preview(
            status: .pendingAccept,
            volunteerName: "张*",
            volunteerTotalCompleted: 32
        )
        let updated = order.replacingStatus(with: .driverEnRoute)

        XCTAssertEqual(updated.status, .driverEnRoute)
        XCTAssertEqual(updated.volunteerTotalCompleted, 32, "状态一变「陪跑 32 次」就没了")
        XCTAssertEqual(updated.volunteerExperienceText, "陪跑 32 次")
        // 同批带过去的另外两项，确认这次改动没把它们挤掉。
        XCTAssertEqual(updated.volunteerName, "张*")
        XCTAssertEqual(updated.volunteerId, order.volunteerId)
    }
}
