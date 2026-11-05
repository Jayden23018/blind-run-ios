import XCTest
@testable import blindRun

/// 个人资料「点哪行改哪行，当场保存」（#750）：`BlindRunnerProfileViewModel.saveChange` 的保存、回退与请求体。
/// 从 `BlindEscortPreferencesTests` 分出来：那个文件已到 swiftlint 长度上限。
@MainActor
final class BlindProfileSaveChangeTests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    /// ⚠️ `BlindRunnerProfileViewModel.appState` 是 **weak**，AppState 必须由调用方持强引用。
    private func makeViewModel(appState: AppState) -> BlindRunnerProfileViewModel {
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.name = "测试昵称"
        return viewModel
    }

    /// 选完当场整份保存：请求带上新值，存上后上屏并念「已保存：搀扶」，值不回退。
    func testSaveChangeSendsTheWholeProfileAndAnnouncesTheChoice() async {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试昵称", tetherPreference: "ARM_HOLD"))
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)
        var reverted = false

        viewModel.tetherPreference = .armHold
        let saved = await viewModel.saveChange(savedLabel: "搀扶") { reverted = true }

        XCTAssertTrue(saved)
        XCTAssertFalse(reverted, "存上了不该回退")
        XCTAssertEqual(client.lastUpdate?.tetherPreference, "ARM_HOLD")
        XCTAssertEqual(client.lastUpdate?.name, "测试昵称", "要整份提交，昵称不能缺")
        XCTAssertEqual(viewModel.savedNotice, "已保存：搀扶")
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 没存上：调 `revert`（对勾回到原值）、上屏错误、不出「已保存」。
    /// **验红方式**：删掉 `saveChange` 里 `if !saved { revert() }`，这条必须失败。
    func testSaveChangeRevertsAndReportsWhenTheSaveFails() async {
        let client = ProfileSaveSpy()
        client.result = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)
        viewModel.tetherPreference = .tetherRope

        viewModel.tetherPreference = .armHold
        let saved = await viewModel.saveChange(savedLabel: "搀扶") { viewModel.tetherPreference = .tetherRope }

        XCTAssertFalse(saved)
        XCTAssertNotNil(client.lastUpdate, "前提：请求发出去了，是服务端没存上")
        XCTAssertEqual(viewModel.tetherPreference, .tetherRope, "没存上，值要回到原来的")
        XCTAssertNil(viewModel.savedNotice)
        XCTAssertNotNil(viewModel.errorMessage, "失败要上屏")
    }

    /// 昵称编辑页（`requiresNickname`）存空昵称或 1 个字：一个请求都不发，值回退，念长度提示。
    /// 1 个字那一档守的是「客户端只判非空」的旧口径 —— 后端 `@Size(min = 2)` 会 400。
    func testSaveChangeRejectsANicknameOutsideTwoToFiftyCharacters() async {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试昵称"))
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)

        for (draft, message) in [
            ("  ", "请填写昵称，2 到 50 个字。"),
            ("测", "昵称至少 2 个字。"),
            (String(repeating: "测", count: 51), "昵称最多 50 个字，现在是 51 个字。"),
        ] {
            viewModel.name = draft
            let saved = await viewModel.saveChange(savedLabel: "昵称", requiresNickname: true) { viewModel.name = "测试昵称" }
            XCTAssertFalse(saved, draft)
            XCTAssertNil(client.lastUpdate, "过不了校验不该发请求：\(draft)")
            XCTAssertEqual(viewModel.name, "测试昵称", "没存上要回到原值：\(draft)")
            XCTAssertEqual(viewModel.errorMessage, message)
        }

        viewModel.name = String(repeating: "测", count: 50)
        let saved = await viewModel.saveChange(savedLabel: "昵称", requiresNickname: true) { viewModel.name = "测试昵称" }
        XCTAssertTrue(saved, "50 个字在上限内")
    }

    /// 还没填昵称（#781 起新用户不填资料就能进首页）时改别的行：照样保存，请求体不带 `name`，
    /// 后端保留原值（backend#926）；带空串会被 400「姓名不能为空」。
    func testSaveChangeWithoutANicknameOmitsTheNameKey() async throws {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(tetherPreference: "ARM_HOLD"))
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)
        viewModel.name = ""

        viewModel.tetherPreference = .armHold
        let saved = await viewModel.saveChange(savedLabel: "搀扶") { viewModel.tetherPreference = nil }

        XCTAssertTrue(saved)
        let sent = try XCTUnwrap(client.lastUpdate)
        XCTAssertNil(sent.name)
        let json = String(decoding: try JSONEncoder().encode(sent), as: UTF8.self)
        XCTAssertFalse(json.contains("\"name\""), "空昵称不能带键：\(json)")
    }

    /// 选「无偏好」要明确发 `NO_PREFERENCE`：查看页会念「已保存：无偏好」，不带键的话服务端保留旧配速，那句话是假的。
    /// 档案里的配速这个版本认不出、用户也没动时才不带键，免得把认不出的值覆盖掉。
    /// **验红方式**：把 `makeProfileUpdateRequest` 的配速改回 `defaultPace == .noPreference ? nil : defaultPace`，第一段必须失败。
    func testNoPacePreferenceIsSentExplicitlyUnlessTheStoredValueIsUnreadable() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试昵称", defaultPace: .fast))
        let viewModel = makeViewModel(appState: appState)
        viewModel.defaultPace = .noPreference
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().defaultPace, .noPreference)

        let unreadableState = makeAppState()
        unreadableState.updateBlindProfile(BlindProfileResponse(name: "测试昵称", defaultPace: .unknown))
        let untouched = makeViewModel(appState: unreadableState)
        XCTAssertEqual(untouched.defaultPace, .noPreference, "前提：认不出的值显示成「无偏好」")
        XCTAssertNil(untouched.makeProfileUpdateRequest().defaultPace, "用户没动认不出的配速，不能覆盖")
        untouched.defaultPace = .easy
        XCTAssertEqual(untouched.makeProfileUpdateRequest().defaultPace, .easy)
    }

    /// `runningPace` 界面不改，但契约是「不带这个键 = 清空」：每次保存要把读到的值原样带回。
    /// **验红方式**：把 `makeProfileUpdateRequest` 的 `runningPace` 改回 `nil`，这条必须失败。
    func testSavingKeepsTheStoredRunningPace() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "测试昵称", runningPace: "MODERATE"))
        let viewModel = makeViewModel(appState: appState)

        viewModel.tetherPreference = .armHold

        XCTAssertEqual(viewModel.makeProfileUpdateRequest().runningPace, "MODERATE", "不带 runningPace 后端会把它清空")
    }
}
