import XCTest
@testable import blindRun

/// 陪跑员「我的」下三个子页（个人资料、我的积分、资质证书，#700）的纯逻辑。
final class VolunteerAccountPagesTests: XCTestCase {

    // MARK: - 积分：本月小结

    /// 「现在」= 北京时间 2026-11-05 中午。
    private let now = "2026-11-05T12:00:00".backendTimestamp!
    private let calendar = Calendar.aidRunBackend

    func testMonthlySummaryCountsOnlyThisMonthWhenEverythingIsLoaded() throws {
        let summary = try XCTUnwrap(PointMonthlySummary.make(
            transactions: [
                makeTransaction(delta: 10, createdAt: "2026-11-03T10:00:00"),
                makeTransaction(delta: 20, createdAt: "2026-11-01T00:00:00"),
                makeTransaction(delta: 10, createdAt: "2026-10-31T23:59:59")
            ],
            hasMorePages: false, now: now, calendar: calendar
        ))
        // 把上月 10 月 31 日那笔算进来会得到 +40 · 3 笔。
        XCTAssertEqual(summary.text, "本月 +30 · 共 2 笔")
        XCTAssertEqual(summary.spokenText, "本月加 30 分，共 2 笔")
    }

    /// 还有更早的页、已加载的又全在本月 ⇒ 本月可能还有没加载的，宁可不显示。
    func testMonthlySummaryIsHiddenWhenThisMonthMayContinueOnTheNextPage() {
        XCTAssertNil(PointMonthlySummary.make(
            transactions: [
                makeTransaction(delta: 10, createdAt: "2026-11-04T10:00:00"),
                makeTransaction(delta: 10, createdAt: "2026-11-02T10:00:00")
            ],
            hasMorePages: true, now: now, calendar: calendar
        ))
    }

    /// 有更早的页，但已加载的里已经出现上个月 ⇒ 本月的都在手里，照样算。
    func testMonthlySummaryIsShownWhenThePageAlreadyReachesLastMonth() throws {
        let summary = try XCTUnwrap(PointMonthlySummary.make(
            transactions: [
                makeTransaction(delta: 10, createdAt: "2026-11-04T10:00:00"),
                makeTransaction(delta: 10, createdAt: "2026-10-20T10:00:00")
            ],
            hasMorePages: true, now: now, calendar: calendar
        ))
        XCTAssertEqual(summary.text, "本月 +10 · 共 1 笔")
    }

    /// `delta = 0` 是真实的一笔（撞上限没加分），条数要算上；扣分写成负数。
    func testMonthlySummaryCountsZeroDeltaAndShowsNegativeNet() throws {
        let zero = try XCTUnwrap(PointMonthlySummary.make(
            transactions: [
                makeTransaction(delta: 10, createdAt: "2026-11-04T10:00:00"),
                makeTransaction(delta: 0, createdAt: "2026-11-04T11:00:00")
            ],
            hasMorePages: false, now: now, calendar: calendar
        ))
        XCTAssertEqual(zero.text, "本月 +10 · 共 2 笔")

        let negative = try XCTUnwrap(PointMonthlySummary.make(
            transactions: [makeTransaction(delta: -10, reason: "REVERSAL", createdAt: "2026-11-04T10:00:00")],
            hasMorePages: false, now: now, calendar: calendar
        ))
        XCTAssertEqual(negative.text, "本月 -10 · 共 1 笔")
        XCTAssertEqual(negative.spokenText, "本月扣 10 分，共 1 笔")
    }

    /// 时间解析不出、或本月一笔都没有，都不显示。
    func testMonthlySummaryIsHiddenWhenItCannotBeTrusted() {
        XCTAssertNil(PointMonthlySummary.make(
            transactions: [
                makeTransaction(delta: 10, createdAt: "2026-11-04T10:00:00"),
                makeTransaction(delta: 10, createdAt: "不是时间")
            ],
            hasMorePages: false, now: now, calendar: calendar
        ))
        XCTAssertNil(PointMonthlySummary.make(
            transactions: [makeTransaction(delta: 10, createdAt: "2026-10-04T10:00:00")],
            hasMorePages: false, now: now, calendar: calendar
        ))
        XCTAssertNil(PointMonthlySummary.make(transactions: [], hasMorePages: false, now: now, calendar: calendar))
    }

    func testRowDateDropsTheYearOnlyForThisYear() {
        XCTAssertEqual(makeTransaction(createdAt: "2026-11-03T10:00:00").dayText(now: now, calendar: calendar), "11月3日")
        XCTAssertEqual(makeTransaction(createdAt: "2025-12-30T10:00:00").dayText(now: now, calendar: calendar), "2025年12月30日")
        XCTAssertNil(makeTransaction(createdAt: "不是时间").dayText(now: now, calendar: calendar))
    }

    /// 合规文案拆成标题 + 说明后，拼回来要和原文逐字一样（`IncentiveAdoptionTests` 的红线断言查的是 `empty`）。
    func testEmptyCopyStillReadsAsTheOriginalSentence() {
        XCTAssertEqual(
            VolunteerPointsCopy.empty,
            "还没有积分记录。完成一次陪跑服务后，这里会显示每一笔的加分和原因。"
        )
    }

    // MARK: - 个人资料

