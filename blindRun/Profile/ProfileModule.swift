import Combine
import SwiftUI

// MARK: - Blind Runner Profile ViewModel

@MainActor
final class BlindRunnerProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var defaultPace: PacePreference = .noPreference
    @Published var specialNeeds = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: 陪跑偏好
    //
    // 这三个字段 2026-09-10 之前**在 iOS 上根本没有采集入口** —— `saveProfile` 里写死传 nil，
    // 值一律来自后端选角色时自动建档的默认值（`visionLevel = TOTAL_BLIND`、`hasGuideDog = false`）。
    // 后果不是「资料不全」而是**低视力用户被记成全盲**，而志愿者接单前看到的正是这一行，
    // 据它决定该不该挥手、该不该递绳。
    //
    // 🔴 **同意边界画在 `tetherPreference` 与另外两个之间，不要合并：**
    // 引导方式是偏好不是身份信息，不敏感，任何时候都能填；视力状况与导盲犬是敏感个人信息
    // （PIPL 第二十八条「特定身份」），要走 `PrivacyConsentPurpose.blindVisionProfile` 单独同意。
    // 拒绝了敏感那一半的人**仍然填得了引导方式**，志愿者仍知道该怎么带他 —— 这是「可拒绝」
    // 在产品上真正成立的支点。依据见 `docs/research/vision-level-collection-ui-20260910.md` §4.2。

    /// 引导方式。**不需要同意**，`nil` = 用户还没选。
    @Published var tetherPreference: TetherPreference?
    /// 视力状况。`nil` = 没选或没同意。
    @Published var visionLevel: VisionLevel?
    @Published var hasGuideDog = false

    /// 是否已就「视力状况 + 导盲犬」取得单独同意。
    ///
    /// 做成 `@Published` 而不是每次现算：现算的计算属性变了 SwiftUI 收不到通知，
    /// 用户在同意页按下「同意并填写」之后界面不会展开，表现就是「点了没反应」。
    @Published private(set) var hasVisionConsent = false

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var isEditing: Bool {
        appState?.blindProfile != nil
    }

    var canSubmit: Bool {
        !name.trimmed.isEmpty && !isLoading
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        if let profile = appState.blindProfile {
            name = profile.name ?? ""
            defaultPace = profile.defaultPace?.selectable ?? .noPreference
            specialNeeds = profile.specialNeeds ?? ""
            tetherPreference = profile.tetherPreference.flatMap(TetherPreference.init(rawValue:))
            visionLevel = profile.visionLevel.flatMap(VisionLevel.init(rawValue:))
            hasGuideDog = profile.hasGuideDog ?? false
        }

        hasVisionConsent = consentStore?.hasConsented(to: .blindVisionProfile, scope: consentScope) == true
    }

    // MARK: - 敏感项的单独同意

    private var consentStore: PrivacyConsentStore? {
        appState.map { PrivacyConsentStore(persistence: $0.persistence) }
    }

    /// 按**账号**记：同一台手机换人用不是罕见场景，视障用户的设备常由家人协助设置
    /// （与 `PrivacyConsentScope` 上那段同源）。这一页在登录后才可达，`.device` 分支正常走不到，
    /// 但留着比 `guard` 掉强 —— 拿不到 userId 时宁可多问一次，也不要让界面一声不响。
    private var consentScope: PrivacyConsentScope {
        appState?.currentUser.map { .user(String($0.userId)) } ?? .device
    }

    func acceptVisionConsent() {
        consentStore?.recordConsent(to: .blindVisionProfile, scope: consentScope)
        hasVisionConsent = true
    }

    #if DEBUG
    func applyUITestProfilePrefillIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] == "1",
              appState?.blindProfile == nil else {
            return
        }

        name = environment["AIDRUN_UI_TEST_PROFILE_NICKNAME"] ?? "UITestBlind"
    }
    #endif

    func submit() {
        guard canSubmit, let appState else {
            let message = "请填写必填信息"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        Task {
            await saveProfile(appState: appState)
        }
    }

    /// 请求体构造抽成纯函数，理由是**这里有一条测不到就守不住的红线**：
    /// 没取得单独同意时 `visionLevel` / `hasGuideDog` 必须缺席。
    /// 走网络去验它要一个 20 个方法的 `ProfileServing` 替身，而这一层本来就没有副作用。
    /// 形状照抄 `BlindBookingViewModel.makeCreateOrderRequest`。
    func makeProfileUpdateRequest() -> BlindProfileUpdateRequest {
        BlindProfileUpdateRequest(
            name: name.trimmed,
            runningPace: nil,
            specialNeeds: specialNeeds.nilIfBlank,
            // 🔴 **没取得单独同意就一律传 nil，绝不传「默认值」。**
            // 传 `TOTAL_BLIND` 或 `false` 会把「用户没说」伪造成「用户说了」——
            // 后端此刻还没有 `NOT_SPECIFIED` 这个取值（已投 handoff），
            // 所以在它上线之前，「拒绝」在协议上唯一诚实的表达就是**不带这两个键**。
            // 用例 `BlindEscortPreferencesTests.testProfileUpdateOmitsVisionFieldsWithoutConsent` 钉住。
            visionLevel: hasVisionConsent ? visionLevel?.rawValue : nil,
            hasGuideDog: hasVisionConsent ? hasGuideDog : nil,
            // 引导方式不在同意门后面 —— 它不敏感，而且它是拒绝了敏感项的用户
            // 唯一还能给志愿者的准备依据。挪到门后面会让「可拒绝」变成空话。
            tetherPreference: tetherPreference?.rawValue,
            chatPreference: nil,
            defaultPace: defaultPace == .noPreference ? nil : defaultPace
        )
    }

    private func saveProfile(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let profile = try await appState.profile.updateBlindProfile(makeProfileUpdateRequest())
            appState.updateBlindProfile(profile)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "保存失败，请重试"
            speechService?.speakError("保存失败，请重试")
        }
    }
}

