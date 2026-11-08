import Combine
import SwiftUI

// MARK: - 已拉黑的人

@MainActor
final class BlockedUsersViewModel: ObservableObject {
    /// 失败必须是 `.failed`，不能落成空列表（那等于说没拉黑过任何人）。
    @Published private(set) var phase: AsyncLoadState<[BlockedUserResponse]> = .idle
    @Published private(set) var notice: String?
    @Published private(set) var actionError: String?
    @Published private(set) var busyUserId: Int64?

    func load(appState: AppState) async {
        do {
            phase = .loaded(try await appState.safety.blockedUsers())
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) { phase = .failed(message: UserSafetyCopy.blockedListFailed) }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(message: UserSafetyCopy.blockedListFailed)
        }
    }

    func retry(appState: AppState) async {
        phase = .loading(requestID: UUID())
        await load(appState: appState)
    }

    /// 幂等。成功后重拉列表，不在本地改一份。返回要朗读的结果句。
    func unblock(_ user: BlockedUserResponse, appState: AppState) async -> String? {
        guard busyUserId == nil else { return nil }
        busyUserId = user.userId
        notice = nil
        actionError = nil
        defer { busyUserId = nil }
        do {
            try await appState.safety.unblockUser(userId: user.userId)
            notice = UserSafetyCopy.unblockSucceeded
            await load(appState: appState)
            return UserSafetyCopy.unblockSucceeded
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return nil }
            let message = UserSafetyCopy.failureMessage(for: error, fallback: UserSafetyCopy.unblockFailed)
            actionError = message
            return message
        } catch {
            actionError = UserSafetyCopy.unblockFailed
            return UserSafetyCopy.unblockFailed
        }
    }
}

/// 「我的」页进来的列表，两端共用。只列我拉黑的人，这一页不说任何关于对方的状态。
struct BlockedUsersView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlockedUsersViewModel()
    @State private var pendingUnblock: BlockedUserResponse?
    /// 与 `BlindPartnerAvatar` 行头像同一个缩放基准，分隔线起点跟着字号走。
    @ScaledMetric(relativeTo: .body) private var avatarSide: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let notice = viewModel.notice {
                    resultLine(notice, color: AppColors.success, identifier: "blockedUsersNotice")
                }
                if let actionError = viewModel.actionError {
                    resultLine(actionError, color: AppColors.destructive, identifier: "blockedUsersActionError")
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(UserSafetyCopy.blockedListTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar) // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blockedUsersView")
        .task { await viewModel.load(appState: appState) }
        .alert(
            UserSafetyCopy.unblockConfirmTitle,
            isPresented: Binding(
                get: { pendingUnblock != nil },
                set: { if !$0 { pendingUnblock = nil } }
            ),
            presenting: pendingUnblock
        ) { user in
            Button(UserSafetyCopy.unblockConfirmAction, role: .destructive) {
                pendingUnblock = nil
                Task {
                    guard let message = await viewModel.unblock(user, appState: appState) else { return }
                    if viewModel.actionError == nil {
                        speechService.speak(message)
                    } else {
                        speechService.speakError(message)
                    }
                }
            }
            Button(UserSafetyCopy.cancel, role: .cancel) { pendingUnblock = nil }
        } message: { _ in
            Text(UserSafetyCopy.unblockConfirmMessage)
        }
    }

    /// 失败走 `RemoteContent`：会念出来，不只是一行红字（#864）。
    private var content: some View {
        RemoteContent(
            viewModel.phase,
            loadingLabel: UserSafetyCopy.blockedListLoading,
            failureIdentifier: "blockedUsersRetry",
            retryTitle: UserSafetyCopy.retry,
            retry: { Task { await viewModel.retry(appState: appState) } }
        ) { users in
            if users.isEmpty {
                emptyCard
            } else {
                // 一人一行，同一张分组卡（定稿 #755，照屏蔽的联系人）。
                GroupedCard {
                    ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                        if index > 0 {
                            GroupedCardDivider(leadingInset: rowDividerInset)
                        }
                        row(user)
                    }
                }
                GroupedCardFootnote(text: UserSafetyCopy.blockedListFootnote)
            }
        }
    }

    /// 空态卡：图标、标题、说明，读屏合成一个焦点。
    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "xmark")
                .font(.title2.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(14)
                .background(Circle().fill(AppColors.Flow.surfaceSubtle))
                .accessibilityHidden(true)
            Text(UserSafetyCopy.blockedListEmptyTitle)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(UserSafetyCopy.blockedListEmptyDetail)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blockedUsersEmpty")
    }

    /// 分隔线从名字起点开始：行内距 + 头像（随字号放大）+ 间距。
    private var rowDividerInset: CGFloat {
        GroupedCardMetrics.rowHorizontalPadding + avatarSide + 12
    }

    /// 灰色首字头像、名字、拉黑时间，右侧一个看得见的「解除」。
    ///
    /// 苹果「屏蔽的联系人」要先点「编辑」才能解除，读屏用户难找，所以每行留一个常驻的按钮（定稿 #755）。
    private func row(_ user: BlockedUserResponse) -> some View {
        let time = user.blockedAt?.nilIfBlank?.displayDateTime
        return AdaptiveHStack(spacing: 12) {
            // 头像、姓名和时间合成一个焦点，分开念等于为同一个人划两次。
            HStack(spacing: 12) {
                BlindPartnerAvatar(name: user.displayName, tint: AppColors.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let time {
                        Text(UserSafetyCopy.blockedAt(time))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([user.spokenName, time.map(UserSafetyCopy.blockedAt)].compactMap { $0 }.joined(separator: "，"))

            // 可点区 64×64 起：最小宽高写在标签里，`TextButtonStyle` 的 `contentShape` 撑满它。
            Button {
                pendingUnblock = user
            } label: {
                Text(UserSafetyCopy.unblockTitle)
                    .padding(.horizontal, 8)
                    .frame(minWidth: AppTouchTarget.blindPrimary)
            }
            .buttonStyle(TextButtonStyle(alignment: .center))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.busyUserId != nil)
            .accessibilityLabel(UserSafetyCopy.unblockLabel(user.spokenName))
            .accessibilityHint(UserSafetyCopy.unblockHint)
            .accessibilityIdentifier("blockedUserUnblockButton")
        }
        .padding(.leading, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
    }

    private func resultLine(_ text: String, color: Color, identifier: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}
