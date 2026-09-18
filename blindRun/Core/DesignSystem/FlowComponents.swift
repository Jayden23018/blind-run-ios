import SwiftUI

// MARK: - 卡片

extension View {
    /// 设计稿的两层阴影。见 `FlowMetrics.cardShadowNear/Far` 对 CSS `blur` 与 SwiftUI
    /// `radius` 不等价的说明。
    func flowCardShadow() -> some View {
        shadow(
            color: FlowMetrics.cardShadowNear.color,
            radius: FlowMetrics.cardShadowNear.radius,
            x: 0,
            y: FlowMetrics.cardShadowNear.y
        )
        .shadow(
            color: FlowMetrics.cardShadowFar.color,
            radius: FlowMetrics.cardShadowFar.radius,
            x: 0,
            y: FlowMetrics.cardShadowFar.y
        )
    }
}

/// 白色卡片容器。订单页的状态卡与信息列表卡都是它。
struct FlowCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = FlowMetrics.orderCardRadius, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(AppColors.Flow.surface)
            // `.continuous` 而不是默认的 `.circular`：设计稿是 24/26pt 的大圆角，
            // 在这个半径上两者的差别肉眼可见，而 iOS 自己的大圆角一律是 continuous。
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .flowCardShadow()
    }
}

/// 卡片内的分隔线。1pt 实线，纯装饰 —— 所以对读屏隐藏。
struct FlowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.Flow.separator)
            // 1pt 是设计稿值。`frame(height:)` 不受 `small-touch-target` 约束（它只查
            // `minHeight:`），但这一行确实不是触达目标，写在这里备查。
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - 头像

/// 圆形头像 + 姓氏首字。陪跑员没有头像图片（后端不提供），所以姓氏就是全部视觉内容。
///
/// **对读屏隐藏**：姓名在同一行的文字里已经有了，念一遍「张」再念一遍「陪跑员张伟」
/// 是纯重复。装饰性内容的标准处理。
struct FlowAvatar: View {
    let name: String?
    let diameter: CGFloat
    let background: Color
    let foreground: Color
    /// 拿不到姓名时圆里那个字。默认「陪」是跑者端在看陪跑员；陪跑员端在看跑者，传「跑」。
    ///
    /// 做成参数而不是在两端各画一枚头像：这个圆的尺寸、字号、底色、对读屏隐藏
    /// 四件事两端完全一样，不同的只有这一个字。
    var placeholder: String = "陪"

