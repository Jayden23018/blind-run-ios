import SwiftUI

// MARK: - 列表里的一行

/// 陪跑员端固定搭档列表的一行：头像字、掩码名、第二行（连续周数 / 设为搭档日期 / 你已退出）、箭头。
///
/// 读屏标签挂在外层 `NavigationLink` 上（一行一个焦点），这里的字只管上屏。
struct VolunteerPartnerRowView: View {
    let row: PartnerRow
    let index: Int

    private var name: String { row.displayName(fallback: PartnerStreakCopy.unknownBlindName) }

    var body: some View {
        HStack(spacing: 12) {
            VolunteerPartnerAvatar(name: name, tint: avatarTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                detailLine
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// 有连续记录时「连续 3 周」用橙色，后半句灰色（稿子）。火苗是 SF Symbol，不是 emoji。
    @ViewBuilder
    private var detailLine: some View {
        if !row.hasOptedOut, let streak = row.streak {
            (Text(Image(systemName: "flame.fill")).foregroundColor(VolunteerSecondaryTint.streak)
                + Text(" 连续 \(streak.currentWeeks) 周").foregroundColor(VolunteerSecondaryTint.streak).fontWeight(.semibold)
                + Text(" · \(PartnerStreakCopy.volunteerBestText(streak))").foregroundColor(AppColors.textSecondary))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } else if let detail = PartnerStreakCopy.volunteerRowDetail(row) {
            Text(detail)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 头像底色轮换，只为把相邻两人分开；已退出的人一律灰。颜色不承载信息（第二行字在说）。
    private var avatarTint: Color {
        if row.hasOptedOut { return AppColors.textSecondary }
        let palette = [VolunteerSecondaryTint.blue, VolunteerSecondaryTint.duration, AppColors.Flow.statePaused]
        return palette[index % palette.count]
    }
}

/// 圆形头像，里面是姓氏（掩码名的第一个字）。纯装饰，读屏不念。
struct VolunteerPartnerAvatar: View {
    let name: String
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        Text(String(name.first ?? "?"))
            .font(.system(size: side * 0.45, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: side, height: side)
            .background(Circle().fill(tint))
            .accessibilityHidden(true)
    }
}

// MARK: - 搭档详情页

/// 一位搭档的页面（#697 新页，照健康 App「共享」点进一个人）。
///
/// 顶部大字名字 + 设为搭档的日期；火花卡把「3 / 7 周」画成 7 格、点亮 3 格（比一根细进度条好读）；
/// 三个操作分两组放在最下面 —— 举报、不再匹配一组，红色「退出固定搭档」单独一组。
///
/// 数据只有列表传进来的这一行，不另拉接口；退出与拉黑也交回列表去做（列表是唯一的数据源）。
struct VolunteerPartnerDetailView: View {
    let row: PartnerRow
    /// 成功返回 nil：这一页关掉，结果显示在列表顶部。失败返回原因，显示在退出按钮下面。
    let optOut: @MainActor @Sendable () async -> String?
    let onBlocked: @MainActor @Sendable () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsOptOutConfirm = false
    @State private var isOptingOut = false
    @State private var optOutError: String?

    private var displayName: String { row.displayName(fallback: PartnerStreakCopy.unknownBlindName) }
    private var spokenName: String { row.spokenName(fallback: PartnerStreakCopy.unknownBlindName) }
    private var canOptOut: Bool { row.isFavorite && !row.hasOptedOut && row.userId != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                header

                if let streak = row.streak, !row.hasOptedOut {
                    VolunteerPartnerStreakCard(streak: streak)
                }

                VolunteerSecondaryCard {
                    Text(PartnerStreakCopy.detailStreakRule)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let userId = row.userId,
                   let target = CounterpartSafetyGate.target(userId: userId, orderId: nil) {
                    CounterpartSafetyActions(
                        target: target,
                        spokenName: spokenName,
                        onBlocked: { await onBlocked() },
                        presentation: .groupedRows
                    )
                    // 换了人就换一份状态，「已不再匹配」不许串到下一位身上。
                    .id(target.userId)
                    .padding(.top, 8)
                }

                optOutSection
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
        // 二级页不挂标签栏（稿子没有；服务成就页同一条，末行曾被标签栏盖住半行）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerPartnerDetailView")
        // 🔴 二次确认必须把后果写进正文，不能只给「确定 / 取消」——
        // 退出是单方面的，且后端没有「撤销退出」端点。文案沿用改版前那一份。
        .alert(PartnerStreakCopy.optOutConfirmTitle, isPresented: $showsOptOutConfirm) {
            Button(PartnerStreakCopy.optOutConfirmAction, role: .destructive) {
                Task { await confirmOptOut() }
            }
            Button(PartnerStreakCopy.optOutCancel, role: .cancel) {}
        } message: {
            Text(PartnerStreakCopy.optOutConfirmMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName)
                .font(AppFonts.largeTitle())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(spokenName)
                .accessibilityAddTraits(.isHeader)
            if let favoritedAt = PartnerStreakCopy.favoritedAtText(row.favoritedAt) {
                Text(favoritedAt)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var optOutSection: some View {
        if canOptOut {
            Button(action: requestOptOut) {
                Text(PartnerStreakCopy.detailOptOutTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.destructive)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppColors.Flow.surface)
                    .clipShape(RoundedRectangle(cornerRadius: VolunteerSecondaryMetrics.cardRadius, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOptingOut)
            // 标题上屏不带名字（页面顶部就是名字），念出来那份带上，免得读屏用户不知道退的是谁。
            .accessibilityLabel(PartnerStreakCopy.optOutButtonTitle(spokenName))
            .accessibilityIdentifier("volunteerPartnerOptOutButton")
            .padding(.top, 8)

            if let optOutError {
                Text(optOutError)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("volunteerPartnerOptOutError")
            }
            VolunteerSecondaryFootnote(text: PartnerStreakCopy.detailOptOutFootnote)
        } else if row.hasOptedOut {
            VolunteerSecondaryFootnote(text: PartnerStreakCopy.detailOptedOutFootnote)
                .padding(.top, 8)
        }
    }

    private func requestOptOut() {
        showsOptOutConfirm = true
    }

    private func confirmOptOut() async {
        isOptingOut = true
        defer { isOptingOut = false }
        if let error = await optOut() {
            optOutError = error
            UIAccessibility.post(notification: .announcement, argument: error)
        } else {
            optOutError = nil
            dismiss()
        }
    }
}

// MARK: - 火花卡

/// 「连续陪跑 3 周」+ 格子。整张卡一个焦点：格子对读屏是空的，进度一律由那句话说。
private struct VolunteerPartnerStreakCard: View {
    let streak: PartnerStreakDisplay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cells: PartnerStreakCells { PartnerStreakCells(streak) }

    var body: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(
                    title: PartnerStreakCopy.streakCardTitle,
                    symbol: .system("flame.fill"),
                    tint: VolunteerSecondaryTint.streak
                )
                VolunteerValueText(parts: [("\(streak.currentWeeks)", PartnerStreakCopy.streakWeeksUnit)])
                Text(PartnerStreakCopy.detailStreakProgress(streak))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                cellGrid
                    .padding(.top, 4)
                Text(PartnerStreakCopy.detailStreakLegend(streak))
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(PartnerStreakCopy.streakCardTitle)，\(streak.currentWeeks) 周，\(PartnerStreakCopy.detailStreakProgress(streak))"
        )
        .accessibilityIdentifier("volunteerPartnerStreakCard")
    }

    /// 一行最多 10 格，多了折行。大字号下一行 5 格。
    private var cellGrid: some View {
        let perRow = max(1, min(cells.total, dynamicTypeSize.isAccessibilitySize ? 5 : 10))
        return VolunteerGrowIn { progress in
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: perRow),
                spacing: 6
            ) {
                ForEach(0..<cells.total, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppColors.Flow.progressTrack)
                        .overlay(alignment: .leading) {
                            if index < cells.lit {
                                // 点亮的格子从左往右长出来（`progress` 0 → 1）。
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(VolunteerSecondaryTint.streak)
                                    .scaleEffect(x: progress, y: 1, anchor: .leading)
                            }
                        }
                        .frame(height: 22)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
