import SwiftUI

/// 删除账户的三个弹窗：预检被拦、初次确认、最终确认（#848，此前两端账户页各抄一份）。
///
/// 顺序是：页面上的「删除账户」按钮把 `isShowingInitialConfirmation` 置真 →
/// 「继续删除账户」跑预检 → 预检拦下就弹「无法删除账户」，放行就弹「最终确认删除账户」 →
/// 「永久删除账户」才真正提交。文案、按钮角色与顺序都是账号生命周期的一部分（skill `aidrun-auth`），改动要逐字核对。
/// 提交失败的弹窗在 `AccountDeletionFailureAlertModifier`。
struct AccountDeletionFlowModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @ObservedObject var viewModel: AccountDeletionViewModel
    @Binding var isShowingInitialConfirmation: Bool
    let role: UserRole

    func body(content: Content) -> some View {
        content
            .alert("无法删除账户", isPresented: $viewModel.isShowingPreflightBlock) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(viewModel.preflightMessage ?? "")
            }
            .alert("确认删除账户", isPresented: $isShowingInitialConfirmation) {
                Button("继续删除账户", role: .destructive) {
                    Task {
                        await viewModel.preflight(
                            appState: appState,
                            speechService: speechService
                        )
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除前还会再确认一次。")
            }
            .alert("最终确认删除账户", isPresented: $viewModel.showFinalConfirmation) {
                Button("永久删除账户", role: .destructive) {
                    Task { await appState.deleteCurrentAccount() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(AccountDeletionViewModel.finalConfirmationMessage(for: role))
            }
    }
}

extension View {
    /// 页面只持有 `viewModel` 和初次确认的开关；三个弹窗都挂在这里。
    func accountDeletionFlow(
        viewModel: AccountDeletionViewModel,
        isShowingInitialConfirmation: Binding<Bool>,
        role: UserRole
    ) -> some View {
        modifier(AccountDeletionFlowModifier(
            viewModel: viewModel,
            isShowingInitialConfirmation: isShowingInitialConfirmation,
            role: role
        ))
    }
}
