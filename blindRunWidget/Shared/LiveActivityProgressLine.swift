import SwiftUI

// MARK: - 实时活动底部那根进度线：两端共用
//
// 🔴 本文件**同时属于 `blindRun` 与 `blindRunWidget`**（`project.pbxproj` 两个 Sources 阶段各引用一次）：
// widget 画卡要它，app target 的卡高单测也要排同一个视图。所以这里只能用 SwiftUI 与本文件自己的常量，
// 不能 `import` 任何只在 app target 里的东西。
//
// 设计源：`docs/ui/mockups/live-activity-v7-20261111/` 「一·补」（负责人 2026-11-11 定稿）。
// - 看步骤：五个节点 = 订单页竖线五步，当前一步加粗、圆点带外圈，走过的实心，没到的空心。
// - 看距离：陪跑员出发后同一根线放大成「出发 → 你 · 南门」，跑步小人按剩余距离走向右端。
// - 里程：开跑后 = 里程 / 目标里程。
// 盲人端（#919）与陪跑员端（#920）都用这一个组件。

/// 进度线画哪一种。
enum LiveActivityProgressMode: Hashable, Sendable {
    /// 看步骤。`current` 是第几步，1...5（越界会被夹回）。
    case steps(current: Int)
    /// 看距离。`progress` 是小人走到哪，0 = 出发处，1 = 右端；`endLabel` 是右端那几个字（「你 · 南门」）。
    case distance(progress: Double, endLabel: String)
    /// 里程 / 目标里程，0...1。
    case mileage(progress: Double)

    /// 读屏念这根线的那一段。视图本身对读屏隐藏，卡片把这一句拼进自己的 `accessibilityLabel`。
    var accessibilityLabel: String {
        switch self {
        case .steps(let current):
            let step = LiveActivityProgressLine.clampedStep(current)
            let title = LiveActivityProgressLine.spokenStepTitles[step - 1]
            return "第 \(step) 步，共 \(LiveActivityProgressLine.stepCount) 步，\(title)"
        case .distance(_, let endLabel):
            // 「你 · 南门」念成「你所在的南门」：中间那个点读屏念出来是噪音。
            let label = endLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " · ", with: "所在的")
            return label.isEmpty ? "陪跑员在路上" : "陪跑员在路上，前往\(label)"
        case .mileage(let progress):
            let percent = Int((LiveActivityProgressLine.clampedProgress(progress) * 100).rounded())
            return "已完成目标的 \(percent)%"
        }
    }
}

struct LiveActivityProgressLine: View {
    /// 节点下面的两个字。**两端同一组**（订单页 v7 五步）。
    static let stepTitles = ["匹配", "商量", "出发", "汇合", "开跑"]
    /// 读屏念的全称（稿「一·补」：「第 3 步，共 5 步，等出发」）。
    static let spokenStepTitles = ["匹配陪跑员", "商量见面安排", "等出发", "汇合", "开跑"]
    static let stepCount = 5
    /// 看距离时左端的字。
    static let distanceStartLabel = "出发"

    /// 尺寸。卡高 ≤ 160pt 的预算里这根线占约 40pt（22pt 节点行 + 3pt 间距 + 一行 13pt 字），里程线只有 6pt。
    enum Metrics {
        static let lineWidth: CGFloat = 3
        static let dot: CGFloat = 10
        static let currentDot: CGFloat = 14
        /// 当前一步外圈（稿：白点外一圈 4pt 浅蓝光晕）。
        static let currentRing: CGFloat = 22
        static let endRing: CGFloat = 16
        /// 看距离时沿线走的那个白底圆（里面是跑步小人）。
        static let runnerMarker: CGFloat = 22
        static let runnerIcon: CGFloat = 12
        /// 稿 `.stp .lb` 13px。
        static let labelSize: CGFloat = 13
        static let labelSpacing: CGFloat = 3
        static let mileageHeight: CGFloat = 6
        /// 切换「看步骤 → 看距离」时线放大的那一下。Apple 上限 2 秒；息屏常亮时系统不做动画，直接换。
        static let modeChangeAnimation: Double = 1
    }

    /// 稿里的浅蓝（`--acc: #A8C8FF`）：当前一步的光晕、看距离右端的圈。
    static let defaultAccent = Color(red: 0xA8 / 255, green: 0xC8 / 255, blue: 0xFF / 255)
    /// 跑步小人画在白底圆里，图标用稿里的卡底深蓝（`--navy: #1F2433`）。
    static let markerInk = Color(red: 0x1F / 255, green: 0x24 / 255, blue: 0x33 / 255)

    let mode: LiveActivityProgressMode
    /// 线、节点、小人的颜色。卡底是彩色或深色，默认白。
    let tint: Color
    /// 看距离右端那个圈的颜色。
    let accent: Color

    init(mode: LiveActivityProgressMode, tint: Color = .white, accent: Color = LiveActivityProgressLine.defaultAccent) {
        self.mode = mode
        self.tint = tint
        self.accent = accent
    }

