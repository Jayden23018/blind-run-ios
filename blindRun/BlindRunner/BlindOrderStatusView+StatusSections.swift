import SwiftUI

extension BlindOrderStatusView {
    /// 一句话 + 一个数字，合成**一个** VoiceOver 焦点。
    ///
    /// 距离此前埋在下面的「志愿者信息」卡片里当正文读，而它恰恰是这一页唯一会变的数字 ——
    /// 对标 GoodMaps 的 `Start Walking … 96 ft`、WeWALK 的 `116 meters`：状态旁边就该是那个数
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 4）。
    func statusHeader(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.system(size: 56))
                .foregroundColor(order.status.statusColor)
                .accessibilityHidden(true)

            Text(order.status.displayName)
                .font(.largeTitle.bold())
                .foregroundColor(AppColors.textPrimary)

            Text(order.status.blindRunnerDescription)
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            // 还在等人时，这一格是「已等待 12 分钟」；有志愿者了换成距离；跑起来了换成
            // 约定结束时间。三者状态集互不相交（`offersWaitedDuration` 的注释里有理由），
            // 所以卡上任何时刻只有一个数字。
            if let waitedText = order.blindRunnerWaitedText() {
                Text(waitedText)
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            if let distanceText = viewModel.volunteerDistanceToStartText {
                Text("陪跑员\(distanceText)")
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // 服务进行中，把约定的结束时间摆在首屏。低视力用户靠这行字看到，
            // 读屏用户靠 `statusHeaderAnnouncement` 听到 —— 两条通道都要有。
            if let plannedEndText = plannedEndHeaderText(order) {
                Text(plannedEndText)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusHeaderAnnouncement(order))
    }

    /// 结束时间只在服务进行中出现在首屏。派单期、汇合期摆它没有用（还没开始跑），
    /// 终态更不该摆（已经结束了，一个「预计」是噪音）。
    ///
    /// 拼接抽成独立函数而不是塞进 `Text(...)`：带可选拆包的字符串插值放在 view builder 里
    /// 会把类型检查器拖到超时（`unable to type-check this expression in reasonable time`）。
    private func plannedEndHeaderText(_ order: OrderDetailResponse) -> String? {
        guard order.status == .inProgress, let end = order.plannedEndForAnnouncement else { return nil }
        return "预计 \(end) 结束"
    }

    /// 合并后的朗读文本写死，不交给 `.combine` 自己拼 —— 自动拼接会把状态名、说明和距离
    /// 糊成一长串没有停顿的音。
    private func statusHeaderAnnouncement(_ order: OrderDetailResponse) -> String {
        var parts = [order.status.displayName, order.status.blindRunnerDescription]
        if let waitedText = order.blindRunnerWaitedText() {
            parts.append(waitedText)
        }
        if let distanceText = viewModel.volunteerDistanceToStartText {
            parts.append("陪跑员\(distanceText)")
        }
        if let plannedEndText = plannedEndHeaderText(order) {
            parts.append(plannedEndText)
        }
        return parts.joined(separator: "。")
    }

    /// 「刚才到底发生了什么」。
    ///
    /// 折叠，理由与「预约信息」同一条：这是用户想回溯时才来找的信息，不是主路径上的动作。
    /// 摊开会让读屏用户在到达「重复当前状态」之前多滑十几次。
    var statusLogSection: some View {
        DisclosureGroup("状态变更记录", isExpanded: $showStatusLogs) {
            statusLogContent
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到此订单每一次状态变化和发生时间")
        .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
    }

    @ViewBuilder
    var statusLogContent: some View {
        if viewModel.isLoadingStatusLogs && viewModel.statusLogs.isEmpty {
            ProgressView("正在获取状态变更记录")
                .tint(AppColors.primary)
                .accessibilityLabel("正在获取状态变更记录")
        } else if let errorMessage = viewModel.statusLogsErrorMessage {
            // 「拿不到」和「没有记录」必须分得开：前者可以重试，后者重试也没用。
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(errorMessage)
        } else if viewModel.statusLogs.isEmpty {
            Text("暂无状态变更记录")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("暂无状态变更记录")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 后端已按时间倒序给，最新的一条在最上面 —— 读屏第一个听到的就是刚发生的事。
                ForEach(viewModel.statusLogs) { log in
                    infoRow(log.changedAt.displayDateTime, log.displayText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
