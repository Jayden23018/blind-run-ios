import SwiftUI

// MARK: - 陪跑员订单页 v2 通用组件
//
// 来源：交付包 `zhumangpao-handoff/01-design-tokens.md`「通用组件」，精确取值对照
// `reference/artboards/Main.dc.html`。主 / 次按钮不在这里 —— 它们是
// `FlowActionButton(style: .raisedPrimary / .outlined)`，与盲人端共用同一个组件。
//
// 与交付包不一样的地方（每一处都写在对应组件上）：
// 1. 求助胶囊加了 1.5pt `helpStroke` 描边（理由见 `FlowHelpPill`）。
// 2. 跑者卡「他写给陪跑员」改「写给陪跑员的话」—— 后端没有性别字段（对接说明 §2）。
// 3. 快捷回复高 64 不是 56（项目负责人 2026-09-26 裁决，见 `FlowMetrics` v2 一节）。

// MARK: 文字按钮

/// 无底色的文字按钮。取消类一律 `.neutral`（交付包 v3 禁止项：取消类用灰色文字）。
struct FlowTextButton: View {
    enum Tone {
        /// 15 semibold 次要灰。
        case neutral
        /// 15 bold 品牌蓝。
        case link
    }

    let title: String
    var tone: Tone = .neutral
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .flowFont((15, tone == .neutral ? .semibold : .bold, .callout))
                .foregroundColor(tone == .neutral ? AppColors.Flow.secondaryText : AppColors.Flow.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: FlowMetrics.v2TextButtonMinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHintIfPresent(accessibilityHint)
    }
}

// MARK: 求助胶囊

/// 导航栏右上角的「求助」。**所有陪跑员订单页都有，位置不变**（交付包 D1）。
///
/// 与交付包的差异：加了 1.5pt `helpStroke` 描边。填充 `#FDECEC` 压页面底只有 1.03:1，
/// 没有描边时它在低视力用户眼里是一段悬空的红字 —— 与 `FlowActionButton(.help)` 同一条理由，
/// 而这是紧急入口，可发现性比像素一致更重要。
///
/// 按下去去哪由调用方决定（`VolunteerOrderSOSMode`）：这个组件只负责「在那里、看得见、按得到」。
struct FlowHelpPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "shield")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text("求助")
                    .flowFont(FlowV2Fonts.callout(bold: true))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(AppColors.Flow.helpText)
            .padding(.horizontal, FlowMetrics.v2HelpPillHorizontalPadding)
            .frame(minHeight: FlowMetrics.v2TextButtonMinHeight)
            .background(AppColors.Flow.helpBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(AppColors.Flow.helpStroke, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("求助与安全")
        .accessibilityIdentifier("volunteerOrderHelpPill")
    }
}

// MARK: 导航栏

/// 订单页导航栏：左返回、中标题、右求助。左右各一个固定宽度的槽，
/// 这样标题始终居中、求助胶囊在任何状态下都在同一个位置。
///
/// 放大字号后两侧槽只增不减（`minWidth`），标题换行而不是把胶囊挤出屏幕。
struct FlowOrderNavBar: View {
    let title: String
    /// `nil` = 不放返回按钮（完成页）。
    var onBack: (() -> Void)?
    let onHelp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .frame(
                                width: FlowMetrics.v2TextButtonMinHeight,
                                height: FlowMetrics.v2TextButtonMinHeight,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                } else {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            .frame(minWidth: FlowMetrics.v2NavSlotWidth, alignment: .leading)

            Text(title)
                .flowFont((16, .bold, .headline))
                .foregroundColor(AppColors.Flow.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            FlowHelpPill(action: onHelp)
                .frame(minWidth: FlowMetrics.v2NavSlotWidth, alignment: .trailing)
        }
        .frame(minHeight: FlowMetrics.v2NavHeight)
    }
}

// MARK: 头卡

/// 订单页最上面那张卡。`.navy` 是全流程的主角（交付包 D5）；`.light` 只给邀请态。
struct FlowHeroCard<Content: View>: View {
    enum Style {
        case navy
        case light
    }

    let style: Style
    private let content: Content

    init(style: Style, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, FlowMetrics.v2HeroVerticalPadding)
        .padding(.horizontal, FlowMetrics.v2HeroHorizontalPadding)
        .background(style == .navy ? AppColors.Flow.navy : AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.orderCardRadius, style: .continuous))
        .flowCardShadow()
    }
}

