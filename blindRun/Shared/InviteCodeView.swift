import SwiftUI
import UIKit

// MARK: - 邀请码页（双方共用）

/// `GET /api/users/me/invite-code`（SPEC-E 第 4 步）。盲人与志愿者共用一屏 ——
/// 两侧的邀请码语义完全相同，发奖规则的差异写在文案里而不是分两个页面。
///
/// ⚠️ **这个端点会写库**（邀请码惰性生成，第一次调才落库），所以：
/// 只在进页面时 `.task` 拉一次，**不预取、不缓存、不在任何列表里逐用户调**。
/// 页面里也**没有下拉刷新** —— 刷新一次就是写一次库，而这个值稳定不变，刷新没有意义。
struct InviteCodeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    @State private var state: AsyncLoadState<InviteCodeResponse> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteContent(
                    state,
                    loadingLabel: "正在加载邀请码",
                    failureIdentifier: "inviteCodeRetryButton",
                    retryTitle: InviteCodeCopy.retry,
                    retry: { Task { await load() } }
                ) { response in
                    codeCard(response)
                    countsSection(response)
                    rulesSection
                    Text(InviteCodeCopy.pointsDisclaimer)
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .accessibilityIdentifier("inviteCodePointsDisclaimer")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(InviteCodeCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inviteCodeView")
        .task {
            guard state.value == nil else { return }
            await load()
        }
    }

    /// 顶部大卡：图标、「我的邀请码」、大号码、卡内一整行「复制邀请码」（定稿 #755）。
    ///
    /// **看**：等宽 + 字符间距。字距用 `tracking` 给，**不在字符串里插空格** ——
    /// 插了的话用户复制出来的码是坏的。
    ///
    /// **听**：`Text(code).speechSpellsOutCharacters()` 让 VoiceOver 逐字念
    /// （`AK37PQR9` 念成「A、K、3、7…」而不是当成一个词）。
    /// 这个修饰符 iOS 15+（本机 SDK `.swiftinterface` 实证），部署目标 16，不需要 `#available`。
    ///
    /// 🔴 **逐字播报必须走这个 API，不要自己在字符串里拼顿号** —— 拼出来的顿号
    /// VoiceOver 会当标点处理（念出来或吞掉），而且拿不到读屏自己的拼读语速。
    /// 标签用 `accessibilityLabel(_ label: Text)`（iOS 14+）拼接两段 `Text`，
    /// 让「我的邀请码」正常念、只有码那一段逐字拼 —— 属性挂在 label 自己身上，
    /// 不经过容器合并，比 `.combine` 那条路少一个不确定性。
    @ViewBuilder
    private func codeCard(_ response: InviteCodeResponse) -> some View {
        if let code = InviteCodeFormatting.display(response.inviteCode) {
            GroupedCard {
                VStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.primary)
                        .accessibilityHidden(true)
                    Text(InviteCodeCopy.codeCaption)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true) // 下面码的读屏标签已经带上这几个字
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .tracking(6)
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        // 大字号下 8 位码放不下一行，允许换行而不是缩小或截断 ——
                        // 截断一个要被念出来、抄下来的码，比换行难看得多。
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            Text("\(InviteCodeCopy.codeCaption) ") + Text(code).speechSpellsOutCharacters()
                        )
                        .accessibilityIdentifier("inviteCodeValue")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 12)

                GroupedCardDivider()

                // 整行可点，64pt 写在样式里（`TextButtonStyle`）。内边距放进标签：
                // 放在按钮外面，卡片左右各 16pt 就点不到。
                Button {
                    UIPasteboard.general.string = InviteCodeFormatting.copyable(response.inviteCode)
                    speechService.announce(InviteCodeCopy.copied)
                } label: {
                    Text(InviteCodeCopy.copyAction)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                }
                .buttonStyle(TextButtonStyle(alignment: .center))
                .accessibilityIdentifier("inviteCodeCopyButton")
            }
        } else {
            Text(InviteCodeCopy.loadFailure)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 人数两行，左名右值（健康详细信息的写法）。还没人用时组下多一行灰字。
    @ViewBuilder
    private func countsSection(_ response: InviteCodeResponse) -> some View {
        GroupedCard {
            VolunteerAccountValueRow(
                title: InviteCodeCopy.invitedCountTitle,
                value: InviteCodeCopy.peopleCount(response.resolvedInvitedCount)
            )
            GroupedCardDivider()
            VolunteerAccountValueRow(
                title: InviteCodeCopy.rewardedCountTitle,
                value: InviteCodeCopy.peopleCount(response.resolvedRewardedCount)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inviteCodeCounts")

        if response.resolvedInvitedCount == 0 {
            GroupedCardFootnote(text: InviteCodeCopy.empty)
        }
    }

    /// 「怎么算数」：照健康 · 共享的说明卡，一条一个「图标 + 粗标题 + 一句话」。
    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(InviteCodeCopy.rulesSectionTitle)
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .accessibilityAddTraits(.isHeader)

            GroupedCard {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(InviteCodeCopy.rules) { rule in
                        ruleItem(rule)
                    }
                }
                .padding(GroupedCardMetrics.rowHorizontalPadding)
            }
        }
    }

    /// 一条规则一个读屏焦点：「标题，一句话」。
    @ViewBuilder
    private func ruleItem(_ rule: InviteRule) -> some View {
        // 🔴 给邀请人的那条警告，用 warning 语义色 + 图标（颜色不是唯一指示）。
        let titleColor = rule.isWarning ? AppColors.warning : AppColors.textPrimary
        let item = AdaptiveHStack(spacing: 12) {
            Image(systemName: rule.systemImage)
                .font(.title3)
                .foregroundColor(rule.isWarning ? AppColors.warning : AppColors.primary)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .font(.headline)
                    .foregroundColor(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.detail)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rule.title)，\(rule.detail)")

        if rule.isWarning {
            item.accessibilityIdentifier("inviteCodeOneShotWarning")
        } else {
            item
        }
    }

    private func load() async {
        state = .loading(requestID: UUID())
        do {
            state = .loaded(try await appState.incentive.inviteCode())
        } catch {
            state = .failed(message: Self.failureMessage(for: error))
        }
    }

    /// 失败时给人看、给读屏念的那一句。
    static func failureMessage(for error: Error) -> String {
        guard let error = error as? APIError else { return InviteCodeCopy.loadFailure }
        // UNSET 用户拿不到邀请码（403）。入口本就放在设完角色之后，这是防御分支 ——
        // 说清楚「先选身份」，而不是把 403 的通用文案甩给用户。
        //
        // 两种形状都要接：契约没给这个 403 定错误码，所以后端可能回一个能解出
        // `SECURITY_FORBIDDEN` 的信封，也可能回一个空体（那时 `APIClient` 给的是
        // `.unknown(statusCode: 403)`）。只判其中一种会漏。
        return isForbidden(error) ? InviteCodeCopy.roleRequired : error.localizedMessage
    }

    static func isForbidden(_ error: APIError) -> Bool {
        switch error {
        case .unknown(let statusCode):
            return statusCode == 403
        case .serverError(let payload):
            return payload.errorCode == .securityForbidden
        default:
            return false
        }
    }
}
