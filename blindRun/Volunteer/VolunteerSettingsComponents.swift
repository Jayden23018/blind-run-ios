import SwiftUI

// 陪跑员「我的」与账户页共用的行、方块、头像（#700）。页面在 `VolunteerSettingsView.swift`。

/// 方块本身：左上图标、左下名称。图标只是装饰，读屏只念名称。
struct VolunteerSettingsTileLabel: View {
    let tile: VolunteerSettingsTile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: tile.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .accessibilityHidden(true)
            Spacer(minLength: 14)
            Text(tile.title)
                .font(.headline.weight(.bold)) // 稿子方块名是粗体；.headline 的中文半粗在真机上偏细
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .leading)
        .background(Color(uiColor: UIColor(rgb: tile.rgb)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 列表里「标题 + 可选值 + 箭头」的一行。可点区由 `contentShape` 撑满整行，高度不低于 64pt
/// （记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
struct VolunteerSettingsRowLabel: View {
    let title: String
    var value: String?
    var titleColor: Color = AppColors.textPrimary
    var showsChevron = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let value {
                Text(value)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                VolunteerSettingsChevron()
            }
        }
        .padding(.horizontal, VolunteerAccountMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct VolunteerSettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .accessibilityHidden(true)
    }
}

/// 头像：后端没有头像字段，画一个通用剪影。装饰，读屏不念。
struct VolunteerAvatarCircle: View {
    let side: CGFloat

    var body: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(side * 0.24)
            .foregroundColor(.white)
            .frame(width: side, height: side)
            .background(Circle().fill(AppColors.Flow.decorMutedInk))
            .accessibilityHidden(true)
    }
}

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
            VolunteerSettingsRowLabel(title: VolunteerSettingsCopy.achievementsTitle, value: "\(count) 次 · \(duration)")
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerSettingsCopy.achievementsTitle)，\(headline)，累计服务 \(duration)")
        .accessibilityHint("打开服务成就")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("volunteerProfileAchievementsCard")
    }
}

/// 「联系客服」「我的工单」两行。盲人端用的 `AccountSafetySettingsRows` 是 `List` 写法且带「已拉黑的人」，
/// 陪跑员这边拉黑挪进了账户页，所以单独写；标识与文案和那边一致。
struct VolunteerSupportSettingsRows: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var showsSupportTicket = false

    var body: some View {
        Button {
            showsSupportTicket = true
        } label: {
            VolunteerSettingsRowLabel(title: SupportTicketCopy.title)
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

        VolunteerAccountRowDivider()

        // 提交之后唯一能看到回复的地方（`SUPPORT_TICKET_REPLIED` 推送错过了就只剩这里）。
        NavigationLink {
            MySupportTicketsView()
        } label: {
            VolunteerSettingsRowLabel(title: SupportTicketCopy.myTicketsTitle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SupportTicketCopy.myTicketsTitle)
        .accessibilityHint(SupportTicketCopy.myTicketsHint)
        .accessibilityIdentifier("mySupportTicketsSettingsEntry")
    }
}