    func testProfileShowsNameMaskedPhoneAndIdentityStatus() {
        let content = VolunteerAccountProfileContent.make(
            profile: VolunteerProfileResponse(name: "测试志愿者"),
            phone: "13800000002",
            registrationStatus: VolunteerRegistrationStatus(idVerifyStatus: "APPROVED")
        )
        XCTAssertEqual(content.displayName, "测试志愿者")
        XCTAssertEqual(content.rows.map(\.title), ["姓名", "手机号", "实名认证"])
        XCTAssertEqual(content.rows.map(\.value), ["测试志愿者", "138****0002", "已认证"])
        // 读屏只念尾号：不念星号，也不出现全号。
        let phone = content.rows[1]
        XCTAssertEqual(phone.spokenValue, "尾号 0002")
        XCTAssertFalse(phone.spokenValue?.contains("13800000002") ?? true)
    }

    /// 线上 `GET /api/auth/me` 给的就是脱敏后的号（后端 `PhoneMaskUtils.mask`）：只按 11 位数字判会整行丢掉。
    func testProfileAcceptsThePhoneTheBackendAlreadyMasked() {
        let content = VolunteerAccountProfileContent.make(
            profile: nil,
            phone: "138****0002",
            registrationStatus: nil
        )
        XCTAssertEqual(content.rows.map(\.value), ["138****0002"])
        XCTAssertEqual(content.rows.first?.spokenValue, "尾号 0002")
    }

    /// 拿不到的行不画，不留占位符号。注册状态只在 `stepDetails` 里给身份状态时也要认。
    func testProfileDropsRowsItCannotFill() {
        let noStatus = VolunteerAccountProfileContent.make(
            profile: VolunteerProfileResponse(name: "测试志愿者"),
            phone: nil,
            registrationStatus: nil
        )
        XCTAssertEqual(noStatus.rows.map(\.title), ["姓名"])

        // 不是 11 位的号码 `maskPhone` 会原样返回 —— 那样全号就上屏了，所以整行不画。
        let oddPhone = VolunteerAccountProfileContent.make(
            profile: VolunteerProfileResponse(name: " "),
            phone: "12345",
            registrationStatus: VolunteerRegistrationStatus(
                stepDetails: VolunteerRegistrationStepDetails(idVerifyStatus: "pending")
            )
        )
        XCTAssertNil(oddPhone.displayName)
        XCTAssertEqual(oddPhone.rows.map(\.title), ["实名认证"])
        XCTAssertEqual(oddPhone.rows.first?.value, "审核中")
    }

    // MARK: - 资质证书卡

    func testCertificateCardStylePerState() {
        XCTAssertTrue(VolunteerCertificateDisplayState.notSubmitted.cardStyle.isPlaceholder)
        XCTAssertTrue(VolunteerCertificateDisplayState.statusUnavailable.cardStyle.isPlaceholder)
        for state in [VolunteerCertificateDisplayState.pending, .approved, .rejected] {
            guard case .filled = state.cardStyle else {
                return XCTFail("\(state) 应该是实心卡")
            }
        }
        XCTAssertEqual(VolunteerCertificateDisplayState.rejected.headline(isAlternativeIdentityPath: false), "审核未通过")
    }

    /// 替代路径（拒绝人脸、传身份材料）的标题和空卡不许出现「证书」：他手上没有证书。
    func testAlternativePathNeverSaysCertificate() {
        let states: [VolunteerCertificateDisplayState] = [.notSubmitted, .pending, .approved, .rejected, .statusUnavailable]
        for state in states {
            XCTAssertFalse(state.headline(isAlternativeIdentityPath: true).contains("证书"), "\(state)")
            XCTAssertFalse(state.placeholderText(isAlternativeIdentityPath: true).contains("证书"), "\(state)")
        }
        XCTAssertFalse(VolunteerCertificateCardCopy.notSubmittedDetail(isAlternativeIdentityPath: true).contains("证书"))
        XCTAssertTrue(VolunteerCertificateCardCopy.notSubmittedDetail(isAlternativeIdentityPath: true).contains("审核时间较长，但结果等效"))
    }

    /// 卡上压白字（发证方 90%、证书名 100%、持证人 94%），状态胶囊是白底压卡色。
    /// 卡色两档外观同值，三种都要过 4.5:1（正文门槛）。
    func testCertificateCardColoursKeepWhiteTextReadable() {
        for state in [VolunteerCertificateDisplayState.pending, .approved, .rejected] {
            guard case .filled(let background) = state.cardStyle else { return XCTFail("\(state)") }
            let eyebrow = Self.blendWhite(opacity: AppColors.Flow.onHeroEyebrowOpacity, over: background)
            XCTAssertGreaterThanOrEqual(
                Self.contrastRatio(eyebrow, background), 4.5,
                "\(state)：90% 白字压 #\(String(format: "%06X", background))"
            )
            XCTAssertGreaterThanOrEqual(Self.contrastRatio(0xFFFFFF, background), 4.5, "\(state)")
        }
    }

    // MARK: - 辅助

    private func makeTransaction(
        delta: Int = 10,
        reason: String? = "ORDER_COMPLETED",
        createdAt: String?
    ) -> PointTransactionResponse {
        PointTransactionResponse(id: 1, delta: delta, reason: reason, orderId: nil, note: nil, createdAt: createdAt)
    }

    /// 半透明白叠在不透明底上之后的颜色。
    private static func blendWhite(opacity: Double, over background: UInt32) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let base = Double((background >> UInt32(shift)) & 0xFF)
            let mixed = UInt32((255 * opacity + base * (1 - opacity)).rounded())
            return result | (mixed << UInt32(shift))
        }
    }

    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    private static func relativeLuminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
