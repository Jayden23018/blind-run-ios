import SwiftUI

// 陪跑员二级页（固定搭档、服务成就、评分、徽章）共用的卡片语言。
// 稿子：`docs/ui/mockups/volunteer-secondary-pages-20261104/`（负责人 2026-11-04 批准 v3，#697）。
//
// 照首页 v3（#696）的写法：浅灰页底 `Flow.page`、白卡 `Flow.surface`、圆角 22、平的不带阴影、
// 卡名彩色 + 图标。#696 合并前它的 `VolunteerHomeCard` 在 main 上不存在，所以这里先有一份；
// ponytail: #696 合并后改用 `VolunteerHomeCard` / `VolunteerHomeCardHeader`，删掉这两个。

// MARK: - 卡名色

/// 卡名色的角色 → **现有**色值。不新增颜色（`docs/ui/design-direction.md` §2）。
///
/// 首页 v3 的天青 / 橙 / 琥珀在 #696 的 `AppColors.VolunteerHome` 里，main 上还没有。
/// 这里只拼已有的值：
/// - 陪伴时长（天青）：亮色 `Flow.stateRunning`（`#0A6B72`，跑步中头卡那一色），
///   暗色 `paceMid`（`#19B3A6`）—— `stateRunning` 暗色档压 `#1C1C1E` 不到 4.5:1，不能当字。
/// - 连续陪跑（橙）：`warning`。
/// - 评分（琥珀）：`Flow.replyUrgentText`。
/// - 里程、星级、陪跑次数（蓝）：`primary`。
///
/// 卡名是字，压白卡与 `#1C1C1E` 卡都要 4.5:1，`VolunteerSecondaryStyleTests` 逐色算。
/// ponytail: #696 合并后改指 `AppColors.VolunteerHome.*`，与首页同一组色。
enum VolunteerSecondaryTint {
    static let durationTone = AppColors.Tone(
        light: AppColors.Flow.stateRunningTone.light,
        dark: AppColors.paceMidTone.dark
    )
    static let streakTone = AppColors.tones.first { $0.name == "warning" }!.tone
    static let ratingTone = AppColors.Flow.replyUrgentTextTone
    static let blueTone = AppColors.tones.first { $0.name == "primary" }!.tone

    static let duration = color(durationTone)
    /// 写在天青横条里的字：亮色天青压白字、暗色天青（`paceMid`，浅）压黑字，两档都过 4.5:1。
    static let onDurationTone = AppColors.Tone(light: 0xFFFFFF, dark: 0x000000)
    static let onDuration = color(onDurationTone)
    static let streak = AppColors.warning
    static let rating = AppColors.Flow.replyUrgentText
    static let blue = AppColors.primary

    /// 压在卡上的字色要对照的两种卡底（亮 `Flow.surface` 白、暗 `#1C1C1E`）。
    static let all: [(name: String, tone: AppColors.Tone)] = [
        ("duration", durationTone),
        ("streak", streakTone),
        ("rating", ratingTone),
        ("blue", blueTone)
    ]

    private static func color(_ tone: AppColors.Tone) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        })
    }
}

// MARK: - 尺寸

enum VolunteerSecondaryMetrics {
    /// 稿子 `.card{border-radius:22px}`，与首页 v3 同值。
    static let cardRadius: CGFloat = 22
    static let cardPadding = EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)
    static let sectionSpacing: CGFloat = 12
    /// 进页长出的时长。稿子：约 0.6 秒，只播一次。
    static let growDuration: Double = 0.6
}

// MARK: - 卡片

/// 白色圆角卡片。边界靠白卡压在浅灰底上，不带阴影（健康 App 摘要页的做法）。
struct VolunteerSecondaryCard<Content: View>: View {
    var padding = VolunteerSecondaryMetrics.cardPadding
    var background: Color = AppColors.Flow.surface
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerSecondaryMetrics.cardRadius, style: .continuous))
    }
}

