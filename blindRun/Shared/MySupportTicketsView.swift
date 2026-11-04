import Combine
import SwiftUI

// MARK: - 我的工单

@MainActor
final class MySupportTicketsViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded([SupportTicketSummary])
        /// 读取失败**不等于**没有工单：这里必须单列一档，否则失败会显示成「你还没有提交过工单」，
        /// 一个刚提交过投诉的人会以为提交丢了。
        case failed
    }

    @Published private(set) var phase: Phase = .loading

    func load(appState: AppState) async {
        do {
            phase = .loaded(try await appState.safety.myTickets())
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) { markFailedUnlessAlreadyShowing() }
        } catch is CancellationError {
            return
        } catch {
            markFailedUnlessAlreadyShowing()
        }
    }

    /// 下拉刷新失败时保留已经显示的列表：用户正在看的客服回复不该因为一次刷新失败消失。
    private func markFailedUnlessAlreadyShowing() {
        if case .loaded = phase { return }
        phase = .failed
    }

    func retry(appState: AppState) async {
        phase = .loading
        await load(appState: appState)
    }
}

/// 「我的」页进来的工单列表，两端共用。只读：看自己提交过什么、客服回了什么。
///
/// 🚨 **不是进度承诺。** 没回复的行写「暂时没有回复」，不写「请等待」「会回复你」：
/// 后端 blind-run-backend#899 还没定谁来看工单（负责人 2026-11-04 定：不承诺回复时限）。
struct MySupportTicketsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = MySupportTicketsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(SupportTicketCopy.myTicketsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mySupportTicketsView")
        .task { await viewModel.load(appState: appState) }
        .refreshable { await viewModel.load(appState: appState) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(SupportTicketCopy.myTicketsLoading)
        case .failed:
            Text(SupportTicketCopy.myTicketsFailed)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mySupportTicketsFailed")
            FlowActionButton(SupportTicketCopy.retry, style: .ghost) {
                Task { await viewModel.retry(appState: appState) }
            }
            .accessibilityIdentifier("mySupportTicketsRetry")
        case .loaded(let tickets) where tickets.isEmpty:
            Text(SupportTicketCopy.myTicketsEmpty)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mySupportTicketsEmpty")
        case .loaded(let tickets):
            ForEach(tickets) { row($0) }
        }
    }

    private func row(_ ticket: SupportTicketSummary) -> some View {
        let time = ticket.createdAt?.nilIfBlank?.displayDateTime
        return VStack(alignment: .leading, spacing: 8) {
            // 状态是标签不是装饰：已回复用主色，其余用次要色，但**不靠颜色传达** —— 文字本身就写着。
            Text(SupportTicketCopy.displayStatus(ticket))
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(ticket.hasReply ? AppColors.primary : AppColors.textPrimary)
            if let time {
                Text(time)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            if !ticket.content.isEmpty {
                Text(ticket.content)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = ticket.csReply {
                VStack(alignment: .leading, spacing: 4) {
                    Text(SupportTicketCopy.replyLabel)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                    Text(reply)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(SupportTicketCopy.noReplyYet)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppColors.secondaryBackground))
        // 一行一个焦点：状态、时间、正文、回复分开念，读屏用户一张工单要划五次。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SupportTicketCopy.rowAccessibilityLabel(ticket, time: time))
        .accessibilityIdentifier("mySupportTicketRow")
    }
}
