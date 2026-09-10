import XCTest
@testable import blindRun

/// 陪跑偏好的采集与**同意分层**。
///
/// 背景（不写清楚下一个人会把分层合并掉）：`visionLevel` / `hasGuideDog` 是敏感个人信息
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

    /// 🔴 没取得单独同意时，`visionLevel` 与 `hasGuideDog` **必须缺席**。
    ///
    /// 不是「传默认值」也不是「传 false」—— 那会把「用户没说」伪造成「用户说了」。
    /// 后端此刻没有 `NOT_SPECIFIED` 取值（已投 handoff），所以在它上线之前，
    /// 「拒绝」在协议上唯一诚实的表达就是不带这两个键。
    ///
    /// **验红方式**：把 `makeProfileUpdateRequest` 里的 `hasVisionConsent ? … : nil`
    /// 改成无条件传值，这条必须失败。
    func testProfileUpdateOmitsVisionFieldsWithoutConsent() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        XCTAssertFalse(viewModel.hasVisionConsent, "全新账号不该默认已同意")

        // 即使内部状态被填上（例如用户先同意、又在别处撤回），没同意就一个键都不许发。
        viewModel.visionLevel = .lowVision
        viewModel.hasGuideDog = true

        let request = viewModel.makeProfileUpdateRequest()

        XCTAssertNil(request.visionLevel, "没有单独同意就上传视力状况 —— PIPL 第二十九条硬违规")
        XCTAssertNil(request.hasGuideDog, "没有单独同意就上传导盲犬信息 —— 同上")
    }

    /// 同意之后才允许带上，且带的是用户真的选的值。
    func testProfileUpdateCarriesVisionFieldsOnceConsentIsGiven() {
        let appState = makeAppState()
        let viewModel = makeViewModel(appState: appState)

        viewModel.acceptVisionConsent()
        viewModel.visionLevel = .lowVision
        viewModel.hasGuideDog = true

        let request = viewModel.makeProfileUpdateRequest()

        XCTAssertTrue(viewModel.hasVisionConsent)
        XCTAssertEqual(request.visionLevel, VisionLevel.lowVision.rawValue)
        XCTAssertEqual(request.hasGuideDog, true)
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
                tetherPreference: TetherPreference.armHold.rawValue
            )
        )

        let viewModel = makeViewModel(appState: appState)

        XCTAssertEqual(viewModel.visionLevel, .lowVision)
        XCTAssertEqual(viewModel.hasGuideDog, true)
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
}