/// 卡名图标。SF Symbols 之外只有「累计里程」一种自绘（负责人 2026-11-04：不能用默认图标）。
enum VolunteerSecondarySymbol: Equatable {
    case system(String)
    case route
}

/// 卡片左上角的「图标 + 卡名」，右边可选一行灰字和箭头。
///
/// 🚩 **箭头只给真有去处的卡**：没有去处的卡画箭头，就是「点了没反应」（#694 同一条）。
struct VolunteerSecondaryCardHeader: View {
    let title: String
    let symbol: VolunteerSecondarySymbol
    let tint: Color
    var meta: String?
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 图标只是装饰：卡名就在旁边，不靠颜色也不靠图标传达（WCAG 1.4.1）。
            symbolView
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let meta {
                Text(meta)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(tint)
    }

    @ViewBuilder
    private var symbolView: some View {
        switch symbol {
        case .system(let name):
            Image(systemName: name)
                .font(.subheadline.weight(.semibold))
        case .route:
            VolunteerRouteGlyph(tint: tint)
        }
    }
}

/// 卡片外的小节标题（「搭档」「徽章」「关于服务成就」）。
struct VolunteerSecondarySectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppFonts.title())
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 卡片下面的灰色脚注。
struct VolunteerSecondaryFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
}

// MARK: - 累计里程图标

/// 「空心起点 → 弯曲路线 → 实心定位点」。和首页「最近陪跑」卡的路线缩略图同一种画法：
/// 圆头细线、起点空心圆、终点实心点（负责人 2026-11-04：不能用默认图标）。
///
/// 尺寸跟字号走：放在 `.subheadline` 那一行里，用 `@ScaledMetric` 跟随 Dynamic Type。
struct VolunteerRouteGlyph: View {
    let tint: Color
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let line = max(1.4, w * 0.11)
            let start = CGPoint(x: w * 0.18, y: h * 0.80)
            let end = CGPoint(x: w * 0.80, y: h * 0.24)

            var route = Path()
            route.move(to: CGPoint(x: start.x + w * 0.10, y: start.y - h * 0.04))
            route.addCurve(
                to: CGPoint(x: end.x - w * 0.10, y: end.y + h * 0.10),
                control1: CGPoint(x: w * 0.78, y: h * 0.92),
                control2: CGPoint(x: w * 0.12, y: h * 0.30)
            )
            context.stroke(route, with: .color(tint), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))

            let startRadius = w * 0.13
            let startRect = CGRect(x: start.x - startRadius, y: start.y - startRadius, width: startRadius * 2, height: startRadius * 2)
            context.stroke(Path(ellipseIn: startRect), with: .color(tint), lineWidth: line)

            let endRadius = w * 0.16
            let endRect = CGRect(x: end.x - endRadius, y: end.y - endRadius, width: endRadius * 2, height: endRadius * 2)
            context.fill(Path(ellipseIn: endRect), with: .color(tint))
        }
        .frame(width: side, height: side)
    }
}

// MARK: - 进度条

/// 圆头进度条。系统 `ProgressView` 只有 4pt 高、颜色不好控；稿子是 6–8pt 圆头。
///
/// 对 VoiceOver 是空的（`accessibilityHidden`）—— 进度一律另有一行文字说。
struct VolunteerSecondaryProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        VolunteerGrowIn { progress in
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.Flow.progressTrack)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, proxy.size.width * min(1, max(0, fraction)) * progress))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - 进页长出

/// 图表、圆环、进度条进页面时从 0 长到数值，约 0.6 秒，**只播一次**。
///
/// 「减弱动态效果」打开时直接给最终值（`progress = 1`）。不做数字滚动：读屏会念到中间值。
struct VolunteerGrowIn<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasGrown = false
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        content(reduceMotion || hasGrown ? 1 : 0)
            .onAppear {
                guard !hasGrown else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: VolunteerSecondaryMetrics.growDuration)) {
                    hasGrown = true
                }
            }
    }
}
