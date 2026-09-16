import XCTest
@testable import blindRun

/// 后端下发的姓名**始终带掩码星号**（`张*`，`NameMaskUtils.mask()`，契约里
/// `volunteerName` / `blindName` 都逐字写着「始终脱敏」）。
///
/// 原样交给 VoiceOver 与 TTS，读屏念出来的是「张星号」—— 而本 App 的读屏是**外放**的，
/// 「星号」还会被当成名字的一部分。这一组钉的是同一条口径的两半，缺一半都不算修好：
///
/// - **念出来的那一份没有 `*`**（`String.unmaskedForSpeech`）
/// - **屏幕上那一份仍然有 `*`** —— 去掩码只发生在朗读通道，不是把脱敏撤掉
///
/// 验红方式：把任一调用点的 `volunteerNameForSpeech` / `spokenName(fallback:)`
/// 换回 `volunteerName` / `name`，这里就会红。
final class MaskedNameSpeechTests: XCTestCase {

    // MARK: - 取值本身

    func testVolunteerNameForSpeechDropsTheMaskWhileTheFieldItselfKeepsIt() {
        let order = Self.makeOrder(volunteerName: "张*")

        XCTAssertEqual(order.volunteerNameForSpeech, "张", "念出来的那一份不许带星号")
        XCTAssertEqual(order.volunteerName, "张*", "屏幕上那一份必须原样保留后端的掩码")
    }

    /// 全角 `＊` 同样要去（后端换掩码字符时不至于静默退回念星号），
    /// 而「整个名字只剩一个星号」要落到兜底名 —— 不能念出一句空白的「把设为固定搭档」。
    func testFullWidthMaskIsDroppedAndAnAllMaskNameFallsBackToTheUnknownCopy() {
        XCTAssertEqual(Self.makeOrder(volunteerName: "李＊").volunteerNameForSpeech, "李")
        XCTAssertEqual(
            Self.makeOrder(volunteerName: "*").volunteerNameForSpeech,
            PartnerStreakCopy.unknownVolunteerName
        )
        XCTAssertEqual(
            Self.makeOrder(volunteerName: nil).volunteerNameForSpeech,
            PartnerStreakCopy.unknownVolunteerName
        )
    }

    // MARK: - 陪跑中那一屏的顶行

    /// 这一屏跑动中长时间开着，顶行是搭档身份的唯一听觉出口。
    /// 可见文字与 accessibilityLabel 取的是**两个不同的属性**，用例同时钉住两边。
    @MainActor
    func testActiveRunHeaderShowsTheMaskOnScreenButNeverSpeaksIt() {
        let view = BlindActiveRunView(
            order: Self.makeOrder(volunteerName: "张*", status: .inProgress),
            stats: nil,
            isLocationFresh: true
        )

        XCTAssertTrue(
            view.partnerHeadline.hasSuffix("张*"),
            "屏幕上那行仍然是掩码原样，实际值：\(view.partnerHeadline)"
        )
        XCTAssertTrue(
            view.spokenPartnerHeadline.hasSuffix("张"),
            "念出来那行去掉星号，实际值：\(view.spokenPartnerHeadline)"
        )
        XCTAssertFalse(view.spokenPartnerHeadline.contains("*"))
    }

    // MARK: - 收藏成功的那一句（屏幕一句、播报另一句）

