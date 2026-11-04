import Combine
import SwiftUI
import UIKit

/// 与后端 `api_spec.yaml` 的 `idCardNumber` 正则一致。
/// 放在文件作用域而不是 `@MainActor` 类里，`nonisolated` 校验方法才能安全引用。
private let idCardNumberPattern = #"^\d{17}[\dXx]$"#

// MARK: - Blind Identity Verification ViewModel

/// 盲人实名认证（`POST /api/blind/verify-identity`）。
///
/// 契约要点（唯一源：后端仓库 `docs/api_spec.yaml`）：
/// - 请求体 `idCardName`(2–50) + `idCardNumber`(`^\d{17}[\dXx]$`)。
/// - 成功响应 `data = {"message": "身份认证通过", "verifyStatus": "VERIFIED"}`（2026-07-30 起）。
///   优先读响应体里的 `verifyStatus`，省掉一次 `GET /api/blind/profile` 往返；
///   **字段缺失时必须回退到 GET**——生产 `47.114.113.171` 还没部署该版本。
///   只解 `message` / `verifyStatus` 两个白名单字段，其余内容一律丢弃，
///   避免后端把提交的身份证号原样回显后被展示或朗读。
/// - `verifyStatus` 只有 `NOT_VERIFIED` / `VERIFIED` / `FAILED`，**没有"审核中"**。
/// - 实名是下单硬门槛：`OrderCreationService` 校验 `verifyStatus == VERIFIED`，
///   否则 403 `IDENTITY_NOT_VERIFIED`。本页文案不得暗示"未实名也能下单"。
///
/// 隐私约束（OpenSpec `blind-identity-and-contact-management`）：
/// 身份证号只在本 ViewModel 内存中短暂存在，不写入 `AppState`、`UserDefaults`、Keychain 或任何日志；
/// 提交拿到结论、页面消失、App 进后台三个时机都会清空。
/// 例外（#657 B-11）：请求没拿到结论（断网、连不上）时**保留**内存里的输入，免得 18 位盲打一次全部重来。
@MainActor
final class BlindIdentityVerificationViewModel: ObservableObject {

    @Published var idCardName = "" {
        didSet { if !idCardName.isEmpty { clearedOnBackgroundNotice = nil } }
    }
    @Published var idCardNumber = "" {
        didSet { if !idCardNumber.isEmpty { clearedOnBackgroundNotice = nil } }
    }
    @Published private(set) var status: BlindVerifyStatus = .unknown
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    /// 进后台时把已填内容清掉了，回前台要说一声（#657 B-11）。原来回来只看到空框，没有任何提示。
    @Published private(set) var clearedOnBackgroundNotice: String?
    private var didClearOnBackground = false

    static let clearedOnBackgroundMessage = "刚才离开了本页面，为保护隐私，已清空姓名和身份证号，请重新输入。"
    static let keptAfterNetworkFailureSuffix = "你填的姓名和身份证号还在，可以直接再提交一次。"

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var cancellables = Set<AnyCancellable>()

    static let nameLengthRange = 2...50

