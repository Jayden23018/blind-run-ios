import SwiftUI

// 徽章的奖章画法。形状与配色照稿子的 `medals.py`（负责人 2026-11-04 批准）：
// 陪跑次数 = 银边蓝面六边形，陪伴时长 = 金边深色圆章，评价 = 银边琥珀盾形；
// 未获得画同形状的灰线框。
//
// 🎨 渐变只取**已有**色值（`AppColors` / `AppColors.Flow` 的 `Tone`），不新增颜色。
// 取亮色档、不随明暗变：奖章是金属材质的图，暗色下换一套色就不是同一枚了。
// 未获得的灰线框例外，它是界面线条，跟随明暗。

// MARK: - 形状

/// 三种轮廓。路径在 100×100 的格子里写（与 `medals.py` 同一组坐标），按实际大小缩放。
enum VolunteerMedalOutline {
    case hexagon
    case circle
    case shield

    init(_ category: VolunteerBadgeCategory) {
        switch category {
        case .runs: self = .hexagon
        case .hours, .other: self = .circle
        case .rating: self = .shield
        }
    }
}

struct VolunteerMedalShape: Shape {
    let outline: VolunteerMedalOutline

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * s
        let oy = rect.midY - 50 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        switch outline {
        case .circle:
            path.addEllipse(in: CGRect(x: ox + 5 * s, y: oy + 5 * s, width: 90 * s, height: 90 * s))
        case .hexagon:
            // M50 4 L90 27 Q94 29.5 94 34 L94 66 Q94 70.5 90 73 L50 96 L10 73 Q6 70.5 6 66 L6 34 Q6 29.5 10 27 Z
            path.move(to: p(50, 4))
            path.addLine(to: p(90, 27))
            path.addQuadCurve(to: p(94, 34), control: p(94, 29.5))
            path.addLine(to: p(94, 66))
            path.addQuadCurve(to: p(90, 73), control: p(94, 70.5))
            path.addLine(to: p(50, 96))
            path.addLine(to: p(10, 73))
            path.addQuadCurve(to: p(6, 66), control: p(6, 70.5))
            path.addLine(to: p(6, 34))
            path.addQuadCurve(to: p(10, 27), control: p(6, 29.5))
            path.closeSubpath()
        case .shield:
            // M50 5 Q72 14 90 12 Q93 52 82 72 Q70 90 50 96 Q30 90 18 72 Q7 52 10 12 Q28 14 50 5 Z
            path.move(to: p(50, 5))
            path.addQuadCurve(to: p(90, 12), control: p(72, 14))
            path.addQuadCurve(to: p(82, 72), control: p(93, 52))
            path.addQuadCurve(to: p(50, 96), control: p(70, 90))
            path.addQuadCurve(to: p(18, 72), control: p(30, 90))
            path.addQuadCurve(to: p(10, 12), control: p(7, 52))
            path.addQuadCurve(to: p(50, 5), control: p(28, 14))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 材质

private enum VolunteerMedalPalette {
    static func color(_ rgb: UInt32) -> Color { Color(uiColor: UIColor(rgb: rgb)) }

    /// 银边：白 → 浅灰 → 描边灰 → 深灰。
    static let silverRim: [Color] = [
        .white,
        color(AppColors.Flow.progressTrackTone.light),
        color(AppColors.Flow.ghostStrokeTone.light),
        color(AppColors.activeRunSecondaryTextTone.light)
    ]
    /// 金边：浅暖 → 描边金 → 金 → 深金。
    static let goldRim: [Color] = [
        color(AppColors.Flow.warmCardTone.light),
        color(AppColors.Flow.ctaStrokeTone.light),
        color(AppColors.Flow.goldTone.light),
        color(AppColors.Flow.replyProgressUrgentTone.light)
    ]

    static func rim(_ category: VolunteerBadgeCategory) -> [Color] {
        category == .hours ? goldRim : silverRim
    }

    /// 面：中心亮、边缘深的径向渐变。
    static func face(_ category: VolunteerBadgeCategory) -> [Color] {
        switch category {
        case .runs, .other:
            return [color(AppColors.Flow.accentTone.dark), color(VolunteerSecondaryTint.blueTone.light)]
        case .hours:
            return [color(AppColors.Flow.statePausedTone.light), color(AppColors.activeRunSurfaceTone.light)]
        case .rating:
            return [color(AppColors.Flow.ctaTone.light), color(AppColors.Flow.replyProgressUrgentTone.light)]
        }
    }

    /// 刻字：深色圆章刻金字，其余刻白字。
    static func ink(_ category: VolunteerBadgeCategory) -> Color {
        category == .hours ? color(AppColors.Flow.goldTone.light) : .white
    }
}

// MARK: - 奖章

/// 一枚奖章。**整枚对读屏隐藏** —— 名字与状态由外面那一格说（一枚一个焦点）。
struct VolunteerBadgeMedal: View {
    let category: VolunteerBadgeCategory
    let engraving: String?
    let engravingUnit: String?
    let glyph: String?
    let isEarned: Bool
    let size: CGFloat

    init(item: VolunteerBadgeItem, size: CGFloat) {
        self.category = item.category
        self.engraving = item.engraving
        self.engravingUnit = item.engravingUnit
        self.glyph = item.glyph
        self.isEarned = item.state.isEarned
        self.size = size
    }

    private var outline: VolunteerMedalOutline { VolunteerMedalOutline(category) }

    var body: some View {
        ZStack {
            if isEarned {
                earnedBody
            } else {
                lockedBody
            }
            engravingView
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(isEarned ? 0.22 : 0), radius: size * 0.05, x: 0, y: size * 0.03)
        .accessibilityHidden(true)
    }

    private var earnedBody: some View {
        ZStack {
            VolunteerMedalShape(outline: outline)
                .fill(LinearGradient(
                    colors: VolunteerMedalPalette.rim(category),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            VolunteerMedalShape(outline: outline)
                .fill(RadialGradient(
                    colors: VolunteerMedalPalette.face(category),
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.6
                ))
                .scaleEffect(0.82)
            // 上沿一道高光，让金属面有弧度（`medals.py` 那条 `M22 30 Q50 14 78 30`）。
            Path { path in
                path.move(to: CGPoint(x: size * 0.22, y: size * 0.30))
                path.addQuadCurve(to: CGPoint(x: size * 0.78, y: size * 0.30), control: CGPoint(x: size * 0.5, y: size * 0.14))
            }
            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
        }
    }

    private var lockedBody: some View {
        ZStack {
            VolunteerMedalShape(outline: outline)
                .fill(AppColors.Flow.surfaceSubtle)
            VolunteerMedalShape(outline: outline)
                .stroke(AppColors.Flow.decorMuted, lineWidth: max(1.5, size * 0.03))
            VolunteerMedalShape(outline: outline)
                .stroke(AppColors.Flow.nodeStroke, lineWidth: max(1, size * 0.015))
                .scaleEffect(0.82)
        }
    }

    private var ink: Color {
        isEarned ? VolunteerMedalPalette.ink(category) : AppColors.Flow.decorMutedInk
    }

    @ViewBuilder
    private var engravingView: some View {
        if let engraving {
            VStack(spacing: 0) {
                Text(engraving)
                    .font(.system(size: size * (engraving.count <= 2 ? 0.34 : 0.27), weight: .heavy, design: .rounded))
                if let engravingUnit {
                    Text(engravingUnit)
                        .font(.system(size: size * 0.12, weight: .bold))
                }
            }
            .foregroundColor(ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .offset(y: size * 0.02)
        } else if let glyph {
            Image(systemName: glyph)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(ink)
        }
    }
}
