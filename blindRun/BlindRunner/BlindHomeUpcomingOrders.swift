import SwiftUI

// MARK: - 首页同时有几张未完成预约（#825）

// 契约允许同时最多 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`），而 `GET /api/orders/active` 只给最早的一张。
// 「记录」里那一段「待进行的预约」11-07 按负责人要求删了（#824），第 2、3 张就只能在首页出现。
// 负责人 11-07 定的版式（草稿甲，`docs/ui/mockups/blind-home-multi-booking-20261107/`）：
// 深蓝卡区域的总高度保持「一张卡时」那么高，有几张就按个数平分。调研里没有先例
// （`docs/research/home-multiple-bookings-20261107.md`），这是负责人的决定。

enum BlindHomeUpcomingOrders {
    /// 首页要显示的全部未完成预约，计划开始早的在前。
    ///
    /// 判据用 `isActiveForBlindRunner`，与 `GET /api/orders/active` 的「还没走完」同一口径：
    /// 未知状态也算（宁可多列一张让用户点开看，不替他判成已结束）。没有计划开始的排最后。
    /// `active` 那份比列表新（WebSocket 会推进它），同号时用它，且它永远排第一 ——
    /// 求助判据、开跑提醒、实时推送都跟着它，屏幕上的第一张必须是同一张。
    ///
    /// `active` 为 nil 时（最早那张刚走完，WebSocket 推来终态）剩下的照样列出，等下次加载再选出新的最早一张。
    static func merge(active: OrderDetailResponse?, mine: [OrderDetailResponse]) -> [OrderDetailResponse] {
        let others = mine
            .filter { $0.orderId != active?.orderId && $0.status.isActiveForBlindRunner }
            .sorted { lhs, rhs in
                switch (lhs.plannedStart?.backendTimestamp, rhs.plannedStart?.backendTimestamp) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                default: return false
                }
            }
        return (active.map { [$0] } ?? []) + others
    }

    /// 进页播报的开头。只有一张时不说，播报与改版前逐字相同。
    static func countAnnouncement(count: Int) -> String {
        count >= 2 ? "你有 \(count) 张预约。最近一张：" : ""
    }

    /// 第 2、3 张没加载出来时的说明（屏幕上和播报里同一句）。
    static let othersFailedMessage = "其余的预约没有加载出来，请点重试加载。"
}

// MARK: - 紧凑卡

/// 两张或三张时的一张卡。**整张卡是一个按钮，也是一个读屏元素**，同 `BlindHomeOrderCard`。
///
/// 读屏第一个词是时间：同时有几张预约时，用户靠时间认「是哪一张」。已经出发的那张时间已过，先念状态。
struct BlindHomeCompactOrderContent: Equatable {
    /// 两张时各占一半，三张时各占三分之一。高度不同，能放的行不同。
    enum Size: Equatable {
        case half
        case third
    }

    let caption: String
    let timeText: String
    let placeText: String
    /// nil = 这一档不显示陪跑员行（三张时并进 `caption`）。
    let partnerText: String?
    let accessibilityLabel: String

    init(order: OrderDetailResponse, size: Size) {
        let partner = (order.volunteerName?.nilIfBlank).map { "陪跑员 \($0)" }
        switch size {
        case .half:
            caption = BlindHomeOrderCard.statusCaption(for: order)
            partnerText = partner ?? "正在匹配陪跑员"
        case .third:
            caption = [order.status.displayName, partner].compactMap { $0 }.joined(separator: " · ")
            partnerText = nil
        }
        timeText = BlindHomeOrderCard.timeText(for: order)
        placeText = order.startAddress?.nilIfBlank ?? "出发地点待确认"

        let spokenPartner = order.volunteerName?.nilIfBlank == nil
            ? "正在匹配陪跑员"
            : "陪跑员\(order.volunteerNameForSpeech)"
        let lead = order.status.isUnderwayForBlindRunner
            ? order.status.displayName
            : "\(order.plannedStartForAnnouncement ?? "预约时间待确认")，\(order.status.displayName)"
        accessibilityLabel = "\(lead)，出发地 \(placeText)，\(spokenPartner)"
    }
}

