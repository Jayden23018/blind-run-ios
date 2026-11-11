import SwiftUI

// MARK: - 约跑前的紧急联系人门页（#805）

/// 门页该显示哪一种。`nil` = 紧急联系人齐了，直接进约跑页。
///
/// 判据与下单硬门槛同源（`AppState.hasValidEmergencyContacts`：至少 1 位且恰好 1 位主联系人；
/// 后端 403 `EMERGENCY_CONTACT_REQUIRED` 是唯一真源）。门槛本身不变，只是挪到约跑之前（负责人 2026-11-06）。
enum BlindBookingContactGateStage: Equatable {
    /// 一位都没有：主路径，弹通讯录选一位。
    case noContacts
    /// 有人但没有唯一的主联系人。后端会把第一位自动设为主联系人，正常用不会走到这里，留着兜底。
    case noPrimary(count: Int)

    static func resolve(hasValidEmergencyContacts: Bool, contactCount: Int) -> BlindBookingContactGateStage? {
        if hasValidEmergencyContacts { return nil }
        return contactCount == 0 ? .noContacts : .noPrimary(count: contactCount)
    }

    var title: String {
        switch self {
        case .noContacts: return "先选一位紧急联系人"
        case .noPrimary: return "先设一位主联系人"
        }
    }

    /// 为什么要它。只说「会发」，不说「已发出 / 已送达」（AGENTS.md §6）。
    var explanation: String {
        switch self {
        case .noContacts:
            return "约跑前要有一位紧急联系人。跑步中你求助时，系统会给这位联系人发短信。只要选一次，以后约跑不再问。"
        case .noPrimary(let count):
            return "你已添加 \(count) 位紧急联系人，还要选其中 1 位作为主联系人。"
        }
    }

    var status: String {
        switch self {
        case .noContacts: return "当前：还没有紧急联系人。"
        case .noPrimary(let count): return "当前：\(count) 位联系人，没有主联系人。"
        }
    }

    var footnote: String {
        switch self {
        case .noContacts: return "助盲跑只拿到你选的这一位的姓名和手机号。"
        case .noPrimary: return "打开紧急联系人页，设好后回到这里接着约跑。"
        }
    }

    /// 进页朗读：标题 + 为什么 + 下一步做什么。
    var spokenIntro: String {
        switch self {
        case .noContacts:
            return "\(title)。\(explanation)点「从通讯录选一位」，或者手动输入。"
        case .noPrimary:
            return "\(title)。\(explanation)点「去设主联系人」。"
        }
    }
}

/// 约跑路由的最内一层闸：紧急联系人不齐时先显示门页，补齐后当场换成约跑页（不回首页）。
///
/// 进来时已经齐了就直接显示约跑页，门页一帧都不出现。门页一旦出现，就只由门页自己说「好了」
/// （`onSatisfied`）才换：添加联系人时 `AppState` 会在确认页还没退出时就变成「齐了」，
/// 那时换掉门页会把推在它上面的确认页一起拆掉。
struct BlindBookingEmergencyContactGate<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    @ViewBuilder let content: () -> Content

    @State private var gateEngaged = false
    @State private var satisfiedThisVisit = false

    var body: some View {
        if satisfiedThisVisit || (!gateEngaged && appState.hasValidEmergencyContacts) {
            content()
        } else {
            BlindBookingEmergencyContactGatePage(onSatisfied: { satisfiedThisVisit = true })
                .onAppear { gateEngaged = true }
        }
    }
}

/// 门页本体。版式见 `docs/ui/mockups/blind-booking-profile-20261106/`（改后 ① / ④）。
///
/// 返回 = 这次不约了，回首页（系统返回按钮，不另加「取消」）。
struct BlindBookingEmergencyContactGatePage: View {
    let onSatisfied: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = EmergencyContactsViewModel()
    @State private var showContactPicker = false
    @State private var destination: Destination?
    @State private var hasSpokenIntro = false
    @AccessibilityFocusState private var explanationFocused: Bool

    /// 门页上推出去的那一页。iOS 16 没有 `navigationDestination(item:)`，用 isPresented 包一层。
    enum Destination {
        /// 通讯录选中、能直接添加的人 → 与 #807 共用的确认页。
        case confirm(ContactPhonePick)
        /// 手动表单。`pick` 非 nil = 通讯录选中但不能直接添加（号码不是手机号、没有名字），值已填好。
        case form(ContactPhonePick?)
        /// 有人但没有主联系人：去紧急联系人页设。
        case contactsList
    }