    init() {
        // App 进后台立即清空敏感字段（锁屏预览、任务切换器截图都可能泄露）。
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleEnterBackground() }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleReturnToForeground() }
            }
            .store(in: &cancellables)
    }

    private func handleEnterBackground() {
        if !idCardName.isEmpty || !idCardNumber.isEmpty {
            didClearOnBackground = true
        }
        clearSensitiveFields()
    }

    private func handleReturnToForeground() {
        guard didClearOnBackground else { return }
        didClearOnBackground = false
        clearedOnBackgroundNotice = Self.clearedOnBackgroundMessage
        speechService?.speak(Self.clearedOnBackgroundMessage)
    }

    // MARK: - 末位 X 与逐位复核

    /// 数字键盘打不出 X，由键盘上方的按钮补（#657 B-11）。X 只能是第 18 位。
    /// - Returns: 没有追加时要播报的原因；`nil` = 已追加。
    @discardableResult
    func appendTrailingX() -> String? {
        guard idCardNumber.count == 17 else {
            let message = "字母 X 只能是第 18 位，现在输入了 \(idCardNumber.count) 位。"
            speechService?.speakError(message)
            return message
        }
        idCardNumber += "X"
        speechService?.speak("已输入 X，共 18 位。")
        return nil
    }

    /// 逐位拼读用的文本：按「6 位地区码、8 位生日、其余」分三段，段内每个字符之间留空格，
    /// 读屏才会一个字一个字地念，而不是念成「一千一百零一……」。
    nonisolated static func spelledOutIdCard(_ value: String) -> String {
        let characters = Array(value)
        let groups = [characters.prefix(6), characters.dropFirst(6).prefix(8), characters.dropFirst(14)]
        return groups
            .filter { !$0.isEmpty }
            .map { $0.map(String.init).joined(separator: " ") }
            .joined(separator: "，")
    }

    // MARK: - Configuration

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        status = appState.blindIdentityStatus
    }

    // MARK: - Validation

    var isNameValid: Bool {
        Self.nameLengthRange.contains(idCardName.trimmed.count)
    }

    var isIdCardNumberValid: Bool {
        Self.isValidIdCardNumber(idCardNumber)
    }

    var canSubmit: Bool {
        isNameValid && isIdCardNumberValid && !isSubmitting
    }

    /// 首个未通过的格式校验提示，供字段错误文案和提交拦截共用。
    var validationMessage: String? {
        if !isNameValid { return "请输入 2 到 50 个字的真实姓名。" }
        if !isIdCardNumberValid { return "请输入 18 位身份证号，最后一位可以是字母 X。" }
        return nil
    }

    static func isValidIdCardNumber(_ value: String) -> Bool {
        value.trimmed.range(of: idCardNumberPattern, options: .regularExpression) != nil
    }

    /// 只保留数字和 X 并统一大写，最长 18 位：避免粘贴带空格/连字符的值被后端直接 400。
    static func normalizedIdCardInput(_ value: String) -> String {
        String(value.uppercased().filter { $0.isNumber || $0 == "X" }.prefix(18))
    }

    func sanitizeIdCardInput(_ value: String) {
        let normalized = Self.normalizedIdCardInput(value)
        if normalized != idCardNumber {
            idCardNumber = normalized
        }
    }

    // MARK: - Announcements

    /// 进入页面、状态变化和「重复当前状态」共用同一句播报，保证语义等价。
    var statusAnnouncement: String {
        var parts = [status.guidanceMessage]
        if status.shouldPromptVerification {
            parts.append("实名认证是预约跑步的必要条件，请填写姓名和身份证号后提交。")
        }
        if let successMessage { parts.append(successMessage) }
        if let errorMessage { parts.append(errorMessage) }
        return parts.joined(separator: " ")
    }

    func announceCurrentStatus() {
        speechService?.speak(statusAnnouncement)
    }

    // MARK: - Status Refresh

    /// 提交响应里带回的状态直接采信，并同步进 `AppState`（下单门槛读的就是它）。
    /// 只写状态位，不碰 name 等其他资料字段——响应体没有它们，写 nil 会把已有资料抹掉。
    private func applyVerifyStatusFromSubmitResponse(_ newStatus: BlindVerifyStatus, appState: AppState) {
        let existing = appState.blindProfile
        appState.updateBlindProfile(
            BlindProfileResponse(
                name: existing?.name,
                runningPace: existing?.runningPace,
                specialNeeds: existing?.specialNeeds,
                verifyStatus: newStatus.rawValue,
                visionLevel: existing?.visionLevel,
                hasGuideDog: existing?.hasGuideDog,
                guideDog: existing?.guideDog,
                tetherPreference: existing?.tetherPreference,
                chatPreference: existing?.chatPreference,
                defaultPace: existing?.defaultPace,
                // 漏了它，资料页会读到空串，再保存一次就把服务器上的引导偏好清空（#473）。
                guidePreferenceText: existing?.guidePreferenceText
            )
        )
        status = newStatus
    }

    /// 权威状态只能从 `GET /api/blind/profile` 得到。失败时保持 AppState 里的已知值，不猜测。
    func refreshStatus() async {
        guard let appState else { return }
        do {
            let profile = try await appState.profile.blindProfile()
            appState.updateBlindProfile(profile)
            status = profile.identityStatus
        } catch let error as APIError {
            _ = appState.handleAuthenticatedAPIError(error)
            status = appState.blindIdentityStatus
        } catch {
            status = appState.blindIdentityStatus
        }
    }

    // MARK: - Submit

    func submit() {
        // 重复提交保护：提交中直接忽略，不排队第二个请求。
        guard !isSubmitting else { return }
        clearedOnBackgroundNotice = nil
        guard canSubmit else {
            let message = validationMessage ?? BlindIdentityVerificationFailure.genericMessage
            errorMessage = message
            successMessage = nil
            speechService?.speakError(message)
            return
        }
        Task { await performSubmit() }
    }

    private func performSubmit() async {
        guard let appState else { return }
        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        let request = BlindVerifyRequest(
            idCardName: idCardName.trimmed,
            idCardNumber: idCardNumber.trimmed
        )

        do {
            // 只解 message / verifyStatus 两个白名单字段，其余回显内容（可能含身份证号）自然丢弃。
            let submitResponse = try await appState.profile.verifyBlindIdentity(request)
            clearSensitiveFields()
            if let resolved = submitResponse.resolvedStatus {
                // 新契约：响应体直接带权威状态，省一次 GET /api/blind/profile。
                applyVerifyStatusFromSubmitResponse(resolved, appState: appState)
            } else {
                // 老后端（生产尚未部署）不返回该字段，回退到原来的重查流程。
                await refreshStatus()
            }
            isSubmitting = false
            applySubmittedStatusCopy()
        } catch let error as APIError {
            isSubmitting = false
            if case .networkError = error {
                // 请求没到服务端，填的内容没有任何问题 —— 清空等于让用户把 18 位再盲打一遍（#657 B-11）。
                errorMessage = BlindIdentityVerificationFailure.message(for: error) + Self.keptAfterNetworkFailureSuffix
            } else {
                clearSensitiveFields()
                if appState.handleAuthenticatedAPIError(error) { return }
                // 固定文案，绝不回显后端 message（后端可能把身份证号带回来）。
                errorMessage = BlindIdentityVerificationFailure.message(for: error) + "请重新输入姓名和身份证号后重试。"
            }
        } catch {
            // 不是 `APIError` 的错误同样没拿到结论，按断网处理。
            isSubmitting = false
            errorMessage = BlindIdentityVerificationFailure.genericMessage + Self.keptAfterNetworkFailureSuffix
        }

        speechService?.speak(statusAnnouncement)
    }

    /// 后端没有"审核中"态：提交后只可能回到三态之一。
    private func applySubmittedStatusCopy() {
        switch status {
        case .verified:
            successMessage = "实名认证已完成。"
        case .failed:
            errorMessage = "实名认证未通过，请核对姓名和身份证号后重新提交。"
        case .notVerified, .unknown:
            successMessage = "实名信息已提交，稍后可返回本页查看最新状态。"
        }
    }

    // MARK: - Sensitive Field Lifecycle

    /// 提交完成、页面消失、App 进后台都会调用。身份证号不允许在此之外继续留在内存里。
    func clearSensitiveFields() {
        idCardName = ""
        idCardNumber = ""
    }

    func handleDisappear() {
        clearSensitiveFields()
    }
}