// MARK: 标签

/// 小标签：「一起跑过 3 次」「待认证」。13 bold，**只用于标签**。
struct FlowTag: View {
    let text: String
    var background: Color = AppColors.Flow.surfaceSubtle
    var foreground: Color = AppColors.Flow.onBlueTint

    var body: some View {
        Text(text)
            .flowFont(FlowV2Fonts.tag())
            .foregroundColor(foreground)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: 跑者卡

/// 跑者信息卡。姓名一律是后端下发的掩码（`李*`），读屏念 `unmaskedForSpeech`（「李」）。
///
/// 四块各自是读屏元素，顺序与交付包 02 一致：身份 → 留言 → 写给陪跑员的话。
struct FlowRunnerCard: View {
    /// 屏幕上显示的名字（掩码）。
    let name: String
    /// 「全盲 · 引导绳 · 跑 5 公里」。
    let detail: String
    /// `nil` 或 0 时不显示标签。
    var togetherCount: Int?
    /// 跑者出发前的留言。`nil` / 空串不显示气泡。
    var message: String?
    /// 跑者自己写的「写给陪跑员」。为空时用 `fallbackHabits`。
    var preferenceText: String?
    /// v3 的结构化引导习惯，`preferenceText` 为空时的回退。也为空则整段不显示。
    var fallbackHabits: [String] = []

    private var spokenName: String {
        let spoken = name.unmaskedForSpeech
        return spoken.isEmpty ? "跑者" : spoken
    }

    private var countText: String? {
        guard let togetherCount, togetherCount > 0 else { return nil }
        return "一起跑过 \(togetherCount) 次"
    }

    private var trimmedMessage: String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private var preference: String? {
        if let text = preferenceText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return "“\(text)”"
        }
        let habits = fallbackHabits.filter { !$0.isEmpty }
        return habits.isEmpty ? nil : habits.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityRow

            if let trimmedMessage {
                Text(trimmedMessage)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(AppColors.Flow.surfaceSubtle, in: FlowBubbleShape())
                    .frame(maxWidth: 280, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(spokenName)说：\(trimmedMessage)")
            }

            if let preference {
                FlowSeparator()
                VStack(alignment: .leading, spacing: 6) {
                    Text("写给陪跑员的话")
                        .flowFont(FlowV2Fonts.subhead(bold: true))
                        .foregroundColor(AppColors.Flow.secondaryText)
                    Text(preference)
                        .flowFont(FlowV2Fonts.body())
                        .foregroundColor(AppColors.Flow.primaryText)
                        .lineSpacing(FlowV2Fonts.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, FlowMetrics.v2CardPadding)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.orderCardRadius, style: .continuous))
        .flowCardShadow()
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 12) {
            FlowAvatar(
                name: name,
                diameter: FlowMetrics.v2ListAvatarDiameter,
                background: AppColors.Flow.blueTint,
                foreground: AppColors.Flow.onBlueTint,
                placeholder: "跑"
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .flowFont(FlowV2Fonts.headline())
                    .foregroundColor(AppColors.Flow.primaryText)
                Text(detail)
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let countText {
                FlowTag(text: countText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [spokenName, detail.replacingOccurrences(of: " · ", with: "，"), countText.map { "你们\($0)" }]
                .compactMap { $0 }
                .joined(separator: "，")
        )
    }
}

/// 留言气泡：左上 4、其余 16。iOS 16 没有 `UnevenRoundedRectangle`（iOS 17 起），自己画。
struct FlowBubbleShape: Shape {
    var small: CGFloat = 4
    var large: CGFloat = FlowMetrics.v2ChipRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = min(small, rect.height / 2)
        let r = min(large, rect.height / 2, rect.width / 2)
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
        path.closeSubpath()
        return path
    }
}

// MARK: 地点行

/// 可点的单行卡：集合点 / 导航去集合点。**整行是一个按钮**，点击跳系统地图（v3 不做 App 内地图）。
struct FlowPlaceRow: View {
    enum Trailing {
        /// 「地图 ↗」
        case mapLink
        /// 单独一个 ↗
        case arrow
    }

    let systemImage: String
    let title: String
    var subtitle: String?
    var trailing: Trailing = .mapLink
    /// 读屏前缀，例如「集合点」「导航去集合点」。
    let accessibilityPrefix: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.Flow.accent)
                    .frame(width: FlowMetrics.v2IconBubbleDiameter, height: FlowMetrics.v2IconBubbleDiameter)
                    .background(AppColors.Flow.blueTint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .flowFont(FlowV2Fonts.callout(bold: true))
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .flowFont(FlowV2Fonts.subhead())
                            .foregroundColor(AppColors.Flow.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if trailing == .mapLink {
                        Text("地图").flowFont(FlowV2Fonts.callout(bold: true))
                    }
                    Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(AppColors.Flow.accent)
            }
            .padding(.horizontal, FlowMetrics.v2CardPadding)
            .padding(.vertical, 10)
            .frame(minHeight: FlowMetrics.v2PlaceRowMinHeight)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.v2RowRadius, style: .continuous))
            .flowCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: FlowMetrics.v2RowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel([accessibilityPrefix, title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，"))
        .accessibilityHint("双击在地图中打开")
    }
}

// MARK: 快捷回复

/// 「一键告诉李*」两列按钮。AX 字号下改竖排（交付包 02「动态字体」）。
///
/// 发送状态由调用方持有（「已发送」60 秒冷却是业务规则，不是组件的事）。
struct FlowQuickReplyGrid: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        var isSent: Bool = false
        var isEnabled: Bool = true
    }

