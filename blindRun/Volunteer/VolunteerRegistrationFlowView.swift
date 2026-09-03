import Combine
import Foundation
import OSLog
import SwiftUI
import UIKit
#if canImport(AliyunFaceAuthFacade)
import AliyunFaceAuthFacade
#endif

// MARK: - Registration Step

enum RegistrationStep: Int, CaseIterable {
    case basicInfo = 1
    case faceVerify = 3

    var title: String {
        switch self {
        case .basicInfo: return "基本信息与身份核验"
        case .faceVerify: return "活体认证"
        }
    }

    var displayIndex: Int {
        switch self {
        case .basicInfo: return 1
        case .faceVerify: return 2
        }
    }
}

// MARK: - CloudAuth MetaInfo

@MainActor
protocol CloudAuthMetaInfoProviding: Sendable {
    func collectMetaInfo(environment: APIEnvironment) async throws -> String
}

enum CloudAuthMetaInfoError: LocalizedError, Sendable {
    case sdkNotConfigured
    case sdkMetaInfoUnavailable
    case sdkMetaInfoSerializationFailed

    var errorDescription: String? {
        switch self {
        case .sdkNotConfigured:
            return "活体认证 SDK 未配置，请更新客户端后重试"
        case .sdkMetaInfoUnavailable, .sdkMetaInfoSerializationFailed:
            return "活体认证 SDK 初始化失败，请重试"
        }
    }
}

@MainActor
final class CloudAuthSDKRuntime: @unchecked Sendable {
    static let shared = CloudAuthSDKRuntime(
        initializeSDK: {
            #if canImport(AliyunFaceAuthFacade)
            AliyunFaceAuthFacade.initSDK()
            #endif
        },
        versionProvider: {
            #if canImport(AliyunFaceAuthFacade)
            return AliyunFaceAuthFacade.getVersion()
            #else
            return nil
            #endif
        }
    )

    private let initializeSDK: @MainActor () -> Void
    private let versionProvider: @MainActor () -> String?
    private(set) var initializationCount = 0

    init(
        initializeSDK: @escaping @MainActor () -> Void,
        versionProvider: @escaping @MainActor () -> String?
    ) {
        self.initializeSDK = initializeSDK
        self.versionProvider = versionProvider
    }

    func initializeIfNeeded() {
        guard initializationCount == 0 else { return }
        initializeSDK()
        initializationCount = 1
    }

    var sdkVersion: String? {
        guard initializationCount > 0 else { return nil }
        return versionProvider()
    }
}

struct DefaultCloudAuthMetaInfoProvider: CloudAuthMetaInfoProviding {
    private let sdkRuntime: CloudAuthSDKRuntime

    init(sdkRuntime: CloudAuthSDKRuntime = .shared) {
        self.sdkRuntime = sdkRuntime
    }

    func collectMetaInfo(environment: APIEnvironment) async throws -> String {
        if environment.isMock {
            return #"{"platform":"ios","mock":true,"sdk":"cloud-auth-placeholder"}"#
        }
        #if canImport(AliyunFaceAuthFacade)
        sdkRuntime.initializeIfNeeded()
        let metaInfo = AliyunFaceAuthFacade.getMetaInfo()
        return try Self.serializedMetaInfo(from: metaInfo)
        #else
        throw CloudAuthMetaInfoError.sdkNotConfigured
        #endif
    }

    nonisolated static func serializedMetaInfo(from dictionary: [AnyHashable: Any]) throws -> String {
        guard !dictionary.isEmpty else {
            throw CloudAuthMetaInfoError.sdkMetaInfoUnavailable
        }
        let jsonObject = normalizedJSONObject(from: dictionary)
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
            guard let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty else {
                throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
            }
            return jsonString
        } catch let error as CloudAuthMetaInfoError {
            throw error
        } catch {
            throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
        }
    }

    nonisolated private static func normalizedJSONObject(from dictionary: [AnyHashable: Any]) -> [String: Any] {
        var object: [String: Any] = [:]
        for (key, value) in dictionary {
            object[String(describing: key.base)] = normalizedJSONValue(value)
        }
        return object
    }

    nonisolated private static func normalizedJSONValue(_ value: Any) -> Any {
        if let dictionary = value as? [AnyHashable: Any] {
            return normalizedJSONObject(from: dictionary)
        }
        if let dictionary = value as? NSDictionary {
            var normalized: [String: Any] = [:]
            for (key, value) in dictionary {
                normalized[String(describing: key)] = normalizedJSONValue(value)
            }
            return normalized
        }
        if let array = value as? [Any] {
            return array.map(normalizedJSONValue)
        }
        if let array = value as? NSArray {
            return array.map(normalizedJSONValue)
        }
        return value
    }
}

struct FixedCloudAuthMetaInfoProvider: CloudAuthMetaInfoProviding {
    let metaInfo: String

    func collectMetaInfo(environment: APIEnvironment) async throws -> String {
        metaInfo
    }
}

// MARK: - Native CloudAuth Verification

struct CloudAuthSDKDiagnostics: Equatable, Sendable {
    let code: Int
    let retCode: Int
    let retCodeSub: String?
    let retMessageSubPresent: Bool
    let retMessageSubLength: Int
    let sdkVersion: String?

