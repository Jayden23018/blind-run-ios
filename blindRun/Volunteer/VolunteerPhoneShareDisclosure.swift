import SwiftUI

/// 第一次按接单（「接下这次陪跑」或「有意向」）时，说明一次手机号的去向（#660 V-17）。
///
/// 依据：响应之后陪跑员的完整号码会给跑者 —— 先通电话的单，跑者在通话页直接拨（`IntroCallView.dialableCounterpartPhone`）；
/// 直接接单的，跑者订单页有「打电话给陪跑员」。一单可能只聊不成，对方仍拿着号码。
/// 隐私政策草案写了，App 里此前一处都没说。
///
/// 说过一次就按账号记住（`VolunteerOnceNotice.phoneShare`）。按「先不接」不记，下次接单再说。
enum VolunteerPhoneShareCopy {
    static let title = "接单前请知悉"
    static let message = "继续后，你的完整手机号会提供给跑者，方便对方给你打电话。即使这一单最后没有约成，对方也已经拿到你的号码。这条说明只出现一次。"
    static let proceedButton = "知道了，继续"
    static let cancelButton = "先不接"
}

struct VolunteerPhoneShareRequest: Equatable {
    let orderId: Int64
    let action: OrderRespondAction
}

private struct VolunteerPhoneShareDisclosureModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Binding var pending: VolunteerPhoneShareRequest?
    let onProceed: (VolunteerPhoneShareRequest) -> Void

    func body(content: Content) -> some View {
        content.alert(
            VolunteerPhoneShareCopy.title,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { request in
            Button(VolunteerPhoneShareCopy.cancelButton, role: .cancel) {}
            Button(VolunteerPhoneShareCopy.proceedButton) {
                VolunteerOnceNotice(.phoneShare, appState: appState).markDone()
                onProceed(request)
            }
        } message: { _ in
            Text(VolunteerPhoneShareCopy.message)
        }
    }
}

extension View {
    /// `pending` 非空时弹说明；调用方先用 `VolunteerOnceNotice(.phoneShare, …).isDone` 判要不要经过这里。
    func volunteerPhoneShareDisclosure(
        pending: Binding<VolunteerPhoneShareRequest?>,
        onProceed: @escaping (VolunteerPhoneShareRequest) -> Void
    ) -> some View {
        modifier(VolunteerPhoneShareDisclosureModifier(pending: pending, onProceed: onProceed))
    }
}
