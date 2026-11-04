import SwiftUI
import UIKit

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
                placeholder: "姓名",
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
                    placeholder: "18位号码",
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