    let title: String
    let items: [Item]
    let onTap: (Item) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .flowFont(FlowV2Fonts.subhead(bold: true))
                .foregroundColor(AppColors.Flow.secondaryText)
                .accessibilityAddTraits(.isHeader)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(items) { item in
                    button(for: item)
                }
            }
        }
        .padding(FlowMetrics.v2CardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.orderCardRadius, style: .continuous))
        .flowCardShadow()
    }

    private func button(for item: Item) -> some View {
        Button { onTap(item) } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isSent ? "checkmark" : "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .accessibilityHidden(true)
                Text(item.isSent ? "已发送" : item.title)
                    .flowFont((16, .bold, .body))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(AppColors.Flow.onBlueTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(minHeight: FlowMetrics.actionButtonMinHeight)
            .background(AppColors.Flow.blueTint)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.v2ChipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.isSent ? "\(item.title)，已发送" : item.title)
        .disabled(!item.isEnabled || item.isSent)
    }
}

// MARK: 在场胶囊

/// 「李*已到 3 号入口附近」。只在后端说「在」时出现（`runnerAtMeetingPoint == true`），
/// 其余时候整个不出现、也不留空位 —— 这是调用方的事，组件只管画。
///
/// 圆点外圈的呼吸是循环动效：项目负责人 2026-09-26 按交付包保留，
/// 「减弱动态效果」与 App 不在前台时静止（`FlowLoopingPulse`）。
struct FlowPresencePill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.Flow.presenceGreen)
                .frame(width: 8, height: 8)
                .background(
                    Circle()
                        .fill(AppColors.Flow.presenceGreen)
                        .frame(width: 16, height: 16)
                        .flowLoopingPulse(period: 1.6, from: 0.25, to: 0)
                )
                .accessibilityHidden(true)
            Text(text)
                .flowFont(FlowV2Fonts.callout(bold: true))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: 提醒条

/// 头卡下方的暖色提醒条：「已自动告诉李*你会晚到约 6 分钟」。**不用红色**（交付包 ③b）。
struct FlowNoticeBar: View {
    let text: String

    var body: some View {
        Text(text)
            .flowFont((15, .semibold, .callout))
            .foregroundColor(AppColors.Flow.warmCardTitle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, FlowMetrics.v2CardPadding)
            .background(AppColors.Flow.warmCard)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.v2ChipRadius, style: .continuous))
    }
}

// MARK: 循环动效

/// 透明度（可选再加缩放）在 `from` 与 `to` 之间循环。交付包 03「持续性动效」。
///
/// 三种情况下静止在 `from`：「减弱动态效果」打开、App 不在前台（`scenePhase != .active`）、
/// 视图不在屏幕上（`onDisappear`）—— 03 §六的性能要求。
struct FlowLoopingPulse: ViewModifier {
    let period: Double
    let from: Double
    let to: Double
    var scaleFrom: CGFloat = 1
    var scaleTo: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var phase = false

    private var isRunning: Bool { isVisible && !reduceMotion && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .opacity(isRunning && phase ? to : from)
            .scaleEffect(isRunning && phase ? scaleTo : scaleFrom)
            .animation(
                isRunning ? .easeOut(duration: period).repeatForever(autoreverses: false) : .default,
                value: phase
            )
            .onAppear { isVisible = true; restart() }
            .onDisappear { isVisible = false; phase = false }
            .onChange(of: isRunning) { _ in restart() }
    }

