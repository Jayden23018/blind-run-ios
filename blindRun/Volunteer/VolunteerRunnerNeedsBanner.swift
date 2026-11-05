import SwiftUI

/// 「本单为视障跑者」提示位。
///
/// 对标打车软件给司机弹的「此订单乘客为视障人士」：那条提示的价值不在于告知身份，
/// 而在于**改变司机接下来的动作**（下车接、口头引导、别按喇叭催）。这里同理，
/// 真正有用的是 `引导方式` 那一行 —— 递牵引绳 / 让对方挽手臂 / 只用口令是三种完全不同的做法。
///
/// 刻意**不做可折叠**：折叠等于把它降级成「想看再看」，而这几行正是志愿者见面前
/// 唯一必须先知道的东西。内容为空时整块不渲染（判定在 `OrderDetailResponse.escortNeeds`），
/// 所以「不可跳过」不会变成「每单都有一块空卡片」。
struct VolunteerRunnerNeedsBanner: View {
    private let needs: [EscortNeed]

    init(order: OrderDetailResponse) {
        self.needs = order.escortNeeds
    }

    /// 接单前的入口（通话磨合页）。那一刻拿不到 `OrderDetailResponse` ——
    /// 后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，通话期它恒为 null → 403。
    /// 所以内容由派单载荷 `WSNewOrder.escortNeeds` 直接给（只剩导盲犬那一行）。
    init(needs: [EscortNeed]) {
        self.needs = needs
    }

    var body: some View {
        if !needs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("本单为视障跑者", systemImage: "figure.walk.motion")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.primary)

                ForEach(needs) { need in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: need.symbolName)
                            .font(AppFonts.caption().weight(.semibold))
                            .foregroundColor(AppColors.primary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("\(need.title)：\(need.value)")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.primary.opacity(0.35), lineWidth: 1)
            )
            // 合成一个焦点，且朗读文本写死：逐行分开会让读屏用户滑过其中一条而不自知，
            // 而这几行的意义恰恰在于「一条都不能漏」。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(needs.escortNeedsAnnouncement)
            .accessibilityIdentifier("volunteerRunnerNeedsBanner")
        }
    }
}