    init(
        code: Int,
        retCode: Int,
        retCodeSub: String?,
        retMessageSub: String?,
        sdkVersion: String?
    ) {
        self.code = code
        self.retCode = retCode
        self.retCodeSub = Self.sanitizedSubcode(retCodeSub)
        self.retMessageSubPresent = retMessageSub != nil
        self.retMessageSubLength = retMessageSub?.count ?? 0
        self.sdkVersion = Self.sanitizedVersion(sdkVersion)
    }

    var debugSummary: String {
        let subcode = retCodeSub ?? "none"
        let version = sdkVersion ?? "unknown"
        return "sdkCode=\(code) retCode=\(retCode) retCodeSub=\(subcode) retMessageSubPresent=\(retMessageSubPresent) retMessageSubLength=\(retMessageSubLength) sdkVersion=\(version)"
    }

    var userFacingSubcodeSuffix: String {
        guard let retCodeSub else { return "" }
        return "（错误码 \(retCodeSub)）"
    }

    nonisolated private static func sanitizedSubcode(_ value: String?) -> String? {
        guard let normalized = value?.trimmed.uppercased(),
              !normalized.isEmpty,
              normalized.range(of: #"^(?:[A-Z][0-9]{4}|[0-9]{4})$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    nonisolated private static func sanitizedVersion(_ value: String?) -> String? {
        guard let normalized = value?.trimmed,
              normalized.range(of: #"^[0-9]+(?:\.[0-9]+){1,3}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }
}

struct CloudAuthVerificationFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case sdkUnavailable
        case presenterUnavailable
        case internalError
        case moduleIntegration
        case businessParameter
        case cameraUnavailable
        case duplicateFlow
        case networkError
        case deviceTimeError
        case unknown(code: Int)
    }

    let kind: Kind
    let diagnostics: CloudAuthSDKDiagnostics?

    static let sdkUnavailable = Self(kind: .sdkUnavailable, diagnostics: nil)
    static let presenterUnavailable = Self(kind: .presenterUnavailable, diagnostics: nil)
    static let internalError = Self(kind: .internalError, diagnostics: nil)
    static let networkError = Self(kind: .networkError, diagnostics: nil)
    static let deviceTimeError = Self(kind: .deviceTimeError, diagnostics: nil)

    static func unknown(code: Int) -> Self {
        Self(kind: .unknown(code: code), diagnostics: nil)
    }

    var message: String {
        let suffix = diagnostics?.userFacingSubcodeSuffix ?? ""
        switch kind {
        case .sdkUnavailable:
            return "活体认证 SDK 未配置，请更新客户端后重试"
        case .presenterUnavailable:
            return "无法打开活体认证页面，请稍后重试"
        case .internalError:
            return "活体认证 SDK 初始化或内部处理失败，请重新发起认证\(suffix)"
        case .moduleIntegration:
            return "活体认证刷脸模块接入异常，请更新客户端后重试\(suffix)"
        case .businessParameter:
            return "活体认证参数或流程配置异常，请重新发起认证\(suffix)"
        case .cameraUnavailable:
            return "无法使用相机完成活体认证，请检查相机权限后重试\(suffix)"
        case .duplicateFlow:
            return "活体认证流程重复发起，请稍后重新开始\(suffix)"
        case .networkError:
            return "活体认证网络连接失败，请检查网络后重试\(suffix)"
        case .deviceTimeError:
            return "设备时间不准确，请校准系统时间后重试\(suffix)"
        case .unknown(let code):
            return "活体认证 SDK 返回未知状态（\(code)），请重新发起认证\(suffix)"
        }
    }
}

enum CloudAuthVerificationOutcome: Equatable, Sendable {
    case submitted
    case cancelled
    case failed(CloudAuthVerificationFailure)
}

@MainActor
protocol CloudAuthVerifying: Sendable {
    func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome
}

struct DefaultCloudAuthVerifier: CloudAuthVerifying {
    private let sdkRuntime: CloudAuthSDKRuntime

    init(sdkRuntime: CloudAuthSDKRuntime = .shared) {
        self.sdkRuntime = sdkRuntime
    }

    func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome {
        if environment.isMock {
            return .submitted
        }

        #if canImport(AliyunFaceAuthFacade)
        guard let presenter = Self.activeViewController() else {
            return .failed(.presenterUnavailable)
        }

        sdkRuntime.initializeIfNeeded()
        let sdkVersion = sdkRuntime.sdkVersion
        return await withCheckedContinuation { continuation in
            let completionGate = CloudAuthOneShotGate()
            AliyunFaceAuthFacade.verify(
                with: certifyId,
                extParams: ["currentCtr": presenter]
            ) { response in
                guard completionGate.claim() else { return }
                let diagnostics = CloudAuthSDKDiagnostics(
                    code: Int(response.code.rawValue),
                    retCode: Int(response.retCode.rawValue),
                    retCodeSub: response.retCodeSub,
                    retMessageSub: response.retMessageSub,
                    sdkVersion: sdkVersion
                )
                Self.logDiagnostics(diagnostics)
                continuation.resume(returning: Self.outcome(for: diagnostics))
            }
        }
        #else
        return .failed(.sdkUnavailable)
        #endif
    }

    nonisolated static func outcome(forSDKCode code: Int) -> CloudAuthVerificationOutcome {
        outcome(for: CloudAuthSDKDiagnostics(
            code: code,
            retCode: code,
            retCodeSub: nil,
            retMessageSub: nil,
            sdkVersion: nil
        ))
    }

