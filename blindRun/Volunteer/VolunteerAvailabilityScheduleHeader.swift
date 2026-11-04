import SwiftUI

/// 空闲时间页列表上方的两行字。从 `VolunteerAvailabilityScheduleView` 拆出来：
/// 那个文件已超过 SwiftLint 的 `file_length` 上限，棘轮只许变小（#654 加第二行后变大，CI 报红）。
/// 两行都是外层 `VStack(spacing: 8)` 的直接子项，排版与拆分前一样。
struct VolunteerAvailabilityScheduleHeader: View {
    var body: some View {
        // 系统组标题与页脚色是 `secondaryLabel`，压在分组底色上亮色只有 3.29:1，
        // 真机审计报「字再大一点才够」（#466）。`textSecondary` 亮 5.96:1 / 暗 9.5:1。
        Text("这些时间里有合适的陪跑，会邀请你")
            .font(.subheadline)
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 16)

        // 空闲时间不等于锁屏也能被派到（#654）。
        Text(VolunteerAvailabilityCopy.keepAppOpenNote + "。")
            .font(.subheadline)
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
}
