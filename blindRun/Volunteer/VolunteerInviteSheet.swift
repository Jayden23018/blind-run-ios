import SwiftUI

// MARK: - 邀请卡（设计交付文档 v3 §4.4.2 / §4.4.3）

/// 派单来了之后那张**底部卡**。替代了此前那个居中的全屏模态 `VolunteerDispatchOverlay`。
///
/// 🚩 **内容全部由 `VolunteerOrderFlowPresentation.make(dispatch:)` 或它用的同一批
/// 格式化函数算出来**，与「查看详情」那一页共用一份口径。抄第二份的表现是
/// 「卡片说明天 7:00、详情页说 9月18日 07:00」—— 那是 `RunPlanFormat.shortStart`
/// 注释里逐字记着的坑。
///
/// 🚩 **这一层不画四步进度条。** 它是一次打断：回复窗口内要让人一眼看完并决定；
/// 完整订单页是给「我想再看看」的人的第二跳。
///
/// 🔴 **2026-09-18 从 `.sheet` 改成自定义 overlay**（设计 §4.4.1「从底部升起」要 spring 回弹，
/// 而 `presentationDetents` 给不了）。改完之后**四件事变成这一层自己的责任**，
/// 一件都不能漏 —— 系统 sheet 原本白送这四样：
///
/// 1. 压暗层（`AppColors.Flow.scrim`，`.dim` 逐字）与点背景收起；
/// 2. 下滑收起；
/// 3. 高度由内容决定（`.presentationDetents([.fraction(0.67), .large])` 钉死的 0.67 正是
///    项目负责人在真机上看到的「底部一大片空白」）；
/// 4. **背景对读屏屏蔽** —— 见 `VolunteerTabView` 里的 `TabBarAccessibilityHider`
///    （SwiftUI 的 `.accessibilityHidden` 进不了 `TabView` 底下那棵 UIKit 树）。
///    overlay 不是真的模态容器，光靠 `.isModal` 兜不住，而「读屏能滑到看不见的东西」
///    在盲人端是实打实的缺陷。
struct VolunteerInviteSheet: View {
    @ObservedObject var viewModel: VolunteerHomeViewModel
    let onRespond: (Int64, OrderRespondAction) -> Void
    let onDecline: (Int64) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 打开时焦点落在标题行（§4.4.2「读屏：打开时焦点在标题行」）。
    @AccessibilityFocusState private var titleFocused: Bool

    /// 拖动中的位移。竖向只取正值（往上拖没有语义），横向只在多条邀请时跟手。
    @State private var dragOffset: CGSize = .zero
    /// 本次拖动锁定的方向。**按首次位移的主轴一次性锁死** —— 不锁的话斜着一划
    /// 会同时翻页又收起，而这两个动作的结果完全不同。
    @State private var dragAxis: DragAxis?

