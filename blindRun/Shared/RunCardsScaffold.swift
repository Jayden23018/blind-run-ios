import SwiftUI

// MARK: - 订单页 v8 卡片页骨架（两端共用）
//
// 盲人端 ⑦ 陪跑中 / ⑧ 已完成（#968）先做，陪跑员端跑步中 / 跑完了照同一套换（#972）。
// 两端同一个骨架、同一张彩色卡（`BlindRunHeroCard`）、同一套卡片底（`BlindRunCardSurface`），
// 彩色卡因此在两端、两屏都落在同一个位置、同一个大小。
// 数值照 `docs/ui/mockups/blind-run-finish-v8-20261112/c-revised.html`（`BlindRunCardsMetrics`）。
//
// 🔴 这里的视图**一律不写 `accessibilityIdentifier`**，由调用方按端写字面量：
// 守卫 `stale-ui-test-identifier` 只认字面量调用形式，参数化会让它看不见（理由同 `OrderFlowBottomActions.Owner`）。

/// 顶栏 → 可滚动的卡片列（标题、彩色卡、调用方的卡）→ 底栏。浅灰页底。
struct RunCardsScaffold<TopBar: View, Header: View, Content: View>: View {
    /// 卡与卡的间距：陪跑中 14，已完成 10。标题到彩色卡两屏都是 14，彩色卡因此在同一个位置。
    let gap: CGFloat
    let topBar: TopBar
    let bottom: OrderFlowBottomActions
    /// 点卡片下面的空白 = 按一次主按钮。`nil` = 空白不可点。
    var onTapBlank: (() -> Void)?
    let header: Header
    /// 彩色卡及以下的全部卡片、结果面。
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: gap) {
                        header
                            .padding(.bottom, BlindRunCardsMetrics.runningGap - gap)
                        content()
                        blankArea
                    }
                    .padding(.horizontal, BlindRunCardsMetrics.pagePadding)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .readableContentColumn()
                }
            }
            bottom
        }
        .background(AppColors.Flow.page)
    }

    /// 卡片与主按钮之间剩下的那一截。主按钮样子不变，可点范围扩到这里（盲人 v8 DECISION「版式」）。
    /// 对读屏隐藏：读屏用户走主按钮本身，这里再给一个元素只是多划一下。
    @ViewBuilder
    private var blankArea: some View {
        if let onTapBlank {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTapBlank)
                .accessibilityHidden(true)
        }
    }
}

/// 标题（「陪跑中」「跑完了」）+ 副标题一行（「和李*一起 · ● 定位正常」）+ 可选的第三行。
/// 只管样子；读屏合成、念法、identifier、焦点都由调用方挂。
struct RunCardsHeader: View {
    let title: String
    /// 「和李*一起」。屏幕上用掩码名。
    let companion: String
    /// 非 `nil` = 副标题后面接「 · ● 定位正常」。只在跑步中给。
    var isLocationFresh: Bool?
    /// 副标题下面再一行（陪跑员暂停时的「暂停期间不计志愿时长」）。
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .flowFont(BlindRunCardsMetrics.titleFont, monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(companion + (isLocationFresh == nil ? "" : " ·"))
                if let isLocationFresh {
                    Circle()
                        .fill(isLocationFresh ? AppColors.success : AppColors.warning)
                        .frame(width: FlowMetrics.locationDotDiameter, height: FlowMetrics.locationDotDiameter)
                    Text(isLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale)
                }
            }
            .flowFont(FlowV2Fonts.callout())
            .foregroundColor(AppColors.Flow.secondaryText)
            if let note {
                Text(note)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}
