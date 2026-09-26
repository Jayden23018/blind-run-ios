import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 陪跑员「出发 / 汇合」锁屏卡（交付包 04，决定源 V3）
//
// 每一行的文字由 `GuideRunActivityPresentation` 算好，这里只管画。
// 按钮只在 iOS 17+ 出现（`Button(intent:)`），16.x 上整行不画。

@available(iOS 16.2, *)
struct GuideRunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuideRunAttributes.self) { context in
            let presentation = GuideRunActivityPresentation(attributes: context.attributes, state: context.state)
            GuideRunLockScreenView(
                attributes: context.attributes,
                presentation: presentation
            )
            .activityBackgroundTint(RunLiveActivityPalette.color(presentation.background))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let presentation = GuideRunActivityPresentation(attributes: context.attributes, state: context.state)
            return DynamicIsland {
                // 展开态：与锁屏第 2–4 行相同，**不放按钮**（交付包 04「灵动岛」）。
                DynamicIslandExpandedRegion(.bottom) {
                    GuideRunInfoRows(attributes: context.attributes, presentation: presentation)
                }
            } compactLeading: {
                GuideRunMiniRope()
            } compactTrailing: {
                Text(presentation.compactTrailing)
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
            } minimal: {
                GuideRunMiniRope()
            }
        }
    }
}

/// 锁屏卡的尺寸。**比交付包 04 紧**：照稿子排（18 内边距、53pt 引导绳、44pt 按钮、状态行单独一行）
/// 2026-09-26 真机量出来快迟到 268pt、汇合 242pt，而锁屏卡上限 160pt（系统截断线）。
/// 压法见 `GuideRunLockScreenView` 的注释，高度由 `LiveActivityCardHeightTests` 在真机上钉住。
enum GuideRunActivityMetrics {
    static let verticalPadding: CGFloat = 10
    static let horizontalPadding: CGFloat = 16
    static let headlineSize: CGFloat = 30
    static let ropeHeight: CGFloat = 18
    static let ropeDotDiameter: CGFloat = 18
    /// 🚩 低于交付包的 44：44 放不进 160。陪跑员端不是读屏主力用户，且锁屏按钮周围是系统留白。
    static let buttonHeight: CGFloat = 40
}

/// 从上到下：图标 + 小标题（右侧到达时刻）/ ETA（快迟到时同行带「晚到约 N 分钟」）/
/// 引导绳**或**状态行 / 按钮。
///
/// 「引导绳或状态行」二选一是为了进 160pt：有状态行（跑者已到附近、汇合距离档位）时它比绳子的
/// 位置信息更有用；汇合时绳子恒在 0.85，本来就不带信息。
@available(iOS 16.2, *)
struct GuideRunLockScreenView: View {
    let attributes: GuideRunAttributes
    let presentation: GuideRunActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(RunLiveActivityPalette.color(LiveActivityStatePalette.yellow))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "figure.run")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(RunLiveActivityPalette.color(LiveActivityStatePalette.onYellow))
                    )
                Text(presentation.eyebrow)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(LiveActivityStatePalette.smallTextOpacityOnGuideCard))
                Spacer(minLength: 8)
                if let arriveClock = presentation.arriveClock {
                    Text(arriveClock)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(LiveActivityStatePalette.smallTextOpacityOnGuideCard))
                }
            }
            .accessibilityHidden(true)
            GuideRunInfoRows(attributes: attributes, presentation: presentation)
            actions
        }
        .padding(.vertical, GuideRunActivityMetrics.verticalPadding)
        .padding(.horizontal, GuideRunActivityMetrics.horizontalPadding)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var actions: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 10) {
                ForEach(presentation.actions, id: \.self) { action in
                    Button(intent: GuideRunActivityIntent(orderID: attributes.orderID, action: action)) {
                        Text(action.title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: GuideRunActivityMetrics.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(LiveActivityStatePalette.buttonFillOpacity))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// ETA 一行 + 引导绳或状态行。锁屏与灵动岛展开态共用；整块合成一站念完（小标题与到达时刻也在里面）。
@available(iOS 16.2, *)
private struct GuideRunInfoRows: View {
    let attributes: GuideRunAttributes
    let presentation: GuideRunActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.headline)
                    .font(.system(size: GuideRunActivityMetrics.headlineSize, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(
                        presentation.headlineIsLate
                            ? RunLiveActivityPalette.color(LiveActivityStatePalette.gold)
                            : .white
                    )
                    .lineLimit(1)
                    .layoutPriority(1)
                // 金色只给左边的大字（大字 3:1 够）；这行 15pt 的金字在出发蓝上只有 4.32:1。
                if let lateSuffix = presentation.lateSuffix {
                    Text(lateSuffix)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(LiveActivityStatePalette.smallTextOpacityOnGuideCard))
                        .lineLimit(1)
                }
            }
            .minimumScaleFactor(0.7)
            if let statusLine = presentation.statusLine {
                HStack(spacing: 8) {
                    Circle()
                        .fill(RunLiveActivityPalette.color(LiveActivityStatePalette.nearDot))
                        .frame(width: 8, height: 8)
                    Text(statusLine)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(minHeight: GuideRunActivityMetrics.ropeHeight)
            } else {
                GuideRunRope(progress: presentation.progress, runnerSurname: attributes.runnerSurname)
                    .frame(height: GuideRunActivityMetrics.ropeHeight)
            }
        }
        // 数字更新时不主动播报（系统默认即如此）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// 引导绳（交付包 `RopeView(state: .departed)` 的锁屏简化版）：
/// 陪跑员实心圆（按 `progress` 走）→ 绳子 → 跑者空心圆（右端，写姓氏）。为进 160pt 去掉了起点圈、圆点缩到 18pt。
///
/// ponytail: App 里那条 `RopeView` 在 app target，widget 编译不到；这里只画四个图元。
/// 要和 App 内逐像素一致时，把 `RopeView` 挪进 `Shared/`。
private struct GuideRunRope: View {
    let progress: Double
    let runnerSurname: String?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY = proxy.size.height / 2
            let radius = GuideRunActivityMetrics.ropeDotDiameter / 2
            let runnerX = width - radius - 1
            let volunteerX = radius + (runnerX - radius) * progress
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: volunteerX + radius + 4, y: midY))
                    path.addLine(to: CGPoint(x: runnerX - radius - 4, y: midY))
                }
                .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle()
                    .fill(.white)
                    .frame(width: GuideRunActivityMetrics.ropeDotDiameter, height: GuideRunActivityMetrics.ropeDotDiameter)
                    .position(x: volunteerX, y: midY)
                Circle()
                    .fill(.white.opacity(0.18))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(
                        Text(runnerSurname.map { String($0.prefix(1)) } ?? "")
                            .font(.system(size: 11, weight: .heavy))
                    )
                    .frame(width: GuideRunActivityMetrics.ropeDotDiameter, height: GuideRunActivityMetrics.ropeDotDiameter)
                    .position(x: runnerX, y: midY)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 灵动岛紧凑态 / 最小态：两个 7pt 圆点 + 一段短线。
private struct GuideRunMiniRope: View {
    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(.white).frame(width: 7, height: 7)
            Capsule().fill(.white.opacity(0.75)).frame(width: 6, height: 2)
            Circle().stroke(.white, lineWidth: 1.5).frame(width: 7, height: 7)
        }
        .accessibilityHidden(true)
    }
}
