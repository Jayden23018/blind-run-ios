import SwiftUI

/// 陪跑员「我的」标签根页顶上的累计卡（#324 第二轮界面迭代，OpenSpec `profile-tab-summary`）。
///
/// 「我的」页此前是一张纯设置列表（2026-10-05 截图评审：吸引力 2/10）。
/// 激励档（`docs/ui/design-direction.md` §6「明快」）：自己的累计 + 一个进成就页的入口；不放排名。
/// 累计时长与成就页同一个格式（`RunRecordHistoryViewModel.serviceDuration`，#351），不按整小时截断。
struct VolunteerProfileAchievementsCard: View {
    let response: VolunteerAchievementsResponse

    var body: some View {
        let headline = response.completedCount > 0 ? "已完成 \(response.completedCount) 次陪跑" : "还没有完成的陪跑"
        let hoursLine = "累计服务 \(RunRecordHistoryViewModel.serviceDuration(max(0, response.totalServiceMinutes ?? 0)))"
        Section {
            NavigationLink {
                VolunteerServiceRecognitionView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(AppFonts.title())
                        .foregroundColor(AppColors.textPrimary)
                    Text("\(hoursLine) · 查看服务成就")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
            }
            // 念的与屏幕上写的是同一句：`summarySpeech` 的小时取自星级、这里取自累计分钟，
            // 后端只给其中一个时两者会对不上。
            .accessibilityLabel("\(headline)，\(hoursLine)")
            .accessibilityHint("打开服务成就")
            .accessibilityIdentifier("volunteerProfileAchievementsCard")
        }
    }
}
