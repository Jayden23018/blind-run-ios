import SwiftUI

// MARK: - 订单页 v7 抽屉内容：⑤ 出发 ⑥ 已到达 ⑦ 陪跑中 ⑧ 已完成（#918）

/// 抽屉里随状态换的那一段。地图、拖动条、竖线、底栏都在外壳 `BlindOrderTrackingView` 里。
///
/// 读屏顺序 = 视觉顺序：标题（这一页最重要的一个元素）→ 副标题 / 数字 → 陪跑员行 → 其余行。
/// 文案判据仍在 `BlindOrderFlowPresentation`（按钮、取消门槛、倒计时、开跑时刻），这里只换版式；
/// 新写的只有稿上的四句标题（`BlindTrackingDrawerCopy`）。
struct BlindOrderTrackingDrawer: View {
    let presentation: BlindOrderFlowPresentation
    let order: OrderDetailResponse
    var stats: TrackStats?
    var isLocationFresh = true
    var isLiveSharing = false
    /// ⑥ 陪跑员行右侧的「打电话」。按钮出不出现由 `presentation.callTitle` 决定。
    var onCallVolunteer: (() -> Void)?
    /// ⑤ 陪跑员行右侧的「留一句话」。`nil` = 这一态不能留言（`acceptsRunnerMessage`）。
    var onEditRunnerMessage: (() -> Void)?
    /// ⑥ 取消本单（弹既有二次确认）。行出不出现、可不可按由 `presentation.arrivalCancel` 决定。
    var onArrivalCancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch presentation.phase {
            case .countdown(let beat):
                countdown(beat)
            case .running:
                header
                runningBlock
            case .finished:
                header
                finishedCard
            case .beforeRun:
                header
                volunteerRow
                if let gate = presentation.arrivalCancel, let onArrivalCancel {
                    arrivalCancelRow(gate, action: onArrivalCancel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 标题

    private var title: String {
        BlindTrackingDrawerCopy.title(
            status: order.status,
            name: order.volunteerNameForSpeech,
            meetSpot: order.meetSpotNote
        ) ?? presentation.title
    }

    /// ⑤ 用稿上那句「距出发地点约 300 米 · 请在集合点原地等」；⑥ 沿用骨架那句（含「先核对对方姓氏」，#660 B-15，不能丢）。
    private var subtitleLines: [String] {
        switch order.status {
        case .driverEnRoute:
            var lines = [BlindTrackingDrawerCopy.enRouteSubtitle(distanceText: distanceText)]
            if let rope = GuideRopeReminder.line(for: order, isVolunteer: false) { lines.append(rope) }
            return lines
        case .driverArrived:
            return presentation.subtitle.split(separator: "\n").map(String.init)
        default:
            return []
        }
    }

    /// 骨架副标题里已经拼好的那段距离（`offersVolunteerDistanceToStart` 两态才有）。
    private var distanceText: String? {
        presentation.subtitle.split(separator: "\n").map(String.init).first { $0.hasPrefix("距出发地点") }
    }

    private var header: some View {
        let lines = subtitleLines
        let spoken = ([title] + lines + [presentation.warning].compactMap { $0 }).joined(separator: "。")
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 只在异常时出现（拿不到陪跑员位置）。正常状态不显示任何反向提示。
            if let warning = presentation.warning {
                Label {
                    Text(warning)
                        .flowFont(FlowV2Fonts.callout(bold: true))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundColor(AppColors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 合成一个元素，念法写死（同 `BlindOrderFlowView.heroBody`）；identifier 沿用骨架的，UI 用例照样找得到。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    // MARK: - ⑤ ⑥ 陪跑员行

    /// 头像 + 掩码名 + 「蓝色上衣 · 陪跑 32 次」+ 右侧一个浅底按钮（⑤ 留一句话 / ⑥ 打电话）。
    /// 一屏只有一个实心按钮，在底栏；这里是浅底（负责人「按钮要克制」）。
    @ViewBuilder
    private var volunteerRow: some View {
        if let name = order.volunteerName?.nilIfBlank {
            let detail = [order.volunteerTopColor?.spokenName.map { "\($0)上衣" }, order.volunteerExperienceText]
                .compactMap { $0 }
                .joined(separator: " · ")
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 12) {
                    FlowAvatar(
                        name: name,
                        diameter: FlowMetrics.v2ListAvatarDiameter,
                        background: AppColors.Flow.blueTint,
                        foreground: AppColors.Flow.onBlueTint
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .flowFont(FlowV2Fonts.headline())
                            .foregroundColor(AppColors.Flow.primaryText)
                        if !detail.isEmpty {
                            Text(detail)
                                .flowFont(FlowV2Fonts.subhead())
                                .foregroundColor(AppColors.Flow.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(["陪跑员\(name.unmaskedForSpeech)", detail.replacingOccurrences(of: " · ", with: "，").nilIfBlank]
                    .compactMap { $0 }
                    .joined(separator: "，"))
                .accessibilityIdentifier("blindOrderTrackingVolunteerRow")

                volunteerRowAction
            }
        }
    }

    @ViewBuilder
    private var volunteerRowAction: some View {
        if presentation.callTitle != nil, let onCallVolunteer {
            chipButton(
                BlindTrackingDrawerCopy.call,
                // 刻意不念号码（理由同 `PrimaryAction.blindAccessibilityHint` 的 `.callVolunteer`）。
                accessibilityLabel: presentation.callTitle ?? BlindTrackingDrawerCopy.call,
                hint: "系统会先弹出拨号确认，确认后才会拨出",
                action: onCallVolunteer
            )
            .accessibilityIdentifier("blindOrderTrackingCallButton")
        } else if let onEditRunnerMessage {
            let message = order.messageToVolunteer?.nilIfBlank
            chipButton(
                BlindTrackingDrawerCopy.leaveMessage,
                accessibilityLabel: message.map { "给陪跑员的留言，\($0)" } ?? "给陪跑员留一句话，还没有留",
                hint: "双击写一句话给陪跑员，比如你穿什么衣服",
                action: onEditRunnerMessage
            )
            .accessibilityIdentifier("blindOrderFlowRunnerMessageRow")
        }
    }

    /// 浅底胶囊。看得见的胶囊约 40pt 高，命中区撑到 64pt（盲人端下限）—— 撑在 label 里面，
    /// 外挂 frame 撑不大可点区（记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
    private func chipButton(_ title: String, accessibilityLabel: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .flowFont(FlowV2Fonts.subhead(bold: true))
                .foregroundColor(AppColors.Flow.onBlueTint)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.Flow.blueTint, in: Capsule())
                .frame(minWidth: 64, minHeight: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
    }

    // MARK: - ⑥ 取消本单（门槛只认 `earliestBlindCancelAt`，判定在 `BlindArrivalCancelGate`）

    private func arrivalCancelRow(_ gate: BlindArrivalCancelGate, action: @escaping () -> Void) -> some View {
        let detail: String
        let label: String
        switch gate {
        case .locked(let opensAt):
            detail = BlindArrivalCancelCopy.lockedDetail(opensAt: opensAt)
            label = BlindArrivalCancelCopy.lockedAccessibilityLabel(opensAt: opensAt)
        case .open:
            detail = BlindArrivalCancelCopy.openDetail
            label = BlindArrivalCancelCopy.openAccessibilityLabel
        }
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BlindArrivalCancelCopy.rowTitle)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(gate.isEnabled ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .flowFont(FlowFonts.rowLabel())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 没到点走 `.disabled()`，读屏念「变暗」；不在 action 里静默 return（同 `BlindOrderFlowView.arrivalCancelRow`）。
        .disabled(!gate.isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(gate.isEnabled ? BlindArrivalCancelCopy.openAccessibilityHint : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("blindOrderFlowArrivalCancelRow")
    }
}

// MARK: - 倒计时、⑦ 陪跑中、⑧ 已完成

extension BlindOrderTrackingDrawer {
    // MARK: - 倒计时（⑥ → ⑦ 之间那三秒）

    private func countdown(_ beat: Int) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(presentation.title)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(AppColors.Flow.primaryText)
            Text("\(beat)")
                .flowHeroNumber(FlowV2Fonts.heroXL)
                .foregroundColor(AppColors.Flow.primaryText)
                .id(beat)
            Text(presentation.subtitle)
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(AppColors.Flow.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title)，\(beat)。\(presentation.subtitle)")
        .accessibilityIdentifier("blindOrderFlowStatusCard")
    }

    // MARK: - ⑦ 陪跑中

    private var runningBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            locationFreshnessRow
            BlindActiveRunView(
                stats: stats,
                paceLabel: BlindRunCopy.metricPaceLabel(isFinished: false),
                distanceFont: BlindTrackingDrawerMetrics.runDistanceFont
            )
            FlowSeparator()
            // 稿上带「›」。跑步中开 / 关分享还没有拍过板（见 `blindActiveRunSafetyHubSheet` 的 `offersLiveShare`），
            // 所以这一行只显示状态、不可点。
            HStack {
                Text(BlindTrackingDrawerCopy.shareRowTitle)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.Flow.primaryText)
                Spacer(minLength: 8)
                Text(isLiveSharing ? BlindTrackingDrawerCopy.shareOn : BlindTrackingDrawerCopy.shareOff)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.Flow.secondaryText)
            }
            .frame(minHeight: 44) // guard:allow small-touch-target 纯展示行，不可点
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("blindOrderTrackingShareStatus")
        }
    }

    /// 本机定位新不新鲜（理由见 `BlindOrderFlowView.locationFreshnessBadge`：低视力用户唯一看得见 GPS 状态的地方）。
    private var locationFreshnessRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                .frame(width: FlowMetrics.locationDotDiameter, height: FlowMetrics.locationDotDiameter)
                .accessibilityHidden(true)
            Text(isLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale)
                .flowFont(FlowFonts.rowDetail())
                .foregroundColor(AppColors.Flow.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindOrderFlowLocationFreshness")
    }

    // MARK: - ⑧ 已完成

    /// 绿色成果卡（稿 ⑧）。评价仍在跑步详情，不搬过来（DECISION 第 10 条）。
    private var finishedCard: some View {
        FlowHeroCard(style: BlindHeroPalette(tone: .done).cardStyle) {
            BlindActiveRunView(
                stats: stats,
                paceLabel: BlindRunCopy.metricPaceLabel(isFinished: true),
                onHero: true,
                distanceFont: BlindTrackingDrawerMetrics.runDistanceFont
            )
        }
        .accessibilityIdentifier("blindOrderTrackingResultCard")
    }
}

extension BlindTrackingDrawerMetrics {
    /// ⑦ ⑧ 里程数字 44pt（负责人定稿时由 64pt 降下来，给地图留上半屏）。
    static let runDistanceFont: (CGFloat, Font.Weight, Font.TextStyle) = (44, .semibold, .largeTitle)
}
