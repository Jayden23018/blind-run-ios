import CoreLocation
import SwiftUI

/// 位置轨迹的单独同意（#368）用的整页说明页，三处共用：预约前（`BlindBookingTrackConsentGate`）、
/// 志愿者接单开关（`VolunteerTabView.trackConsentScreen`）、同行态（`ContentView.EscortTrackConsentOverlay`）。
///
/// 2026-11-05 由 #771 的「左不同意、右同意」小弹窗改成这样（#776，负责人定「照 HIG 改成说明页」）。
/// 这份同意正好排在系统定位授权框前面，而苹果 HIG「Pre-alert screens」要求这种页面
/// 只放一个按钮、用「继续」不用「允许」、不放取消或关闭（除非为了取得法律同意）。
///
/// - 系统定位还没决定：只有「继续」。点了弹系统框；系统框选允许 = 同意，选不允许 = 拒绝。
/// - 系统定位已决定（不会再弹系统框）：「继续」直接记同意，另给一个「不同意」—— 否则拒绝就没有出口了。
///
/// 读屏的「返回」手势（双指 Z）等同拒绝：没有别的出口，不能让它什么都不做。
/// 同意之后的事（记录、放行、开定位）和拒绝后的反馈都交给调用方，与改动前一样。
struct LocationTrackPreAlertView: View {
    let purpose: PrivacyConsentPurpose
    /// 显式传入而不是读环境：志愿者那处放在 `fullScreenCover` 里。
    @ObservedObject var locationService: LocationService
    let speechService: SpeechService
    let onAgree: () -> Void
    let onDecline: () -> Void

    @State private var awaitsSystemAnswer = false
    @State private var showsDetails = false

    private var identifierPrefix: String { "\(purpose.rawValue)Consent" }

    /// 点「继续」会不会弹系统框。
    private var systemAlertWillAsk: Bool { locationService.isNotDetermined }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 16)
            }
            actions
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(AppColors.background.ignoresSafeArea())
        // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，UI 测试找不到按钮。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)View")
        .accessibilityAction(.escape, decline)
        .task(id: purpose) {
            speechService.speak(text: purpose.preAlertSpokenScript)
        }
        .onChange(of: locationService.authorizationStatus) { status in
            guard awaitsSystemAnswer, let agreed = Self.consentAnswer(to: status) else { return }
            awaitsSystemAnswer = false
            if agreed { onAgree() } else { onDecline() }
        }
    }

    /// 系统定位框的回答 → 同意（true）/ 拒绝（false）；还没回答为 nil。
    static func consentAnswer(to status: CLAuthorizationStatus) -> Bool? {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .denied, .restricted: return false
        case .notDetermined: return nil
        @unknown default: return nil
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(purpose.preAlertTitle)
                .font(AppFonts.title().weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            ForEach(purpose.preAlertUses, id: \.self) { use in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: use.symbol)
                        .font(.title2)
                        .foregroundColor(AppColors.primary)
                        .frame(width: 36)
                        .accessibilityHidden(true)
                    Text(use.text)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(purpose.preAlertFootnote)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                detailsToggle
                if showsDetails {
                    disclosureList
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsToggle: some View {
        Button {
            showsDetails.toggle()
        } label: {
            Text(showsDetails ? "收起详细说明" : "查看详细说明")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityHint(showsDetails ? "收起逐条说明" : "逐条展开我们会怎么使用你的位置")
        .accessibilityIdentifier("\(identifierPrefix)DetailsToggle")
    }

    /// 每条告知各自成为一个读屏焦点。**不要**在这个 VStack 上加 `.accessibilityElement(children: .combine)`。
    private var disclosureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(purpose.disclosures, id: \.self) { text in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("·")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.callout)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    /// 「继续」在上，「不同意」（只在系统框不会再弹时出现）在下，都整行铺满。
    private var actions: some View {
        VStack(spacing: 0) {
            Button(PrivacyConsentPurpose.preAlertContinueTitle, action: continueTapped)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint(systemAlertWillAsk ? "打开系统的定位授权框，在那里选择是否允许" : "同意按上面说的使用你的位置")
                .accessibilityIdentifier("\(identifierPrefix)ContinueButton")
            if !systemAlertWillAsk {
                Button(PrivacyConsentPurpose.preAlertDeclineTitle, action: decline)
                    .buttonStyle(NeutralButtonStyle())
                    .accessibilityIdentifier("\(identifierPrefix)DeclineButton")
            }
        }
    }

    private func continueTapped() {
        speechService.stop()
        guard systemAlertWillAsk else {
            onAgree()
            return
        }
        awaitsSystemAnswer = true
        locationService.requestPermission(fromTrackConsentScreen: true)
    }

    private func decline() {
        speechService.stop()
        awaitsSystemAnswer = false
        onDecline()
    }
}
