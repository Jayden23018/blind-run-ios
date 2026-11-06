import SwiftUI

// MARK: - Blind Runner Profile View

/// 个人资料（#812，负责人 2026-11-06 批准，定稿 `docs/ui/mockups/blind-profile-checklist-20261106/`）：
/// 照健康「健康核对清单」，5 张卡分「未设置 / 已设置」两组。点卡片弹出一题一屏的弹层
/// （`BlindProfileQuestionFlow`），整张卡答完点「完成」才保存；紧急联系人卡进 `EmergencyContactsView`。
///
/// 只有这一种排法：#781 起新用户登录后直接进首页，约跑页缺资料时也推入本页。
struct BlindRunnerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerProfileViewModel()
    @State private var hasConfigured = false
    /// 正在打开的那张卡（弹层）。初始答案在点卡片那一刻定下：弹层开着时 view model 会变
    /// （同意视力授权、保存），重绘时现算会让「改没改过」的判断跟着漂。
    @State private var activeSession: CardSession?
    /// 刚保存的那张卡：状态行改成绿字「已保存：…」，读屏焦点放到它上面。
    @State private var savedCard: BlindProfileCard?
    @AccessibilityFocusState private var focusedCard: BlindProfileCard?

    static let lede = "完成以下设置，陪跑员即可了解你的需求。各项均为选择题，可随时修改。"
    static let unsetGroupTitle = "未设置"
    static let setGroupTitle = "已设置"
    /// 弹层收起后等这么久再把读屏焦点放到卡上（弹层下滑动画约 0.5 秒）。
    private static let savedFocusDelayNanoseconds: UInt64 = 700_000_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(Self.lede)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                let statuses = Dictionary(uniqueKeysWithValues: BlindProfileCard.allCases.map { ($0, status($0)) })
                cardGroup(Self.unsetGroupTitle, statuses: statuses, isSet: false)
                cardGroup(Self.setGroupTitle, statuses: statuses, isSet: true)
                pageNotices
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(BlindAccountCopy.profileTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guard !hasConfigured else {
                // 从改昵称页 / 紧急联系人页退回来：那一页的结果已经念过，这里不再说话，
                // 否则后到的播报会把它切断（记忆 `later-speak-silently-cuts-the-earlier-one`）。
                viewModel.clearTransientNotices()
                savedCard = nil
                return
            }
            hasConfigured = true
            viewModel.configure(with: appState, speechService: speechService)
            // 撤回没存上时，失败文案让用户再点视力卡上的「撤回同意」（同隐私与授权页，#393）。
            viewModel.withdrawalRetryButtonTitle = BlindProfileCopy.withdrawRowTitle
            speechService.speak("个人资料。共 \(BlindProfileCard.allCases.count) 项设置，点按任一项即可设置或修改。")
        }
        .sheet(item: $activeSession, onDismiss: {
            // 没存上就关掉（放弃或下滑）：弹层里那句「请再次点按完成」不能留在清单页上。
            if savedCard == nil { viewModel.clearTransientNotices() }
        }) { session in
            BlindProfileQuestionFlow(
                card: session.card,
                viewModel: viewModel,
                initialDraft: session.initialDraft,
                startsWithConsent: session.startsWithConsent,
                onFinished: { finish(session.card) }
            )
        }
    }

    // MARK: - 头部：头像、昵称、修改昵称

    private var header: some View {
        VStack(spacing: 0) {
            ProfileAccountHeader(
                name: viewModel.name.nilIfBlank ?? BlindProfileCopy.unfilled,
                roleLine: BlindProfileCopy.roleLine
            )
            NavigationLink {
                BlindProfileTextEditPage(viewModel: viewModel, text: $viewModel.name)
            } label: {
                Text("修改昵称")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("修改昵称")
            .accessibilityValue(viewModel.name.nilIfBlank ?? BlindProfileCopy.unfilled)
            .accessibilityIdentifier("blindProfileNicknameRow")
        }
    }

    // MARK: - 两组卡片

    private func status(_ card: BlindProfileCard) -> BlindProfileCardStatus {
        BlindProfileCardStatus.resolve(
            card,
            viewModel: viewModel,
            profile: appState.blindProfile,
            contactCount: appState.emergencyContactCount,
            primaryContactName: appState.primaryEmergencyContact.map { $0.name?.nilIfBlank ?? "未命名" }
        )
    }

    @ViewBuilder
    private func cardGroup(_ title: String, statuses: [BlindProfileCard: BlindProfileCardStatus], isSet: Bool) -> some View {
        let cards = BlindProfileCard.allCases.filter { statuses[$0]?.isSet == isSet }
        if !cards.isEmpty {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .padding(.top, 12)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(cards) { card in
                if let status = statuses[card] {
                    cardView(card, status: status)
                }
            }
        }
    }

}

// MARK: - 卡片、视力卡附加行、保存之后

