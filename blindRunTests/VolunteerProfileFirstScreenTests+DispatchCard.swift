import XCTest
@testable import blindRun

/// 接单页派单状态卡的原因句，与首页作业区去掉培训、资质提醒之后的覆盖（#706）。
/// 写成扩展：`VolunteerProfileFirstScreenTests` 已超过类与文件长度上限（SwiftLint 棘轮只许变小）。
extension VolunteerProfileFirstScreenTests {

    /// 首页作业区不再画培训、资质卡，状态卡的原因句**一条不省**。
    ///
    /// 🔴 第一、二条是这条用例的价值：#706 之前的实现会省掉培训、资质，
    /// 它们在那个实现下得到 nil / 只剩「当前未在线」，这里会红。
    func testDispatchCardSaysTrainingAndCertificateReasonsNow() {
        XCTAssertEqual(
            VolunteerDispatchSummaryCard.reasonText(for: Self.summary(reasons: [.trainingIncomplete])),
            VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText,
            "作业区已经不说培训了，状态卡再省掉它就哪里都不说"
        )
        XCTAssertEqual(
            VolunteerDispatchSummaryCard.reasonText(for: Self.summary(reasons: [.trainingIncomplete, .offline])),
            [VolunteerDispatchNotAvailableReason.trainingIncomplete, .offline].map(\.displayText).joined(separator: "、")
        )
        XCTAssertEqual(
            VolunteerDispatchSummaryCard.reasonText(for: Self.summary(reasons: [.notVerified, .unknown])),
            VolunteerDispatchNotAvailableReason.notVerified.displayText,
            "混有未识别取值时只说能解释清楚的那条"
        )
        XCTAssertNil(
            VolunteerDispatchSummaryCard.reasonText(for: Self.summary(reasons: [])),
            "可派单时状态卡标题「接单中」已经说了，不再有原因句"
        )
    }

    /// 每一种接不了单的原因，去掉作业区之后仍**至少说一次**（#706 易错点）。
    ///
    /// 两处分工：滑块被挡住（滑不开）时胶囊自己说原因并通往接单前进度页；
    /// 没被挡住时人能滑进接单页，由状态卡说。开关开着、关着两种都要成立。
    func testEveryNotAvailableReasonIsStillSaidOnTheSliderOrTheDispatchCard() {
        // 胶囊说明里能认出这条原因的字样。只列滑块会挡住的三条，其余走状态卡。
        let sliderWording: [VolunteerDispatchNotAvailableReason: String] = [
            .trainingIncomplete: "必修培训",
            .notVerified: "证书",
            .accountSuspended: AccountSuspensionCopy.dispatchNotice
        ]
        for reason in VolunteerDispatchNotAvailableReason.allCases {
            let summary = Self.summary(reasons: [reason])
            for isAvailable in [false, true] {
                let status = VolunteerAvailabilityStatus.resolve(
                    isAvailable: isAvailable,
                    hasSummary: true,
                    canDispatch: summary.canDispatch,
                    reasons: [reason],
                    explanation: summary.reasonText
                )
                let context = "\(reason.rawValue)，开关\(isAvailable ? "开" : "关")"
                guard status.blocksOpening else {
                    XCTAssertTrue(
                        VolunteerDispatchSummaryCard.reasonText(for: summary)?.contains(reason.displayText) == true,
                        "\(context)：人能进接单页，状态卡必须说出这条原因"
                    )
                    continue
                }
                let detail = status.notice(certificate: .notSubmitted, isAlternativeIdentityPath: false)?.detail ?? ""
                guard let wording = sliderWording[reason] else {
                    XCTFail("\(context)：滑块挡住了却没有登记胶囊该怎么说")
                    continue
                }
                XCTAssertTrue(detail.contains(wording), "\(context)：胶囊说明里找不到这条原因（detail=\(detail)）")
            }
        }
    }
}
