import UIKit
import XCTest
@testable import blindRun

/// 第 3 组（Blind Identity Flow）的最小可运行检查：
/// 格式校验、输入规范化、敏感字段清理时机、提交后的权威状态回读与失败文案。
@MainActor
final class BlindIdentityVerificationViewModelTests: XCTestCase {

    // MARK: - Validation

    func testIdCardNumberAcceptsOnlyEighteenDigitsWithOptionalTrailingX() {
        XCTAssertTrue(BlindIdentityVerificationViewModel.isValidIdCardNumber("11010119900307123X"))
        XCTAssertTrue(BlindIdentityVerificationViewModel.isValidIdCardNumber("11010119900307123x"))
        XCTAssertTrue(BlindIdentityVerificationViewModel.isValidIdCardNumber("110101199003071234"))

        XCTAssertFalse(BlindIdentityVerificationViewModel.isValidIdCardNumber(""))
        XCTAssertFalse(BlindIdentityVerificationViewModel.isValidIdCardNumber("1101011990030712"))
        XCTAssertFalse(BlindIdentityVerificationViewModel.isValidIdCardNumber("1101011990030712345"))
        // X 只能出现在末位
        XCTAssertFalse(BlindIdentityVerificationViewModel.isValidIdCardNumber("X1010119900307123"))
    }

    func testNormalizedInputStripsSeparatorsUppercasesAndCapsAtEighteen() {
        XCTAssertEqual(
            BlindIdentityVerificationViewModel.normalizedIdCardInput(" 110101 1990-0307 123x "),
            "11010119900307123X"
        )
        XCTAssertEqual(
            BlindIdentityVerificationViewModel.normalizedIdCardInput("1101011990030712345678"),
            "110101199003071234"
        )
    }

    func testCanSubmitRequiresBothNameLengthAndIdCardFormat() {
        let viewModel = BlindIdentityVerificationViewModel()
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.idCardName = "张"
        viewModel.idCardNumber = "11010119900307123X"
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertEqual(viewModel.validationMessage, "请输入 2 到 50 个字的真实姓名。")

        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "1101011990030712"
        XCTAssertFalse(viewModel.canSubmit)
        XCTAssertEqual(viewModel.validationMessage, "请输入 18 位身份证号，最后一位可以是字母 X。")

        viewModel.idCardNumber = "11010119900307123X"
        XCTAssertTrue(viewModel.canSubmit)
        XCTAssertNil(viewModel.validationMessage)
    }

    // MARK: - Sensitive Field Lifecycle

    func testDisappearClearsNameAndIdCardNumber() {
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307123X"

        viewModel.handleDisappear()

        XCTAssertTrue(viewModel.idCardName.isEmpty)
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
    }

    /// 锁屏预览和任务切换器截图都会拍到前台内容，所以进后台必须立刻清空。
    func testEnteringBackgroundClearsNameAndIdCardNumber() async {
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307781X"

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        await waitUntilCleared(viewModel)

        XCTAssertTrue(viewModel.idCardName.isEmpty)
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
    }

    // MARK: - Submit

