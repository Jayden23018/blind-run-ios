import SwiftUI
import UIKit

// MARK: - Blind Identity Verification View

/// 可独立 push 的实名认证页（首页实名入口、账户页、首次引导三处进入）。
///
/// 版式照定稿 `docs/ui/mockups/blind-identity-20261105/identity-final.png`（#751）：
/// 灰底白卡；顶部图标 + 一句话；状态卡最后一行是「重复当前状态」；姓名、身份证号左名右值；
/// 底部「提交核验」没填完不可点，按钮下写「还差：xx」；未通过时按钮叫「重新提交」；已认证只剩结果，不出表单。
/// 提交、校验、清空时机都在 `BlindIdentityVerificationViewModel`，这里只管画。
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
        // 按钮栏放在滚动区**下面**，不叠在内容上：叠上去时栏后面的字会被审计判成对比度不足
        // （记忆 `opaque-bottom-bar-fakes-contrast-failure`）。
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statusCard
                    if showsForm {
                        formCard
                        idCardActionsCard
                    }
                    messageSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            if showsForm {
                bottomBar
            }
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle("实名认证")
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏，否则最后一行被它盖住（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
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

    /// 已认证整页只剩结果：不出表单，也没有提交按钮。
    private var showsForm: Bool {
        viewModel.status != .verified
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

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch viewModel.status {
        case .verified:
            BlindIdentityVerifiedHeader()
        case .failed:
            BlindIdentityLeadingHeader(
                systemImage: "exclamationmark",
                tileColor: AppColors.destructive,
                title: "没有通过核验",
                subtitle: "姓名和身份证号对不上。核对后重新提交。"
            )
        case .notVerified, .unknown:
            BlindIdentityLeadingHeader(
                systemImage: "person.text.rectangle",
                tileColor: AppColors.primarySolidSurface,
                title: "先确认是你本人",
                subtitle: "实名后才能预约跑步。身份证号只用于这次核验，不会保存在这台手机上。"
            )
        }
    }

    // MARK: - Status Card

    /// 状态卡：当前状态一行 +「重复当前状态」一行。已认证时状态行改成「实名状态 · 已通过」，
    /// 「重复当前状态」单独一张卡（定稿第二屏）。读屏标签和以前一样：「当前实名状态，xx」+ 完整引导。
    @ViewBuilder
    private var statusCard: some View {
        if viewModel.status == .verified {
            GroupedCard {
                HStack(spacing: 8) {
                    Text("实名状态")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("已通过")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
                .modifier(BlindIdentityStatusRowStyle(status: viewModel.status))
            }
            GroupedCard {
                repeatStatusRow
            }
        } else {
            GroupedCard {
                (Text("当前：") + Text(statusLine).fontWeight(.semibold))
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(BlindIdentityStatusRowStyle(status: viewModel.status))
                GroupedCardDivider()
                repeatStatusRow
            }
        }
    }

    /// 状态卡上看得见的那半句。读屏念的仍是 `guidanceMessage` 全文（见 `BlindIdentityStatusRowStyle`）。
    /// 状态未知时没有更短的说法，沿用原文案。
    private var statusLine: String {
        switch viewModel.status {
        case .notVerified: return "还没有实名认证。"
        case .failed: return "实名认证未通过，暂时不能预约跑步。"
        case .verified: return "已通过"
        case .unknown: return viewModel.status.guidanceMessage
        }
    }

    private var repeatStatusRow: some View {
        BlindIdentityRepeatStatusRow { viewModel.announceCurrentStatus() }
    }

    // MARK: - Form

    private var formCard: some View {
        GroupedCard {
            BlindIdentityFieldRow(
                title: "姓名",
                placeholder: "身份证上的姓名",
                text: $viewModel.idCardName,
                errorMessage: viewModel.idCardName.isEmpty || viewModel.isNameValid
                    ? nil
                    : "请输入 2 到 50 个字的真实姓名",
                accessibilityLabel: "真实姓名，必填",
                accessibilityValue: viewModel.idCardName.isEmpty ? "尚未输入" : "已输入",
                accessibilityHint: "请输入身份证上的姓名"
            )

            GroupedCardDivider()

            BlindIdentityFieldRow(
                title: "身份证号",
                placeholder: "18 位，最后一位可以是 X",
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
        }
    }

    /// 「临时显示 / 隐藏」与「逐位朗读」两行蓝字。两行一直都在（定稿空表单也画着逐位朗读）；
    /// 没填号码时点逐位朗读，念一句「还没有输入」，不让点了没反应。
    private var idCardActionsCard: some View {
        GroupedCard {
            Button(isRevealingNumber ? "隐藏身份证号" : "临时显示身份证号") {
                isRevealingNumber.toggle()
            }
            .buttonStyle(TextButtonStyle())
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .accessibilityLabel(isRevealingNumber ? "隐藏身份证号" : "临时显示身份证号")
            .accessibilityHint(
                isRevealingNumber
                    ? "再次点击后重新隐藏身份证号"
                    : "点击后在屏幕上临时显示身份证号，再次点击即可隐藏"
            )
            .accessibilityIdentifier("blindIdentityRevealToggle")

            // 读屏用户核对 18 位的唯一办法：字段本身只念位数和末四位（#657 B-11）。
            GroupedCardDivider()
            Button("逐位朗读身份证号") {
                readIdCardDigitByDigit()
            }
            .buttonStyle(TextButtonStyle())
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .accessibilityHint("用读屏把完整号码一位一位念出来，周围的人可能听到，建议戴耳机")
            .accessibilityIdentifier("blindIdentityReadDigits")
        }
    }

    /// 读屏开着：直接发一条读屏通告，**不经过 `SpeechService`** —— 那里播过的话会留在
    /// 「重复当前状态」的缓存里，换个页面一按就把身份证号外放出来。
    /// 读屏没开：不念号码，改成临时在屏幕上显示。
    private func readIdCardDigitByDigit() {
        guard !viewModel.idCardNumber.isEmpty else {
            speechService.speak("还没有输入身份证号。")
            return
        }
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

    // MARK: - Messages

    private var messageSection: some View {
        BlindIdentityMessageList(
            clearedOnBackgroundNotice: viewModel.clearedOnBackgroundNotice,
            consentDeclinedNotice: consentDeclinedNotice,
            successMessage: viewModel.successMessage,
            errorMessage: viewModel.errorMessage
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            PrimaryButton(submitTitle, isLoading: viewModel.isSubmitting) {
                handleSubmitTapped()
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.45)
            .accessibilityLabel(submitTitle)
            .accessibilityHint(
                viewModel.canSubmit
                    ? "点击后提交核验"
                    : "按钮下面写着还差哪几项"
            )
            .accessibilityIdentifier("blindIdentitySubmitButton")

            if let submitFootnote {
                Text(submitFootnote)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("blindIdentitySubmitFootnote")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(AppColors.Flow.page)
        // 审计按这个标识认出底栏：滚到栏后面的状态卡文字不算对比度失败（AX5 实测，#751）。
        // `.contain` 保住按钮与灰字自己的标识（记忆 `accessibility-identifier-overwrites-children`）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindIdentitySubmitBar")
    }

    // MARK: - Helpers

    /// 改名（#751）：「提交实名信息」→「提交核验」，失败后「重新提交实名信息」→「重新提交」。
    /// 播报同步：提交后念「已提交核验」；失败引导「请核对姓名和身份证号后重新提交」与新名一致。
    private var submitTitle: String {
        viewModel.status == .failed ? "重新提交" : "提交核验"
    }

    /// 按钮下面那行灰字：没填完写「还差：xx」；填完了但还没同意过，先说清点了会先问同意。
    private var submitFootnote: String? {
        guard !viewModel.isSubmitting else { return nil }
        var missing: [String] = []
        if !viewModel.isNameValid { missing.append("姓名") }
        if !viewModel.isIdCardNumberValid { missing.append("身份证号") }
        if !missing.isEmpty {
            return "还差：\(missing.joined(separator: "、"))"
        }
        guard !consentStore.hasConsented(to: .blindIdentity, scope: consentScope) else { return nil }
        return "提交前会先问你同不同意使用身份证号"
    }

    /// VoiceOver 永远读不到完整身份证号：只播报位数和末四位。
    private var idCardAccessibilityValue: String {
        let count = viewModel.idCardNumber.count
        guard count > 0 else { return "尚未输入" }
        guard count >= 4 else { return "已输入\(count)位" }
        return "已输入\(count)位，末四位\(viewModel.idCardNumber.suffix(4))"
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