    /// 取姓氏。`nil` / 空名字给一个中性占位，**不给「?」** —— 问号在读屏被隐藏的前提下
    /// 只对视觉用户可见，而它传达的是「出错了」而不是「还没匹配到人」。
    private var initial: String {
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return placeholder }
        return String(first)
    }

    var body: some View {
        Text(initial)
            .flowFont(FlowFonts.avatarInitial(diameter: diameter))
            .foregroundColor(foreground)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - 进度条

/// 订单流程的四步进度：匹配 → 约好 → 出发 → 汇合。
///
/// **整条合成一个无障碍元素**，标签是「进度，第 N 步，共 4 步，<当前步骤名>」。
/// 拆成 4 个元素的后果是读屏用户要划 4 次才走完一条纯状态信息，而那 4 次里有 3 次
/// 念的是「还没到的步骤」。
///
/// **不可点**：它是状态展示，没有「跳到某一步」这回事。所以节点 22pt 不受 64pt 线约束。
///
/// 三种节点形态**靠形状区分而不是只靠颜色**（WCAG 1.4.1）：
/// 已完成 = 蓝色实心 + 白色对勾；当前 = 蓝色描边 + 蓝色圆点；未到达 = 灰色描边、空。
/// 所以不需要额外响应「不使用颜色区分」开关 —— 关掉颜色三者依然可辨。
struct FlowStepper: View {
    /// 0-based 当前步骤。
    let currentStep: Int
    let titles: [String]

    /// 动画由调用方通过 `withAnimation` 驱动（阶段 4），组件本身不带动画字面量。
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                stepColumn(index: index, title: title)
                if index < titles.count - 1 {
                    connector(isFilled: index < currentStep)
                }
            }
        }
        .padding(.top, FlowMetrics.stepperTopPadding)
        .padding(.horizontal, FlowMetrics.stepperHorizontalPadding)
        .padding(.bottom, FlowMetrics.stepperBottomPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(currentStep: currentStep, titles: titles))
    }

    /// 读屏标签。**抽成纯静态函数而不是留一个私有计算属性**，理由同
    /// `BlindLayout.decorativeMapHeight`：布局只有真机能验，但「第几步、共几步、叫什么」
    /// 是纯字符串拼接，不该也要开一次真机才知道对不对。见 `FlowDesignSystemTests`。
    ///
    /// `min/max` 夹一下不是防御性代码：映射表在后端加状态时会漏，落到这里的就是越界值，
    /// 而它念出来是「第 0 步」或「第 5 步，共 4 步」—— 对看不见屏幕的人那是错信息，
    /// 比崩掉更难发现。
    static func accessibilityLabel(currentStep: Int, titles: [String]) -> String {
        guard !titles.isEmpty else { return "进度" }
        let step = min(max(currentStep, 0), titles.count - 1)
        return "进度，第 \(step + 1) 步，共 \(titles.count) 步，\(titles[step])"
    }

    @ViewBuilder
    private func stepColumn(index: Int, title: String) -> some View {
        let isDone = index < currentStep
        let isCurrent = index == currentStep

        VStack(spacing: 6) {
            node(isDone: isDone, isCurrent: isCurrent)
            Text(title)
                .flowFont(FlowFonts.stepLabel(isCurrent: isCurrent))
                .foregroundColor(
                    // 未到达步骤的文字用 `secondaryText` 而不是设计稿的 `#8C93A3`
                    // （3.08:1，不达 WCAG 4.5）。见 `AppColors.Flow` 的类型注释第 1 条。
                    isDone || isCurrent ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        // 固定列宽只在默认字号下成立；放大字号后「匹配」两个字会被挤成两行再被裁。
        // 所以给的是**最小**宽度，让列随文字长大。
        .frame(minWidth: FlowMetrics.stepColumnWidth)
    }

    @ViewBuilder
    private func node(isDone: Bool, isCurrent: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isDone ? AppColors.Flow.accent : AppColors.Flow.surface)
            if !isDone {
                Circle()
                    .strokeBorder(
                        isCurrent ? AppColors.Flow.accent : AppColors.Flow.nodeStroke,
                        lineWidth: FlowMetrics.stepNodeStrokeWidth
                    )
            }
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            } else if isCurrent {
                Circle()
                    .fill(AppColors.Flow.accent)
                    .frame(width: FlowMetrics.stepNodeDotDiameter, height: FlowMetrics.stepNodeDotDiameter)
            }
        }
        .frame(width: FlowMetrics.stepNodeDiameter, height: FlowMetrics.stepNodeDiameter)
    }

    private func connector(isFilled: Bool) -> some View {
        Rectangle()
            .fill(isFilled ? AppColors.Flow.accent : AppColors.Flow.progressTrack)
            .frame(height: FlowMetrics.stepConnectorHeight)
            .frame(maxWidth: .infinity)
            // 节点直径 22 ⇒ 半径 11，减去线宽让连接线对齐节点圆心。
            .padding(.top, (FlowMetrics.stepNodeDiameter - FlowMetrics.stepConnectorHeight) / 2)
    }
}

// MARK: - 信息列表行

/// 信息列表的一行。三种形态：纯展示、可点（带箭头）、陪跑员（两行值）。
///
/// **可点行的最小高度是 64 而不是设计稿的 52** —— 见 `FlowMetrics` 类型注释第 2 条。
/// 纯展示行保留 52。
struct FlowInfoRow<Value: View>: View {
    enum Kind {
        /// 纯展示，不可点。
        case display
        /// 可点，行尾带箭头。
        case navigable(action: () -> Void)
    }

    let label: String?
    let kind: Kind
    /// 合并后的读屏标签。`nil` 时由 `label` 与 value 自动合成。
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let minHeight: CGFloat
    @ViewBuilder let value: Value

    init(
        label: String?,
        kind: Kind = .display,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        minHeight: CGFloat? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.minHeight = minHeight ?? {
            switch kind {
            case .display: return FlowMetrics.infoRowDisplayMinHeight
            case .navigable: return FlowMetrics.infoRowTappableMinHeight
            }
        }()
        self.value = value()
    }

