import XCTest
@testable import blindRun

/// 首次启动告知与两个实名收集点的**单独同意**。
///
/// 守的是合规约束，不是体验约束：PIPL 第 14 条要求告知后取得同意，第 29 条要求处理敏感个人信息
/// （身份证号、人脸、行踪轨迹）取得**单独**同意。「同意页没弹出来」这类缺陷在 UI 里几乎测不出来，
/// 所以判定被抽成纯逻辑放在这里。
@MainActor
final class PrivacyConsentTests: XCTestCase {

    // MARK: - Store

    func testConsentIsNotGrantedUntilItIsRecorded() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = PrivacyConsentStore(persistence: persistence)

        for purpose in PrivacyConsentPurpose.allCases {
            XCTAssertFalse(store.hasConsented(to: purpose, scope: .device), "\(purpose) 不该默认已同意")
        }

        store.recordConsent(to: .appLaunch, scope: .device)
        XCTAssertTrue(store.hasConsented(to: .appLaunch, scope: .device))
    }

    /// 三个目的互不相干：同意首启告知**不等于**同意交出身份证号，这正是「单独同意」的含义。
    func testOnePurposeDoesNotGrantAnother() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = PrivacyConsentStore(persistence: persistence)

        store.recordConsent(to: .appLaunch, scope: .device)

        XCTAssertFalse(store.hasConsented(to: .blindIdentity, scope: .user("42")))
        XCTAssertFalse(store.hasConsented(to: .volunteerIdentity, scope: .user("42")))
    }

    /// 实名那两条按**人**记。同一台手机换人用不是罕见场景，视障用户的设备常由家人协助设置。
    func testIdentityConsentDoesNotCarryOverToAnotherAccount() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = PrivacyConsentStore(persistence: persistence)

        store.recordConsent(to: .blindIdentity, scope: .user("42"))

        XCTAssertTrue(store.hasConsented(to: .blindIdentity, scope: .user("42")))
        XCTAssertFalse(store.hasConsented(to: .blindIdentity, scope: .user("43")), "另一个账号不该继承同意")
        XCTAssertFalse(store.hasConsented(to: .blindIdentity, scope: .device))
    }

    /// 告知内容一改，旧同意就没有覆盖到新内容，必须重新征得。版本号进 key，旧记录自然失效。
    func testBumpingTheDisclosureVersionInvalidatesOldConsent() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = PrivacyConsentStore(persistence: persistence)

        store.recordConsent(to: .appLaunch, scope: .device)

        let nextVersionKey = PrivacyConsentStore.storageKey(
            purpose: .appLaunch,
            scope: .device,
            version: PrivacyConsentPurpose.appLaunch.disclosureVersion + 1
        )
        XCTAssertNil(persistence.object(forKey: nextVersionKey), "改版后不该读到上一版的同意")
    }

    // MARK: - AppState 接线

    /// 全新安装：没同意过就是没同意。`ContentView` 靠这个标志决定要不要挡在路由前面。
    func testFreshInstallHasNotAcceptedTheLaunchDisclosure() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }

        let appState = AppState(persistence: persistence)

        XCTAssertFalse(appState.didAcceptPrivacyConsent)
    }

    /// 「同意」必须是一个主动动作，且要落盘 —— 只改内存的话下次冷启动又会挡一遍。
    func testAcceptingTheLaunchDisclosurePersistsAcrossRelaunch() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }

        let appState = AppState(persistence: persistence)
        appState.acceptPrivacyConsent()
        XCTAssertTrue(appState.didAcceptPrivacyConsent)

        // 同一个持久化域上重建 AppState = 下一次冷启动。
        let relaunched = AppState(persistence: persistence)
        XCTAssertTrue(relaunched.didAcceptPrivacyConsent, "同意应当跨启动保留")
    }

    /// UI 用例默认跳过同意门，专测它的那条用 `FORCE` 走真实首启路径。
    /// 写反的表现是**全部 UI 用例被同意页挡住**，而真机 UI 通道时好时坏，坏的时候没人会发现。
    func testUITestLaunchSkipsTheGateUnlessItIsTheOneUnderTest() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }

        XCTAssertTrue(
            AppState.resolveInitialPrivacyConsent(
                persistence: persistence,
                environment: ["AIDRUN_UI_TEST_RESET_STATE": "1"]
            ),
            "普通 UI 用例应当跳过同意门"
        )
        XCTAssertFalse(
            AppState.resolveInitialPrivacyConsent(
                persistence: persistence,
                environment: [
                    "AIDRUN_UI_TEST_RESET_STATE": "1",
                    "AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT": "1"
                ]
            ),
            "专测同意门的用例必须真的看到它"
        )
        XCTAssertFalse(
            AppState.resolveInitialPrivacyConsent(persistence: persistence, environment: [:]),
            "真实安装没有这些环境变量，一律要同意"
        )
    }

    // MARK: - 告知文案

    /// 每条告知在 UI 上是**独立的 VoiceOver 焦点**，拼成一段长文本等于没有告知：
    /// 读屏会一口气念完，用户记不住也回不去。
    func testEveryPurposeHasDistinctWholeSentenceDisclosures() {
        for purpose in PrivacyConsentPurpose.allCases {
            let disclosures = purpose.disclosures
            XCTAssertGreaterThanOrEqual(disclosures.count, 3, "\(purpose) 的告知太少")
            XCTAssertEqual(Set(disclosures).count, disclosures.count, "\(purpose) 的告知有重复")
            for text in disclosures {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertTrue(text.hasSuffix("。"), "每条告知都该是完整的一句话：\(text)")
            }
            XCTAssertFalse(purpose.title.isEmpty)
            XCTAssertFalse(purpose.agreeButtonTitle.isEmpty)
            XCTAssertFalse(purpose.declineButtonTitle.isEmpty)
            XCTAssertFalse(purpose.declinedFeedback.isEmpty)
        }
    }

    /// 两个实名收集点必须逐字说出「身份证号」，首启那条必须说出三类敏感信息 ——
    /// 告知里不点名，用户无从判断自己在同意什么。
    func testSensitiveItemsAreNamedInTheDisclosures() {
        let launch = PrivacyConsentPurpose.appLaunch.disclosures.joined()
        for keyword in ["身份证号", "人脸", "位置", "手机号"] {
            XCTAssertTrue(launch.contains(keyword), "首启告知漏了「\(keyword)」")
        }

        XCTAssertTrue(PrivacyConsentPurpose.blindIdentity.disclosures.joined().contains("身份证号"))
        let volunteer = PrivacyConsentPurpose.volunteerIdentity.disclosures.joined()
        XCTAssertTrue(volunteer.contains("身份证号"))
        XCTAssertTrue(volunteer.contains("人脸"), "志愿者下一步就是活体认证，必须在这一屏说清")
    }

    /// 告知内容改了而 `disclosureVersion` 该 +1 却没 +1，旧同意会被当成对新内容的同意 ——
    /// 那是合规上的漏洞，且没有任何运行时表现，只能靠这条钉住。
    ///
    /// ⚠️ **这条红了不是「去 +1 版本号」，是「去做一次判断」**（判据见
    /// `PrivacyConsentPurpose.disclosureVersion` 的文档注释）：
    /// - 告知的**处理行为**变了（新收集一类信息、换用途、换接收方、改删除规则）→ +1 版本号，再换指纹
    /// - 同一个行为**换一种说法**（更准、更好懂、错别字）→ 版本号不动，只换指纹，
    ///   并在下面 `pinned` 里那一行写清这次属于哪一种
    ///
    /// 无脑 +1 的代价不是零：每个老用户下次冷启动都会被拦在同意页前面重来一次，
    /// 而对读屏用户那是一整屏要逐条听完的文本。
    func testDisclosureFingerprintIsPinnedToItsVersion() {
        // 指纹自己算，不用 `hashValue`：Swift 的 Hasher 每个进程重新播种，跨进程不稳定。
        func fingerprint(_ purpose: PrivacyConsentPurpose) -> Int {
            ([purpose.title] + purpose.disclosures)
                .joined(separator: "\u{1}")
                .unicodeScalars
                .reduce(into: 5381) { $0 = ($0 &* 33 &+ Int($1.value)) % 1_000_000_007 }
        }

        let pinned: [PrivacyConsentPurpose: (version: Int, fingerprint: Int)] = [
            // 2026-08-20 指纹变了而版本号没变，是**有意的**：删除账户那句改成正面列举保留了什么、
            // 并拆成两条独立焦点，但后端 `UserService.cascadeDeletePii` 的删除行为一个字节都没改
            // （handoff 2026-08-19 逐句核过）—— 属「同一行为换个说法」，不属「行为变了」。
            .appLaunch: (1, 787_414_606),
            .blindIdentity: (1, 997_349_647),
            .volunteerIdentity: (1, 57_319_275)
        ]

        for purpose in PrivacyConsentPurpose.allCases {
            guard let expected = pinned[purpose] else {
                return XCTFail("新增了处理目的 \(purpose) 却没有钉住它的告知内容")
            }
            XCTAssertEqual(purpose.disclosureVersion, expected.version, "\(purpose) 的版本号变了，更新这里的指纹")
            XCTAssertEqual(
                fingerprint(purpose),
                expected.fingerprint,
                """
                \(purpose) 的告知文案变了。先判一次这次属于哪一种：
                ① 告知的处理行为变了 → 把 disclosureVersion +1，再把新指纹填进来；
                ② 同一行为换个说法 → 版本号不动，只换指纹，并在 pinned 那一行写清理由。
                """
            )
        }
    }

    // MARK: - 内置隐私政策全文

    /// 后端 `privacyPolicyUrl` 目前返回 null，**用户和审核员读到的就是这份内置文案**。
    /// 漏列一项等于「未公开收集使用规则」，是中国区上架的直接违规项。
    func testBuiltInPrivacyPolicyListsEveryCollectedItem() {
        let text = LegalFallbackCopy.document(for: .privacyPolicy)
            .sections
            .flatMap(\.bullets)
            .joined()

        for item in ["手机号", "身份证号", "位置", "轨迹", "麦克风", "相机", "人脸", "紧急联系人"] {
            XCTAssertTrue(text.contains(item), "内置隐私政策漏列了「\(item)」")
        }
        XCTAssertTrue(text.contains("敏感个人信息"), "敏感项要点名，不能混在普通收集项里")
    }
}