    nonisolated static func outcome(for diagnostics: CloudAuthSDKDiagnostics) -> CloudAuthVerificationOutcome {
        let subcodeFailureKind: CloudAuthVerificationFailure.Kind?
        switch diagnostics.retCodeSub {
        case "Z1014", "Z1023":
            subcodeFailureKind = .internalError
        case "I4001":
            subcodeFailureKind = .moduleIntegration
        case "Z1010", "Z1037":
            subcodeFailureKind = .businessParameter
        case "Z1001", "Z1002", "Z1020":
            subcodeFailureKind = .cameraUnavailable
        case "Z1024":
            subcodeFailureKind = .duplicateFlow
        default:
            subcodeFailureKind = nil
        }

        switch diagnostics.code {
        case 1000, 2006:
            return .submitted
        case 1003:
            return .cancelled
        case 1001:
            return .failed(CloudAuthVerificationFailure(
                kind: subcodeFailureKind ?? .internalError,
                diagnostics: diagnostics
            ))
        case 2002:
            return .failed(CloudAuthVerificationFailure(kind: .networkError, diagnostics: diagnostics))
        case 2003:
            return .failed(CloudAuthVerificationFailure(kind: .deviceTimeError, diagnostics: diagnostics))
        default:
            if let subcodeFailureKind {
                return .failed(CloudAuthVerificationFailure(kind: subcodeFailureKind, diagnostics: diagnostics))
            }
            return .failed(CloudAuthVerificationFailure(kind: .unknown(code: diagnostics.code), diagnostics: diagnostics))
        }
    }

    nonisolated private static func logDiagnostics(_ diagnostics: CloudAuthSDKDiagnostics) {
        #if DEBUG
        let logger = Logger(subsystem: "com.aidrun.ios", category: "CloudAuth")
        logger.debug("\(diagnostics.debugSummary, privacy: .public)")
        #endif
    }

    private static func activeViewController() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? windowScenes.flatMap(\.windows).first
        guard let rootViewController = window?.rootViewController else { return nil }
        return topViewController(from: rootViewController)
    }

    private static func topViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigationController = viewController as? UINavigationController,
           let visible = navigationController.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return topViewController(from: selected)
        }
        return viewController
    }
}

final class CloudAuthOneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

// MARK: - Registration ViewModel

@MainActor
final class VolunteerRegistrationViewModel: ObservableObject {
    @Published var currentStep: RegistrationStep = .basicInfo
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var registrationRetryAfterSeconds: Int?

    // Step 1
    @Published var name = ""
    @Published var phone = "" {
        didSet {
            let normalized = Self.normalizedPhoneNumber(phone)
            if normalized != phone {
                phone = normalized
            }
        }
    }
    @Published var idCardName = ""
    @Published var idCardNumber = "" {
        didSet {
            let normalized = Self.normalizedIdCardNumber(idCardNumber)
            if normalized != idCardNumber {
                idCardNumber = normalized
            }
        }
    }
    @Published var runningExperience = ""
    @Published var hasGuidedBefore = false
    @Published var emergencyExperience = ""

    // Step 3
    @Published var activeCertifyId: String?
    @Published var faceVerifyMessage: String?
    @Published var isPerformingFaceVerify = false
    @Published var isPollingFaceResult = false
    @Published var canReturnToBasicInfoForIdentityEdit = false

    @Published private(set) var isAwaitingRegistrationCompletion = false
    @Published private(set) var isRegistrationCompleted = false

    @Published var registrationStatus: VolunteerRegistrationStatus?

    /// 已完成但尚未发布给 AppState 的注册状态，见 `applyRegistrationStatus`。
    private var pendingCompletedStatus: VolunteerRegistrationStatus?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private let apiClientOverride: (any APIClientProtocol)?
    private let metaInfoProvider: any CloudAuthMetaInfoProviding
    private let cloudAuthVerifier: any CloudAuthVerifying
    private var registrationRateLimitTimer: AnyCancellable?

    static let idCardNumberRegex = #"^\d{17}[\dXx]$"#
    static let faceResultPollingIntervalNanoseconds: UInt64 = 3_000_000_000
    nonisolated static let maxFaceResultPollingAttempts = 240