    var body: some View {
        switch kind {
        case .display:
            rowContent(showsChevron: false)
                .accessibilityElement(children: accessibilityLabel == nil ? .combine : .ignore)
                .accessibilityLabelIfPresent(accessibilityLabel)
        case .navigable(let action):
            Button(action: action) {
                rowContent(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabelIfPresent(accessibilityLabel)
            .accessibilityHintIfPresent(accessibilityHint)
        }
    }

    /// 🔴 **`label == nil` 时不许有 `Spacer`。**
    ///
    /// 那一支的 value 是整行文字（「暂停接单」「修改或取消」「之后还有 N 次陪跑」），
    /// 它自己带 `.frame(maxWidth: .infinity, alignment: .leading)`。`Spacer` 和它**都是
    /// 无限可伸缩的**，于是 `HStack` 把剩余宽度对半分 —— 文字落在一个既不居中、
    /// 也不与上一行 label 左对齐的位置。真机上就是「看着怪，也说不出哪儿怪」。
    ///
    /// 设计稿 `png/01-首页-准入-主页-接单.png` 与 `png/03-订单页全流程.png` 上，
    /// 这类整行文字与带 label 的行**左边缘齐平**。
    ///
    /// ⚠️ **抓不成守卫也抓不成用例**：`.navigable` 行是 `.accessibilityElement(children: .ignore)`，
    /// 内部 `Text` 不进无障碍树，XCUITest 只能拿到整行 `Button` 的 frame（两种行都是满宽、
    /// 完全相同）。判据是"文字的左边缘在哪"，而那是一个渲染几何，无障碍树里看不见。
    private func rowContent(showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if let label {
                Text(label)
                    .flowFont(FlowFonts.rowLabel())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                value
            } else {
                value
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, FlowMetrics.infoRowHorizontalPadding)
        .frame(minHeight: minHeight) // guard:allow small-touch-target
        .contentShape(Rectangle())
    }
}

// MARK: - 底部操作按钮

/// 底部操作区的按钮。三种样式，**高度与圆角一致**，靠颜色 + 图标区分职责。
struct FlowActionButton: View {
    enum Style {
        /// 当前状态唯一的主操作。黄色。**全 App 只有这一处用黄色**，它就是「现在该按这个」。
        case primary
        /// 「求助与安全」。浅红底 + 深红字 + 描边。
        /// **实心红只留给求助中心里的「紧急求助」** —— 入口醒目，但不能让人以为按一下就报警。
        case help
        /// 次级操作。白底 + 灰描边。
        case ghost
    }

    let title: String
    let systemImage: String?
    let style: Style
    let isLoading: Bool
    /// 倒计时那三秒的「准备中」。
    ///
    /// 🔴 **走 `.disabled()`，不是在 `action` 里 `guard ... return`。** `.disabled()`
    /// 同时做两件事：阻断点击，**并且**给无障碍元素打上「不可用」—— VoiceOver 会念「变暗」。
    /// 静默 return 只做前一件，读屏里它仍是一个完全正常的按钮，盲人双击之后什么都不发生、
    /// 什么都不念，也就是红线里那句「点了没反应就是事故」。同一条理由见
    /// `BlindActiveRunView` 里那块红块的 `.disabled(coordinator.state.isBusy)`。
    let isEnabled: Bool
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .primary,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .flowFont(FlowFonts.actionButton())
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            // 文字放大后靠内容的固有高度顶开；64 只是下限，不是固定值。
            .padding(.vertical, 10)
            .frame(minHeight: FlowMetrics.actionButtonMinHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: strokeColor == .clear ? 0 : 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHintIfPresent(accessibilityHint)
        // 🔴 **`.disabled()` 必须挂在 `.accessibilityElement(children: .ignore)` 之后。**
        //
        // 反过来（原先就是反的）时，`.disabled` 打在**里面那个 `Button`** 上，而
        // `children: .ignore` 紧接着合成了一个**新的**无障碍元素并丢掉子元素的全部特征 ——
        // 「不可用」跟着一起丢。表现是：按钮真的点不动（`.disabled` 的交互那一半照常生效），
        // 但读屏里它仍是一个完全正常的按钮，**不念「变暗」**，盲人双击之后什么都不发生、
        // 什么都不念。而那正是这个组件的注释里承诺不会发生的事。
        //
        // 2026-09-17 由 `testVolunteerServiceRemainsInteractiveWhenTransitionConfirmationNeverReturns`
        // 红出来（`isEnabled` 恒为真）。在此之前全仓没有任何用例断言过某枚
        // `FlowActionButton` 是禁用的，所以这条承诺**三周里一次都没被验过** ——
        // 跑者端倒计时那三秒的「准备中」同样中招。
        .disabled(isLoading || !isEnabled)
    }

    private var foreground: Color {
        switch style {
        case .primary: return AppColors.Flow.onCTA
        case .help: return AppColors.Flow.helpText
        case .ghost: return AppColors.Flow.primaryText
        }
    }

    private var background: Color {
        switch style {
        // 不可用的黄按钮换**具名浅黄**而不是降透明度：那三秒里这枚按钮的颜色
        // 是「现在还不能按」唯一的视觉状态，见 `AppColors.Flow.ctaDisabled`。
        case .primary: return isEnabled ? AppColors.Flow.cta : AppColors.Flow.ctaDisabled
        case .help: return AppColors.Flow.helpBackground
        case .ghost: return AppColors.Flow.surface
        }
    }

    /// 主按钮**不描边**：黄底压页面底 1.50:1，边界靠的是 18pt Semibold 的达标标签
    /// （10.57:1）—— W3C Understanding 1.4.11 对自带达标文字标签的控件豁免边界比。
    /// 求助按钮不同：它的填充压页面底只有 1.05:1，没有描边就没有按钮形状。
    private var strokeColor: Color {
        switch style {
        case .primary: return .clear
        case .help: return AppColors.Flow.helpStroke
        case .ghost: return AppColors.Flow.ghostStroke
        }
    }
}

// MARK: - 可选无障碍属性

extension View {
    /// `nil` 时不加修饰符。
    ///
    /// 直接写 `.accessibilityLabel(text ?? "")` 是错的：空串会**覆盖**掉自动合成的标签，
    /// 结果是 VoiceOver 聚焦到这个元素时一个字都不念 —— 而那看起来和「没加修饰符」一样。
    @ViewBuilder
    func accessibilityLabelIfPresent(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            accessibilityLabel(text)
        } else {
            self
        }
    }

    @ViewBuilder
    func accessibilityHintIfPresent(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            accessibilityHint(text)
        } else {
            self
        }
    }
}

