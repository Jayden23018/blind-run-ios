import SwiftUI

// 盲人端固定搭档的一行与搭档详情页（#752，照健康 · 共享；定稿 `docs/ui/mockups/blind-partners-20261105/`）。
// 写法照陪跑员端 #697（`VolunteerPartnerRowView` / `VolunteerPartnerDetailView`），那两个不改。

// MARK: - 首字头像

/// 浅色圆底 + 同色姓氏（定稿）。颜色只为把相邻两人分开，不承载信息；退出的人一律灰。纯装饰，读屏不念。
struct BlindPartnerAvatar: View {
    let name: String
    let tint: Color
    var size: Size = .row

    enum Size {
        case row
        case header
    }

    @ScaledMetric(relativeTo: .body) private var rowSide: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var headerSide: CGFloat = 72

    var body: some View {
        let side = size == .row ? rowSide : headerSide
        Text(String(name.first ?? "?"))
            .font(size == .row ? .title3.weight(.semibold) : .largeTitle.weight(.semibold))
            .foregroundColor(tint)
            .frame(width: side, height: side)
            .background(Circle().fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }

    /// 按行号轮换的底色：橙、蓝、绿（定稿顺序）。
    static func tint(for row: PartnerRow, index: Int) -> Color {
        if row.hasOptedOut { return AppColors.textSecondary }
        let palette = [AppColors.warning, AppColors.primary, AppColors.success]
        return palette[index % palette.count]
    }
}

// MARK: - 列表里的一行

/// 头像、掩码名、第二行（火焰 +「连续 N 周」· 一起跑完 N 次 / 对方已退出 / 还不是固定搭档）、箭头。
///
/// 读屏标签挂在外层 `NavigationLink` 上（一行一个焦点），这里的字只管上屏。
struct BlindPartnerRowLabel: View {
    let row: PartnerRow
    let index: Int

    private var name: String { row.displayName(fallback: PartnerStreakCopy.unknownVolunteerName) }

