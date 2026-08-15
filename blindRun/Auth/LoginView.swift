import SwiftUI
import UIKit

// MARK: - Shake Modifier

/// 输入框抖动动画修饰器，用于验证码错误反馈。
///
/// 「减弱动态效果」开启时**整个不抖**：`interpolatingSpring(stiffness: 2000, damping: 5)`
/// 配 `repeatCount(3)` 是一次高频往复位移，正是那个开关要挡的前庭刺激来源
/// （晕动敏感、前庭偏头痛的用户会因此恶心，不是"觉得晃"而已）。
///
/// 关掉不丢信息：验证码错误同时会写 `errorMessage`（「验证码错误，请重新输入」），
/// 抖动一直只是那句话的强调，不是唯一通道。
private struct ShakeEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let shouldShake: Bool

    private var isShaking: Bool { shouldShake && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .offset(x: isShaking ? -10 : 0)
            .animation(
                isShaking
                    ? Animation.interpolatingSpring(stiffness: 2000, damping: 5)
                        .repeatCount(3, autoreverses: true)
                    : .default,
                value: isShaking
            )
    }
}

private extension View {
    func shake(_ shouldShake: Bool) -> some View {
        modifier(ShakeEffect(shouldShake: shouldShake))
    }
}

// MARK: - Fixed Length Phone Field

private struct LoginPhoneNumberField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxLength: Int
    let accessibilityLabel: String
    let accessibilityHint: String

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        context.coordinator.textField = textField

        textField.placeholder = placeholder
        textField.keyboardType = .numberPad
        textField.textContentType = .telephoneNumber
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.font = UIFont.preferredFont(forTextStyle: .title3)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.clearButtonMode = .never
        textField.inputAccessoryView = context.coordinator.makeAccessoryToolbar()
        textField.accessibilityLabel = accessibilityLabel
        textField.accessibilityHint = accessibilityHint

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self

        let normalized = LoginViewModel.normalizedPhoneNumber(text)
        if text != normalized {
            DispatchQueue.main.async {
                self.text = normalized
            }
        }
        if textField.text != normalized {
            textField.text = normalized
        }
        textField.accessibilityLabel = accessibilityLabel
        textField.accessibilityHint = accessibilityHint
        textField.accessibilityValue = normalized.isEmpty ? "未输入" : normalized
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LoginPhoneNumberField
        weak var textField: UITextField?

        init(parent: LoginPhoneNumberField) {
            self.parent = parent
        }

        func makeAccessoryToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexibleSpace = UIBarButtonItem(
                barButtonSystemItem: .flexibleSpace,
                target: nil,
                action: nil
            )
            let doneButton = UIBarButtonItem(
                title: "完成",
                style: .done,
                target: self,
                action: #selector(doneTapped)
            )
            doneButton.accessibilityLabel = "收起键盘"
            toolbar.items = [flexibleSpace, doneButton]
            return toolbar
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else {
                return false
            }

            let proposedText = currentText.replacingCharacters(in: stringRange, with: string)
            let normalized = String(proposedText.filter(\.isNumber).prefix(parent.maxLength))
            parent.text = normalized
            textField.text = normalized
            textField.accessibilityValue = normalized.isEmpty ? "未输入" : normalized
            updateCursor(in: textField, currentText: currentText, changedRange: stringRange, replacement: string)
            return false
        }

        @objc private func doneTapped() {
            textField?.resignFirstResponder()
        }

        private func updateCursor(
            in textField: UITextField,
            currentText: String,
            changedRange: Range<String.Index>,
            replacement: String
        ) {
            let rangeStart = currentText.distance(from: currentText.startIndex, to: changedRange.lowerBound)
            let replacementDigits = replacement.filter(\.isNumber).count
            let targetOffset = min(rangeStart + replacementDigits, textField.text?.count ?? 0)
            guard let position = textField.position(from: textField.beginningOfDocument, offset: targetOffset) else {
                return
            }
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }
    }
}

// MARK: - Login View

/// 登录页：手机号 + 验证码登录。
/// 遵循 MVVM：纯渲染 View，所有业务逻辑在 LoginViewModel 中。
struct LoginView: View {
    private enum FocusField: Hashable {
        case phone
        case verificationCode
    }

    private enum ScrollTarget: Hashable {
        case verificationCode
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = LoginViewModel()
    @State private var pendingVerificationFocus = false
    /// 「减弱动态效果」是**前庭功能**的无障碍设置，与看不看得见无关 —— 它服务的是晕动症用户，
    /// 而这一屏的三处动效（验证码框滑入、错误提示淡入淡出、滚动到验证码框）全是位移。
    /// `ShakeEffect` 早就尊重了它，同一屏的其余三处一直没有。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedField: FocusField?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.top + 60)

                        // App 品牌标识
                        HighContrastText("助盲跑", style: .title)
                            .font(.largeTitle.weight(.bold))

                        Spacer()
                            .frame(height: 40)

                        // 手机号输入区
                        VStack(alignment: .leading, spacing: 8) {
                            LoginPhoneNumberField(
                                text: phoneNumberBinding,
                                placeholder: "请输入手机号",
                                maxLength: 11,
                                accessibilityLabel: "手机号输入框，请输入 11 位手机号",
                                accessibilityHint: "请输入 11 位手机号，只能输入数字"
                            )
                                .font(.title3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            viewModel.phoneValidationError != nil
                                                ? AppColors.destructive
                                                : Color(.systemGray4),
                                            lineWidth: viewModel.phoneValidationError != nil ? 2 : 1
                                        )
                                )
                                .accessibilityLabel("手机号输入框，请输入 11 位手机号")
                                .accessibilityHint("请输入 11 位手机号，只能输入数字")
                                .accessibilityValue(viewModel.phoneNumber.isEmpty ? "未输入" : viewModel.phoneNumber)

