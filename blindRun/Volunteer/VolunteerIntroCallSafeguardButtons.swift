import SwiftUI

// 陪跑员通话页的「不合适」「未接到来电」，按下先确认（#660 V-9）。
// 单放一个文件：`VolunteerIntroCallView.swift` 已超长，SwiftLint 棘轮只许它变短。
// 两个按钮仍是**两个端点**，不能合并（`VolunteerIntroCallViewModel.reportUnreachable` 的注释：统计口径相反）。

/// 「不合适」。V1 是白色按钮、V3 是文字按钮，确认框同一个。
struct VolunteerIntroCallDeclineButton: View {
    enum Look { case button, text }

    @ObservedObject var viewModel: VolunteerIntroCallViewModel
    let look: Look
    @State private var confirms = false

    private static let hint = IntroCallCopy.volunteerDeclineAccessibilityHint

    var body: some View {
        Group {
            switch look {
            case .button:
                FlowActionButton(
                    IntroCallCopy.volunteerDeclineButtonTitle,
                    style: .ghost,
                    isEnabled: !viewModel.isSubmitting,
                    accessibilityHint: Self.hint
                ) { confirms = true }
            case .text:
                FlowTextButton(title: IntroCallCopy.volunteerDeclineButtonTitle, accessibilityHint: Self.hint) {
                    confirms = true
                }
                .disabled(viewModel.isSubmitting)
            }
        }
        .accessibilityIdentifier("volunteerIntroCallDeclineButton")
        .alert(IntroCallCopy.volunteerDeclineConfirmTitle, isPresented: $confirms) {
            Button(IntroCallCopy.declineConfirmCancelButton, role: .cancel) {}
            Button(IntroCallCopy.volunteerDeclineConfirmButton) {
                Task { await viewModel.submit(.decline) }
            }
        } message: {
            Text(IntroCallCopy.volunteerDeclineConfirmMessage)
        }
    }
}

/// 「未接到来电」。进页满 `volunteerUnreachableDelayMinutes` 分钟才出现，之前原位置是一行说明。
struct VolunteerIntroCallUnreachableButton: View {
    @ObservedObject var viewModel: VolunteerIntroCallViewModel
    let orderId: Int64
    @State private var confirms = false
    @State private var firstSeen: Date?
    /// 15 秒一拍足够：门槛是分钟级，晚出现十几秒没有代价。
    private static let tick: TimeInterval = 15

    private var round: VolunteerIntroCallUnreachableGate.Round {
        .init(orderId: orderId, windowEndsAt: viewModel.introCall?.windowEndsAt)
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: Self.tick)) { context in
            if let firstSeen, VolunteerIntroCallUnreachableGate.isAvailable(firstSeenAt: firstSeen, now: context.date) {
                FlowTextButton(
                    title: IntroCallCopy.volunteerUnreachableButtonTitle,
                    accessibilityHint: IntroCallCopy.volunteerUnreachableAccessibilityHint
                ) { confirms = true }
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("volunteerIntroCallUnreachableButton")
            } else {
                Text(IntroCallCopy.volunteerUnreachablePendingNotice)
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("volunteerIntroCallUnreachablePending")
            }
        }
        .onAppear { firstSeen = VolunteerIntroCallUnreachableGate.noteSeen(round) }
        .onChange(of: round) { firstSeen = VolunteerIntroCallUnreachableGate.noteSeen($0) }
        .alert(IntroCallCopy.volunteerUnreachableConfirmTitle, isPresented: $confirms) {
            Button(IntroCallCopy.declineConfirmCancelButton, role: .cancel) {}
            Button(IntroCallCopy.volunteerUnreachableConfirmButton) {
                Task { await viewModel.reportUnreachable() }
            }
        } message: {
            Text(IntroCallCopy.volunteerUnreachableConfirmMessage)
        }
    }
}
