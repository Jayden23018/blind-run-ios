import SwiftUI

/// 预约向导前的位置轨迹单独同意（#368）。
///
/// 问在预约前而不是同行时：拒绝的代价只是「这次不约了」，不会让已经出发的志愿者白跑。
/// 有本机记录就直接放行，不再问。页面是系统定位框前的说明页（`LocationTrackPreAlertView`，#776）：
/// 「继续」弹系统框，选允许 → 记同意、当场换成向导；选不允许（或系统定位已决定时点「不同意」）→ 回首页，
/// 首页念并留下后果说明。没有返回按钮：读屏的「返回」手势等同拒绝。
struct BlindBookingTrackConsentGate<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    let onDecline: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var agreedThisVisit = false

    private let purpose = PrivacyConsentPurpose.blindLocationTrack

    var body: some View {
        if agreedThisVisit || appState.hasLocationTrackConsent(purpose) {
            content()
        } else {
            LocationTrackPreAlertView(
                purpose: purpose,
                locationService: locationService,
                speechService: speechService,
                onAgree: {
                    appState.recordLocationTrackConsent(purpose)
                    agreedThisVisit = true
                },
                onDecline: onDecline
            )
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