extension BlindRunnerProfileView {
    private func cardView(_ card: BlindProfileCard, status: BlindProfileCardStatus) -> some View {
        let notice = savedCard == card ? viewModel.savedNotice : nil
        return VStack(alignment: .leading, spacing: 0) {
            if card == .emergencyContacts {
                NavigationLink {
                    EmergencyContactsView()
                } label: {
                    cardLabel(card, status: status, notice: nil, action: "管理")
                }
                .buttonStyle(.plain)
                .modifier(CardAccessibility(card: card, label: "管理紧急联系人", value: status.line, hint: "添加、编辑、删除紧急联系人，或切换主联系人"))
            } else {
                Button {
                    viewModel.clearTransientNotices()
                    savedCard = nil
                    activeSession = CardSession(
                        card: card,
                        initialDraft: .initial(for: card, viewModel: viewModel, isSet: status.isSet),
                        startsWithConsent: card == .vision && !viewModel.hasVisionConsent
                    )
                } label: {
                    cardLabel(card, status: status, notice: notice, action: status.isSet ? "修改" : "设置")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .modifier(CardAccessibility(
                    card: card,
                    label: card.title,
                    value: notice ?? status.line,
                    hint: [card.detail, status.isSet ? "点按修改" : "点按设置"].compactMap { $0 }.joined(separator: "")
                ))
            }
            if card == .vision {
                visionExtras
            }
        }
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
        .accessibilityFocused($focusedCard, equals: card)
    }

    private func cardLabel(_ card: BlindProfileCard, status: BlindProfileCardStatus, notice: String?, action: String) -> some View {
        // 视力卡拒绝后的反馈不是「已保存」，用灰字；其余卡刚存上的那句用绿勾。
        let isSuccessNotice = notice != nil && !(card == .vision && !viewModel.hasVisionConsent)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.systemImage)
                .font(.title3)
                .foregroundColor(card.tint)
                .frame(width: 44, height: 44) // guard:allow small-touch-target 装饰图标，不是触达目标
                .background(Circle().fill(card.tint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                if let notice {
                    Label(notice, systemImage: isSuccessNotice ? "checkmark.circle.fill" : "info.circle")
                        .font(.subheadline.weight(isSuccessNotice ? .semibold : .regular))
                        .foregroundColor(isSuccessNotice ? AppColors.success : AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(status.isSet ? AppColors.success : AppColors.Flow.decorMutedInk)
                            .frame(width: 8, height: 8) // guard:allow small-touch-target 状态圆点，装饰
                        Text(status.line)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let detail = card.detail, !status.isSet || card == .vision {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                    .padding(.top, 4)
                Text(action)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) // guard:allow small-touch-target 整张卡才是触达目标
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - 视力卡：撤回同意与撤回结果

    /// 同意要能撤回（PIPL 第十五条），按下立刻保存（#352）。撤回已按下还没存上时也留着，让用户重试。
    @ViewBuilder
    private var visionExtras: some View {
        if viewModel.hasVisionConsent || viewModel.isVisionConsentWithdrawalPending {
            GroupedCardDivider()
            Button {
                savedCard = nil
                if viewModel.isVisionConsentWithdrawalPending {
                    viewModel.submit()
                } else {
                    viewModel.withdrawVisionConsent()
                }
            } label: {
                Text(BlindProfileCopy.withdrawRowTitle)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel(VisionConsentWithdrawalCopy.accessibilityLabel)
            .accessibilityIdentifier("blindProfileVisionConsentWithdraw")
        }
        if let notice = viewModel.visionConsentWithdrawnNotice {
            // 必须上屏，不能只播报（记忆 `claimed-fallback-may-not-exist-in-release`）。
            Text(notice)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("blindProfileVisionConsentWithdrawnNotice")
        }
    }

    /// 页面级的错误（撤回没存上等）。卡片弹层里的错误在弹层里显示。
    @ViewBuilder
    private var pageNotices: some View {
        if activeSession == nil, let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .accessibilityLabel(errorMessage)
                .accessibilityIdentifier("blindProfilePageError")
        }
    }

    // MARK: - 保存之后

    /// 弹层存上了：关掉弹层，这张卡显示「已保存：…」，读屏焦点放过去（卡片可能已挪到「已设置」组，
    /// 不主动放的话盲人找不到刚改的东西）。等弹层收起再放，否则焦点落在正在消失的弹层上。
    private func finish(_ card: BlindProfileCard) {
        savedCard = card
        activeSession = nil
        Task {
            try? await Task.sleep(nanoseconds: Self.savedFocusDelayNanoseconds)
            focusedCard = card
        }
    }
}

/// 一次打开的弹层：哪张卡、打开时的答案、要不要先过同意页。
private struct CardSession: Identifiable {
    let card: BlindProfileCard
    let initialDraft: BlindProfileCardDraft
    let startsWithConsent: Bool
    var id: String { card.rawValue }
}

/// 一张卡读屏念成一个按钮：标题、状态、怎么操作。标识是 `blindProfileCard_<rawValue>`。
private struct CardAccessibility: ViewModifier {
    let card: BlindProfileCard
    let label: String
    let value: String
    let hint: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value.replacingOccurrences(of: " · ", with: "，"))
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            // 写成字面量（不调 `card.identifier`）：守卫 `stale-ui-test-identifier` 只认字面量里的 id。
            .accessibilityIdentifier("blindProfileCard_\(card.rawValue)")
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