    static func normalizedPhoneNumber(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    static func normalizedIdCardNumber(_ value: String) -> String {
        String(value.filter { $0.isNumber || $0 == "X" || $0 == "x" }.prefix(18))
    }

    init(
        apiClient: (any APIClientProtocol)? = nil,
        metaInfoProvider: (any CloudAuthMetaInfoProviding)? = nil,
        cloudAuthVerifier: (any CloudAuthVerifying)? = nil
    ) {
        self.apiClientOverride = apiClient
        self.metaInfoProvider = metaInfoProvider ?? DefaultCloudAuthMetaInfoProvider()
        self.cloudAuthVerifier = cloudAuthVerifier ?? DefaultCloudAuthVerifier()
    }

    var canSubmitBasicInfo: Bool {
        basicInfoValidationMessage == nil && !isLoading && !isRegistrationRateLimited
    }

    var isRegistrationRateLimited: Bool {
        (registrationRetryAfterSeconds ?? 0) > 0
    }

    var registrationRateLimitMessage: String? {
        guard let seconds = registrationRetryAfterSeconds, seconds > 0 else { return nil }
        return "注册操作过于频繁，请在\(seconds)秒后重试。"
    }

    var basicInfoValidationMessage: String? {
        if name.trimmed.isEmpty {
            return "请填写姓名"
        }
        if !AppState.isValidMainlandPhone(phone.trimmed) {
            return "请输入 11 位中国大陆手机号"
        }
        return identityInfoValidationMessage
    }

    var identityInfoValidationMessage: String? {
        if idCardNumber.trimmed.range(of: Self.idCardNumberRegex, options: .regularExpression) == nil {
            return "请输入18位有效身份证号码"
        }
        return nil
    }

    var canStartFaceVerify: Bool {
        currentStep == .faceVerify &&
            !isFaceVerifyBusy &&
            !isRegistrationRateLimited &&
            !isAwaitingRegistrationCompletion &&
            !isRegistrationCompleted
    }

    var isFaceVerifyBusy: Bool {
        isLoading || isPerformingFaceVerify || isPollingFaceResult
    }

    var faceVerifyButtonTitle: String {
        activeCertifyId == nil ? "开始活体认证" : "重新开始活体认证"
    }

    var shouldPollRegistrationStatus: Bool {
        isAwaitingRegistrationCompletion && !isRegistrationCompleted
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        phone = ""
    }

    // MARK: - Load Registration Status

    func loadStatus(showLoading: Bool = true) async {
        guard let appState else { return }
        if showLoading {
            isLoading = true
        }
        do {
            let status = try await activeProfileService(appState: appState).volunteerRegistrationStatus()
            applyRegistrationStatus(status)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if showLoading {
                currentStep = .basicInfo
            }
        } catch {
            isLoading = false
            if showLoading {
                currentStep = .basicInfo
            }
        }
    }

    func pollStatusWhileNeeded() async {
        while shouldPollRegistrationStatus && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await loadStatus(showLoading: false)
        }
    }

    func applyRegistrationStatus(_ status: VolunteerRegistrationStatus) {
        let wasCompleted = isRegistrationCompleted
        let wasAwaitingCompletion = isAwaitingRegistrationCompletion
        registrationStatus = status
        // 完成态**不能**立刻发布给 AppState：`isVolunteerProfileApproved` 一翻真，
        // ContentView 的 `rootRoutingKey` 就变，根路由会重跑 hydrate 并切到 .volunteerHome，
        // 把整个注册流连同「注册完成」页一起拆掉——用户只听到 TTS 报了完成，却看不到确认页，
        // 也点不到「返回志愿者首页」。改为攒着，等用户主动离开时再发布。
        if status.isRegistrationComplete {
            pendingCompletedStatus = status
        } else {
            appState?.updateVolunteerRegistrationStatus(status)
        }
        isRegistrationCompleted = status.isRegistrationComplete
        // `wasCompleted` 必须参与这个 sticky 判断：一条过期/乱序的状态响应不能把已经完成注册的人
        // 拖回基本信息页。此前 STEP_3_FACE_VERIFY 永远到不了「已完成」（要等 STEP_4_* 或 canAcceptOrders），
        // 完成态必然经过 `isAwaitingRegistrationCompletion` 这个中间态，所以缺这一项没暴露出来；
        // 现在活体一过就直接完成，中间态可能被整个跳过，缺了它就会退回 .basicInfo。
        isAwaitingRegistrationCompletion = !isRegistrationCompleted &&
            (wasCompleted || wasAwaitingCompletion || statusIndicatesCompletedFaceVerification(status))
        currentStep = isAwaitingRegistrationCompletion ? .faceVerify : resolvedRegistrationStep(from: status)
        if currentStep != .faceVerify {
            canReturnToBasicInfoForIdentityEdit = false
        }
        if isRegistrationCompleted {
            faceVerifyMessage = nil
            if !wasCompleted {
                speechService?.speak("注册完成，请返回首页开启可服务状态")
            }
        }
    }

    func prepareReturnToVolunteerHome() {
        guard isRegistrationCompleted, let appState else { return }

        // 这里才把完成态交给 AppState，根路由随后切到志愿者首页。
        // 必须在下面那道 `volunteerProfile == nil` 早退之前做，否则已有资料的用户永远发布不出去。
        if let pendingCompletedStatus {
            appState.updateVolunteerRegistrationStatus(pendingCompletedStatus)
            self.pendingCompletedStatus = nil
        }

        guard appState.volunteerProfile == nil else { return }

        appState.updateVolunteerProfile(VolunteerProfileResponse(
            name: name.trimmed.isEmpty ? nil : name.trimmed,
            verificationStatus: nil,
            adminReviewStatus: nil,
            registrationStep: registrationStatus?.registrationStep ?? registrationStatus?.currentStepCode,
            canAcceptOrders: registrationStatus?.canAcceptOrders,
            isAvailable: false,
            wantsDispatch: false,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        ))
    }

