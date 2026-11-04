import XCTest
@testable import blindRun

/// 陪跑培训的学习时长：答题改成整页弹出之后（#698）的结清时机。
///
/// 学习时长是合规记录（中央社会工作部 2025-06 培训指引），报少了不会有任何报错。
@MainActor
final class VolunteerTrainingStudyTimeTests: XCTestCase {

    /// 弹出整页答题时课程页也会消失，那一刻不许结清学习时长。
    ///
    /// 结清会把计时起点清空，交卷前退出的话，答题那段时间整段不算。
    func testOpeningTheQuizPageDoesNotSettleStudyTime() {
        XCTAssertFalse(
            VolunteerTrainingCourseView.settlesStudyTimeOnDisappear(quizIsPresented: true),
            "答题页盖上来不是离开这门课"
        )
        XCTAssertTrue(
            VolunteerTrainingCourseView.settlesStudyTimeOnDisappear(quizIsPresented: false),
            "真正退回列表时要结清，否则这段时长永远报不上去"
        )
    }
}