                            // 手机号格式错误提示
                            if let error = viewModel.phoneValidationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(AppColors.destructive)
                                    .accessibilityLabel(error)
                            }
                        }

                        // "获取验证码" / 倒计时 按钮
                        Button {
                            requestCodeAndPrepareVerificationFocus(using: scrollProxy)
                        } label: {
                            Text(viewModel.countdownText)
                                .font(AppFonts.primaryButton())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    (!viewModel.canRequestCode)
                                        ? Color(.systemGray4)
                                        : AppColors.primary
                                )
                                .cornerRadius(12)
                        }
                        .disabled(!viewModel.canRequestCode)
                        .accessibilityLabel(viewModel.countdownText)
                        .accessibilityHint(viewModel.isCountdownActive ? "服务端限制发送频率，倒计时结束后可重试" : "点击后发送验证码到手机")

                        // 验证码输入区（条件显示）
                        if viewModel.showCodeInput {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(
                                    "请输入6位验证码",
                                    text: verificationCodeBinding
                                )
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .font(.title3)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                viewModel.errorMessage != nil
                                                    ? AppColors.destructive
                                                    : Color(.systemGray4),
                                                lineWidth: viewModel.errorMessage != nil ? 2 : 1
                                            )
                                    )
                                    .focused($focusedField, equals: .verificationCode)
                                    .shake(viewModel.shakeCodeField)
                                    .accessibilityLabel("验证码输入框，请输入 6 位验证码")
                                    .accessibilityValue(viewModel.verificationCode.isEmpty ? "未输入" : viewModel.verificationCode)

                            }
                            .id(ScrollTarget.verificationCode)
                            // 开启「减弱动态效果」时只淡入，不从顶端滑进来。淡入保留了
                            // 「有新东西出现」这个提示本身，去掉的只是位移（与 `ContentView` 的横幅同一处理）。
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }

                        // Loading 状态文字
                        if viewModel.isLoading && !viewModel.showCodeInput {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在登录...")
                                    .font(AppFonts.body())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .accessibilityLabel("正在登录，请稍候")
                        }

                        // 错误消息
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(AppFonts.body())
                                .foregroundColor(AppColors.destructive)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .accessibilityLabel(error)
                        }

                        Spacer()

                        // 环境切换入口（底部角落，灰色小字）
                        #if DEBUG
                        if AppBuildChannel.current.allowsEnvironmentSwitcher {
                            environmentSwitcher
                        }
                        #endif
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, viewModel.showCodeInput ? 160 : 0)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: viewModel.showCodeInput) { showCodeInput in
                    guard showCodeInput, pendingVerificationFocus else { return }
                    focusVerificationCode(using: scrollProxy)
                }
                .onChange(of: viewModel.errorMessage) { errorMessage in
                    if errorMessage != nil, !viewModel.showCodeInput {
                        pendingVerificationFocus = false
                    }
                }
            }
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            if viewModel.showCodeInput {
                PrimaryButton("登录", isLoading: viewModel.isLoading) {
                    focusedField = nil
                    viewModel.submitLogin()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
                .accessibilityLabel("收起键盘")
            }
        }
        .onAppear {
            viewModel.configure(with: appState, speechService: speechService)
        }
        .onDisappear {
            viewModel.resetCountdown()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.showCodeInput)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.errorMessage)
    }

    private func requestCodeAndPrepareVerificationFocus(using scrollProxy: ScrollViewProxy) {
        pendingVerificationFocus = true
        focusedField = nil
        dismissActiveInput()
        viewModel.requestCode()

        if viewModel.showCodeInput {
            focusVerificationCode(using: scrollProxy)
        }
    }

    private func focusVerificationCode(using scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            // 动画滚动是位移里最容易引起不适的一种（整屏内容移动）。关掉动画不影响落点，
            // 焦点仍然会移到验证码框上。
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(ScrollTarget.verificationCode, anchor: .center)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedField = .verificationCode
                pendingVerificationFocus = false
            }
        }
    }

    private func dismissActiveInput() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var phoneNumberBinding: Binding<String> {
        Binding(
            get: { viewModel.phoneNumber },
            set: { viewModel.sanitizePhoneInput($0) }
        )
    }

    private var verificationCodeBinding: Binding<String> {
        Binding(
            get: { viewModel.verificationCode },
            set: { newValue in
                viewModel.sanitizeVerificationCodeInput(newValue)
                if viewModel.verificationCode.count == 6, viewModel.canSubmit {
                    focusedField = nil
                }
            }
        )
    }

    // MARK: - Environment Switcher

    #if DEBUG
    private var environmentSwitcher: some View {
        VStack(spacing: 10) {
            Button {
                // 循环切换环境
                let allEnvs = AppState.debugTestEnvironments
                guard let currentIndex = allEnvs.firstIndex(of: appState.currentEnvironment) else {
                    appState.currentEnvironment = .mock
                    return
                }
                let nextIndex = (currentIndex + 1) % allEnvs.count
                appState.currentEnvironment = allEnvs[nextIndex]
            } label: {
                Text(environmentLabel)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .accessibilityLabel("API 环境切换")
            .accessibilityHint("当前环境：\(environmentLabel)")
            .accessibilityValue(appState.currentEnvironment.displayName)
        }
    }

    private var environmentLabel: String {
        return "API 环境: \(appState.currentEnvironment.displayName)"
    }
    #endif
}
// MARK: - Preview

#if DEBUG
#Preview {
    LoginView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
