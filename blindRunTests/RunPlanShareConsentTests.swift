import XCTest
@testable import blindRun

/// 实时行程分享的明示同意。
///
/// 这一组用例守的是一条**合规**约束，不是体验约束：调 `POST /api/orders/{id}/share`
/// 等同于盲人对「向持链接者提供本人实时位置与轨迹」作出单独同意（PIPL 第 23 / 28 / 29 条）。
/// 后端 2026-08-13 的通报逐字写着「做成一键静默分享，这个同意在法律上不成立」。
/// 「首次没走全屏引导」这类缺陷在 UI 里几乎测不出来，所以判定被抽成纯逻辑放在这里。
@MainActor
final class RunPlanShareConsentTests: XCTestCase {

    // MARK: - 分支判定

    func testFirstShareGoesThroughFullDisclosure() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = RunPlanShareConsentStore(persistence: persistence)

        XCTAssertFalse(store.hasGivenConsent(userKey: "42"))
        XCTAssertEqual(
            RunPlanShareConsentStep.next(hasGivenConsent: store.hasGivenConsent(userKey: "42")),
            .fullDisclosure
        )
    }

    func testLaterSharesGetTheShortConfirmation() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = RunPlanShareConsentStore(persistence: persistence)

        store.recordConsent(userKey: "42")

        XCTAssertTrue(store.hasGivenConsent(userKey: "42"))
        XCTAssertEqual(
            RunPlanShareConsentStep.next(hasGivenConsent: store.hasGivenConsent(userKey: "42")),
            .shortConfirmation
        )
    }

    /// 同意是**个人**作出的。换账号登录不继承前一个人的同意 ——
    /// 同一台手机换人用不是罕见场景，视障用户的设备常由家人协助设置。
    func testConsentDoesNotCarryOverToAnotherAccount() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = RunPlanShareConsentStore(persistence: persistence)

        store.recordConsent(userKey: "42")

        XCTAssertFalse(store.hasGivenConsent(userKey: "43"), "另一个账号不该继承同意")
        XCTAssertEqual(
            RunPlanShareConsentStep.next(hasGivenConsent: store.hasGivenConsent(userKey: "43")),
            .fullDisclosure
        )
    }

    /// 告知内容一改，旧同意就没有覆盖到新内容，必须重新征得。
    /// 版本号进 key，旧记录自然失效 —— 这是唯一能让「告知内容」和「已同意」不漂移的做法。
    func testBumpingTheDisclosureVersionInvalidatesOldConsent() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = RunPlanShareConsentStore(persistence: persistence)

        store.recordConsent(userKey: "42")
        XCTAssertTrue(store.hasGivenConsent(userKey: "42"))

        // 模拟文案改版后 key 的样子：同一个人，新版本，读不到旧同意。
        let nextVersionKey = RunPlanShareConsentStore.storageKey(
            userKey: "42",
            version: RunPlanShareConsentStore.disclosureVersion + 1
        )
        XCTAssertNil(persistence.object(forKey: nextVersionKey), "改版后不该读到上一版的同意")
    }

    // MARK: - 告知内容

    /// 三条告知必须都在、互不相同、且各自是完整的一句话 ——
    /// 它们在 UI 上是**三个独立的 VoiceOver 焦点**，拼成一段长文本等于没有告知：
    /// 读屏会一口气念完，用户记不住也回不去。
    func testThereAreThreeDistinctDisclosures() {
        let disclosures = RunPlanShareConsentCopy.allDisclosures

        XCTAssertEqual(disclosures.count, 3)
        XCTAssertEqual(Set(disclosures).count, 3, "三条告知不能有重复")
        for text in disclosures {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertTrue(text.hasSuffix("。"), "每条告知都该是完整的一句话：\(text)")
        }
    }

    /// 三件事逐条钉住。后端通报点名要求告知的就是这三件：
    /// 分享的是什么、给谁、能不能撤回。
    func testDisclosuresCoverWhatWhoAndHowToStop() {
        XCTAssertTrue(RunPlanShareConsentCopy.whatIsShared.contains("实时位置"))
        XCTAssertTrue(RunPlanShareConsentCopy.whatIsShared.contains("轨迹"))
        XCTAssertTrue(RunPlanShareConsentCopy.whoCanSee.contains("任何拿到"))
        XCTAssertTrue(RunPlanShareConsentCopy.howToStop.contains("随时"))
    }

    /// **这条红了不要直接改断言 —— 先 bump `RunPlanShareConsentStore.disclosureVersion`。**
    ///
    /// 告知内容变了而版本没变，等于拿旧同意去覆盖新告知，这正是 PIPL 上不成立的那种同意。
    /// 字面断言是刻意的：任何聪明写法（hash、长度、关键词）都可能在文案实质改变时仍然通过。
    func testDisclosureVersionCoversEveryDisclosure() {
        XCTAssertEqual(RunPlanShareConsentStore.disclosureVersion, 1)
        XCTAssertEqual(
            RunPlanShareConsentCopy.whatIsShared,
            "分享的是你的实时位置和这次跑步的轨迹。"
        )
        XCTAssertEqual(
            RunPlanShareConsentCopy.whoCanSee,
            "任何拿到这个链接的人都能看到，不只是你发给的那个人。"
        )
        XCTAssertEqual(
            RunPlanShareConsentCopy.howToStop,
            "你可以随时停止分享，停止后链接立刻失效。"
        )
    }

    /// 简短确认不重复全文（每次都念长文本，用户会开始跳过它，那才是真正失去告知效力的时候），
    /// 但必须保留「谁能看」这条最有意外性的 —— 用户默认以为只有家人能看。
    func testShortConfirmationKeepsTheSurprisingPart() {
        XCTAssertTrue(RunPlanShareConsentCopy.repeatConfirmationMessage.contains("任何拿到链接"))
        XCTAssertTrue(RunPlanShareConsentCopy.repeatConfirmationMessage.contains("停止"))
        XCTAssertLessThan(
            RunPlanShareConsentCopy.repeatConfirmationMessage.count,
            RunPlanShareConsentCopy.allDisclosures.joined().count,
            "简短确认应当短于全文告知"
        )
    }

    /// 拒绝是一个完整的答案：不劝、不重试、不把入口藏起来。
    func testDecliningIsAcknowledgedWithoutPressure() {
        let declined = RunPlanShareConsentCopy.declined
        XCTAssertTrue(declined.contains("没有分享"))
        for word in ["建议", "推荐", "更安全", "为了你好", "再想想"] {
            XCTAssertFalse(declined.contains(word), "拒绝反馈不该带劝说：\(word)")
        }
    }
}