    private func restart() {
        phase = false
        guard isRunning else { return }
        DispatchQueue.main.async { phase = true }
    }
}

extension View {
    func flowLoopingPulse(
        period: Double,
        from: Double,
        to: Double,
        scaleFrom: CGFloat = 1,
        scaleTo: CGFloat = 1
    ) -> some View {
        modifier(FlowLoopingPulse(period: period, from: from, to: to, scaleFrom: scaleFrom, scaleTo: scaleTo))
    }
}

// MARK: - Previews

#Preview("v2 组件 · 默认") {
    FlowV2ComponentGallery()
}

#Preview("v2 组件 · 深色") {
    FlowV2ComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("v2 组件 · AX5") {
    FlowV2ComponentGallery()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("v2 组件 · SE + AX3") {
    FlowV2ComponentGallery()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 375, height: 667)
}

/// 示意数据只在这里出现。实际页面的姓名、时间、地点一律来自接口（交付包 00 §四）。
private struct FlowV2ComponentGallery: View {
    @State private var sent: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            FlowOrderNavBar(title: "陪跑订单", onBack: {}, onHelp: {})
                .padding(.horizontal, FlowMetrics.v2ScreenPadding - 8)
            ScrollView {
                VStack(spacing: FlowMetrics.v2SectionGap) {
                    FlowHeroCard(style: .navy) {
                        Text("已约好 · 明天早上")
                            .flowFont((14, .semibold, .subheadline))
                            .foregroundColor(AppColors.Flow.onNavyEyebrow)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("6:35").flowHeroNumber(FlowV2Fonts.heroM)
                            Text("出发").flowFont(FlowV2Fonts.heroUnit())
                        }
                        .foregroundColor(.white)
                        Text("骑车约 20 分钟，7:00 在 3 号入口见李*")
                            .flowFont(FlowV2Fonts.callout())
                            .foregroundColor(AppColors.Flow.onNavyBody)
                        FlowPresencePill(text: "李*已到 3 号入口附近")
                    }
                    FlowNoticeBar(text: "已自动告诉李*你会晚到约 6 分钟")
                    FlowRunnerCard(
                        name: "李*",
                        detail: "全盲 · 引导绳 · 跑 5 公里",
                        togetherCount: 3,
                        message: "明天见，谢谢你陪我跑！",
                        preferenceText: "我习惯你在我左边。过台阶和转弯前，提前说一声就好。"
                    )
                    FlowPlaceRow(
                        systemImage: "mappin",
                        title: "深圳湾公园 3 号入口",
                        accessibilityPrefix: "集合点",
                        action: {}
                    )
                    FlowQuickReplyGrid(
                        title: "一键告诉李*",
                        items: [
                            .init(id: "ALMOST_THERE", title: "我快到了", isSent: sent.contains("ALMOST_THERE")),
                            .init(id: "WAIT_5_MIN", title: "再等我 5 分钟", isSent: sent.contains("WAIT_5_MIN")),
                        ],
                        onTap: { sent.insert($0.id) }
                    )
                    FlowHeroCard(style: .light) {
                        Text("新的陪跑邀请")
                            .flowFont(FlowV2Fonts.subhead(bold: true))
                            .foregroundColor(AppColors.Flow.accent)
                        Text("周六 7:00").flowHeroNumber(FlowV2Fonts.heroS)
                            .foregroundColor(AppColors.Flow.primaryText)
                    }
                    HStack {
                        FlowTag(text: "待认证", background: AppColors.Flow.blueTint, foreground: AppColors.Flow.bluePressed)
                        FlowTag(text: "一起跑过 3 次")
                    }
                }
                .padding(.horizontal, FlowMetrics.v2ScreenPadding)
                .padding(.vertical, FlowMetrics.v2SectionGap)
            }
            VStack(spacing: 8) {
                FlowActionButton("我出发了", style: .raisedPrimary) {}
                FlowActionButton("我已经出发了", style: .outlined) {}
                FlowTextButton(title: "修改或取消") {}
                FlowTextButton(title: "查看跑步记录", tone: .link) {}
            }
            .padding(.horizontal, FlowMetrics.v2ScreenPadding)
            .padding(.bottom, 8)
        }
        .background(AppColors.Flow.page)
    }
}