    var body: some View {
        HStack(spacing: 12) {
            BlindPartnerAvatar(name: name, tint: BlindPartnerAvatar.tint(for: row, index: index))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                detailLine
            }
            Spacer(minLength: 8)
            SettingsChevron()
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 「连续 3 周」橙色半粗，后半句灰色（定稿）。火焰是 SF Symbol，不是 emoji。
    @ViewBuilder
    private var detailLine: some View {
        let trailing = PartnerStreakCopy.blindRowTrailing(row)
        if !row.hasOptedOut, let streak = row.streak {
            (Text(Image(systemName: "flame.fill")).foregroundColor(AppColors.warning)
                + Text(" 连续 \(streak.currentWeeks) 周").foregroundColor(AppColors.warning).fontWeight(.semibold)
                + Text(trailing.map { " · \($0)" } ?? "").foregroundColor(AppColors.textSecondary))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } else if let trailing {
            Text(trailing)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 搭档详情页

/// 一位搭档（或一起跑过的人）的页面。
///
/// 数据只有列表传进来的这一行，不另拉接口；收藏、取消、拉黑都交回列表去做（列表是唯一的数据源）。
/// 成功后这一页关掉，结果显示并播报在列表顶部；失败留在这一页，原因写在按钮下面
/// （列表那一侧已经播报过，这里不再念第二遍）。
struct BlindPartnerDetailView: View {
    let row: PartnerRow
    /// 头像底色要和列表那一行一致。
    let index: Int
    /// `true` = 设为固定搭档，`false` = 取消。成功返回 nil，失败返回给人看的原因。
    let setFavorite: @MainActor @Sendable (Bool) async -> String?
    let onBlocked: @MainActor @Sendable () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingRemoval: PartnerStreakCopy.RemoveFavoriteConfirmation?
    @State private var isWorking = false
    @State private var actionError: String?

    private var displayName: String { row.displayName(fallback: PartnerStreakCopy.unknownVolunteerName) }
    private var spokenName: String { row.spokenName(fallback: PartnerStreakCopy.unknownVolunteerName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let streak = row.streak, !row.hasOptedOut {
                    BlindPartnerStreakCard(streak: streak)
                }

                if !row.isFavorite, row.userId != nil {
                    addSection
                }

                if row.isFavorite, let count = row.completedRunsTogether, count > 0 {
                    GroupedCard {
                        SettingsRowLabel(
                            title: PartnerStreakCopy.blindTogetherRowTitle,
                            value: PartnerStreakCopy.blindTogetherRowValue(count),
                            showsChevron: false
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("blindPartnerTogetherRow")
                }

                if let userId = row.userId,
                   let target = CounterpartSafetyGate.target(userId: userId, orderId: nil) {
                    CounterpartSafetyActions(
                        target: target,
                        spokenName: spokenName,
                        onBlocked: {
                            // 先关这一页再重拉：这个人会从列表里消失，结果写在列表顶部。
                            dismiss()
                            await onBlocked()
                        },
                        presentation: .groupedRows,
                        groupedRowMinHeight: AppTouchTarget.blindPrimary
                    )
                    // 换了人就换一份状态，「已不再匹配」不许串到下一位身上。
                    .id(target.userId)
                }

                if row.isFavorite, row.userId != nil {
                    removeSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        // 名字画在内容里而不是导航栏：导航栏标题会被读屏原样念成「李星号」。
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindPartnerDetailView")
        // 🔴 每次都确认（负责人 2026-11-05 定）。后果写进正文，次要按钮不写「取消」。
        // 不额外播报：VoiceOver 自己会念 alert。
        .alert(
            pendingRemoval?.title ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { confirmation in
            Button(confirmation.confirm, role: .destructive) {
                pendingRemoval = nil
                Task { await perform(false) }
            }
            Button(confirmation.cancel, role: .cancel) { pendingRemoval = nil }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            BlindPartnerAvatar(
                name: displayName,
                tint: BlindPartnerAvatar.tint(for: row, index: index),
                size: .header
            )
            Text(displayName)
                .font(.title.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(spokenName)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = headerSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("blindPartnerDetailSubtitle")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// 退出了说退出；固定搭档说哪天设的；只一起跑过的人说一起跑完几次。
    private var headerSubtitle: String? {
        if row.hasOptedOut { return PartnerStreakCopy.partnerOptedOutSuffix }
        if row.isFavorite { return PartnerStreakCopy.favoritedAtText(row.favoritedAt) }
        return PartnerStreakCopy.blindTogetherText(row.completedRunsTogether)
    }

    /// 还不是固定搭档：64pt 主按钮（样式随 #749 的 `PrimaryButton` 走）+ 一行说明。
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrimaryButton(PartnerStreakCopy.blindAddTitle, isLoading: isWorking) {
                Task { await perform(true) }
            }
            .accessibilityLabel(PartnerStreakCopy.addFavoriteTitle(spokenName))
            .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
            .accessibilityIdentifier("blindAddFavoriteButton")
            GroupedCardFootnote(text: PartnerStreakCopy.blindAddFootnote)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            errorLine
        }
    }

    /// 红字「取消固定搭档」单独一组，每次先确认。
    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                pendingRemoval = PartnerStreakCopy.removeFavoriteConfirmation(
                    name: displayName,
                    hasOptedOut: row.hasOptedOut
                )
            } label: {
                Text(PartnerStreakCopy.blindRemoveTitle)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                    .background(AppColors.Flow.surface)
                    .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel(PartnerStreakCopy.blindRemoveSpoken(spokenName))
            .accessibilityIdentifier("blindRemoveFavoriteButton")
            .padding(.top, 8)

            GroupedCardFootnote(text: PartnerStreakCopy.blindRemoveFootnote)
            errorLine
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let actionError {
            Text(actionError)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .accessibilityIdentifier("blindPartnerDetailError")
        }
    }

    private func perform(_ isFavorite: Bool) async {
        isWorking = true
        defer { isWorking = false }
        if let error = await setFavorite(isFavorite) {
            actionError = error
        } else {
            actionError = nil
            dismiss()
        }
    }
}

// MARK: - 连续周数卡

/// 「连续一起跑 / 3 周 / 格子 / 规则」。整张卡一个焦点：格子对读屏是空的，进度一律由那句话说。
///
/// 和陪跑员端那张的区别：没有进页长出的动效（盲人端二级页只有系统推入 / 返回，交接书 §1）。
private struct BlindPartnerStreakCard: View {
    let streak: PartnerStreakDisplay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cells: PartnerStreakCells { PartnerStreakCells(streak) }

    var body: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(PartnerStreakCopy.blindStreakCardTitle)
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(AppColors.warning)

                VolunteerValueText(parts: [("\(streak.currentWeeks)", PartnerStreakCopy.streakWeeksUnit)])

                cellGrid

                Text(PartnerStreakCopy.blindStreakRule)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PartnerStreakCopy.blindStreakSpoken(streak))
        .accessibilityIdentifier("blindPartnerStreakCard")
    }

    /// 一行最多 10 格，多了折行；大字号下一行 5 格。不用 Lazy：懒加载的格子滚出屏幕就不渲染。
    private var cellGrid: some View {
        let perRow = max(1, min(cells.total, dynamicTypeSize.isAccessibilitySize ? 5 : 10))
        let rows = stride(from: 0, to: cells.total, by: perRow).map { start in
            Array(start..<min(start + perRow, cells.total))
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex], id: \.self) { index in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index < cells.lit ? AppColors.warning : AppColors.Flow.progressTrack)
                            .frame(height: 22)
                    }
                    // 末行不满时补空位，格子宽度与上一行一致。
                    ForEach(0..<(perRow - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear.frame(height: 22)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