struct BlindHomeCompactOrderCard: View {
    let content: BlindHomeCompactOrderContent
    let size: BlindHomeCompactOrderContent.Size
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.caption)
                        .flowFont(FlowFonts.homeCardCaption())
                        .foregroundColor(AppColors.Flow.onNavySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(content.timeText)
                        .flowFont(size == .half ? Self.halfTime : Self.thirdTime, monospacedDigit: true)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .regular))
                            .accessibilityHidden(true)
                        Text(content.placeText)
                            .flowFont(FlowFonts.homeCardPlace())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(AppColors.Flow.onNavyTertiary)
                    .padding(.top, 6)
                    if let partner = content.partnerText {
                        Text(partner)
                            .flowFont(FlowFonts.homeCardRowTitle())
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .overlay(alignment: .top) {
                                // 同 `BlindHomeOrderCard.partnerRow` 的分隔线：深蓝上用白色低透明度。
                                Rectangle()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(height: 1)
                                    .padding(.top, 4)
                                    .accessibilityHidden(true)
                            }
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 整张卡可点。去掉了单张时的「打开订单」条，靠这个箭头告诉看得见的人。
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppColors.Flow.onNavyTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, FlowMetrics.homeCardPadding)
            .padding(.vertical, 16)
            // 平分出来的高度由外层布局给，这里铺满；可点区至少 64pt（盲人端门槛）。
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .leading)
            .background(AppColors.Flow.navy)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeCardRadius, style: .continuous))
            .flowCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("双击打开这张预约，查看进度或取消")
        .accessibilityIdentifier("blindRunnerHomeUpcomingOrderCard")
    }

    /// 两张时的大字时间。单张是 52（`FlowFonts.homeCardTime`），半高放不下。
    private static let halfTime: (CGFloat, Font.Weight, Font.TextStyle) = (40, .semibold, .largeTitle)
    /// 三张时的大字时间。
    private static let thirdTime: (CGFloat, Font.Weight, Font.TextStyle) = (30, .semibold, .title)
}

// MARK: - 平分布局

/// 第一个子视图是**量高度用的参照**（单张时的完整卡，隐藏、不进读屏），其余是要平分的卡。
///
/// 每张分到 `(参照高度 - 间距) / 张数`；某张放不下（大字号）时按它自己要的高度长高，
/// 整页由外层 `ScrollView` 滚动 —— 不裁字。参照随字号一起变，所以平分的总高度在各档字号下
/// 都等于「一张卡时那么高」。
struct BlindHomeEqualSplitLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = slotHeights(width: width, subviews: subviews)
        let total = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let reference = subviews.first else { return }
        reference.place(at: bounds.origin, proposal: .zero)
        var y = bounds.minY
        for (card, height) in zip(subviews.dropFirst(), slotHeights(width: bounds.width, subviews: subviews)) {
            card.place(
                at: CGPoint(x: bounds.minX, y: y),
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }

    private func slotHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        guard let reference = subviews.first, subviews.count > 1 else { return [] }
        let cards = subviews.dropFirst()
        let free = ProposedViewSize(width: width, height: nil)
        let total = reference.sizeThatFits(free).height
        let slot = (total - spacing * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        return cards.map { max(slot, $0.sizeThatFits(free).height) }
    }
}

/// 首页的预约卡区。一张时就是原来的 `BlindHomeOrderCard`，两三张时平分它的高度。
struct BlindHomeOrderStack: View {
    let orders: [OrderDetailResponse]
    var isFirstFocused: AccessibilityFocusState<Bool>.Binding
    let open: (OrderDetailResponse) -> Void

    private static let spacing: CGFloat = 12

    var body: some View {
        if orders.count == 1, let order = orders.first {
            BlindHomeOrderCard(order: order) { open(order) }
                .accessibilityFocused(isFirstFocused)
        } else if let first = orders.first {
            let size: BlindHomeCompactOrderContent.Size = orders.count == 2 ? .half : .third
            BlindHomeEqualSplitLayout(spacing: Self.spacing) {
                BlindHomeOrderCard(order: first, action: {})
                    .hidden()
                    .accessibilityHidden(true)
                ForEach(orders, id: \.orderId) { order in
                    let card = BlindHomeCompactOrderCard(
                        content: BlindHomeCompactOrderContent(order: order, size: size),
                        size: size
                    ) { open(order) }
                    if order.orderId == first.orderId {
                        card.accessibilityFocused(isFirstFocused)
                    } else {
                        card
                    }
                }
            }
        }
    }
}

#if DEBUG
private struct BlindHomeOrderStackPreview: View {
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        BlindHomeOrderStack(
            orders: [
                .preview(orderId: 1, status: .scheduledConfirmed, plannedStart: "2026-11-08T07:00:00", volunteerName: "张*"),
                .preview(orderId: 2, status: .pendingMatch, startAddress: "香蜜湖体育中心", plannedStart: "2026-11-12T18:30:00"),
                .preview(orderId: 3, status: .pendingMatch, startAddress: "莲花山公园", plannedStart: "2026-11-15T06:30:00"),
            ],
            isFirstFocused: $focused,
            open: { _ in }
        )
    }
}

#Preview("首页预约卡 · 3 张") {
    ScrollView {
        BlindHomeOrderStackPreview()
            .padding(16)
    }
    .background(AppColors.Flow.page)
}
#endif
