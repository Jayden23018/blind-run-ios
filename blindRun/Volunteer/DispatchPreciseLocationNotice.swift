import SwiftUI

/// 陪跑员开着接单开关、而「精确位置」关着时（#520）：派单位置已经停报（`VolunteerLocationReporter` 与根视图的定时上报都拦住了），
/// 这里把原因说出来 —— 否则他只会发现「开着开关却一直收不到单」，对看不清屏幕的人就是「点了没反应」。
/// 条件成立时顶部常驻一条、念一次，并按「同一次开着开关」申请一次临时精确位置。
enum DispatchPreciseLocationCopy {
    static let notice = "「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，所以暂停为派单上报你的位置，附近的陪跑邀请会收不到。"
        + "如果弹出提示请选允许，或到系统设置里为助盲跑打开「精确位置」。"
}

private struct DispatchPreciseLocationNotice: ViewModifier {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    let isDispatching: Bool

    private var isShowing: Bool { isDispatching && locationService.isPreciseLocationOff }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if isShowing {
                    Text(DispatchPreciseLocationCopy.notice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.regularMaterial)
                        .accessibilityIdentifier("volunteerDispatchPreciseLocationNotice")
                }
            }
            .onChange(of: isShowing) { showing in
                guard showing else { return }
                speechService.speak(DispatchPreciseLocationCopy.notice)
                locationService.requestTemporaryPreciseLocation(for: .volunteerDispatch)
            }
    }
}

extension View {
    /// 陪跑员端根容器挂一次。`isDispatching` = 此刻开着接单开关。
    func dispatchPreciseLocationNotice(isDispatching: Bool) -> some View {
        modifier(DispatchPreciseLocationNotice(isDispatching: isDispatching))
    }
}