    /// 页面跟着 `AppState` 走：从通讯录添加失败、或加载后发现情况变了，文案当场跟上。
    private var stage: BlindBookingContactGateStage {
        BlindBookingContactGateStage.resolve(
            hasValidEmergencyContacts: appState.hasValidEmergencyContacts,
            contactCount: appState.emergencyContactCount
        ) ?? .noContacts
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(AppColors.destructive, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(stage.title)
                        .font(AppFonts.title().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stage.explanation)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 标题和说明合成一个读屏焦点，进页焦点先落在这里。
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($explanationFocused)
                .accessibilityIdentifier("bookingContactGateExplanation")

                GroupedCard {
                    Text(stage.status)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: GroupedCardMetrics.rowMinHeight, alignment: .leading)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                    GroupedCardDivider()
                    Button {
                        speechService.speak(stage.spokenIntro)
                    } label: {
                        EmergencyContactActionRowLabel(
                            title: "重复当前状态",
                            systemImage: "speaker.wave.2.fill",
                            tint: AppColors.primary,
                            isEnabled: true
                        )
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重复当前状态")
                    .accessibilityHint("再次朗读为什么要设紧急联系人，以及下一步做什么")
                    .accessibilityIdentifier("bookingContactGateRepeatStatus")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .background(
            ContactPhonePicker(isPresented: $showContactPicker) { pick in
                // 与紧急联系人页同一判据（#807）：能直接添加的进确认页，否则进手动表单，值已填好。
                destination = EmergencyContactAddConfirmPage.canConfirm(pick) ? .confirm(pick) : .form(pick)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .navigationDestination(isPresented: destinationBinding) { destinationView }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookingContactGatePage")
        .onAppear {
            // 从确认页 / 表单 / 紧急联系人页返回时也走这里：补齐了就换成约跑页。
            if settleIfReady() { return }
            explanationFocused = true
            guard !hasSpokenIntro else { return }
            hasSpokenIntro = true
            speechService.speak(stage.spokenIntro)
        }
        .task {
            // 缓存可能是空的（登录时拉联系人失败）：拉一次服务端列表，其实已经齐了就直接放行。
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.load()
            settleIfReady()
        }
    }

    // MARK: 按钮

    private var actions: some View {
        VStack(spacing: 0) {
            switch stage {
            case .noContacts:
                PrimaryButton("从通讯录选一位") {
                    speechService.stop()
                    showContactPicker = true
                }
                .disabled(viewModel.isMutating)
                .accessibilityHint("打开系统通讯录选一位联系人。助盲跑只拿到你选的这一位")
                .accessibilityIdentifier("bookingContactGatePickButton")
                Button("手动输入") {
                    speechService.stop()
                    destination = .form(nil)
                }
                .buttonStyle(OutlineSecondaryButtonStyle())
                .disabled(viewModel.isMutating)
                .accessibilityHint("填写姓名和手机号后添加")
                .accessibilityIdentifier("bookingContactGateManualButton")
            case .noPrimary:
                PrimaryButton("去设主联系人") {
                    speechService.stop()
                    destination = .contactsList
                }
                .accessibilityHint("打开紧急联系人页，设好后回到这里接着约跑")
                .accessibilityIdentifier("bookingContactGateSetPrimaryButton")
            }
            Text(stage.footnote)
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(AppColors.Flow.page.ignoresSafeArea())
        .readableContentColumn()
    }

    // MARK: 推出去的页

    private var destinationBinding: Binding<Bool> {
        Binding(
            get: { destination != nil },
            set: { isPresented in
                guard !isPresented else { return }
                destination = nil
                // 按返回退出时，那一页显示过的失败一并清掉。
                viewModel.isShowingFailure = false
            }
        )
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .confirm(let pick):
            EmergencyContactAddConfirmPage(viewModel: viewModel, pick: pick) { added in
                // 只退回门页：门页 `onAppear` 看到已补齐就换成约跑页。不在这里直接换，见 `BlindBookingEmergencyContactGate`。
                if added { destination = nil }
            }
        case .form(let pick):
            EmergencyContactFormView(viewModel: viewModel, contact: nil, initialPick: pick) {
                destination = nil
            }
        case .contactsList:
            EmergencyContactsView()
        case nil:
            EmptyView()
        }
    }

    /// 补齐了且门页在最上面：换成约跑页。返回是否已换。
    /// 通讯录开着时不换：选择器挂在门页上，换页会把它一起拆掉。
    @discardableResult
    private func settleIfReady() -> Bool {
        guard destination == nil, !showContactPicker, appState.hasValidEmergencyContacts else { return false }
        onSatisfied()
        return true
    }
}

#if DEBUG
#Preview("门页 · 没有联系人") {
    NavigationStack {
        BlindBookingEmergencyContactGatePage(onSatisfied: {})
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