// MARK: - Blind Runner Profile View

struct BlindRunnerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerProfileViewModel()
    @State private var showLogoutConfirm = false
    @State private var showVisionConsent = false
    @State private var visionConsentDeclineNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    requiredSection

                    emergencyContactSection

                    optionalSection

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            submitButton
        }
        .onAppear {
            viewModel.configure(with: appState, speechService: speechService)
            #if DEBUG
            viewModel.applyUITestProfilePrefillIfNeeded()
            #endif
            speechService.speak("请填写个人资料。昵称为必填项。紧急联系人在下方单独管理，至少需要 1 位。")
        }
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                Task { await appState.logout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
        // 全屏而不是 sheet：每条告知要各自可听、可停、可回头再听。
        // 理由整段写在 `ConsentDisclosureView` 的文档注释里，别在这里复述。
        .fullScreenCover(isPresented: $showVisionConsent) {
            visionConsentScreen
        }
    }

    /// 视力状况的单独同意页（PIPL 第二十九条）。
    ///
    /// 复用 `ConsentDisclosureView(purpose:)`，文案全部取自 `PrivacyConsentPurpose`——
    /// 那是被单测钉住的合规文本，**不许在 View 里另写一份**。
    private var visionConsentScreen: some View {
        NavigationStack {
            ConsentDisclosureView(
                purpose: .blindVisionProfile,
                onAgree: {
                    viewModel.acceptVisionConsent()
                    visionConsentDeclineNotice = nil
                    showVisionConsent = false
                },
                onDecline: {
                    // 不劝返、不重试 —— 拒绝是一个完整的答案
                    // （`docs/research/face-verify-decline-alternative-path-ux-20260908.md`）。
                    // 反馈同时给屏幕和耳朵：只给一边就有一半用户拿不到。
                    visionConsentDeclineNotice = PrivacyConsentPurpose.blindVisionProfile.declinedFeedback
                    showVisionConsent = false
                    speechService.speak(PrivacyConsentPurpose.blindVisionProfile.declinedFeedback)
                }
            )
            .navigationTitle("视力状况")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            speechService.speak(text: PrivacyConsentPurpose.blindVisionProfile.spokenScript)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HighContrastText(viewModel.isEditing ? "编辑资料" : "完善信息", style: .title)
                    .accessibilityAddTraits(.isHeader)

                Text("昵称为必填项。紧急联系人在下方单独管理。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("昵称为必填项。紧急联系人在下方单独管理")
            }

            Spacer()

            if !viewModel.isEditing {
                Button {
                    showLogoutConfirm = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.destructive)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("退出登录")
                .accessibilityHint("退出后需要重新登录，需要二次确认")
            }
        }
    }

    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileTextField(
                title: "昵称",
                placeholder: "请输入昵称",
                text: $viewModel.name,
                isRequired: true,
                errorMessage: viewModel.name.trimmed.isEmpty ? "请填写必填信息" : nil,
                accessibilityLabel: "昵称，必填",
                accessibilityHint: "请输入您的昵称"
            )
        }
    }

    /// 资料页只展示主联系人摘要 + 管理入口；增删改和主联系人切换都在 `EmergencyContactsView`。
    private var emergencyContactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("紧急联系人")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(emergencyContactSummary)
                .font(AppFonts.body())
                .foregroundColor(
                    appState.hasExactlyOnePrimaryEmergencyContact
                        ? AppColors.textSecondary
                        : AppColors.destructive
                )
                .accessibilityLabel(emergencyContactSummary)

            NavigationLink {
                EmergencyContactsView()
            } label: {
                Text("管理紧急联系人")
                    .font(AppFonts.primaryButton())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(12)
            }
            .accessibilityLabel("管理紧急联系人")
            .accessibilityHint("添加、编辑、删除紧急联系人，或切换主联系人")
        }
    }

    private var emergencyContactSummary: String {
        guard appState.emergencyContactCount > 0 else {
            return "还没有紧急联系人。下单前至少需要 1 位，最多 \(EmergencyContactRules.maxCount) 位。"
        }
        guard let primary = appState.primaryEmergencyContact else {
            return "共 \(appState.emergencyContactCount) 位紧急联系人，但还没有唯一的主联系人，请进入管理页设置。"
        }
        let relationshipText = primary.relationship?.nilIfBlank.map { "，关系\($0)" } ?? ""
        return "共 \(appState.emergencyContactCount) 位紧急联系人。主联系人：\(primary.name?.nilIfBlank ?? "未命名")，\(primary.maskedPhone ?? "未填写手机号")\(relationshipText)。"
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("默认配速偏好")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Picker("默认配速偏好", selection: $viewModel.defaultPace) {
                    ForEach(PacePreference.allCases, id: \.self) { pace in
                        Text(pace.displayName).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("默认配速偏好，选填")
                .accessibilityHint("选择跑步配速偏好")
            }

            escortGuidanceSection

            visionSection

            ProfileTextField(
                title: "特殊需求",
                placeholder: "例如：需要语言引导",
                text: $viewModel.specialNeeds,
                isRequired: false,
                errorMessage: nil,
                accessibilityLabel: "特殊需求，选填",
                accessibilityHint: "如有特殊需求请填写"
            )
        }
    }

    // MARK: - 陪跑偏好（不敏感的那一半）

    /// 引导方式。**排在视力状况前面**是有意的：一线引导材料（RNIB 官方指南逐字
    /// 「there are no hard and fast rules… ask them how they like to be guided」）一致主张
    /// 直接问引导方式，而不是问视力分级再推导 —— 分级到引导方式之间没有稳定映射，
    /// 同样是低视力，有人用绳有人挽手臂。读屏顺序即优先级，最有用的那一项排前面。
    ///
    /// 它**不在单独同意门后面**：引导方式是偏好不是身份信息。
    private var escortGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("希望怎么被引导")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("志愿者到场前会看到这一项，好提前准备。不填也能约跑。")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)

            Picker("希望怎么被引导", selection: $viewModel.tetherPreference) {
                Text("还没决定").tag(TetherPreference?.none)
                ForEach(TetherPreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(TetherPreference?.some(preference))
                }
            }
            // 用系统菜单而不是 `.segmented`：四个中文选项在 AX4 / AX5 档会被挤成截断的省略号，
            // 而那两档正是低视力用户实际会设的（见记忆 `low-vision-visual-channel-unaudited`）。
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .accessibilityLabel("希望怎么被引导，选填")
            .accessibilityHint("选择牵引绳、搀扶，或者只用语言引导")
            .accessibilityIdentifier("blindProfileTetherPreferencePicker")
        }
    }

    // MARK: - 视力状况（敏感，走单独同意）

    /// 视力状况与导盲犬。
    ///
    /// 未同意时这里是**一个按钮**而不是两个摊开的控件：读屏用户一次划动就跳过
    /// （与 `RoleSelectionView.inviteCodeSection` 折叠成按钮同一条理由），
    /// 而且摊开的控件本身就意味着「已经可以填了」—— 那与「收集前取得单独同意」相反。
    @ViewBuilder
    private var visionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("视力状况")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if viewModel.hasVisionConsent {
                Picker("视力状况", selection: $viewModel.visionLevel) {
                    Text("不填").tag(VisionLevel?.none)
                    // 文案用**功能性自述**而不是残疾等级：同类产品（United In Stride 的
                    // "How would you characterize your vision?"）与 Washington Group 的
                    // WHO/联合国统计标准都是这个问法。写「一级/二级视力残疾」是医学分级口径，
                    // 用途不对，用户也未必知道自己证上是几级。
                    Text("完全看不见").tag(VisionLevel?.some(VisionLevel.totalBlind))
                    Text("还有一些视力").tag(VisionLevel?.some(VisionLevel.lowVision))
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .accessibilityLabel("视力状况，选填")
                .accessibilityHint("选择完全看不见，或者还有一些视力")
                .accessibilityIdentifier("blindProfileVisionLevelPicker")

                Toggle("平时使用导盲犬", isOn: $viewModel.hasGuideDog)
                    .font(AppFonts.body())
                    .frame(minHeight: 64)
                    .accessibilityLabel("平时使用导盲犬，选填")
                    .accessibilityHint("开启后，只会给你派接受与导盲犬同行的志愿者")
                    .accessibilityIdentifier("blindProfileHasGuideDogToggle")
            } else {
                Text("这两项属于敏感个人信息，填之前我们会先单独问你一次。")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)

                Button {
                    showVisionConsent = true
                } label: {
                    Text("填写视力状况")
                        .font(AppFonts.primaryButton())
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(12)
                }
                .accessibilityLabel("填写视力状况")
                .accessibilityHint("视力状况和导盲犬属于敏感个人信息，点开后会先告知再由你决定填不填")
                .accessibilityIdentifier("blindProfileVisionConsentDisclosure")
            }

            if let notice = visionConsentDeclineNotice {
                // 🚩 拒绝的反馈必须**上屏**，不能只 `speak`。只播报的话，明眼陪同者与
                // 低视力用户按下「不填这一项」之后屏幕上一个字都不多，看起来就是按钮坏了
                // （记忆 `claimed-fallback-may-not-exist-in-release` 的同一形状）。
                Text(notice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(notice)
                    .accessibilityIdentifier("blindProfileVisionConsentDeclineNotice")
            }
        }
    }

    private var submitButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                viewModel.isEditing ? "保存" : "完成",
                isLoading: viewModel.isLoading
            ) {
                viewModel.submit()
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.45)
            .accessibilityLabel(viewModel.isEditing ? "保存，保存资料" : "完成，保存资料")
            .accessibilityHint(viewModel.canSubmit ? "点击后保存资料" : "请先填写必填资料")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
}

// MARK: - Profile Text Field

private struct ProfileTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isRequired: Bool
    var keyboardType: UIKeyboardType = .default
    let errorMessage: String?
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                if isRequired {
                    Text("*")
                        .font(.headline)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityHidden(true)
                }
            }

            TextField(placeholder, text: $text)
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
        BlindRunnerProfileView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
