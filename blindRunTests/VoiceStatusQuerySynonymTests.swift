import XCTest
@testable import blindRun

/// 「问一句」认得用户对陪跑一方的各种叫法（#527）。
///
/// 界面一律叫「陪跑员」（`GLOSSARY.md`「界面用词」），而原词表只认「联系志愿者」——
/// 用户照屏幕说「联系陪跑员」会落进「没听懂」。嘴上的「志愿者」「对方」「他 / 她」也照样要认。
@MainActor
final class VoiceStatusQuerySynonymTests: XCTestCase {

    func testCallIntentAcceptsEveryNameForTheEscort() {
        for utterance in ["联系陪跑员", "联系志愿者", "联系对方", "联系他", "联系她", "打电话给陪跑员", "陪跑员电话是多少"] {
            XCTAssertEqual(VoiceStatusQuery.classify(utterance), .callVolunteer, "「\(utterance)」应判为要打电话")
        }
    }

    func testDistanceAndStatusQuestionsUsingTheScreenNameStillRoute() {
        XCTAssertEqual(VoiceStatusQuery.classify("陪跑员还有多远"), .distance)
        XCTAssertEqual(VoiceStatusQuery.classify("对方到哪了"), .distance)
        XCTAssertEqual(VoiceStatusQuery.classify("陪跑员接单了吗"), .status)
    }

    /// 提示里教用户怎么问，用的必须是屏幕上的叫法 —— 而且照着念出来要能被认出来。
    func testTheAskableHintTeachesPhrasesTheClassifierUnderstands() {
        let hint = VoiceStatusQuery.askableHint
        XCTAssertTrue(hint.contains("陪跑员"), "提示里应教「陪跑员」这个叫法：\(hint)")
        XCTAssertFalse(hint.contains("志愿者"), "盲人端提示不再用「志愿者」：\(hint)")
        XCTAssertEqual(VoiceStatusQuery.classify("陪跑员还有多远"), .distance)
        XCTAssertEqual(VoiceStatusQuery.classify("打电话给陪跑员"), .callVolunteer)
    }
}
