import XCTest
@testable import blindRun

/// 陪跑偏好的采集与**同意分层**。
///
/// 背景（不写清楚下一个人会把分层合并掉）：`visionLevel` / `guideDog` 是敏感个人信息
/// （PIPL 第二十八条「特定身份」，依据链见 `docs/research/vision-level-collection-ui-20260910.md`），
/// 走 `PrivacyConsentPurpose.blindVisionProfile` 单独同意；而 `tetherPreference`（引导方式）
/// **不敏感**，在同意门之外。
///
/// 🔴 **分层不是体面，是「可拒绝」能不能成立的唯一支点**：拒绝敏感项的人仍然填得了引导方式，
/// 志愿者仍知道该递绳还是该让人挽手臂，服务照常可用。把两者合并成一次同意，
/// 「拒绝」就等于服务降级 —— 而 GB/T 42574-2023 允许「多字段一次性单独同意」的前提恰恰是
/// 「逐项拆分后无法达成处理目的」，我们拆得开，所以打包反而不满足那条豁免。
@MainActor
final class BlindEscortPreferencesTests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    /// ⚠️ `BlindRunnerProfileViewModel.appState` 是 **weak**，传临时对象等于传 nil
    /// （记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    /// 所以 AppState 必须由调用方持强引用，这里只负责接线。
    private func makeViewModel(appState: AppState) -> BlindRunnerProfileViewModel {
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.name = "测试昵称"
        return viewModel
    }

    // MARK: - 红线一：没同意就不许上传敏感项

    /// 🔴 没取得单独同意时，`visionLevel` 与 `guideDog` **必须缺席**。
    ///
    /// 不是「传默认值」也不是「传 false」—— 那会把「用户没说」伪造成「用户说了」。
    /// 「没被问过」在协议上的诚实表达是不带这两个键（后端保留原值）；
    /// 「明确拒绝」才显式传 `NOT_SPECIFIED`，见 `testDecliningVisionConsentSendsNotSpecified`。
    ///
    /// **验红方式**：把 `makeProfileUpdateRequest` 里的 `hasVisionConsent ? … : nil`
    /// 改成无条件传值，这条必须失败。
    func testProfileUpdateOmitsVisionFieldsWithoutConsent() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        XCTAssertFalse(viewModel.hasVisionConsent, "全新账号不该默认已同意")

        // 即使内部状态被填上（例如用户先同意、又在别处撤回），没同意就一个键都不许发。
        viewModel.visionLevel = .lowVision
        viewModel.guideDog = .yes

        let request = viewModel.makeProfileUpdateRequest()

        XCTAssertNil(request.visionLevel, "没有单独同意就上传视力状况 —— PIPL 第二十九条硬违规")
        XCTAssertNil(request.guideDog, "没有单独同意就上传导盲犬信息 —— 同上")
    }

    /// 同意之后才允许带上，且带的是用户真的选的值。
    func testProfileUpdateCarriesVisionFieldsOnceConsentIsGiven() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.acceptVisionConsent()
        viewModel.visionLevel = .lowVision
        viewModel.guideDog = .yes

        let request = viewModel.makeProfileUpdateRequest()

        XCTAssertTrue(viewModel.hasVisionConsent)
        XCTAssertEqual(request.visionLevel, VisionLevel.lowVision.rawValue)
        XCTAssertEqual(request.guideDog, "YES")
    }

    /// 同意了但没选，仍然不许替用户填一个值。
    ///
    /// 这一条挡的是「同意 = 默认全盲」这种顺手写法：同意的是**可以问**，不是**已经答**。
    func testConsentAloneDoesNotFabricateAVisionLevel() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.acceptVisionConsent()

        XCTAssertNil(viewModel.makeProfileUpdateRequest().visionLevel)
    }

    // MARK: - 拒绝 = 显式 NOT_SPECIFIED（后端迁移 0056，backend#326）

    /// 用户在同意页明确拒绝 ⇒ 视力状况与导盲犬都显式传 `NOT_SPECIFIED`。
    ///
    /// 导盲犬最早是缺席，服务端旧的 `true` 一直留着；#352 改成传 `hasGuideDog: false`，
    /// 后端却会存成「明确没有」—— 把「用户没说」伪造成「用户说了」。后端 #800 起有了
    /// `guideDog = NOT_SPECIFIED`，负责人 2026-10-19 定改发它（#472）。
    ///
    /// **验红方式**：把拒绝分支的 `guideDog` 改成 `GuideDogStatus.no.rawValue`，这条必须失败。
    func testDecliningVisionConsentSendsNotSpecified() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.declineVisionConsent()
        // 就算内部状态被填过，拒绝也不许把它带出去。
        viewModel.visionLevel = .lowVision
        viewModel.guideDog = .yes

        let request = viewModel.makeProfileUpdateRequest()

        XCTAssertEqual(request.visionLevel, "NOT_SPECIFIED")
        XCTAssertEqual(request.guideDog, "NOT_SPECIFIED", "拒绝时传 NO 会被后端存成「明确没有导盲犬」")
    }

    /// 「从没被问过」≠「拒绝」：新设备同意记录不在，一律传 `NOT_SPECIFIED` 会把后端已存的
    /// `LOW_VISION` 覆盖掉。没拒绝就不带键。
    ///
    /// **验红方式**：把拒绝判据改成 `!hasVisionConsent`，这条必须失败。
    func testNeverAskedIsNotADeclineAndOmitsTheKey() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        XCTAssertFalse(viewModel.hasVisionConsent)
        XCTAssertFalse(viewModel.hasDeclinedVisionConsent)
        XCTAssertNil(viewModel.makeProfileUpdateRequest().visionLevel)
        XCTAssertNil(viewModel.makeProfileUpdateRequest().guideDog)
    }

    /// 先拒绝、后来又同意：以最后一次为准，传用户选的值而不是 `NOT_SPECIFIED`。
    func testAcceptingAfterDecliningSendsTheChosenValue() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.declineVisionConsent()
        viewModel.acceptVisionConsent()
        viewModel.visionLevel = .totalBlind

        XCTAssertEqual(viewModel.makeProfileUpdateRequest().visionLevel, VisionLevel.totalBlind.rawValue)
    }

    /// 生产存量档案全是 `NOT_SPECIFIED`：回读成「没选」（Picker 没有它的 tag），
    /// 保存时不带键 ⇒ 后端保留原值。
    func testStoredNotSpecifiedPrefillsAsUnsetAndIsNotResent() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "存量", visionLevel: "NOT_SPECIFIED"))

        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()

        XCTAssertNil(viewModel.visionLevel)
        XCTAssertNil(viewModel.makeProfileUpdateRequest().visionLevel)
    }

    func testVisionLevelDisplayNames() {
        XCTAssertEqual(VisionLevel.totalBlind.displayName, "全盲")
        XCTAssertEqual(VisionLevel.lowVision.displayName, "低视力")
        XCTAssertEqual(VisionLevel.notSpecified.displayName, "未提供")
        XCTAssertNil(VisionLevel.notSpecified.escortDisplayName)
        XCTAssertEqual(VisionLevel.lowVision.escortDisplayName, "低视力")
    }

    // MARK: - 红线二：引导方式在同意门之外

    /// 🔴 引导方式**不受同意门影响**，任何时候都发得出去。
    ///
    /// 它是拒绝了敏感项的用户唯一还能给志愿者的准备依据。把它挪到门后面，
    /// 「不填也能约跑」那句承诺（`PrivacyConsentTests` 钉住）就变成了空话 ——
    /// 用户拒绝之后志愿者什么都不知道，服务实际上降级了，那正是捆绑同意。
    ///
    /// **验红方式**：把 `tetherPreference` 也加上 `hasVisionConsent ? … : nil`，这条必须失败。
    func testTetherPreferenceIsSubmittedWithoutAnyConsent() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.tetherPreference = .tetherRope

        XCTAssertFalse(viewModel.hasVisionConsent, "本条的前提就是「没同意」")
        XCTAssertEqual(
            viewModel.makeProfileUpdateRequest().tetherPreference,
            TetherPreference.tetherRope.rawValue,
            "引导方式不敏感，不该被视力状况那道同意门挡住"
        )
    }

    /// 三档引导方式逐个都传得出去 —— 挡住「只有牵引绳那档被正确映射」这种半对的实现。
    func testEveryTetherPreferenceRoundTrips() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        for preference in TetherPreference.allCases {
            viewModel.tetherPreference = preference
            XCTAssertEqual(viewModel.makeProfileUpdateRequest().tetherPreference, preference.rawValue)
        }

        viewModel.tetherPreference = nil
        XCTAssertNil(viewModel.makeProfileUpdateRequest().tetherPreference, "没选就该缺席，不要塞一个默认档")
    }

    // MARK: - 回填

    /// 已有档案要能读回来，否则用户每次进资料页看到的都是空的，
    /// 一保存就把后端已有的值覆盖成 nil。
    func testExistingProfilePrefillsAllThreePreferences() {
        let appState = makeAppState()
        appState.updateBlindProfile(
            BlindProfileResponse(
                name: "已有用户",
                visionLevel: VisionLevel.lowVision.rawValue,
                hasGuideDog: true,
                guideDog: GuideDogStatus.yes.rawValue,
                tetherPreference: TetherPreference.armHold.rawValue
            )
        )

        let viewModel = makeViewModel(appState: appState)

        XCTAssertEqual(viewModel.visionLevel, .lowVision)
        XCTAssertEqual(viewModel.guideDog, .yes)
        XCTAssertEqual(viewModel.tetherPreference, .armHold)
    }

    /// 后端给了一个客户端不认识的取值时，回填成 `nil` 而不是崩、也不是猜一个。
    ///
    /// `visionLevel` 在响应模型里是 `String?`、从不作为枚举参与解码
    /// （见 `ProfileModels.swift` 上 `VisionLevel` 那段注释），所以坏值不会让整条响应解不出，
    /// 但展示层必须自己接住。
    func testUnknownBackendVisionLevelFallsBackToUnset() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "x", visionLevel: "SOMETHING_NEW"))

        let viewModel = makeViewModel(appState: appState)

        XCTAssertNil(viewModel.visionLevel, "不认识的取值要落回「没选」，不要猜成全盲")
        XCTAssertNil(viewModel.makeProfileUpdateRequest().visionLevel)
    }

    // MARK: - 选项文案

    /// 选项用**功能性自述**，不用医学分级。
    ///
    /// 依据：United In Stride 注册表原文问的是 "How would you characterize your vision?"，
    /// Washington Group（WHO/联合国统计标准）官方 FAQ 也明确反对是非题与诊断式问法。
    /// 写「一级 / 二级视力残疾」是残疾人证口径 —— 用途不对（那是福利认定，不是「志愿者该怎么准备」），
    /// 而且用户未必知道自己证上是几级。
    func testVisionOptionsUseFunctionalWordingNotDisabilityGrades() {
        for level in VisionLevel.allCases {
            for grade in ["一级", "二级", "三级", "四级", "残疾"] {
                XCTAssertFalse(
                    level.displayName.contains(grade),
                    "视力状况选项出现了医学分级口径「\(grade)」：\(level.displayName)"
                )
            }
        }
    }

    // MARK: - 撤回同意（#352，安卓 #91 同步）

    private func makeSavingViewModel(
        client: ProfileSaveSpy
    ) -> (BlindRunnerProfileViewModel, AppState) {
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()
        viewModel.visionLevel = .lowVision
        viewModel.guideDog = .yes
        return (viewModel, appState)
    }

    private func hasStoredConsent(_ appState: AppState) -> Bool {
        PrivacyConsentStore(persistence: appState.persistence).hasConsented(to: .blindVisionProfile, scope: .device)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// 撤回 ⇒ 立刻保存一次，两项都带 `NOT_SPECIFIED`；**保存成功后**才删本机同意记录。
    ///
    /// **验红方式**：把 `makeProfileUpdateRequest` 拒绝 / 撤回分支的导盲犬改成 `GuideDogStatus.no.rawValue`
    /// （#352 时 `hasGuideDog: false` 的等价写法），这条必须失败。
    func testWithdrawingSavesAtOnceAndRevokesOnlyAfterTheSaveSucceeds() async throws {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试昵称", visionLevel: "NOT_SPECIFIED", hasGuideDog: false, guideDog: "NOT_SPECIFIED"))
        let (viewModel, appState) = makeSavingViewModel(client: client)
        XCTAssertTrue(hasStoredConsent(appState), "前提：已同意")

        viewModel.withdrawVisionConsent()
        XCTAssertFalse(viewModel.hasVisionConsent, "按下就要收起两项")

        await waitUntil { viewModel.visionConsentWithdrawnNotice != nil || viewModel.errorMessage != nil }
        let sent = try XCTUnwrap(client.lastUpdate, "撤回没有立刻保存")
        XCTAssertEqual(sent.visionLevel, "NOT_SPECIFIED")
        XCTAssertEqual(sent.guideDog, "NOT_SPECIFIED", "撤回发 NO 会被后端存成「明确没有导盲犬」")
        XCTAssertFalse(hasStoredConsent(appState), "保存成功后本机同意记录必须删掉")
        XCTAssertEqual(viewModel.visionConsentWithdrawnNotice, VisionConsentWithdrawalCopy.succeeded)
        XCTAssertFalse(viewModel.isVisionConsentWithdrawalPending)
    }

    /// 保存失败：同意记录**不删**，说清要再按一次（首次引导态按钮叫「完成」）；下一次保存仍是撤回。
    func testFailedWithdrawalKeepsTheConsentRecordAndAsksToSaveAgain() async {
        let client = ProfileSaveSpy()
        client.result = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        let (viewModel, appState) = makeSavingViewModel(client: client)

        viewModel.withdrawVisionConsent()
        await waitUntil { viewModel.errorMessage != nil }

        XCTAssertEqual(viewModel.errorMessage, VisionConsentWithdrawalCopy.failed(saveButtonTitle: "完成"))
        XCTAssertTrue(hasStoredConsent(appState), "没存上就删记录：两边说的是两件事")
        XCTAssertTrue(viewModel.isVisionConsentWithdrawalPending)
        let retry = viewModel.makeProfileUpdateRequest()
        XCTAssertEqual(retry.visionLevel, "NOT_SPECIFIED")
        XCTAssertEqual(retry.guideDog, "NOT_SPECIFIED")
    }

    /// 表单过不了校验（昵称空）时按撤回：一个请求都发不出去，所以界面不能先收起、也不能记成待撤回，
    /// 只念校验错误。对照是上面的成功用例 —— 同一个撤回，昵称在时立刻收起并发请求。
    func testWithdrawingWithAnInvalidFormSendsNothingAndKeepsTheConsentShown() async {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试昵称", visionLevel: "NOT_SPECIFIED", hasGuideDog: false, guideDog: "NOT_SPECIFIED"))
        let (viewModel, appState) = makeSavingViewModel(client: client)
        viewModel.name = "  "

        viewModel.withdrawVisionConsent()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(client.lastUpdate, "表单过不了校验，不该有请求")
        XCTAssertTrue(viewModel.hasVisionConsent, "没发出去就不能收起两项")
        XCTAssertFalse(viewModel.isVisionConsentWithdrawalPending)
        XCTAssertEqual(viewModel.visionLevel, .lowVision, "没撤回成功，用户填的值不能被清掉")
        XCTAssertTrue(hasStoredConsent(appState))
        XCTAssertEqual(viewModel.errorMessage, "请填写必填信息")
    }

    /// 撤回还没存上时又重新同意 ⇒ 那次撤回作废，保存的是用户这次选的值。
    func testReconsentingWhileAWithdrawalIsPendingVoidsIt() async {
        let client = ProfileSaveSpy()
        client.result = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        let (viewModel, _) = makeSavingViewModel(client: client)
        viewModel.withdrawVisionConsent()
        await waitUntil { viewModel.errorMessage != nil }

        viewModel.acceptVisionConsent()
        viewModel.visionLevel = .totalBlind
        viewModel.guideDog = .yes

        XCTAssertFalse(viewModel.isVisionConsentWithdrawalPending)
        let request = viewModel.makeProfileUpdateRequest()
        XCTAssertEqual(request.visionLevel, VisionLevel.totalBlind.rawValue)
        XCTAssertEqual(request.guideDog, "YES")
    }

    // MARK: - 导盲犬三选一（#472，后端 #800 / backend#773）

    /// 🔴 档案是「不说」，用户同意后没碰导盲犬就保存 ⇒ 原样发 `NOT_SPECIFIED`，**不许改写成 `NO`**。
    ///
    /// 旧的 `hasGuideDog` 在「不说」时也是 `false`。照它回读，任何一次带同意的保存都会把
    /// 「不说」变成「明确没有」—— 用户从没碰过那一项也一样。
    ///
    /// **验红方式**：把 `configure` 里的回读改成 `profile.hasGuideDog == true ? .yes : .no`，这条必须失败。
    func testStoredNotSpecifiedGuideDogIsSentBackUnchanged() {
        let appState = makeAppState()
        appState.updateBlindProfile(
            BlindProfileResponse(name: "新账号", hasGuideDog: false, guideDog: GuideDogStatus.notSpecified.rawValue)
        )
        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()

        XCTAssertEqual(viewModel.guideDog, .notSpecified, "旧字段的 false 不是「没有」")
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().guideDog, "NOT_SPECIFIED")
    }

    /// 三个选项逐个发得出去，且「没有」与「不说」不塌缩成同一个值。
    func testEveryGuideDogChoiceIsSentAsItsOwnValue() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()

        for status in GuideDogStatus.allCases {
            viewModel.guideDog = status
            XCTAssertEqual(viewModel.makeProfileUpdateRequest().guideDog, status.rawValue)
        }
        XCTAssertEqual(GuideDogStatus.allCases.map(\.profileOptionTitle), ["有", "没有", "不说"])
    }

    /// 后端给了一个这个版本认不出的导盲犬取值：显示「不说」，但用户没改就保存时**不带键**，
    /// 免得把它覆盖成 `NOT_SPECIFIED`；用户改过就照选的发。
    func testUnreadableGuideDogValueIsLeftAloneUntilTheUserChangesIt() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "x", guideDog: "SOMETHING_NEW"))
        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()

        XCTAssertEqual(viewModel.guideDog, .notSpecified)
        XCTAssertNil(viewModel.makeProfileUpdateRequest().guideDog)

        viewModel.guideDog = .no
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().guideDog, "NO")
    }

    /// 旧入参 `hasGuideDog` 表达不了「不说」，请求体里**不许再出现这个键**：
    /// 两个键都带时后端以 `guideDog` 为准，留着它只会让下一个人以为它还在起作用。
    func testProfileUpdateNeverEncodesTheLegacyGuideDogKey() throws {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)
        viewModel.acceptVisionConsent()
        viewModel.guideDog = .yes

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(viewModel.makeProfileUpdateRequest())) as? [String: Any]
        )
        XCTAssertEqual(json["guideDog"] as? String, "YES")
        XCTAssertNil(json["hasGuideDog"], "旧入参还在请求体里")
    }

    // MARK: - 引导方式能撤回（#472，backend#795）

    /// 档案里是「牵引绳」，用户改回「还没决定」⇒ 发 `NOT_SPECIFIED`。不带键的话后端保留牵引绳，撤不回。
    ///
    /// **验红方式**：把 `tetherPreference:` 那行的 `?? (tetherPreferenceBaseline …)` 删掉，这条必须失败。
    func testChangingTetherBackToUndecidedSendsNotSpecified() {
        let appState = makeAppState()
        appState.updateBlindProfile(BlindProfileResponse(name: "x", tetherPreference: TetherPreference.tetherRope.rawValue))
        let viewModel = makeViewModel(appState: appState)

        viewModel.tetherPreference = nil

        XCTAssertEqual(viewModel.makeProfileUpdateRequest().tetherPreference, "NOT_SPECIFIED")
    }

    /// 档案本来就是「还没决定」或认不出的值 ⇒ 选「还没决定」不带键（后者不能被覆盖）。
    func testUndecidedTetherIsOmittedWhenNothingWasStored() {
        for stored in ["NOT_SPECIFIED", "SOMETHING_NEW"] {
            let appState = makeAppState()
            appState.updateBlindProfile(BlindProfileResponse(name: "x", tetherPreference: stored))
            let viewModel = makeViewModel(appState: appState)

            XCTAssertNil(viewModel.tetherPreference)
            XCTAssertNil(viewModel.makeProfileUpdateRequest().tetherPreference, "存的是 \(stored)")
        }
    }

    /// 先选牵引绳保存成功、再改回「还没决定」⇒ 第二次也要发 `NOT_SPECIFIED`。
    /// 基线若停在进页面那一刻（空），第二次就不带键，牵引绳撤不回。
    ///
    /// **验红方式**：删掉 `saveProfile` 成功分支里更新 `tetherPreferenceBaseline` 那一行，这条必须失败。
    func testTetherBaselineFollowsTheSavedProfile() async throws {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试昵称", tetherPreference: TetherPreference.tetherRope.rawValue))
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = makeViewModel(appState: appState)

        viewModel.tetherPreference = .tetherRope
        viewModel.submit()
        await waitUntil { client.lastUpdate != nil && !viewModel.isLoading }
        XCTAssertEqual(client.lastUpdate?.tetherPreference, TetherPreference.tetherRope.rawValue)

        viewModel.tetherPreference = nil
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().tetherPreference, "NOT_SPECIFIED")
    }
}

/// 只接 `PUT /api/blind/profile` 那一下。
private final class ProfileSaveSpy: APIClientProtocol, @unchecked Sendable {
    var result: Result<BlindProfileResponse, Error> = .failure(APIError.unknown(statusCode: -1))
    private(set) var lastUpdate: BlindProfileUpdateRequest?

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if let update = body as? BlindProfileUpdateRequest { lastUpdate = update }
        guard let typed = try result.get() as? T else { throw APIError.unknown(statusCode: -1) }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.unknown(statusCode: -1)
    }
}