// MARK: - Previews

#Preview("组件 · 默认字号") {
    FlowComponentGallery()
}

#Preview("组件 · AX5") {
    FlowComponentGallery()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("组件 · 深色") {
    FlowComponentGallery()
        .preferredColorScheme(.dark)
}

/// Preview 用的组件画廊。抽成具名类型而不是写在 `#Preview` 闭包里，是为了三个 Preview
/// 共用同一份内容 —— 抄三遍的话改一处就会漏两处，而 Preview 的漂移没人会发现。
private struct FlowComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { step in
                    FlowCard {
                        FlowStepper(currentStep: step, titles: ["匹配", "约好", "出发", "汇合"])
                    }
                }

                FlowCard {
                    VStack(spacing: 0) {
                        FlowInfoRow(label: "时间") {
                            Text("明天 7:00")
                                .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                                .foregroundColor(AppColors.Flow.primaryText)
                        }
                        FlowSeparator()
                        FlowInfoRow(
                            label: "集合地点",
                            kind: .navigable(action: {}),
                            accessibilityLabel: "集合地点，深圳湾公园 3 号入口",
                            accessibilityHint: "双击查看地点详情"
                        ) {
                            Text("深圳湾公园 3 号入口")
                                .flowFont(FlowFonts.rowValue())
                                .foregroundColor(AppColors.Flow.primaryText)
                        }
                    }
                }

                HStack(spacing: 12) {
                    FlowAvatar(
                        name: "张伟",
                        diameter: FlowMetrics.avatarDiameter,
                        background: AppColors.Flow.avatarBackground,
                        foreground: AppColors.Flow.avatarInitial
                    )
                    FlowAvatar(
                        name: nil,
                        diameter: FlowMetrics.homeVolunteerAvatarDiameter,
                        background: AppColors.Flow.navyAvatar,
                        foreground: .white
                    )
                }

                VStack(spacing: FlowMetrics.actionButtonSpacing) {
                    FlowActionButton("打电话给张伟", systemImage: "phone.fill", style: .primary) {}
                    FlowActionButton("求助与安全", systemImage: "shield", style: .help) {}
                    FlowActionButton("继续等待", style: .ghost) {}
                }
            }
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .padding(.vertical, 24)
        }
        .background(AppColors.Flow.page)
    }
}
