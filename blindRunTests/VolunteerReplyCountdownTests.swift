import XCTest
@testable import blindRun

/// 邀请回复倒计时的文案与「紧迫」阈值（后端 #371 起期限是 60 / 15 分钟）。
/// 从 `VolunteerOrderFlowPresentationTests` 拆出（SwiftLint 棘轮 #488：那个类只许变短）。
final class VolunteerReplyCountdownTests: XCTestCase {

    /// 后端 #371 起期限是 60 / 15 分钟：一分钟以上按分钟、向上取整；最后一分钟按秒。
    /// 60 与 61 落在「整一分钟」两侧，59 与 60 落在「换单位」两侧 —— 取整写成向下的实现在 61 上红，
    /// 换单位写成 `> 60` 的在 60 上红。
    func testReplyCountdownSpeaksMinutesAndRoundsUp() {
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: 3600), "还剩 60 分钟回复")
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: 61), "还剩 2 分钟回复")
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: 60), "还剩 1 分钟回复")
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: 59), "还剩 59 秒回复")
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: -3), "还剩 0 秒回复")
    }

    /// 紧迫阈值取在**边界两侧**，而不是随手取一个明显该红的值。
    ///
    /// 设计稿「剩余**不到** 15 分钟变深黄」，按**显示出来的分钟数**判（向上取整）：840 秒字上是「14 分钟」算，
    /// 841 秒字上是「15 分钟」不算。按秒判 `< 900` 的实现在第二条上红（字写 15、颜色却深黄），
    /// 阈值还停在旧的 10 秒的实现在第一条上红。取 3 和 3000 两个值则两种错误实现都测不出来。
    func testReplyUrgencyFlipsExactlyAtTheNamedThreshold() {
        func urgent(_ seconds: Int) -> Bool {
            VolunteerOrderFlowPresentation.make(
                dispatch: OrderDetailResponse.previewDispatch(),
                remainingSeconds: seconds
            ).isReplyUrgent
        }

        XCTAssertTrue(urgent(14 * 60), "字上显示 14 分钟，算紧迫")
        XCTAssertEqual(VolunteerOrderFlowCopy.replyCountdown(seconds: 14 * 60 + 1), "还剩 15 分钟回复")
        XCTAssertFalse(urgent(14 * 60 + 1), "字上还是 15 分钟，颜色不能先变")
    }
}
