import SwiftUI

/// 预约向导前的位置轨迹单独同意（#368）。
///
/// 问在预约前而不是同行时：拒绝的代价只是「这次不约了」，不会让已经出发的志愿者白跑。
/// 有本机记录就直接放行，不再问。同意 → 当场换成向导（系统定位授权框由向导的 `onAppear` 弹，晚于告知）；
/// 拒绝 → 回首页，首页念并留下后果说明。没有返回按钮：出口只有这两个，读屏的「返回」手势等同拒绝。
struct BlindBookingTrackConsentGate<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    let onDecline: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var agreedThisVisit = false

    private let purpose = PrivacyConsentPurpose.blindLocationTrack

    var body: some View {
        if agreedThisVisit || appState.hasLocationTrackConsent(purpose) {
            content()
        } else {
            ConsentDisclosureView(
                purpose: purpose,
                onAgree: {
                    speechService.stop()
                    appState.recordLocationTrackConsent(purpose)
                    agreedThisVisit = true
                },
                onDecline: decline
            )
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityAction(.escape, decline)
            .task {
                speechService.speak(text: purpose.spokenScript)
            }
        }
    }

    private func decline() {
        speechService.stop()
        onDecline()
    }
}