    private func resolvedRegistrationStep(from status: VolunteerRegistrationStatus) -> RegistrationStep {
        let stepCode = (status.registrationStep ?? status.currentStepCode)?.uppercased()
        switch stepCode {
        case "STEP_1_BASIC_INFO", "STEP_2_ID_UPLOAD":
            return .basicInfo
        case "STEP_3_FACE_VERIFY":
            return .faceVerify
        case "STEP_4_TRAINING", "STEP_4_COMPLETED":
            return .faceVerify
        default:
            break
        }

        if let currentStep = status.currentStep {
            switch currentStep {
            case 1, 2:
                return .basicInfo
            case 3:
                return .faceVerify
            case 4:
                return .faceVerify
            default:
                break
            }
        }

        let faceStatus = (status.faceVerifyStatus ?? status.stepDetails?.faceVerifyStatus ?? "").uppercased()
        let idStatus = (status.idVerifyStatus ?? status.stepDetails?.idVerifyStatus ?? "").uppercased()
        if status.step3Completed == true || faceStatus == "APPROVED" || faceStatus == "PASSED" {
            return .faceVerify
        }
        if status.step1Completed == true || idStatus == "APPROVED" {
            return .faceVerify
        }
        return .basicInfo
    }

    private func statusIndicatesCompletedFaceVerification(_ status: VolunteerRegistrationStatus) -> Bool {
        let stepCode = (status.registrationStep ?? status.currentStepCode)?.uppercased()
        let faceStatus = (status.faceVerifyStatus ?? status.stepDetails?.faceVerifyStatus ?? "").uppercased()
        return stepCode == "STEP_4_TRAINING" ||
            stepCode == "STEP_4_COMPLETED" ||
            status.currentStep == 4 ||
            status.step3Completed == true ||
            faceStatus == "APPROVED" ||
            faceStatus == "PASSED"
    }

    // MARK: - Step 1

