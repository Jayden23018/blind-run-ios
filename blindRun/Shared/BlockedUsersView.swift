import Combine
import SwiftUI

// MARK: - 已拉黑的人

@MainActor
final class BlockedUsersViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded([BlockedUserResponse])
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var notice: String?
    @Published private(set) var actionError: String?
    @Published private(set) var busyUserId: Int64?

    func load(appState: AppState) async {
        do {
            phase = .loaded(try await appState.safety.blockedUsers())
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) { phase = .failed }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed
        }
    }

    func retry(appState: AppState) async {
        phase = .loading
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(UserSafetyCopy.blockedListTitle)
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(UserSafetyCopy.blockedListLoading)
        case .failed:
            Text(UserSafetyCopy.blockedListFailed)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blockedUsersFailed")
            FlowActionButton(UserSafetyCopy.retry, style: .ghost) {
                Task { await viewModel.retry(appState: appState) }
            }
            .accessibilityIdentifier("blockedUsersRetry")
        case .loaded(let users) where users.isEmpty:
            Text(UserSafetyCopy.blockedListEmpty)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blockedUsersEmpty")
        case .loaded(let users):
            ForEach(users) { row($0) }
        }
    }

    private func row(_ user: BlockedUserResponse) -> some View {
        let time = user.blockedAt?.nilIfBlank?.displayDateTime
        return VStack(alignment: .leading, spacing: 10) {
            // 姓名和时间合成一个焦点，分开念等于为同一个人划两次。
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                if let time {
                    Text(UserSafetyCopy.blockedAt(time))
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([user.spokenName, time.map(UserSafetyCopy.blockedAt)].compactMap { $0 }.joined(separator: "，"))

            FlowActionButton(
                UserSafetyCopy.unblockTitle,
                style: .ghost,
                isEnabled: viewModel.busyUserId == nil,
                accessibilityLabel: UserSafetyCopy.unblockLabel(user.spokenName),
                accessibilityHint: UserSafetyCopy.unblockHint
            ) {
                pendingUnblock = user
            }
            .accessibilityIdentifier("blockedUserUnblockButton")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppColors.secondaryBackground))
    }

    private func resultLine(_ text: String, color: Color, identifier: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}
