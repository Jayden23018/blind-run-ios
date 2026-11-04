import XCTest
@testable import blindRun

/// 四个时间类码念后端 message（#659，审计 F-11）。
///
/// 后端 `OrderLifecycleService` 抛这四个码时，message 带着最早可操作的时刻（`M月d日 HH:mm`），
/// 本地文案说不出这个时刻。下面的后端原文按 `origin/main` 的拼法写：
/// `requireNotTooEarly`、`endWaiting`、`startService` 三处。
///
/// **验红方式**：把四个码从 `ErrorCode.prefersServerMessage` 里删掉，前两条必须失败，最后一条照样通过。
@MainActor
final class TimeGateServerMessageTests: XCTestCase {

    private static let serverMessages: [(code: String, message: String)] = [
        ("DEPARTURE_TOO_EARLY", "还没到可以出发的时间，最早11月4日 08:30可以操作"),
        ("SERVICE_START_TOO_EARLY", "还没到可以开始陪跑的时间，最早11月4日 09:15可以操作"),
        ("END_WAIT_TOO_EARLY", "还没等满，11月4日 09:45之后可以结束等待")
    ]

    func testTimeCodesSpeakTheServerTime() {
        for (code, message) in Self.serverMessages {
            let error = APIError.serverError(ErrorResponse(code: code, message: message))
            XCTAssertEqual(error.localizedMessage, message, code)
        }
    }

    /// 后端那句只说「对方」，本地补上跑者那一端的按钮名。
    func testBlindConfirmationPendingKeepsTheTimeAndNamesTheRunnersButton() {
        let message = "还需要对方在手机上确认可以开始；若一直联系不上，11月4日 09:45之后可以直接开始"
        let error = APIError.serverError(ErrorResponse(code: "BLIND_CONFIRMATION_PENDING", message: message))
        XCTAssertTrue(error.localizedMessage.hasPrefix(message), error.localizedMessage)
        XCTAssertTrue(error.localizedMessage.contains("开始跑步"), error.localizedMessage)
    }

    /// 后端 message 为空时退回本地文案，不念出一句空话。
    func testBlankServerMessageFallsBackToLocalCopy() {
        for code in [ErrorCode.departureTooEarly, .serviceStartTooEarly, .endWaitTooEarly, .blindConfirmationPending] {
            let error = APIError.serverError(ErrorResponse(code: code.rawValue, message: " "))
            XCTAssertEqual(error.localizedMessage, code.localizedMessage, code.rawValue)
        }
    }
}