    func submitBasicInfo() async {
        if let message = basicInfoValidationMessage {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard let appState else { return }
        isLoading = true
        errorMessage = nil

        let request = BasicInfoRequest(
            name: name.trimmed,
            phone: phone.trimmed,
            idCardName: name.trimmed,
            idCardNumber: idCardNumber.trimmed,
            runningExperience: runningExperience.trimmed.isEmpty ? nil : runningExperience.trimmed,
            hasGuidedBefore: hasGuidedBefore,
            emergencyExperience: emergencyExperience.trimmed.isEmpty ? nil : emergencyExperience.trimmed
        )

        do {
            try await activeProfileService(appState: appState).submitVolunteerBasicInfo(request)
            await syncStatusAfterBasicInfoSuccess(appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                isLoading = false
                return
            }
            await handleBasicInfoSubmissionError(error)
        } catch {
            isLoading = false
            errorMessage = "提交失败，请重试"
            speechService?.speakError("提交失败，请重试")
        }
    }

    private func syncStatusAfterBasicInfoSuccess(appState: AppState) async {
        do {
            let status = try await activeProfileService(appState: appState).volunteerRegistrationStatus()
            applyRegistrationStatus(status)
        } catch {
            currentStep = .faceVerify
        }
        isLoading = false
        switch currentStep {
        case .basicInfo:
            speechService?.speak("身份信息已提交，请等待状态同步")
        case .faceVerify:
            faceVerifyMessage = "身份核验通过，请开始活体认证"
            speechService?.speak("身份核验通过，请开始活体认证")
        }
    }

    private func handleBasicInfoSubmissionError(_ error: APIError) async {
        if handleRegistrationRateLimit(error) {
            isLoading = false
            return
        }
        let previousStep = currentStep
        let localizedMessage = error.localizedMessage
        if shouldRefreshRegistrationStatus(after: error), let appState {
            do {
                let status = try await activeProfileService(appState: appState).volunteerRegistrationStatus()
                applyRegistrationStatus(status)
                isLoading = false
                if currentStep != previousStep {
                    let message = "已同步注册进度，请继续完成\(currentStep.title)"
                    errorMessage = message
                    speechService?.speak(message)
                    return
                }
            } catch {
                // Fall through to the original backend error.
            }
        }

        isLoading = false
        errorMessage = localizedMessage
        speechService?.speakError(localizedMessage)
    }

    private func shouldRefreshRegistrationStatus(after error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        let normalizedMessage = response.message.uppercased()
        return normalizedMessage.contains("CURRENT STEP") ||
            normalizedMessage.contains("当前步骤") ||
            normalizedMessage.contains("STEP_")
    }

    func refreshStatus() {
        Task { await loadStatus(showLoading: false) }
    }

    // MARK: - Step 3

    func startFaceVerify() async {
        guard canStartFaceVerify, let appState else { return }
        isLoading = true
        errorMessage = nil
        faceVerifyMessage = nil
        canReturnToBasicInfoForIdentityEdit = false

        do {
            let metaInfo = try await metaInfoProvider.collectMetaInfo(environment: appState.currentEnvironment)
            let request = FaceVerifyInitRequest(metaInfo: metaInfo)
            let response = try await activeProfileService(appState: appState).initFaceVerify(request)
            isLoading = false
            await handleFaceVerifyInitResponse(response, environment: appState.currentEnvironment)
        } catch let error as CloudAuthMetaInfoError {
            isLoading = false
            let message = error.localizedDescription
            errorMessage = message
            speechService?.speakError(message)
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if handleRegistrationRateLimit(error) {
                return
            }
            if isIdentityInfoError(error) {
                await handleFaceVerifyIdentityInfoError(error.localizedMessage)
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "活体认证发起失败，请重试"
            speechService?.speakError("活体认证发起失败，请重试")
        }
    }

    private func handleFaceVerifyInitResponse(
        _ response: FaceVerifyInitResponse,
        environment: APIEnvironment
    ) async {
        if response.isError {
            let message = response.message ?? "活体认证发起失败，请重试"
            if isIdentityInfoMessage(message) {
                await handleFaceVerifyIdentityInfoError(message)
                return
            }
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard response.isPending,
              let certifyId = response.certifyId?.trimmed,
              !certifyId.isEmpty else {
            let message = response.message ?? "活体认证服务返回不完整，请稍后重试"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        activeCertifyId = certifyId
        canReturnToBasicInfoForIdentityEdit = false
        faceVerifyMessage = response.message ?? "活体认证已发起，正在打开客户端认证页面"
        speechService?.speak(faceVerifyMessage ?? "活体认证已发起")

        isPerformingFaceVerify = true
        let outcome = await cloudAuthVerifier.verify(certifyId: certifyId, environment: environment)
        isPerformingFaceVerify = false
        await handleCloudAuthVerificationOutcome(outcome)
    }

    private func handleCloudAuthVerificationOutcome(_ outcome: CloudAuthVerificationOutcome) async {
        switch outcome {
        case .submitted:
            faceVerifyMessage = "动作活体已提交，正在查询认证结果"
            errorMessage = nil
            await pollFaceVerifyResultUntilFinished()
        case .cancelled:
            activeCertifyId = nil
            faceVerifyMessage = nil
            errorMessage = "已取消活体认证，可重新开始"
            speechService?.speak("已取消活体认证，可重新开始")
        case .failed(let failure):
            activeCertifyId = nil
            faceVerifyMessage = nil
            errorMessage = failure.message
            speechService?.speakError(failure.message)
        }
    }

    private func handleFaceVerifyIdentityInfoError(_ message: String) async {
        activeCertifyId = nil
        faceVerifyMessage = nil

        if let appState {
            do {
                let status = try await activeProfileService(appState: appState).volunteerRegistrationStatus()
                applyRegistrationStatus(status)
            } catch {
                // Keep the user on the current screen and expose the manual edit path.
            }
        }

        if currentStep == .faceVerify {
            canReturnToBasicInfoForIdentityEdit = true
            errorMessage = message
            speechService?.speakError(message)
        } else {
            canReturnToBasicInfoForIdentityEdit = false
            errorMessage = "请修改身份信息后重新提交"
            speechService?.speakError("请修改身份信息后重新提交")
        }
    }

    private func isIdentityInfoError(_ error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        return isIdentityInfoMessage("\(response.code) \(response.message)")
    }

    private func isIdentityInfoMessage(_ message: String) -> Bool {
        let normalizedMessage = message.uppercased()
        return normalizedMessage.contains("身份信息") ||
            normalizedMessage.contains("身份证") ||
            normalizedMessage.contains("IDCARD") ||
            normalizedMessage.contains("ID_CARD") ||
            normalizedMessage.contains("ID_INFO") ||
            normalizedMessage.contains("IDENTITY")
    }

    func returnToBasicInfoForIdentityEdit() {
        currentStep = .basicInfo
        activeCertifyId = nil
        faceVerifyMessage = nil
        errorMessage = nil
        isAwaitingRegistrationCompletion = false
        isRegistrationCompleted = false
        pendingCompletedStatus = nil
        canReturnToBasicInfoForIdentityEdit = false
        speechService?.speak("请修改姓名和身份证号码后重新提交")
    }

    func pollFaceVerifyResultUntilFinished(maxAttempts: Int = maxFaceResultPollingAttempts) async {
        guard activeCertifyId != nil, !isPollingFaceResult else { return }
        isPollingFaceResult = true
        defer { isPollingFaceResult = false }

        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return }
            let finished = await pollFaceVerifyResultOnce()
            if finished {
                return
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: Self.faceResultPollingIntervalNanoseconds)
            }
        }
        activeCertifyId = nil
        errorMessage = "活体认证结果查询超时，请重新发起认证"
        speechService?.speakError("活体认证结果查询超时，请重新发起认证")
    }

    @discardableResult
    func pollFaceVerifyResultOnce() async -> Bool {
        guard let appState, let certifyId = activeCertifyId else { return true }
        do {
            let request = FaceVerifyResultRequest(certifyId: certifyId)
            let response = try await activeProfileService(appState: appState).faceVerifyResult(request)
            return await handleFaceVerifyResult(response)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return true
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return true
        } catch {
            errorMessage = "活体认证结果查询失败，请重试"
            speechService?.speakError("活体认证结果查询失败，请重试")
            return true
        }
    }

    private func handleFaceVerifyResult(_ response: FaceVerifyResponse) async -> Bool {
        if response.isPassed {
            activeCertifyId = nil
            isAwaitingRegistrationCompletion = true
            faceVerifyMessage = "活体已通过，注册状态同步中，无需课程或答题"
            currentStep = .faceVerify
            speechService?.speak(faceVerifyMessage ?? "活体认证通过")
            await loadStatus(showLoading: false)
            return true
        }
        if response.isPending {
            faceVerifyMessage = response.message ?? "活体认证结果处理中，请稍候"
            return false
        }
        if response.isRejected {
            activeCertifyId = nil
            faceVerifyMessage = nil
            let message = response.message ?? "活体认证未通过，请重新发起认证"
            errorMessage = message
            speechService?.speakError(message)
            return true
        }
        if response.isError {
            activeCertifyId = nil
            faceVerifyMessage = nil
            let message = response.message ?? "活体认证结果异常，请重新发起认证"
            errorMessage = message
            speechService?.speakError(message)
            return true
        }

        activeCertifyId = nil
        let message = response.message ?? "活体认证未通过，请重新发起认证"
        errorMessage = message
        speechService?.speakError(message)
        return true
    }

    @discardableResult
    private func handleRegistrationRateLimit(_ error: APIError) -> Bool {
        // 后端 429 只发 message + retryAfterSeconds（`GlobalExceptionHandler.handleRateLimitException`），
        // 不区分限流桶，所以注册流里的 429 一律按注册限流处理。
        guard case .rateLimited(let info) = error else {
            return false
        }
        let message = error.localizedMessage
        errorMessage = message
        speechService?.speakError(message)
        guard let seconds = info.retryAfterSeconds, seconds > 0 else { return true }
        startRegistrationRateLimitCountdown(seconds: seconds)
        return true
    }

    private func startRegistrationRateLimitCountdown(seconds: Int) {
        registrationRateLimitTimer?.cancel()
        registrationRetryAfterSeconds = seconds
        registrationRateLimitTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard let current = self.registrationRetryAfterSeconds, current > 1 else {
                    self.registrationRetryAfterSeconds = nil
                    self.registrationRateLimitTimer?.cancel()
                    self.registrationRateLimitTimer = nil
                    self.speechService?.speak("现在可以重新提交注册操作")
                    return
                }
                self.registrationRetryAfterSeconds = current - 1
            }
    }

