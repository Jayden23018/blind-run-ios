import SwiftUI

// 陪跑员「我的」专用的列表行（#700）。页面在 `VolunteerSettingsView.swift`；
// 两端共用的方块、行、头像在 `Shared/SettingsTileComponents.swift`。

/// 列表第一行「服务成就」（原「我的」顶上的累计卡，#324 / OpenSpec `profile-tab-summary`）。
/// 累计时长与成就页同一个格式（`RunRecordHistoryViewModel.serviceDuration`，#351），不按整小时截断。
struct VolunteerSettingsAchievementsRow: View {
    let response: VolunteerAchievementsResponse

    var body: some View {
        let count = max(0, response.completedCount)
        let duration = RunRecordHistoryViewModel.serviceDuration(max(0, response.totalServiceMinutes ?? 0))
        let headline = count > 0 ? "已完成 \(count) 次陪跑" : "还没有完成的陪跑"
        NavigationLink {
            VolunteerServiceRecognitionView()
        } label: {
            SettingsRowLabel(title: VolunteerSettingsCopy.achievementsTitle, value: "\(count) 次 · \(duration)")
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerSettingsCopy.achievementsTitle)，\(headline)，累计服务 \(duration)")
        .accessibilityHint("打开服务成就")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("volunteerProfileAchievementsCard")
    }
}

/// 「联系客服」「我的工单」两行。盲人端联系客服是方块、我的工单是列表行，分开写；标识与文案和那边一致。
struct VolunteerSupportSettingsRows: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var showsSupportTicket = false

    var body: some View {
        Button {
            showsSupportTicket = true
        } label: {
            SettingsRowLabel(title: SupportTicketCopy.title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SupportTicketCopy.title)
        .accessibilityHint(SupportTicketCopy.settingsHint)
        .accessibilityIdentifier("supportTicketSettingsEntry")
        .sheet(isPresented: $showsSupportTicket) {
            SupportTicketView(
                orderID: nil,
                category: .account,
                appState: appState,
                speak: { speechService.speak($0) },
                speakError: { speechService.speakError($0) }
            )
        }

        GroupedCardDivider()

        // 提交之后唯一能看到回复的地方（`SUPPORT_TICKET_REPLIED` 推送错过了就只剩这里）。
        NavigationLink {
            MySupportTicketsView()
        } label: {
            SettingsRowLabel(title: SupportTicketCopy.myTicketsTitle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SupportTicketCopy.myTicketsTitle)
        .accessibilityHint(SupportTicketCopy.myTicketsHint)
        .accessibilityIdentifier("mySupportTicketsSettingsEntry")
    }
}