// MARK: - Blind Identity Verification View

/// 可独立 push 的实名认证页。入口挂载见任务 3.3（设置页 / 引导流程）。
struct BlindIdentityVerificationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindIdentityVerificationViewModel()
    /// 明文查看必须由用户主动触发，再点一次立刻回到掩码。
    @State private var isRevealingNumber = false
    /// 身份证号的**单独同意**（PIPL 第 29 条）。首次提交前全屏告知，同意后才发请求。
    @State private var showIdentityConsent = false
    @State private var consentDeclinedNotice: String?
    @FocusState private var isIdCardFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusCard
                if viewModel.status != .verified {
                    formSection
                }
                messageSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(AppColors.background)
        .navigationTitle("实名认证")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                // 只在身份证号框聚焦时出现：姓名框用的是带回车键的普通键盘。
                if isIdCardFieldFocused {
                    Button("输入 X") { viewModel.appendTrailingX() }
                        .accessibilityLabel("输入字母 X")
                        .accessibilityHint("身份证号最后一位是 X 时用，只能输在第 18 位")
                    Spacer()
                    Button("完成") { isIdCardFieldFocused = false }
                        .accessibilityLabel("收起键盘")
                }
            }
        }
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.refreshStatus()
            viewModel.announceCurrentStatus()
        }
        .onChange(of: viewModel.idCardNumber) { newValue in
            if newValue.isEmpty { isRevealingNumber = false }
        }
        .onDisappear {
            // 全屏同意页盖上来也会触发这里。那时用户还在提交途中，清空的话同意之后发出去的是空表单，
            // 要把 18 位重打一遍（#657 B-11）。真正离开页面时同意页已经关了，照常清空。
            guard !showIdentityConsent else { return }
            isRevealingNumber = false
            viewModel.handleDisappear()
        }
        // 全屏而不是对话框：三条告知要各自可听、可停、可回头再听，理由见 `ConsentDisclosureView`。
        .fullScreenCover(isPresented: $showIdentityConsent) {
            ConsentDisclosureView(
                purpose: .blindIdentity,
                onAgree: {
                    showIdentityConsent = false
                    consentDeclinedNotice = nil
                    // 同意在**发请求之前**落盘，与行程分享同一个理由：一次网络失败不该让用户
                    // 再看一遍全文告知，他已经同意过了，重复告知是在消耗告知本身的效力。
                    consentStore.recordConsent(to: .blindIdentity, scope: consentScope)
                    viewModel.submit()
                },
                onDecline: {
                    showIdentityConsent = false
                    consentDeclinedNotice = PrivacyConsentPurpose.blindIdentity.declinedFeedback
                    speechService.speak(PrivacyConsentPurpose.blindIdentity.declinedFeedback)
                }
            )
        }
    }

    // MARK: - Sensitive Consent

    private var consentStore: PrivacyConsentStore {
        PrivacyConsentStore(persistence: appState.persistence)
    }

    /// 同意按**人**记。拿不到 userId 时用一个恒不命中的 scope，效果是每次都走全屏告知 ——
    /// 宁可多问一次，也不能让一个身份不明的会话继承别人的同意。
    private var consentScope: PrivacyConsentScope {
        guard let userId = appState.userId else { return .user("unknown") }
        return .user(String(userId))
    }

    /// 提交按钮的唯一入口：**没有单独同意就不发请求**。
    /// 按钮本身有 `.disabled(!canSubmit)`，格式校验仍由 `viewModel.submit()` 兜底。
    private func handleSubmitTapped() {
        guard consentStore.hasConsented(to: .blindIdentity, scope: consentScope) else {
            showIdentityConsent = true
            return
        }
        viewModel.submit()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("实名认证", style: .title)
                .accessibilityAddTraits(.isHeader)

            Text("完成实名认证后才能预约跑步。身份证号只用于本次核验，不会保存在本机。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("完成实名认证后才能预约跑步。身份证号只用于本次核验，不会保存在本机")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText(viewModel.status.displayName, style: .status)
            Text(viewModel.status.guidanceMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前实名状态，\(viewModel.status.displayName)")
        .accessibilityValue(viewModel.status.guidanceMessage)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            IdentityInputField(
                title: "真实姓名",
                placeholder: "请输入身份证上的姓名",
                text: $viewModel.idCardName,
                errorMessage: viewModel.idCardName.isEmpty || viewModel.isNameValid
                    ? nil
                    : "请输入 2 到 50 个字的真实姓名",
                accessibilityLabel: "真实姓名，必填",
                accessibilityValue: viewModel.idCardName.isEmpty ? "尚未输入" : "已输入",
                accessibilityHint: "请输入身份证上的姓名"
            )

            VStack(alignment: .leading, spacing: 8) {
                IdentityInputField(
                    title: "身份证号",
                    placeholder: "请输入18位身份证号",
                    text: $viewModel.idCardNumber,
                    isSecure: !isRevealingNumber,
                    keyboardType: .numberPad,
                    errorMessage: viewModel.idCardNumber.isEmpty || viewModel.isIdCardNumberValid
                        ? nil
                        : "请输入 18 位身份证号，最后一位可以是字母 X",
                    accessibilityLabel: "身份证号，必填，18位",
                    accessibilityValue: idCardAccessibilityValue,
                    accessibilityHint: "数字键盘。最后一位是 X 时，用键盘上方的「输入 X」。输入内容默认隐藏，只用于实名认证，不会保存在本机"
                )
                .focused($isIdCardFieldFocused)
                .onChange(of: viewModel.idCardNumber) { newValue in
                    viewModel.sanitizeIdCardInput(newValue)
                }

                Button(isRevealingNumber ? "隐藏身份证号" : "临时显示身份证号") {
                    isRevealingNumber.toggle()
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityLabel(isRevealingNumber ? "隐藏身份证号" : "临时显示身份证号")
                .accessibilityHint(
                    isRevealingNumber
                        ? "再次点击后重新隐藏身份证号"
                        : "点击后在屏幕上临时显示身份证号，再次点击即可隐藏"
                )

                // 读屏用户核对 18 位的唯一办法：字段本身只念位数和末四位（#657 B-11）。
                if !viewModel.idCardNumber.isEmpty {
                    Button("逐位朗读身份证号") {
                        readIdCardDigitByDigit()
                    }
                    .buttonStyle(TextButtonStyle())
                    .accessibilityHint("用读屏把完整号码一位一位念出来，周围的人可能听到，建议戴耳机")
                    .accessibilityIdentifier("blindIdentityReadDigits")
                }
            }
        }
    }

    /// 读屏开着：直接发一条读屏通告，**不经过 `SpeechService`** —— 那里播过的话会留在
    /// 「重复当前状态」的缓存里，换个页面一按就把身份证号外放出来。
    /// 读屏没开：不念号码，改成临时在屏幕上显示。
    private func readIdCardDigitByDigit() {
        guard UIAccessibility.isVoiceOverRunning else {
            isRevealingNumber = true
            speechService.speak("已在屏幕上临时显示身份证号。")
            return
        }
        let spelled = BlindIdentityVerificationViewModel.spelledOutIdCard(viewModel.idCardNumber)
        let announcement = NSAttributedString(
            string: spelled,
            attributes: [
                .accessibilitySpeechSpellOut: true,
                .accessibilitySpeechQueueAnnouncement: true
            ]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    @ViewBuilder
    private var messageSection: some View {
        if let notice = viewModel.clearedOnBackgroundNotice {
            Text(notice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(notice)
                .accessibilityIdentifier("blindIdentityClearedOnBackgroundNotice")
        }
        if let consentDeclinedNotice {
            Text(consentDeclinedNotice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel(consentDeclinedNotice)
                .accessibilityIdentifier("blindIdentityConsentDeclinedNotice")
        }
        if let successMessage = viewModel.successMessage {
            Text(successMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel(successMessage)
        }
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .accessibilityLabel(errorMessage)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if viewModel.status != .verified {
                PrimaryButton(submitTitle, isLoading: viewModel.isSubmitting) {
                    handleSubmitTapped()
                }
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.45)
                .accessibilityLabel(submitTitle)
                .accessibilityHint(
                    viewModel.canSubmit
                        ? "点击后提交实名信息"
                        : "请先填写真实姓名和18位身份证号"
                )
            }

            PrimaryButton("重复当前状态") {
                viewModel.announceCurrentStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前实名状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private var submitTitle: String {
        viewModel.status == .failed ? "重新提交实名信息" : "提交实名信息"
    }

    /// VoiceOver 永远读不到完整身份证号：只播报位数和末四位。
    private var idCardAccessibilityValue: String {
        let count = viewModel.idCardNumber.count
        guard count > 0 else { return "尚未输入" }
        guard count >= 4 else { return "已输入\(count)位" }
        return "已输入\(count)位，末四位\(viewModel.idCardNumber.suffix(4))"
    }
}

// MARK: - Identity Input Field

/// `ProfileModule` 里的输入框是 private，这里保留一个支持隐私输入的最小版本。
private struct IdentityInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    let errorMessage: String?
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text("*")
                    .font(.headline)
                    .foregroundColor(AppColors.destructive)
                    .accessibilityHidden(true)
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(AppFonts.body())
            .padding()
            .background(AppColors.secondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(errorMessage == nil ? Color.clear : AppColors.destructive, lineWidth: 1)
            )
            .cornerRadius(8)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindIdentityVerificationView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