    static func clampedStep(_ step: Int) -> Int {
        min(max(step, 1), stepCount)
    }

    /// 夹到 0...1。`NaN` 当 0：后端或除法给出 `NaN` 时小人不能飞出卡外。
    static func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        Group {
            switch mode {
            case .steps(let current):
                StepsLine(current: Self.clampedStep(current), tint: tint, accent: accent)
            case .distance(let progress, let endLabel):
                DistanceLine(progress: Self.clampedProgress(progress), endLabel: endLabel, tint: tint, accent: accent)
            case .mileage(let progress):
                MileageLine(progress: Self.clampedProgress(progress), tint: tint)
            }
        }
        .animation(.easeInOut(duration: Metrics.modeChangeAnimation), value: mode)
        .accessibilityHidden(true)
    }
}

// MARK: - 看步骤

private struct StepsLine: View {
    let current: Int
    let tint: Color
    let accent: Color

    private typealias M = LiveActivityProgressLine.Metrics

    var body: some View {
        VStack(spacing: M.labelSpacing) {
            ZStack {
                // 线从第一个节点中心画到最后一个节点中心：两端各缩进半格。
                GeometryReader { proxy in
                    let cell = proxy.size.width / CGFloat(LiveActivityProgressLine.stepCount)
                    let start = cell / 2
                    let end = proxy.size.width - cell / 2
                    let reached = start + (end - start) * CGFloat(current - 1) / CGFloat(LiveActivityProgressLine.stepCount - 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.3))
                            .frame(width: end - start, height: M.lineWidth)
                            .offset(x: start)
                        Capsule().fill(tint)
                            .frame(width: max(reached - start, 0), height: M.lineWidth)
                            .offset(x: start)
                    }
                    .frame(maxHeight: .infinity)
                }
                HStack(spacing: 0) {
                    ForEach(1...LiveActivityProgressLine.stepCount, id: \.self) { step in
                        node(step)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: M.currentRing)
            HStack(spacing: 0) {
                ForEach(1...LiveActivityProgressLine.stepCount, id: \.self) { step in
                    Text(LiveActivityProgressLine.stepTitles[step - 1])
                        .font(.system(size: M.labelSize, weight: step == current ? .bold : .regular))
                        .foregroundStyle(tint.opacity(step == current ? 1 : 0.6))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func node(_ step: Int) -> some View {
        if step == current {
            ZStack {
                Circle().fill(accent.opacity(0.38))
                    .frame(width: M.currentRing, height: M.currentRing)
                Circle().fill(tint)
                    .frame(width: M.currentDot, height: M.currentDot)
            }
        } else if step < current {
            Circle().fill(tint)
                .frame(width: M.dot, height: M.dot)
        } else {
            // 空心点要盖住背后的线：先填卡底色做不到（卡底由调用方定），所以描边粗一点、中间留空。
            Circle().stroke(tint.opacity(0.45), lineWidth: 2)
                .frame(width: M.dot, height: M.dot)
        }
    }
}

// MARK: - 看距离

private struct DistanceLine: View {
    let progress: Double
    let endLabel: String
    let tint: Color
    let accent: Color

    private typealias M = LiveActivityProgressLine.Metrics

    var body: some View {
        VStack(spacing: M.labelSpacing) {
            GeometryReader { proxy in
                let inset = M.endRing / 2
                let usable = max(proxy.size.width - inset * 2, 0)
                let x = inset + usable * progress
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.3))
                        .frame(width: usable, height: M.lineWidth)
                        .offset(x: inset)
                    Capsule().fill(tint)
                        .frame(width: max(x - inset, 0), height: M.lineWidth)
                        .offset(x: inset)
                    Circle().fill(tint)
                        .frame(width: M.dot, height: M.dot)
                        .offset(x: inset - M.dot / 2)
                    Circle().stroke(accent, lineWidth: 3)
                        .frame(width: M.endRing, height: M.endRing)
                        .offset(x: proxy.size.width - M.endRing)
                    Circle().fill(tint)
                        .frame(width: M.runnerMarker, height: M.runnerMarker)
                        .overlay(
                            Image(systemName: "figure.run")
                                .font(.system(size: M.runnerIcon, weight: .bold))
                                .foregroundStyle(LiveActivityProgressLine.markerInk)
                        )
                        .offset(x: min(max(x - M.runnerMarker / 2, 0), proxy.size.width - M.runnerMarker))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: M.runnerMarker)
            HStack {
                Text(LiveActivityProgressLine.distanceStartLabel)
                    .font(.system(size: M.labelSize))
                    .foregroundStyle(tint.opacity(0.6))
                Spacer(minLength: 8)
                Text(endLabel)
                    .font(.system(size: M.labelSize, weight: .bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - 里程

private struct MileageLine: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: LiveActivityProgressLine.Metrics.mileageHeight)
    }
}
