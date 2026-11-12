import SwiftUI

// MARK: - 陪跑员订单页 ⑧ 跑完了：v8 卡片页（#972）
//
// 批准稿 `docs/ui/mockups/volunteer-run-finish-v8-20261112/`（负责人 2026-11-12「藏青，开始改」）。
// 照盲人端 ⑧（`BlindRunCardsPage`，#968）同一套骨架：标题「跑完了」→ 绿色彩色卡（与跑步中青绿卡同一个位置、同一个大小）
// → 路线小图 → 跑者卡（右边「上报问题」）→ 国标星级卡 →「查看跑步记录」；底部「完成」藏青胶囊。
// 不再是「上半屏地图 + 抽屉」。
extension VolunteerOrderFlowPage {
    func finishedCardsLayout(order: OrderDetailResponse) -> some View {
        RunCardsScaffold(
            gap: BlindRunCardsMetrics.finishedGap,
            topBar: topBar(surface: .onMap),
            bottom: OrderFlowBottomActions(owner: .volunteer, primary: trackingPrimary, safetyHub: nil, usesNavyPrimary: true),
            header: finishedHeader(order: order)
        ) {
            BlindRunHeroCard(stats: VolunteerRunFinishedSummary.stats(order: order, track: finishedTrack), isFinished: true)
                .accessibilityIdentifier("volunteerRunFinishedHero")
            BlindRunCardsRouteMap(track: finishedTrack)
            VolunteerFinishedRunnerCard(
                order: order,
                report: rows.first { $0.action == .reportIssue },
                onReport: { onRowAction(.reportIssue) }
            )
            VolunteerCompletionStarProgress()
            if let record = rows.first(where: { $0.action == .viewRunRecord }) {
                runRecordLink(record)
            }
            footer()
        }
    }

    /// 「跑完了」+「和李*一起 · 今天 7:02–7:44」。念法与焦点沿用 v7 抽屉标题（同一个 identifier，状态一变读屏焦点落这里）。
    private func finishedHeader(order: OrderDetailResponse) -> some View {
        RunCardsHeader(
            title: VolunteerOrderFlowCopy.completedDrawerTitle,
            companion: VolunteerRunFinishedSummary.subtitle(order: order, track: finishedTrack)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerOrderFlowStatusCard")
        .accessibilityFocused($headerFocused)
    }

    /// 卡片下面居中一行「查看跑步记录 ›」（批准稿），可点区撑到 64pt。
    private func runRecordLink(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
        Button { onRowAction(.viewRunRecord) } label: {
            HStack(spacing: 4) {
                Text(row.value)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .flowFont(FlowV2Fonts.callout())
            .foregroundColor(AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHintIfPresent(row.accessibilityHint)
        .accessibilityIdentifier("volunteerOrderFlowRow-runRecord")
    }
}

// MARK: - 跑完了页的数字与副标题（纯逻辑，用例 `VolunteerRunFinishedSummaryTests`）

enum VolunteerRunFinishedSummary {
    /// 彩色卡的数字：先用 `/track` 的跑者那一份（与盲人端、跑步中同一份数）；还没拉到或拉失败时退回订单上的实跑里程与用时。
    /// 退回时不算配速（没有就是没有，卡上那一格写「--」）。两样都没有时彩色卡写「稍等一下」，不摆三个杠。
    static func stats(order: OrderDetailResponse, track: OrderTrackResponse?) -> TrackStats? {
        if let stats = track?.blindStats, stats.distanceMeters != nil { return stats }
        guard let meters = order.actualDistanceMeters, meters > 0 else { return track?.blindStats }
        return TrackStats(
            distanceMeters: Double(meters),
            durationSeconds: order.actualDurationSeconds.map(Int64.init),
            avgPaceSecPerKm: nil
        )
    }

    /// 副标题：「和李*一起 · 今天 7:02–7:44」（批准稿）。起止时间取跑者轨迹第一个点和最后一个点的记录时刻 ——
    /// 订单详情里没有开跑 / 结束时刻，轨迹是唯一的真数。轨迹没拉到、不足两个点或时刻解析不了时，
    /// 退回「和李*一起 · 第 N 次」（一起跑过两次以上才写次数），再不行只写「和李*一起」。
    static func subtitle(
        order: OrderDetailResponse,
        track: OrderTrackResponse?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let companion = BlindRunCardsCopy.companion(name: order.blindName?.nilIfBlank ?? order.runnerShortName)
        if let range = timeRange(track: track, now: now, calendar: calendar) {
            return "\(companion) · \(range)"
        }
        let count = order.completedTogetherCount ?? 0
        return count > 1 ? "\(companion) · 第 \(count) 次" : companion
    }

    /// 「今天 7:02–7:44」。开跑那一刻的日子沿用 `RunPlanFormat.shortStart`（今天 / 明天 / 月日）。
    static func timeRange(track: OrderTrackResponse?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let points = track?.blindTrack, points.count >= 2,
              let first = points.first?.recordedAt, let last = points.last?.recordedAt,
              let end = last.backendTimestamp,
              let start = RunPlanFormat.shortStart(first, now: now, calendar: calendar) else { return nil }
        return "\(start)–\(DateFormatter.aidRunDisplayClock.string(from: end))"
    }
}

// MARK: - 跑者卡

/// 头像、名字（掩码）、「全盲 · 牵引绳」，右边灰底胶囊「上报问题」。样子同盲人 v8 的陪跑员卡（`BlindRunPartnerCard`）：
/// 一行、卡高 72，名字那一行与胶囊各自的可点区 64；最大字号下胶囊排到名字下面、不放头像。
/// 名字不可点：陪跑员端没有跑者详情页，举报 / 不再匹配在顶栏「···」。
struct VolunteerFinishedRunnerCard: View {
    let order: OrderDetailResponse
    /// `nil` = 这一屏没有「上报问题」（展示层没给这一行）。
    let report: VolunteerOrderFlowPresentation.Row?
    let onReport: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String { order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName }
    private var needs: String? { order.escortNeeds.map(\.value).joined(separator: " · ").nilIfBlank }

    var body: some View {
        BlindRunCardSurface(insets: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                person
                if let report { reportChip(report) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerRunFinishedRunnerCard")
    }

    private var person: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                BlindPartnerAvatar(name: name, tint: AppColors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .flowFont((18, .bold, .headline))
                    .foregroundColor(AppColors.Flow.primaryText)
                if let needs {
                    Text(needs)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .accessibilityElement(children: .ignore)
        // 读屏不念掩码星号（`blindNameForSpeech`），同 v7 跑者行。
        .accessibilityLabel(
            ["\(VolunteerOrderFlowCopy.runnerLabel)\(order.blindNameForSpeech)", needs?.replacingOccurrences(of: " · ", with: "，")]
                .compactMap { $0 }.joined(separator: "，")
        )
    }

    /// 灰底胶囊，看得见的部分 44pt 高，可点区撑到 64pt（撑在 label 里，外挂 frame 撑不大可点区）。
    private func reportChip(_ row: VolunteerOrderFlowPresentation.Row) -> some View {
        Button(action: onReport) {
            Text(row.value)
                .flowFont((16, .semibold, .callout))
                .foregroundColor(AppColors.Flow.primaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .frame(minHeight: 44) // guard:allow small-touch-target 只是看得见的胶囊，可点区是下一行的 64pt
                .background(Capsule().fill(AppColors.ButtonPalette.neutralFill))
                .frame(minHeight: AppTouchTarget.blindPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHintIfPresent(row.accessibilityHint)
        .accessibilityIdentifier("volunteerOrderFlowRow-reportIssue")
    }
}
