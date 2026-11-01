import SwiftUI

/// 选择默认出发地点。选中后之后的预约默认从这里出发。
struct BlindHomeStartPlacePage: View {
    let places: [ResolvedPlace]
    let selectedID: String?
    let onSelect: (ResolvedPlace?) -> Void
    let onAddFavorite: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                choiceRow("当前定位", isSelected: selectedID == nil) { onSelect(nil) }
                ForEach(places) { place in
                    choiceRow(place.title, isSelected: place.id == selectedID) { onSelect(place) }
                }
                BlindHomeQuickRow(
                    title: "添加常用地点",
                    hint: "搜索地点并收藏",
                    identifier: "blindHomeAddFavoritePlace",
                    action: onAddFavorite
                )
            }
            .padding(FlowMetrics.pageHorizontalPadding)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle("默认出发地点")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .flowFont(FlowFonts.homeCardRowTitle())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.Flow.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, FlowMetrics.bookingBlockHorizontalPadding)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeRowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
