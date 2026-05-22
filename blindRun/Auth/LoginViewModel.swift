import Combine
import Foundation
import SwiftUI

// MARK: - Login ViewModel

/// 登录页 ViewModel，管理手机号/验证码输入、校验、倒计时和登录 API 调用。
/// 遵循 MVVM：View 只渲染状态和转发用户意图，所有业务逻辑在此处理。
/// 依赖 AppState 通过 ``configure(with:)`` 方法在 View.onAppear 中注入。
@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - Published State

    /// 手机号输入（仅保留数字并限制为 11 位）
    @Published var phoneNumber: String = "" {
        didSet {
            let normalized = LoginViewModel.normalizedPhoneNumber(phoneNumber)
            if normalized != phoneNumber {
                phoneNumber = normalized
                return
            }
            if !phoneNumber.isEmpty {
                errorMessage = nil
            }
            hasAttemptedSend = false
            speakPhoneValidationErrorIfNeeded()
        }
    }

    /// 验证码输入（仅保留数字并限制为 6 位）
    @Published var verificationCode: String = "" {
        didSet {
            let normalized = LoginViewModel.normalizedVerificationCode(verificationCode)
            if normalized != verificationCode {
                verificationCode = normalized
                return
            }
            if !verificationCode.isEmpty {
                errorMessage = nil
            }
        }
    }

    /// 倒计时秒数（nil = 空闲，60...0 = 倒计时中）
    @Published var countdown: Int? = nil

    /// API 请求 loading 状态
    @Published var isLoading: Bool = false

    /// 用户可见的错误消息
    @Published var errorMessage: String? = nil

    /// 触发验证码输入框抖动动画
    @Published var shakeCodeField: Bool = false

    /// 是否已展示验证码输入区
    @Published var showCodeInput: Bool = false

    /// 用户是否已尝试获取验证码（控制手机号格式错误显示时机）
    @Published var hasAttemptedSend: Bool = false

    // MARK: - Dependencies

    private weak var appState: AppState?
    private var speechService: SpeechService?

    // MARK: - Timer

    private var timerCancellable: AnyCancellable?
    private var lastSpokenInvalidPhoneNumber: String?

    // MARK: - Computed Properties

    var isPhoneValid: Bool {
        let phoneRegex = #"^1\d{10}$"#
        return phoneNumber.range(of: phoneRegex, options: .regularExpression) != nil
    }

    var isCodeValid: Bool {
        let codeRegex = #"^\d{6}$"#
        return verificationCode.range(of: codeRegex, options: .regularExpression) != nil
    }

    var canSubmit: Bool {
        isPhoneValid && isCodeValid && !isLoading
    }

    var phoneValidationError: String? {
        if !phoneNumber.isEmpty && !isPhoneValid {
            return "请输入正确的手机号"
        }
        return nil
    }

    var countdownText: String {
        if let countdown = countdown, countdown > 0 {
            return "重新发送(\(countdown)s)"
        }
        if countdown == 0 {
            return "重新发送"
        }
        return "获取验证码"
    }

    var isCountdownActive: Bool {
        guard let countdown = countdown else { return false }
        return countdown > 0
    }

    // MARK: - Init

    init() {}

    /// 注入依赖，在 View.onAppear 中调用
    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func sanitizePhoneInput(_ value: String) {
        let normalized = LoginViewModel.normalizedPhoneNumber(value)
        phoneNumber = normalized
    }

    func sanitizeVerificationCodeInput(_ value: String) {
        let wasComplete = verificationCode.count == 6
        let normalized = LoginViewModel.normalizedVerificationCode(value)
        verificationCode = normalized
        if !wasComplete, normalized.count == 6, canSubmit {
            submitLogin()
        }
    }

    // MARK: - Actions

    func requestCode() {
        sanitizePhoneInput(phoneNumber)
        hasAttemptedSend = true
        guard isPhoneValid else {
            speakPhoneValidationErrorIfNeeded(force: true)
            return
        }

        errorMessage = nil
        showCodeInput = true
        startCountdown()
        // Demo 阶段验证码固定为 123456，无需向后端发送请求
    }

    func submitLogin() {
        guard canSubmit else {
            if showCodeInput, !isCodeValid, !verificationCode.isEmpty {
                errorMessage = "请输入6位验证码"
            }
            return
        }
        Task { await performLogin() }
    }

    func resetCountdown() {
        timerCancellable?.cancel()
        timerCancellable = nil
        countdown = nil
    }

    // MARK: - Private

    private func performLogin() async {
        guard let appState = appState else {
            errorMessage = "应用未初始化，请重启"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let request = PhoneLoginRequest(phoneNumber: phoneNumber, verificationCode: verificationCode)
            let response: AuthResponse = try await appState.apiClient.request(
                method: .post,
                path: "/api/auth/phone-login",
                query: nil,
                body: request,
                requiresAuth: false
            )
            appState.handleLoginSuccess(response: response)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            handleLoginError(error)
        } catch {
            isLoading = false
            errorMessage = "网络错误，请重试"
            speechService?.speakError("网络错误，请重试")
        }
    }

    private func handleLoginError(_ error: APIError) {
        switch error {
        case .serverError(let response):
            if response.errorCode == .invalidVerificationCode {
                errorMessage = "验证码错误，请重新输入"
                verificationCode = ""
                withAnimation { shakeCodeField = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.shakeCodeField = false
                }
            } else {
                errorMessage = response.message
            }
        case .networkError:
            errorMessage = "网络错误，请重试"
        case .unauthorized:
            errorMessage = "登录已过期，请重新登录。"
        case .decodingError, .invalidURL, .unknown:
            errorMessage = "登录失败，请稍后重试。"
        }
        // TTS 播报错误信息，确保盲人用户能听到错误提示
        if let message = errorMessage {
            speechService?.speakError(message)
        }
    }

    private func speakPhoneValidationErrorIfNeeded(force: Bool = false) {
        guard let message = phoneValidationError else {
            lastSpokenInvalidPhoneNumber = nil
            return
        }

        guard force || phoneNumber.count >= 11 else { return }
        guard lastSpokenInvalidPhoneNumber != phoneNumber else { return }

        lastSpokenInvalidPhoneNumber = phoneNumber
        speechService?.speakError(message)
    }

    private func startCountdown() {
        timerCancellable?.cancel()
        countdown = 60
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if let current = self.countdown, current > 0 {
                    self.countdown = current - 1
                } else {
                    self.timerCancellable?.cancel()
                    self.timerCancellable = nil
                }
            }
    }

    private static func normalizedPhoneNumber(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    private static func normalizedVerificationCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(6))
    }
}