    private enum DragAxis { case vertical, horizontal }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if viewModel.isInviteSheetPresented {
                    // 压暗层与卡片是**两个并列的 `if`**，各自带各自的转场：
                    // 压暗层淡入、卡片从底部升起。合成一个 `if` 的话整块只会用一种转场，
                    // 于是压暗层也跟着从屏幕下缘滑上来。
                    AppColors.Flow.scrim
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissWithoutReplying() }
                        // 设计稿的「点空白处收起」在读屏里没有对应动作 ——
                        // VoiceOver 用户走的是转子里的「关闭」或直接两指擦除。
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    card
                        .frame(
                            maxHeight: geometry.size.height * FlowMetrics.inviteSheetMaxHeightFraction,
                            alignment: .bottom
                        )
                        .offset(x: dragOffset.width, y: dragOffset.height)
                        .gesture(dragGesture)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        // 开了「减弱动态效果」就瞬时到位（`nil` = 不动画），不做弹簧位移。
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82),
            value: viewModel.isInviteSheetPresented
        )
        .onChange(of: viewModel.isInviteSheetPresented) { presented in
            guard presented else { return }
            dragOffset = .zero
            dragAxis = nil
            titleFocused = true
        }
        // 队列翻到下一张时把焦点带过去。没有这一行的表现是：回复完一条之后卡片换了，
        // 而读屏焦点还停在已经不存在的那张卡上 —— VoiceOver 会跳回屏幕顶端从头念。
        .onChange(of: viewModel.currentInviteID) { _ in titleFocused = true }
    }

    // MARK: 白卡本体

    /// `.offer{background:#fff;border-radius:22px 22px 0 0;padding:14px 16px 24px;gap:8px}`。
    ///
    /// **贴底**：下两角不圆、背景一直铺到屏幕最下缘。`padding-bottom:24` 就是稿子给
    /// Home Indicator 留的那段距离，不要再叠一份安全区内边距。
    private var card: some View {
        // 装得下就按内容高度（第一个分支），装不下才滚（第二个分支）。
        // AX5 下一张完整的卡装不进一屏，而这一屏的每个字都要能看见 ——
        // 这正是原先 `.presentationDetents` 里 `.large` 那一档干的事。
        // ⚠️ 同样的写法在星火页上被真机无障碍审计判成「整页改不了字号」（2026-09-23，已验红），
        // 而这张卡没有审计用例覆盖 —— 很可能有同一个问题，见 `XinghuoMapView.overlay` 的改法。
        ViewThatFits(in: .vertical) {
            cardContent
            ScrollView { cardContent }
        }
        .background(sheetBackground)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("volunteerInviteSheet")
    }

    private var sheetBackground: some View {
        // 只圆上面两角。iOS 16 没有 `UnevenRoundedRectangle`（那是 17+），
        // 所以把整个圆角矩形往下多画两个半径、让下两角落到屏幕外面去。
        RoundedRectangle(cornerRadius: FlowMetrics.inviteSheetRadius, style: .continuous)
            .fill(AppColors.Flow.surface)
            .padding(.bottom, -FlowMetrics.inviteSheetRadius * 2)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: FlowMetrics.inviteRowSpacing) {
            grabber
            header

            if let invite = viewModel.currentInvite {
                VolunteerInviteCard(
                    invite: invite,
                    isResponding: viewModel.isRespondingToDispatch,
                    onAccept: { onRespond(invite.id, invite.order.dispatchRespondAction) },
                    onDecline: { onDecline(invite.id) },
                    onOpenOrder: { viewModel.openAcceptedOrder(orderID: invite.id) },
                    onDismiss: { viewModel.dismissInvite(orderID: invite.id) }
                )
            }
        }
        .padding(.top, FlowMetrics.inviteSheetTopPadding)
        .padding(.horizontal, FlowMetrics.inviteSheetHorizontalPadding)
        .padding(.bottom, FlowMetrics.inviteSheetBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 跑者那一行是 `GET /api/orders/available` 补回来的（`loadInviteSupplements`），
        // 而那条请求常常正好落在弹卡的 spring 还没走完的时候 —— 不加这一行的表现是
        // 卡片在升起途中**瞬间长高一截**，看着像动画卡了，其实是布局瞬移。
        // 开了「减弱动态效果」就瞬时到位，与本文件其余几处同一口径。
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: viewModel.currentInvite?.supplement != nil
        )
    }

    /// `.offer .grab` —— 自定义 overlay 没有系统那枚 `presentationDragIndicator`，自己画。
    private var grabber: some View {
        Capsule()
            .fill(AppColors.Flow.nodeStroke)
            .frame(width: FlowMetrics.inviteGrabWidth, height: FlowMetrics.inviteGrabHeight)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: 标题行 → 进度条 → 剩余时间

    /// 顺序是项目负责人 2026-09-18 当面定的：分页点**恒**占标题行右侧，
    /// 「还剩 X 秒回复」挪到进度条**下方**右对齐。
    ///
    /// 🔴 **那行字不许删。** 看不见屏幕的人靠它知道还剩多久 —— 进度条是纯视觉的
    /// （对读屏隐藏），删掉这行等于把倒计时从读屏用户手里拿走。
    @ViewBuilder
    private var header: some View {
        let invite = viewModel.currentInvite

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(VolunteerInviteCopy.sheetTitle(count: viewModel.invites.count))
                .flowFont(FlowFonts.inviteHeader())
                .foregroundColor(AppColors.Flow.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)

            Spacer(minLength: 0)

            pageDots
        }
        // 多张卡时给读屏一条**确定**能用的翻页路径。手势翻页对 VoiceOver 用户不可用：
        // 开了读屏之后单指拖动是「探索」，到不了下面那个 `DragGesture`。
        //
        // ⚠️ 用例只能断言这两个动作**存在**（无障碍树的形状）：`XCUIElement.tap()` 注入的是
        // 物理触摸，走不到 accessibility action —— 见记忆 `xcuitest-cannot-invoke-accessibility-actions`。
        // 行为那一半由 `VolunteerInviteQueue` 的单测直接调 view model 验。
        .accessibilityAction(named: "下一个邀请") { step(by: 1) }
        .accessibilityAction(named: "上一个邀请") { step(by: -1) }

        if let invite, invite.isAwaitingReply {
            replyProgress(invite)

            Text(VolunteerOrderFlowCopy.replyCountdown(seconds: invite.remainingSeconds))
                .flowFont(FlowFonts.inviteCountdown(), monospacedDigit: true)
                .foregroundColor(
                    invite.isUrgent ? AppColors.Flow.replyUrgentText : AppColors.Flow.secondaryText
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 分页点。**恒显示**，数量 = 邀请条数（项目负责人拍板；HTML 稿单条那屏没有点，不照它）。
    ///
    /// **纯装饰** —— 「第几个 / 共几个」已经在标题行的「N 个新邀请」里说过了，
    /// 再念一遍 N 个圆点是纯噪音。
    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.invites) { invite in
                let isCurrent = invite.id == viewModel.currentInvite?.id
                Capsule()
                    .fill(isCurrent ? AppColors.Flow.accent : AppColors.Flow.progressTrack)
                    // `.dots b{width:14px}` / `.dots i{width:6px}`，高度都是 6。
                    .frame(width: isCurrent ? 14 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    /// 回复进度条（§4.4.2 第 3 项，3pt，剩余时间占比）。
    ///
    /// **对读屏隐藏**：它和下面那行「还剩 X 秒回复」说的是同一件事，而那行是文字。
    /// 取值 ≥3:1 的理由与断言在 `FlowDesignSystemTests` 里 ——
    /// 设计稿给的 `#D99A00` 压这条底只有 1.96，照抄等于让它在低视力眼里消失。
    private func replyProgress(_ invite: VolunteerInviteState) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.Flow.progressTrack)
                Capsule()
                    .fill(invite.isUrgent ? AppColors.Flow.replyProgressUrgent : AppColors.Flow.accent)
                    .frame(width: geometry.size.width * invite.remainingFraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    // MARK: 拖动

    /// 一条手势管两件事，**按主轴分流**：竖着拖是收起，横着拖是翻页。
    ///
    /// 🚩 **收起不算回复**（§4.4.2）：邀请留在队列里，接单主页那张「N 个新邀请」卡还能点回来。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal
                        : .vertical
                }
                switch dragAxis {
                case .horizontal:
                    // 只有一条邀请时横滑不跟手 —— 跟了手又翻不了页，反馈是错的。
                    guard viewModel.invites.count > 1 else { return }
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                case .vertical:
                    // 往上拖没有语义（卡已经贴底了），所以只取正值。
                    dragOffset = CGSize(width: 0, height: max(0, value.translation.height))
                case .none:
                    break
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                    dragOffset = .zero
                }
                switch axis {
                case .vertical where value.translation.height > FlowMetrics.inviteDismissDragDistance:
                    dismissWithoutReplying()
                case .horizontal where value.translation.width <= -FlowMetrics.invitePageDragDistance:
                    step(by: 1)
                case .horizontal where value.translation.width >= FlowMetrics.invitePageDragDistance:
                    step(by: -1)
                default:
                    break
                }
            }
    }

    private func dismissWithoutReplying() {
        viewModel.isInviteSheetPresented = false
    }

    private func step(by offset: Int) {
        guard let current = viewModel.currentInvite?.id,
              let index = viewModel.invites.firstIndex(where: { $0.id == current }) else { return }
        let next = index + offset
        guard viewModel.invites.indices.contains(next) else { return }
        viewModel.currentInviteID = viewModel.invites[next].id
    }
}

