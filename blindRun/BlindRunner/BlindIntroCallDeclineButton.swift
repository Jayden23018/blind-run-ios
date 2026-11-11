import SwiftUI

/// 盲人通话的「更换陪跑员」二次确认（#660 B-14）。按钮本身 2026-11-11 起收进订单页顶栏「···」
/// （v7 第 9 条），确认框挂在 `BlindIntroCallView` 上。
///
/// 不用红色：「更换陪跑员」是平权的退出，不是拒绝谁（`IntroCallCopy.declineButtonTitle` 的注释）；
/// 红色在本 App 里专指求助与阻断，用在这里等于替用户说了一句「不行」。确认框里的按钮同理不标 `.destructive`。
extension View {
    func blindIntroCallDeclineConfirmation(
        isPresented: Binding<Bool>,
        viewModel: BlindOrderStatusViewModel
    ) -> some View {
        alert(IntroCallCopy.blindDeclineConfirmTitle, isPresented: isPresented) {
            Button(IntroCallCopy.declineConfirmCancelButton, role: .cancel) {}
            Button(IntroCallCopy.blindDeclineConfirmButton) {
                Task { await viewModel.declineIntroCall() }
            }
        } message: {
            Text(IntroCallCopy.blindDeclineConfirmMessage)
        }
    }
}
