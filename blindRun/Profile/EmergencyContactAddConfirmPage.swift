import SwiftUI

// MARK: - 选人后确认添加（#807）

/// 从通讯录选中一位联系人之后的唯一一步：看一眼是谁、听一遍短信告知，按「添加」就存好。
///
/// 负责人 2026-11-06（#807）：「盲人不可能去填这么多的表单」。原来选完人还要进表单，
/// 面对姓名、手机号、关系、主联系人开关和右上角「保存」6 个控件。现在：
/// - 关系不在这里填，添加后到编辑页补；
/// - 主联系人不给开关：第一位自动是主联系人（后端也强制），后面的人到编辑页自己设。
///
/// 为什么不选完直接保存：新增联系人会让后端给这个号码发一条告知短信，这是对第三方的外部副作用，
/// 盲人在保存之前有权知道（`EmergencyContactFormView.addSmsNotice`）。所以保留这一次确认。
///
/// 页面由调用方 push 进 `NavigationStack`，页内没有「取消」：返回就是不添加。
/// #805 的约跑前补联系人门页也走这一页（共享笔记 `807-confirm-page-api.md`）。
struct EmergencyContactAddConfirmPage: View {
    @ObservedObject var viewModel: EmergencyContactsViewModel
    /// `added == true` 表示已经存好。失败时页面不调它，留在原地显示原因。
    let onFinish: (_ added: Bool) -> Void

    @EnvironmentObject private var speechService: SpeechService
    @State private var pick: ContactPhonePick
    @State private var showContactPicker = false
    /// 换人时选到的号码不能用：上屏 + 朗读，原来那位保持不变。
    @State private var pickProblem: String?
    @State private var hasSpokenIntro = false
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSide: CGFloat = 88
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        viewModel: EmergencyContactsViewModel,
        pick: ContactPhonePick,
        onFinish: @escaping (_ added: Bool) -> Void
    ) {
        self.viewModel = viewModel
        self.onFinish = onFinish
        _pick = State(initialValue: pick)
    }

    /// 选中的人能不能直接走这一页：号码是 11 位大陆手机号，且通讯录里有名字、不超长。
    /// 不能时调用方改进手动表单（`EmergencyContactFormView(initialPick:)`），值已经填好。
    static func canConfirm(_ pick: ContactPhonePick) -> Bool {
        let fields = EmergencyContactFormView.pickedFields(pick)
        guard fields.isValidPhone, let name = fields.name else { return false }
        return name.count <= EmergencyContactRules.maxNameLength
    }

    private var fields: EmergencyContactFormView.PickedFields {
        EmergencyContactFormView.pickedFields(pick)
    }

    private var displayName: String { fields.name ?? "这位联系人" }

    /// 后端在新增第一位时强制设为主联系人；这里同口径提前告诉用户。
    private var willBePrimary: Bool { viewModel.contacts.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                header

                if willBePrimary {
                    GroupedCard {
                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text(Self.primaryTitle(name: displayName))
                                .font(AppFonts.body().weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(Self.primaryDetail)
                                .font(AppFonts.body())
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(GroupedCardMetrics.rowHorizontalPadding)
                    }
                    .accessibilityElement(children: .combine)
                }

                GroupedCard {
                    Text(EmergencyContactFormView.addSmsNotice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(GroupedCardMetrics.rowHorizontalPadding)
                }

                if let message = pickProblem ?? viewModel.errorMessage {
                    Text(message)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .accessibilityIdentifier("emergencyContactConfirmError")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(EmergencyContactFormView.addTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏，底部按钮才贴得到屏幕底（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .background(
            ContactPhonePicker(isPresented: $showContactPicker) { newPick in
                replacePick(with: newPick)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .onAppear {
            // 从通讯录选择器回来时 onAppear 会再跑一次，开场白只念一遍。
            guard !hasSpokenIntro else { return }
            hasSpokenIntro = true
            speechService.speak(intro)
        }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.xSmall) {
            // AX 字号下头像只占地方（纯装饰，读屏不念），那一档不画。
            if !dynamicTypeSize.isAccessibilitySize {
                FlowAvatar(
                    name: fields.name,
                    diameter: avatarSide,
                    background: AppColors.primary,
                    foreground: .white,
                    placeholder: "联"
                )
                .padding(.top, AppSpacing.medium)
            }
            Text(displayName)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.phoneTail(fields.phone))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppSpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("emergencyContactConfirmHeader")
    }

    private var actions: some View {
        VStack(spacing: 0) {
            PrimaryButton(Self.addButtonTitle, isLoading: viewModel.isMutating) { add() }
                .accessibilityLabel("添加\(displayName)为紧急联系人")
                .accessibilityHint("添加后会给这个号码发一条告知短信")
                .accessibilityIdentifier("emergencyContactConfirmAdd")
            Button(Self.pickAnotherTitle) {
                pickProblem = nil
                showContactPicker = true
            }
            .buttonStyle(TextButtonStyle(alignment: .center))
            .disabled(viewModel.isMutating)
            .accessibilityHint("重新打开通讯录选一位")
            .accessibilityIdentifier("emergencyContactConfirmPickAnother")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(AppColors.Flow.page)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emergencyContactConfirmActions")
    }

    private var intro: String {
        let primary = willBePrimary ? "\(Self.primaryTitle(name: displayName))。" : ""
        return "\(EmergencyContactFormView.addTitle)。\(displayName)，\(Self.phoneTail(fields.phone))。\(primary)\(EmergencyContactFormView.addSmsNotice)"
    }

    private func replacePick(with newPick: ContactPhonePick) {
        guard Self.canConfirm(newPick) else {
            // 号码不能用时不换人，留着原来那位；原因同时上屏和朗读。
            let problem = Self.unusablePickMessage(newPick)
            pickProblem = problem
            speechService.speakError(problem)
            return
        }
        pick = newPick
        pickProblem = nil
        viewModel.errorMessage = nil
        let picked = EmergencyContactFormView.pickedFields(newPick)
        speechService.speak(EmergencyContactFormView.pickAnnouncement(name: newPick.name, phone: picked.phone))
    }

    private func add() {
        pickProblem = nil
        Task {
            // relationship 留空：关系添加后到编辑页补（#807）。第一位由 view model 与后端强制为主联系人。
            let added = await viewModel.create(
                name: fields.name ?? "",
                phone: fields.phone,
                relationship: "",
                makePrimary: viewModel.contacts.isEmpty
            )
            if added { onFinish(true) }
        }
    }
}

// MARK: - 文案

extension EmergencyContactAddConfirmPage {
    static let addButtonTitle = "添加"
    static let pickAnotherTitle = "换一位联系人"
    static let primaryDetail = "紧急情况下优先联系这一位。"

    static func primaryTitle(name: String) -> String { "\(name)会是你的主联系人" }

    /// 号码只给末四位：这一页会被朗读，外放时周围的人听得到。
    static func phoneTail(_ phone: String) -> String { "手机号尾号 \(phone.suffix(4))" }

    /// 换人时选到不能直接添加的人：没名字、名字太长，或号码不是手机号。
    static func unusablePickMessage(_ pick: ContactPhonePick) -> String {
        let fields = EmergencyContactFormView.pickedFields(pick)
        guard fields.isValidPhone else { return fields.notice }
        guard fields.name != nil else {
            return "这位联系人在通讯录里没有名字，请换一位，或者回到上一页用「手动输入」。"
        }
        return "这位联系人的名字超过 \(EmergencyContactRules.maxNameLength) 个字，请换一位，或者回到上一页用「手动输入」。"
    }
}
