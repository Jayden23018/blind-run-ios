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

    @State private var response: InviteCodeResponse?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let response {
                    codeCard(response)
                    countsText(response)
                    rulesCard
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载邀请码")
                } else {
                    IncentiveFailureSection(
                        message: errorMessage ?? InviteCodeCopy.loadFailure,
                        retryTitle: InviteCodeCopy.retry,
                        identifier: "inviteCodeRetryButton"
                    ) {
                        Task { await load() }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(InviteCodeCopy.navigationTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inviteCodeView")
        .task {
            guard response == nil else { return }
            await load()
        }
    }

    /// 邀请码本体。
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
            VStack(alignment: .leading, spacing: 12) {
                Text(InviteCodeCopy.codeCaption)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)

                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .tracking(6)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 大字号下 8 位码放不下一行，允许换行而不是缩小或截断 ——
                    // 截断一个要被念出来、抄下来的码，比换行难看得多。
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text("\(InviteCodeCopy.codeCaption) ") + Text(code).speechSpellsOutCharacters()
                    )
                    .accessibilityIdentifier("inviteCodeValue")

                Button(InviteCodeCopy.copyAction) {
                    UIPasteboard.general.string = InviteCodeFormatting.copyable(response.inviteCode)
                    speechService.announce(InviteCodeCopy.copied)
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .accessibilityIdentifier("inviteCodeCopyButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text(InviteCodeCopy.loadFailure)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countsText(_ response: InviteCodeResponse) -> some View {
        Text(InviteCodeCopy.countsText(response))
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("inviteCodeCounts")
    }

    private var rulesCard: some View {
        IncentiveCard(title: InviteCodeCopy.rulesSectionTitle) {
            Text(InviteCodeCopy.rewardRule)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // 🔴 给邀请人的那条警告，用 warning 语义色 + 图标（颜色不是唯一指示）。
            AdaptiveHStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.body)
                    .foregroundColor(AppColors.warning)
                    .accessibilityHidden(true)
                Text(InviteCodeCopy.oneShotWarning)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(InviteCodeCopy.oneShotWarning)
            .accessibilityIdentifier("inviteCodeOneShotWarning")

            Text(InviteCodeCopy.pointsDisclaimer)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await appState.apiClient.get("/api/users/me/invite-code")
            errorMessage = nil
        } catch let error as APIError {
            // UNSET 用户拿不到邀请码（403）。入口本就放在设完角色之后，这是防御分支 ——
            // 说清楚「先选身份」，而不是把 403 的通用文案甩给用户。
            //
            // 两种形状都要接：契约没给这个 403 定错误码，所以后端可能回一个能解出
            // `SECURITY_FORBIDDEN` 的信封，也可能回一个空体（那时 `APIClient` 给的是
            // `.unknown(statusCode: 403)`）。只判其中一种会漏。
            errorMessage = Self.isForbidden(error) ? InviteCodeCopy.roleRequired : error.localizedMessage
        } catch {
            errorMessage = InviteCodeCopy.loadFailure
        }
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
