import SwiftUI

// 两端「我的」共用的方块、列表行、箭头、头像（陪跑员 #700 先做，盲人端 #711 复用）。
// 照健康 App「浏览」的版式，只学版式，图标和颜色用自己的（审核 5.2.5）。

enum SettingsTileLayout {
    /// AX3 及以上两列放不下「陪跑培训」四个字，改单列。
    static func tileColumnCount(for size: DynamicTypeSize) -> Int {
        size >= .accessibility3 ? 1 : 2
    }
}

/// 方块本身：左上图标、左下名称。图标只是装饰，读屏只念名称。
///
/// 底色是纯色，压白字，亮暗两档同值。不用渐变：渐变底在真机无障碍审计里判对比度不足（2026-11-05，#700）。
struct SettingsTileLabel: View {
    let title: String
    let systemImage: String
    let rgb: UInt32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .accessibilityHidden(true)
            Spacer(minLength: 14)
            Text(title)
                .font(.headline.weight(.bold)) // 稿子方块名是粗体；.headline 的中文半粗在真机上偏细
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .leading)
        .background(Color(uiColor: UIColor(rgb: rgb)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 列表里「标题 + 可选值 + 箭头」的一行。可点区由 `contentShape` 撑满整行，高度不低于 64pt
/// （记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
struct SettingsRowLabel: View {
    let title: String
    var value: String?
    var titleColor: Color = AppColors.textPrimary
    var showsChevron = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let value {
                Text(value)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                SettingsChevron()
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .accessibilityHidden(true)
    }
}

/// 「类别」小标题 + 两列方块（AX3 及以上单列）。方块本身由调用方给，读屏标签和去处各端不同。
struct SettingsTileGrid<Item: Identifiable, Tile: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let items: [Item]
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        let columns = SettingsTileLayout.tileColumnCount(for: dynamicTypeSize)
        let rows = stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            // 不用 LazyVGrid：懒加载的格子滚出屏幕就不在无障碍树里，UI 用例按标识找不到。
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[index]) { item in
                        tile(item)
                    }
                }
                // 同一排两块等高：一块换行时另一块跟着长。
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 「我的」顶上的头像卡：头像、名字、一行灰字、箭头。读屏标签、标识、去处由调用方挂。
struct ProfileAccountCardLabel: View {
    let name: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatarCircle(side: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            SettingsChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// 账户页顶部：大头像、名字（读屏标题）、一行角色说明。
struct ProfileAccountHeader: View {
    let name: String
    let roleLine: String

    var body: some View {
        VStack(spacing: 8) {
            ProfileAvatarCircle(side: 96)
            Text(name)
                .font(.title.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(roleLine)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// 头像：后端没有头像字段，画一个通用剪影。装饰，读屏不念。
struct ProfileAvatarCircle: View {
    let side: CGFloat

    var body: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(side * 0.24)
            .foregroundColor(.white)
            .frame(width: side, height: side)
            .background(Circle().fill(AppColors.Flow.decorMutedInk))
            .accessibilityHidden(true)
    }
}
