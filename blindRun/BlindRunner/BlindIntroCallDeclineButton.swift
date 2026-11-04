import SwiftUI

/// 盲人通话页的「更换陪跑员」，按下先确认（#660 B-14）。
///
/// 单放一个视图而不是在 `BlindIntroCallView` 里加 `@State`：那个类型已超长，SwiftLint 棘轮只许它变短。
/// 确认框挂在按钮自己身上，B1 / B2 底栏与 B3 滚动区两个落点各带一份，互不干扰。
///
/// 不用红色：「更换陪跑员」是平权的退出，不是拒绝谁（`IntroCallCopy.declineButtonTitle` 的注释）；
/// 红色在本 App 里专指求助与阻断，用在这里等于替用户说了一句「不行」。确认框里的按钮同理不标 `.destructive`。
struct BlindIntroCallDeclineButton: View {
    @ObservedObject var viewModel: BlindOrderStatusViewModel
    @State private var confirms = false

    var body: some View {
        FlowActionButton(
            IntroCallCopy.declineButtonTitle,
            style: .ghost,
            isEnabled: !viewModel.isPerformingAction,
            accessibilityHint: IntroCallCopy.declineAccessibilityHint
        ) {
            confirms = true
        }
        .accessibilityIdentifier("blindIntroCallDeclineButton")
        .alert(IntroCallCopy.blindDeclineConfirmTitle, isPresented: $confirms) {
            Button(IntroCallCopy.declineConfirmCancelButton, role: .cancel) {}
            Button(IntroCallCopy.blindDeclineConfirmButton) {
                Task { await viewModel.declineIntroCall() }
            }
        } message: {
            Text(IntroCallCopy.blindDeclineConfirmMessage)
        }
    }
}