    /// 注入口仍收 `APIClientProtocol`（`init(apiClient:)` 没变）：用例注入的桩实现的就是它，
    /// 迁到 service 层不该逼 30 多个用例跟着换类型。service 在这里就地架在那个桩上。
    private func activeProfileService(appState: AppState) -> any ProfileServing {
        ProfileService(transport: apiClientOverride ?? appState.apiClient)
    }
}

// MARK: - Registration Flow View

struct VolunteerRegistrationFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @StateObject private var viewModel = VolunteerRegistrationViewModel()
    /// 身份证号 + 人脸的**单独同意**（PIPL 第 29 条）。与盲人实名页同一套告知组件，
    /// 只是告知内容多一条人脸活体 —— 这一步提交成功后下一屏就是活体认证，不能等到那时才说。
    @State private var showIdentityConsent = false
    @State private var consentDeclinedNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.isRegistrationCompleted {
                        completionStep
                    } else {
                        switch viewModel.currentStep {
                        case .basicInfo:
                            basicInfoStep
                        case .faceVerify:
                            faceVerifyStep
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                    }
                    if let message = viewModel.registrationRateLimitMessage {
                        Text(message)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(message)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .background(AppColors.background)
        .navigationTitle("志愿者注册")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(appState: appState, speechService: speechService)
            await viewModel.loadStatus()
        }
        .task(id: viewModel.shouldPollRegistrationStatus) {
            guard viewModel.shouldPollRegistrationStatus else { return }
            await viewModel.pollStatusWhileNeeded()
        }
        // 全屏而不是对话框：三条告知要各自可听、可停、可回头再听，理由见 `ConsentDisclosureView`。
        .fullScreenCover(isPresented: $showIdentityConsent) {
            ConsentDisclosureView(
                purpose: .volunteerIdentity,
                onAgree: {
                    showIdentityConsent = false
                    consentDeclinedNotice = nil
                    // 同意先落盘再发请求：一次网络失败不该让用户再看一遍全文告知。
                    consentStore.recordConsent(to: .volunteerIdentity, scope: consentScope)
                    Task { await viewModel.submitBasicInfo() }
                },
                onDecline: {
                    showIdentityConsent = false
                    consentDeclinedNotice = PrivacyConsentPurpose.volunteerIdentity.declinedFeedback
                    speechService.speak(PrivacyConsentPurpose.volunteerIdentity.declinedFeedback)
                }
            )
        }
    }

    // MARK: - Sensitive Consent

    private var consentStore: PrivacyConsentStore {
        PrivacyConsentStore(persistence: appState.persistence)
    }

    /// 同意按**人**记；拿不到 userId 时用恒不命中的 scope，宁可多问一次。
    private var consentScope: PrivacyConsentScope {
        guard let userId = appState.userId else { return .user("unknown") }
        return .user(String(userId))
    }

    /// 提交按钮的唯一入口：**没有单独同意就不发请求**。
    private func handleBasicInfoSubmitTapped() {
        guard consentStore.hasConsented(to: .volunteerIdentity, scope: consentScope) else {
            showIdentityConsent = true
            return
        }
        Task { await viewModel.submitBasicInfo() }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(RegistrationStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    // 已完成 / 未完成此前只有填充色不同，圈里那个白色序号在两种状态下都一样。
                    // 与盲人端预约向导共用同一条「实心 / 空心」规则（见 `StepProgressDot`），
                    // 不在这里再写一遍 —— 两处各写各的，漏改一处的表现是「某些页面的进度条
                    // 对色觉障碍用户还是一排相同的圈」，而那种漏没人会发现。
                    StepProgressDot(
                        isReached: step.displayIndex <= viewModel.currentStep.displayIndex,
                        differentiateWithoutColor: differentiateWithoutColor,
                        diameter: 28,
                        stepNumber: step.displayIndex
                    )
                    Text(step.title)
                        .font(.caption2)
                        .foregroundColor(step == viewModel.currentStep ? AppColors.primary : AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("volunteerRegistrationStep.\(step.displayIndex)")
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("步骤\(step.displayIndex) \(step.title)")
                .accessibilityValue(step == viewModel.currentStep ? "当前步骤" : step.displayIndex < viewModel.currentStep.displayIndex ? "已完成" : "未完成")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.secondaryBackground)
    }

    // MARK: - Step 1

    private var basicInfoStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("基本信息与身份核验")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请填写基本信息和身份证信息，姓名需与身份证一致。提交后系统会进行身份证二要素核验，通过后进入活体认证。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            formField(title: "姓名", placeholder: "请输入真实姓名", text: $viewModel.name)
            formField(title: "手机号", placeholder: "请输入手机号", text: $viewModel.phone)
                .keyboardType(.phonePad)
            formField(title: "身份证号码", placeholder: "请输入18位身份证号码", text: $viewModel.idCardNumber)
                .keyboardType(.asciiCapable)
            formField(title: "跑步经验", placeholder: "描述您的跑步经验（选填）", text: $viewModel.runningExperience)

            Toggle("是否有陪跑经验", isOn: $viewModel.hasGuidedBefore)
                .font(AppFonts.body())
                .accessibilityLabel("是否有陪跑经验")

            formField(title: "急救经验", placeholder: "描述您的急救经验（选填）", text: $viewModel.emergencyExperience)

            if let validationMessage = viewModel.basicInfoValidationMessage {
                Text(validationMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel("无法提交身份信息：\(validationMessage)")
            }

            if let consentDeclinedNotice {
                Text(consentDeclinedNotice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(consentDeclinedNotice)
                    .accessibilityIdentifier("volunteerIdentityConsentDeclinedNotice")
            }

            PrimaryButton("提交身份信息", isLoading: viewModel.isLoading) {
                handleBasicInfoSubmitTapped()
            }
            .disabled(!viewModel.canSubmitBasicInfo)
            .opacity(viewModel.canSubmitBasicInfo ? 1 : 0.45)
            .accessibilityLabel("提交身份信息")
            .accessibilityHint(viewModel.basicInfoValidationMessage ?? "提交基本信息和身份证二要素核验")
        }
    }

    // MARK: - Step 3

    private var faceVerifyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("活体认证")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("点击开始后将打开阿里云原生活体认证页面。请按页面提示完成动作，完成后系统会自动查询认证结果。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            if let faceVerifyMessage = viewModel.faceVerifyMessage,
               !viewModel.isAwaitingRegistrationCompletion {
                Text(faceVerifyMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel(faceVerifyMessage)
            }

            if viewModel.isAwaitingRegistrationCompletion {
                Text("活体已通过，注册状态同步中，无需课程或答题")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel("活体已通过，注册状态同步中，无需课程或答题")
                    .accessibilityAddTraits(.updatesFrequently)

                ProgressView("正在同步注册状态...")
                    .accessibilityLabel("正在同步注册状态")

                Button("刷新注册状态") {
                    viewModel.refreshStatus()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .accessibilityLabel("刷新注册状态")
                .accessibilityHint("重新查询志愿者注册是否已完成")
            } else {
                PrimaryButton(viewModel.faceVerifyButtonTitle, isLoading: viewModel.isLoading || viewModel.isPerformingFaceVerify) {
                    Task { await viewModel.startFaceVerify() }
                }
                .disabled(!viewModel.canStartFaceVerify)
                .opacity(viewModel.canStartFaceVerify ? 1 : 0.45)
                .accessibilityLabel(viewModel.faceVerifyButtonTitle)
                .accessibilityHint("发起认证并打开阿里云原生活体认证页面")

                if viewModel.canReturnToBasicInfoForIdentityEdit {
                    Button("返回修改身份信息") {
                        viewModel.returnToBasicInfoForIdentityEdit()
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .accessibilityLabel("返回修改身份信息")
                    .accessibilityHint("返回基本信息页面修改姓名和身份证号码")
                }

                if viewModel.activeCertifyId != nil {
                    Button("查询活体认证结果") {
                        Task { await viewModel.pollFaceVerifyResultUntilFinished() }
                    }
                    .disabled(viewModel.isPollingFaceResult)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(viewModel.isPollingFaceResult ? AppColors.textSecondary : AppColors.primary)
                    .accessibilityLabel("查询活体认证结果")
                }

                if viewModel.isPollingFaceResult {
                    ProgressView("正在查询活体认证结果...")
                        .accessibilityLabel("正在查询活体认证结果")
                }
            }
        }
    }

    private var completionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppColors.success)
                .accessibilityHidden(true)

            Text("注册完成，请返回首页开启可服务状态")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("volunteerRegistrationCompleted")

            Text("注册完成不会自动开启接单，请在志愿者首页手动开启可服务状态。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            PrimaryButton("返回志愿者首页") {
                viewModel.prepareReturnToVolunteerHome()
                dismiss()
            }
            .accessibilityLabel("返回志愿者首页")
            .accessibilityHint("返回后可手动开启可服务状态")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("注册完成，请返回首页开启可服务状态")
    }

    // MARK: - Helpers

    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            TextField(placeholder, text: text)
                .font(AppFonts.body())
                .padding()
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .accessibilityLabel(title)
                .accessibilityHint(placeholder)
                .accessibilityIdentifier("volunteerRegistrationField.\(title)")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerRegistrationFlowView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