    /// `favoriteNotice` 上屏、`speak(_:)` 进耳朵，两者**不是同一个字符串**。
    ///
    /// 这是本轮唯一一条真的走了一遍调用点的用例：它盯的是
    /// `BlindOrderStatusViewModel.addVolunteerToFavorites` 里那两行分叉，
    /// 把播报那行换回 `name` 就会红。
    @MainActor
    func testFavoriteAnnouncementDropsTheMaskWhileTheOnScreenNoticeKeepsIt() async throws {
        let incentive = FakeIncentiveService()
        incentive.addBlindFavoriteVolunteerResult = .success(())
        let appState = AppState(incentive: incentive)
        appState.currentEnvironment = .mock

        let speech = SpeechService()
        speech.resetSpokenHistoryForTesting()

        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = Self.makeOrder(
            volunteerName: "张*",
            status: .completed,
            volunteerId: 88
        )

        await viewModel.addVolunteerToFavorites()

        let spoken = try XCTUnwrap(speech.spokenHistoryForTesting.last, "这一步必须播报，否则盲人没有反馈")
        XCTAssertFalse(spoken.contains("*"), "播报里不许出现掩码星号，实际念的是：\(spoken)")
        XCTAssertTrue(spoken.contains("张"), "去星号之后姓氏要还在，实际念的是：\(spoken)")
        XCTAssertEqual(
            viewModel.favoriteNotice,
            PartnerStreakCopy.favoriteAdded("张*"),
            "屏幕上那行仍然是掩码原样"
        )
    }

    // MARK: - 固定搭档列表（同一个名字同时是按钮文字和读屏标签）

    func testPartnerRowKeepsTheMaskOnScreenAndDropsItInSpeech() {
        let row = PartnerRow(
            userId: 9,
            name: "王*",
            completedRunsTogether: 3,
            favoritedAt: nil,
            hasOptedOut: false,
            streak: nil,
            isFavorite: true
        )
        let fallback = PartnerStreakCopy.unknownVolunteerName

        XCTAssertEqual(row.displayName(fallback: fallback), "王*")
        XCTAssertEqual(row.spokenName(fallback: fallback), "王")

        // 按钮标题是可见文字，accessibilityLabel 是同一句话的另一份取值。
        XCTAssertEqual(
            PartnerStreakCopy.addFavoriteTitle(row.displayName(fallback: fallback)),
            "把王*设为固定搭档"
        )
        XCTAssertEqual(
            PartnerStreakCopy.addFavoriteTitle(row.spokenName(fallback: fallback)),
            "把王设为固定搭档"
        )
    }

    /// 名字为空（对方已注销）时两条通道都落到兜底名，不留一个空洞。
    func testMissingPartnerNameFallsBackOnBothChannels() {
        let row = PartnerRow(
            userId: nil,
            name: nil,
            completedRunsTogether: nil,
            favoritedAt: nil,
            hasOptedOut: true,
            streak: nil,
            isFavorite: false
        )

        XCTAssertEqual(row.displayName(fallback: PartnerStreakCopy.unknownBlindName), "这位跑者")
        XCTAssertEqual(row.spokenName(fallback: PartnerStreakCopy.unknownBlindName), "这位跑者")
    }

    // MARK: - 志愿者端念盲人姓名

    /// 志愿者端的历史行：整条 label 只进读屏（可见文字在卡片里另有一份）。
    func testVolunteerHistoryRowLabelNeverSpeaksTheMask() {
        let record = VolunteerServiceRecord(
            order: Self.makeOrder(volunteerName: nil, status: .completed, blindName: "李*")
        )

        XCTAssertFalse(
            record.accessibilityLabel.contains("*"),
            "读屏标签里不许出现掩码星号，实际值：\(record.accessibilityLabel)"
        )
        XCTAssertTrue(
            record.accessibilityLabel.contains("盲人：李，"),
            "去星号之后姓氏要还在，实际值：\(record.accessibilityLabel)"
        )
    }

    // MARK: - Fixture

    private static func makeOrder(
        volunteerName: String?,
        status: RunOrderStatus = .inProgress,
        volunteerId: Int64? = nil,
        blindName: String? = nil
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 9001,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: "2026-09-16T09:00:00",
            plannedEnd: "2026-09-16T10:00:00",
            blindName: blindName,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: "2026-09-16T08:00:00",
            expectedDurationMinutes: 60,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil,
            volunteerId: volunteerId,
            volunteerName: volunteerName
        )
    }
}
