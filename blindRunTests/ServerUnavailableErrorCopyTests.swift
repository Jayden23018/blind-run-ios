import XCTest
@testable import blindRun

/// 服务器宕机、网关报错、连不上服务器时，不再让用户「检查网络」（#659，审计 F-7）。
///
/// 背景：连接失败和断网原来是同一句「网络连接失败，请检查网络设置」，网关 502 念「未知错误 (502)」。
/// 盲人用户会花时间查自己的网络，或反复开关飞行模式。
///
/// **验红方式**：把 `APIError.networkFailureKind(_:)` 改成除证书错误外恒返回 `.offline`，
/// 并把 `.unknown` 分支改回只念状态码，前三条必须失败，最后一条照样通过。
@MainActor
final class ServerUnavailableErrorCopyTests: XCTestCase {

    func testServerUnreachableSaysItIsNotThePhone() {
        for code: URLError.Code in [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .badServerResponse] {
            let message = APIError.networkError(URLError(code)).localizedMessage
            XCTAssertEqual(message, APIError.serverUnavailableMessage, "\(code.rawValue)")
            XCTAssertTrue(message.contains("不是你的手机"), "\(code.rawValue)")
            XCTAssertTrue(message.contains("120"), "\(code.rawValue)")
        }
    }

    /// 网关 502 / 503 / 504 没有后端错误体，落在 `.unknown`。500 与 599 是边界，一起钉住。
    func testGatewayErrorsWithoutABodyUseTheServerCopy() {
        for status in [500, 502, 503, 504, 599] {
            XCTAssertEqual(
                APIError.unknown(statusCode: status).localizedMessage,
                APIError.serverUnavailableMessage,
                "\(status)"
            )
        }
    }

    /// 超时与中途断开：弱网和服务器卡住都会这样，所以两边都说，不断言「不是你的手机」。
    func testTimeoutNamesBothPossibleCauses() {
        for code: URLError.Code in [.timedOut, .networkConnectionLost] {
            let message = APIError.networkError(URLError(code)).localizedMessage
            XCTAssertEqual(message, APIError.ambiguousConnectionMessage, "\(code.rawValue)")
            XCTAssertFalse(message.contains("不是你的手机"), "\(code.rawValue)")
            XCTAssertTrue(message.contains("信号弱"), "\(code.rawValue)")
        }
    }

    /// 对照组：真没网时仍叫用户检查网络；500–599 以外的状态码不被误判成服务端故障。
    func testOfflineAndClientStatusesKeepTheirOldCopy() {
        XCTAssertEqual(APIError.networkError(URLError(.notConnectedToInternet)).localizedMessage, APIError.offlineMessage)
        XCTAssertEqual(APIError.networkError(CancellationError()).localizedMessage, APIError.offlineMessage)
        for status in [-1, 404, 499, 600] {
            XCTAssertEqual(
                APIError.unknown(statusCode: status).localizedMessage,
                "未知错误 (\(status))，请稍后重试。",
                "\(status)"
            )
        }
    }

    /// 求助失败的整句自带下一步（重试、拨 110）。嵌进去的原因不能再带「稍后再试」——
    /// 求助场景叫人「稍后」是错的指引。验红：把 `reasonClause` 改回 `localizedMessage`，这条必须失败。
    func testEmergencyFailureSentenceDoesNotTellTheUserToWait() {
        let errors: [APIError] = [
            .networkError(URLError(.cannotConnectToHost)), .networkError(URLError(.timedOut)), .unknown(statusCode: 503)
        ]
        for error in errors {
            for sentence in [
                EmergencySafetyCopy.failure(error.reasonClause),
                EmergencySafetyCopy.withdrawFailed(error.reasonClause),
                EmergencySafetyCopy.cancelOwnerFailed(error.reasonClause)
            ] {
                XCTAssertFalse(sentence.contains("稍后"), sentence)
                XCTAssertFalse(sentence.contains("。。"), sentence)
            }
        }
        XCTAssertTrue(EmergencySafetyCopy.failure(APIError.unknown(statusCode: 503).reasonClause).contains("不是你的手机"))
    }
}