    /// 新契约：`data.verifyStatus` 直接带回权威状态，省掉 `GET /api/blind/profile` 那次往返。
    func testSubmitUsesVerifyStatusFromResponseAndSkipsProfileRefetch() async {
        let client = IdentityVerifyAPIClient(
            verifyStatus: BlindVerifyStatus.notVerified.rawValue, // 回退路径若被误走，状态会对不上
            submitVerifyStatus: BlindVerifyStatus.verified.rawValue
        )
        let appState = AppState(apiClient: client, tokenStore: InMemoryTokenStoreStub())
        appState.updateBlindProfile(BlindProfileResponse(name: "张三", verifyStatus: "NOT_VERIFIED"))
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307123X"

        viewModel.submit()
        await waitUntilSubmitFinished(viewModel)

        XCTAssertEqual(client.verifyCount, 1)
        XCTAssertEqual(client.profileFetchCount, 0, "响应体已带状态，不应再回读资料")
        XCTAssertEqual(viewModel.status, .verified)
        XCTAssertEqual(appState.blindIdentityStatus, .verified)
        // 只写状态位，其余已知资料字段不得被抹成 nil
        XCTAssertEqual(appState.blindProfile?.name, "张三")
        XCTAssertTrue(viewModel.idCardName.isEmpty)
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 容错路径：生产 `47.114.113.171` 尚未部署带 `verifyStatus` 的版本，
    /// 字段缺失时必须回退到 `GET /api/blind/profile`，不能把状态当成未知就卡住。
    func testSubmitFallsBackToProfileFetchWhenResponseOmitsVerifyStatus() async {
        let client = IdentityVerifyAPIClient(
            verifyStatus: BlindVerifyStatus.verified.rawValue,
            submitVerifyStatus: nil
        )
        let appState = AppState(apiClient: client, tokenStore: InMemoryTokenStoreStub())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307123X"

        viewModel.submit()
        await waitUntilSubmitFinished(viewModel)

        XCTAssertEqual(client.verifyCount, 1)
        XCTAssertEqual(client.profileFetchCount, 1, "字段缺失必须回退到 GET")
        XCTAssertEqual(viewModel.status, .verified)
        XCTAssertEqual(appState.blindIdentityStatus, .verified)
        XCTAssertTrue(viewModel.idCardName.isEmpty)
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailedStatusAfterSubmitGivesRetryGuidance() async {
        let client = IdentityVerifyAPIClient(verifyStatus: BlindVerifyStatus.failed.rawValue)
        let appState = AppState(apiClient: client, tokenStore: InMemoryTokenStoreStub())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = "11010119900307123X"

        viewModel.submit()
        await waitUntilSubmitFinished(viewModel)

        XCTAssertEqual(viewModel.status, .failed)
        XCTAssertEqual(viewModel.errorMessage, "实名认证未通过，请核对姓名和身份证号后重新提交。")
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
    }

    func testSubmitFailureNeverEchoesBackendMessageOrIdCardNumber() async {
        let idCardNumber = "11010119900307123X"
        let client = IdentityVerifyAPIClient(
            verifyError: APIError.serverError(
                ErrorResponse(code: "ID_INFO_INVALID", message: "身份证号 \(idCardNumber) 核验失败")
            )
        )
        let appState = AppState(apiClient: client, tokenStore: InMemoryTokenStoreStub())
        let viewModel = BlindIdentityVerificationViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.idCardName = "张三"
        viewModel.idCardNumber = idCardNumber

        viewModel.submit()
        await waitUntilSubmitFinished(viewModel)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.errorMessage?.contains(idCardNumber) ?? true)
        XCTAssertFalse(viewModel.statusAnnouncement.contains(idCardNumber))
        XCTAssertTrue(viewModel.idCardNumber.isEmpty)
        // 提交失败不回读资料
        XCTAssertEqual(client.profileFetchCount, 0)
    }

    // MARK: - Helpers

    /// 进后台的清理走 `NotificationCenter` -> `Task { @MainActor }`，不是同步的。
    private func waitUntilCleared(
        _ viewModel: BlindIdentityVerificationViewModel,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await Task.yield()
            if viewModel.idCardNumber.isEmpty && viewModel.idCardName.isEmpty { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("敏感字段未在 \(timeout) 秒内清空")
    }

    /// `submit()` 内部起 `Task`，这里等它跑完（带上限，避免挂死）。
    private func waitUntilSubmitFinished(
        _ viewModel: BlindIdentityVerificationViewModel,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await Task.yield()
            if !viewModel.isSubmitting,
               viewModel.errorMessage != nil || viewModel.successMessage != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("提交未在 \(timeout) 秒内结束")
    }
}

// MARK: - Test Doubles

private final class IdentityVerifyAPIClient: APIClientProtocol, @unchecked Sendable {
    /// `GET /api/blind/profile` 回读到的状态（回退路径用）。
    private let verifyStatus: String?
    /// `POST /api/blind/verify-identity` 的 `data.verifyStatus`；
    /// nil 模拟生产上尚未部署新版本的老后端（只回 `message`）。
    private let submitVerifyStatus: String?
    private let verifyError: APIError?
    private(set) var verifyCount = 0
    private(set) var profileFetchCount = 0
    private(set) var capturedRequest: BlindVerifyRequest?

    init(
        verifyStatus: String? = nil,
        submitVerifyStatus: String? = nil,
        verifyError: APIError? = nil
    ) {
        self.verifyStatus = verifyStatus
        self.submitVerifyStatus = submitVerifyStatus
        self.verifyError = verifyError
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if method == .post, path == "/api/blind/verify-identity" {
            verifyCount += 1
            capturedRequest = body as? BlindVerifyRequest
            if let verifyError {
                throw verifyError
            }
            // 后端成功分支只返回 message + verifyStatus 两个字段。
            let payload = BlindVerifySubmitResponse(
                message: "身份认证通过",
                verifyStatus: submitVerifyStatus
            )
            guard let response = payload as? T else { throw APIError.invalidURL }
            return response
        }
        if method == .get, path == "/api/blind/profile" {
            profileFetchCount += 1
            let profile = BlindProfileResponse(name: "张三", verifyStatus: verifyStatus)
            guard let response = profile as? T else { throw APIError.invalidURL }
            return response
        }
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}

private final class InMemoryTokenStoreStub: TokenStoring {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