// MARK: - 一张卡的内容

/// 单张邀请卡。三种形态在**同一张卡上原地切换**（§4.4.3「不关闭再弹新弹层」）：
/// 待回复 / 已约好 / 已失效。
///
/// 🚩 **「被别人接」那一种不做。** 它只在从「附近还没人接的」列表进入时才可能发生，
/// 而那条链路当前是关的（`MockAPIClient.swift` 对 `/api/orders/available` 恒返空数组，
/// 本 App 调它只为给这张卡补三项，不做列表 UI）。
/// 定向派单的失败只有一种：过期。
struct VolunteerInviteCard: View {
    let invite: VolunteerInviteState
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onOpenOrder: () -> Void
    let onDismiss: () -> Void

    @State private var showsDetail = false

    private var presentation: VolunteerOrderFlowPresentation {
        .make(
            dispatch: invite.order,
            remainingSeconds: invite.remainingSeconds,
            supplement: invite.supplement
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlowMetrics.inviteRowSpacing) {
            switch invite.outcome {
            case .none:
                awaitingContent
            case .accepted:
                acceptedContent
            case .expired:
                expiredContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(isPresented: $showsDetail) { detailPage }
    }

    // MARK: 待回复

    @ViewBuilder
    private var awaitingContent: some View {
        Text(presentation.title)
            .flowFont(FlowFonts.inviteTime())
            .foregroundColor(AppColors.Flow.primaryText)
            .fixedSize(horizontal: false, vertical: true)

        if let meetingPoint = invite.order.startAddress?.nilIfBlank {
            Text(meetingPoint)
                .flowFont(FlowFonts.invitePlace())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                // `.op{margin-top:-4px}` —— 地点贴住时间，两者是一组。
                .padding(.top, FlowMetrics.invitePlaceOverlap)
        }

        metrics
        runnerRow

        // 🔴 设计稿这里还有一条「赶路时间不足 30 分钟」的浅黄提示条，**不渲染，不是漏了**：
        // 「赶过来约 25 分钟」要路程估算，本 App 不做路线导航；而真正能预测「接下会失败」
        // 的判据是后端配置 `app.order.booking-buffer-minutes`（当前 60 分钟，接单那一刻
        // 冲突直接回 `VOLUNTEER_ALREADY_ENGAGED`），客户端拿不到。照设计稿写 30 分钟
        // 会让 30–60 分钟那一档连提示都没有就撞 409。已投 handoff。

        FlowActionButton(
            VolunteerOrderFlowCopy.acceptInvite,
            isLoading: isResponding,
            isEnabled: !isResponding,
            accessibilityHint: acceptHint,
            action: onAccept
        )
        .accessibilityIdentifier(
            invite.order.dispatchRespondAction == .interested
                ? "volunteerDispatchInterestedButton"
                : "volunteerDispatchAcceptButton"
        )

        HStack {
            Button(VolunteerOrderFlowCopy.declineInvite) { onDecline() }
                .accessibilityHint("直接回复去不了，不问原因、不计任何记录。5 秒内可以撤销")
                .accessibilityIdentifier("volunteerInviteDeclineButton")

            Spacer(minLength: 0)

            Button(VolunteerInviteCopy.detail) { showsDetail = true }
                .accessibilityHint("打开完整的陪跑订单页，倒计时继续走")
                .accessibilityIdentifier("volunteerDispatchDetailButton")
        }
        .flowFont(FlowFonts.inviteSecondaryAction())
        .foregroundColor(AppColors.Flow.accent)
        // `.two{padding:0 18px}`。**高度仍是 44** —— 稿子只给了字号，没给触达区，
        // 而这两枚是真的要按的。
        .padding(.horizontal, FlowMetrics.inviteSecondaryActionInset)
        .frame(minHeight: 44)
        .disabled(isResponding)
    }

    /// 「先聊聊」那一支要说清**还不是接单**：把 `INTERESTED` 当成接单的人会以为事情定了，
    /// 然后错过跑者那通电话 —— 而 20 分钟窗口过了这一单就换人了。
    ///
    /// 按钮**文字**两种情况相同（设计交付 v3 §5：主按钮就叫「接下这次陪跑」）：
    /// 陪跑员要做的决定是同一个，「先聊聊还是直接接」是后端的机制，不该变成两个按钮。
    private var acceptHint: String {
        invite.order.dispatchRespondAction == .interested
            ? "先锁定这一单并等跑者打电话给你，聊完双方都说合适才算接单"
            : "接下这一单并进入服务流程"
    }

    /// 三格数据（§4.4.2 第 6 项）。**缺哪格就不画哪格**，不摆「--」——
    /// 用户没填时后端整个键不出现，写「未填写」是把「不知道」显示成一个值。
    ///
    /// 🔴 **不画竖分隔线，底色是页面灰不是浅蓝**（`.m3{background:var(--ui-bg)}`）。
    /// 竖线把一块柔和的底切成了表格，而这三格不是表格，是三个并排的数。
    @ViewBuilder
    private var metrics: some View {
        let tiles: [MetricTile] = [
            invite.order.distanceKm.map {
                MetricTile(
                    label: VolunteerInviteCopy.distanceToStartLabel,
                    value: String(format: "%.1f", $0),
                    unit: "公里"
                )
            },
            RunPlanFormat.plannedDistanceParts(meters: invite.order.plannedDistanceMeters).map {
                MetricTile(
                    label: VolunteerOrderFlowCopy.plannedDistanceLabel,
                    value: $0.value,
                    unit: $0.unit
                )
            },
            invite.order.plannedPaceText.map {
                MetricTile(label: VolunteerOrderFlowCopy.paceLabel, value: $0, unit: nil)
            }
        ].compactMap { $0 }

        if !tiles.isEmpty {
            HStack(spacing: 0) {
                ForEach(tiles) { tile in
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(tile.value)
                                .flowFont(FlowFonts.inviteMetricValue())
                                .foregroundColor(AppColors.Flow.primaryText)
                            if let unit = tile.unit {
                                Text(unit)
                                    .flowFont(FlowFonts.inviteMetricUnit())
                                    .foregroundColor(AppColors.Flow.primaryText)
                            }
                        }
                        .multilineTextAlignment(.center)

                        Text(tile.label)
                            .flowFont(FlowFonts.inviteMetricLabel())
                            .foregroundColor(AppColors.Flow.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    // 读屏念「离你，3.2 公里」而不是屏幕上的「3.2 公里 / 离你」——
                    // 屏幕上值在上是为了扫读，念出来必须先说这是什么。
                    .accessibilityLabel(tile.spokenLabel)
                }
            }
            .padding(.vertical, FlowMetrics.inviteMetricTileVerticalPadding)
            .padding(.horizontal, FlowMetrics.inviteMetricTileHorizontalPadding)
            .frame(maxWidth: .infinity)
            .background(AppColors.Flow.page)
            .clipShape(
                RoundedRectangle(cornerRadius: FlowMetrics.inviteMetricTileRadius, style: .continuous)
            )
        }
    }

    /// 三格里的一格。值与单位分开存，是因为它们在稿子里是两个字号（`.m3 b` / `.m3 b small`）。
    private struct MetricTile: Identifiable {
        let label: String
        let value: String
        let unit: String?

        var id: String { label }
        var spokenLabel: String { "\(label)，\(value)\(unit.map { " \($0)" } ?? "")" }
    }

    /// 跑者行（§4.4.2 第 7 项）。**拿不到就整行不渲染。**
    ///
    /// 内容来自 `VolunteerInviteSupplement`：优先取派单推送自带的几项（后端 #306 起），
    /// 老服务端再由 `GET /api/orders/available` 补。补不到时不占位、不编：
    /// 给还没见面的陪跑员印一个猜的视力程度，见面第一下就会抓错人。
    ///
    /// 右边的「一起跑过 N 次 / 第一次一起跑」标签来自 `completedTogetherCount`（后端 #306），
    /// 后端没给时不显示。头像圆里仍是「跑」不是姓氏 —— 掩码姓名 `blindName` 是 #357 那一条，另做。
    @ViewBuilder
    private var runnerRow: some View {
        let summary = invite.supplement?.runnerSummary
        let together = invite.supplement?.togetherText
        if summary != nil || together != nil {
            HStack(spacing: 9) {
                FlowAvatar(
                    name: nil,
                    diameter: FlowMetrics.inviteAvatarDiameter,
                    background: AppColors.Flow.avatarBackground,
                    foreground: AppColors.Flow.avatarInitial,
                    placeholder: "跑"
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(VolunteerOrderFlowCopy.runnerLabel)
                        .flowFont(FlowFonts.inviteRunnerName())
                        .foregroundColor(AppColors.Flow.primaryText)
                    if let summary {
                        Text(summary)
                            .flowFont(FlowFonts.inviteRunnerDetail())
                            .foregroundColor(AppColors.Flow.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if let together {
                    Text(together)
                        .flowFont(FlowFonts.inviteRunnerDetail())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                ([VolunteerOrderFlowCopy.runnerLabel, summary, together].compactMap { $0 })
                    .joined(separator: "，")
            )
        }
    }

    // MARK: 已约好（§4.4.3「接下成功」）

    @ViewBuilder
    private var acceptedContent: some View {
        outcomeBadge(systemImage: "checkmark", tint: AppColors.Flow.successBadge)

        Text(VolunteerInviteCopy.acceptedTitle)
            .flowFont(FlowFonts.inviteTime())
            .foregroundColor(AppColors.Flow.primaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)

        Text(acceptedDetailLine)
            .flowFont(FlowFonts.invitePlace())
            .foregroundColor(AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        // 设计稿原话是「李明的全名和电话已放进订单」。**名字这一刻拿不到**
        //（`NEW_ORDER` 与 `AvailableOrderResponse` 都没有 `blindName`），
        // 换成「跑者」而不是留一个空位。
        Text(VolunteerInviteCopy.acceptedDetail)
            .flowFont(FlowFonts.invitePlace())
            .foregroundColor(AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        FlowActionButton(VolunteerInviteCopy.acceptedPrimary, action: onOpenOrder)
            .accessibilityIdentifier("volunteerInviteOpenOrderButton")

        Button(VolunteerInviteCopy.acceptedSecondary) { onDismiss() }
            .flowFont(FlowFonts.inviteSecondaryAction())
            .foregroundColor(AppColors.Flow.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("volunteerInviteBackToDispatchButton")
    }

    private var acceptedDetailLine: String {
        [presentation.title, invite.order.startAddress?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "　")
    }

    // MARK: 已失效（§4.4.3「已过期」与「在卡片打开期间过期」是同一张卡）

    @ViewBuilder
    private var expiredContent: some View {
        outcomeBadge(systemImage: "clock", tint: AppColors.Flow.secondaryText)

        Text(VolunteerInviteCopy.expiredTitle)
            .flowFont(FlowFonts.inviteTime())
            .foregroundColor(AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityAddTraits(.isHeader)

        Text(VolunteerInviteCopy.expiredDetail)
            .flowFont(FlowFonts.invitePlace())
            .foregroundColor(AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        FlowActionButton(VolunteerInviteCopy.expiredPrimary, action: onDismiss)
            .accessibilityIdentifier("volunteerInviteExpiredAcknowledgeButton")
    }

    /// 结果态那枚圆形图标。**对读屏隐藏** —— 紧跟着的标题已经把结果说清楚了。
    /// 靠**形状**区分成功与失效（对勾 / 时钟），不只靠颜色（WCAG 1.4.1）。
    private func outcomeBadge(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 26, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 58, height: 58)
            .background(tint, in: Circle())
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: 查看详情

    /// 完整的「邀请」订单页（v2：白色头卡 + 虚线引导绳），与其余各态同一个页面。
    ///
    /// 倒计时照常走：这一层是**同一次派单的另一种看法**，不是一个可以慢慢看的副本。
    ///
    /// ⚠️ 这是**从自定义 overlay 里再弹一层 `fullScreenCover`**。上一轮真机验过的是
    /// 「从 sheet 里弹」，换成 overlay 之后那条结论不自动成立 ——
    /// `blindRunUITests` 里那条点「查看详情」的用例必须在 overlay 版下重新跑通。
    private var detailPage: some View {
        VolunteerOrderFlowPage(
            presentation: presentation,
            // 派单载荷与 `AvailableOrderResponse` 都没有跑者姓名（`AGENTS.md` §8：
            // 接单前只给取值空间封闭的字段），头卡只放时间与三宫格。**不编一个名字**。
            hero: .make(invite: presentation),
            inviteMetrics: VolunteerOrderMetric.invite(invite.order),
            // 回到邀请卡，倒计时没有停。页面自带导航栏，不再套 `NavigationStack` 的那条。
            onBack: { showsDetail = false },
            onRowAction: { action in
                guard case .declineInvite = action else { return }
                showsDetail = false
                onDecline()
            },
            onPrimaryAction: {
                showsDetail = false
                onAccept()
            },
            isPrimaryLoading: isResponding,
            isPrimaryEnabled: !isResponding,
            footer: { EmptyView() }
        )
    }
}

// MARK: - 顶部横幅（§4.4.1「App 在前台，位于其他页面」）

/// 他不在接单主页时，新邀请只在头顶停 4 秒。
///
/// 🚩 **整条就是一枚按钮，不是「一块文字 + 一枚查看按钮」。** 两种写法在视觉上一样，
/// 但读屏下差别很大：拆开的话 VoiceOver 要右划两次才摸到那个动作，而它只活 4 秒。
/// 「查看」那两个字留在视觉上是因为不读屏的人需要看出这里可以点。
///
/// 🔴 **没有关闭按钮，也不该有。** 收起不等于回复 —— 邀请还在队列里、倒计时照常走，
/// 接单主页那张「N 个新邀请」卡是回来的路（§4.4.2「下滑或点背景：收起，不算回复」）。
/// 多一枚「×」会让人以为按下去就是拒绝了。
struct VolunteerInviteBanner: View {
    let invite: VolunteerInviteState
    let onView: () -> Void

    private var subtitle: String {
        let time = VolunteerOrderFlowPresentation.make(
            dispatch: invite.order,
            remainingSeconds: invite.remainingSeconds,
            supplement: invite.supplement
        ).title
        // 地点拿不到就只说时间 —— 不占位、不编一个集合点。
        guard let place = invite.order.startAddress?.nilIfBlank else { return time }
        return "\(time) · \(place)"
    }

    var body: some View {
        Button(action: onView) {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .foregroundColor(AppColors.Flow.cta)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerInviteCopy.bannerTitle)
                        .flowFont(FlowFonts.rowValueEmphasized())
                        .foregroundColor(AppColors.Flow.primaryText)
                    Text(subtitle)
                        .flowFont(FlowFonts.rowValue())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(VolunteerInviteCopy.bannerAction)
                    .flowFont(FlowFonts.rowValueEmphasized())
                    .foregroundColor(AppColors.Flow.cta)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.inviteSheetRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VolunteerInviteCopy.bannerTitle)，\(subtitle)")
        .accessibilityHint("双击查看这个邀请")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("volunteerInviteBanner")
    }
}

// MARK: - 「这次去不了」的撤销 toast（§4.4.3）

/// 底部那条 5 秒可撤销的提示。
///
/// 🔴 **撤销之所以能实现，是因为请求还没发出去。** 后端 `POST /{id}/respond` 只有三个
/// action，`handleDecline` 一进去就把这一单推给下一个人，**没有撤销入口** ——
/// 先发再撤是撤不回来的（见 `VolunteerHomeViewModel.declineInvite`）。
struct VolunteerDeclineUndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(VolunteerInviteCopy.declineToastText)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(.white)

            Spacer(minLength: 0)

            Button(VolunteerInviteCopy.declineToastUndo, action: onUndo)
                .flowFont(FlowFonts.rowValueEmphasized())
                .foregroundColor(AppColors.Flow.cta)
                // 撤销是这条 toast 存在的**唯一**理由，而它只活 5 秒 ——
                // 64pt 触达区在这里不是体例，是「点不中就真的拒绝了」。
                .frame(minWidth: 64, minHeight: 44)
                .accessibilityHint("取消这次「去不了」，把邀请放回来")
                .accessibilityIdentifier("volunteerDeclineUndoButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.Flow.navy)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .accessibilityElement(children: .contain)
    }
}
