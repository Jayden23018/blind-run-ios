import SwiftUI

/// 国标星级卡：星级、进度条、「还差多少小时」。成就页与陪跑完成页共用（2026-10-05 起）。
///
/// 进度条对 VoiceOver 是空的，所以下面那行文字不是装饰 —— 它是这一栏
/// 唯一能被读出来的进度信息。两者顺序不能倒，也不能只留进度条。
///
/// 标题与进度行取首屏星级卡同一套文案（`VolunteerProfileCopy.starCard*`）：
/// 未达一星时说「距离一星还差 N 小时」而不是「尚未达到一星」（2026-10-03 试用反馈，
/// 2026-10-06 负责人定三处统一）。一星以上两套文案本来就相同。
struct VolunteerStarProgressCard: View {
    let level: VolunteerStarLevelDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VolunteerAchievementsCopy.starSectionTitle)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(VolunteerAchievementsCopy.starSectionStandard)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(VolunteerProfileCopy.starCardTitle(level))
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: Self.progress(level))
                .tint(AppColors.primary)
                .accessibilityHidden(true)

            Text(VolunteerProfileCopy.starCardProgress(level))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerProfileCopy.starCardAccessibilityLabel(level))
        .accessibilityIdentifier("volunteerStarLevelSection")
    }

    static func progress(_ level: VolunteerStarLevelDto) -> Double {
        guard let nextTarget = level.nextTarget, nextTarget > 0 else { return 1 }
        let hours = Double(max(0, level.currentHours ?? 0))
        return min(1, hours / Double(nextTarget))
    }
}

/// 陪跑完成页的星级进度（负责人 2026-10-05：这一屏吸引力 3/10、下面 60% 空白）。
///
/// 进页面才拉、每次都拉：首页那份（`VolunteerHomeIncentiveViewModel`）一个会话只拉一次，此刻还不含刚跑完的这一单。
/// 这是附加信息：拉不到就整块不出现，不挤占「完成」这个出口，也不报错 —— 成就页自己有完整的失败态。
struct VolunteerCompletionStarProgress: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var achievements = VolunteerAchievementsViewModel()

    var body: some View {
        // `.task` 挂在常驻的 0 高占位上：数据没到时卡片不在树里，挂在空视图上的 `.task` 永远不会触发
        //（记忆 task-on-empty-view-never-fires）。
        VStack(spacing: 0) {
            Color.clear.frame(height: 0)
            if let level = achievements.achievements?.resolvedStarLevel {
                VolunteerStarProgressCard(level: level)
            }
        }
        .task {
            achievements.configure(appState: appState)
            await achievements.load()
        }
    }
}

