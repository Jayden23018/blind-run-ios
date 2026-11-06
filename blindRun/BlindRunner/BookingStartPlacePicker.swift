import CoreLocation
import SwiftUI

/// 约跑页的「从哪出发？」（#821，v5）。
///
/// v4 是两个一模一样的白胶囊「当前位置 / 常用地点」，看不出区别，常用地点也只能用首页那一个默认的。
/// v5 照「默认出发地点」页（#817）的资料库圆排：当前定位（蓝箭头）、每个常用地点（按地名配图标、写离你几公里）、添加。
/// 选中的圆外一圈蓝环，下面写「这次从这里」—— 只管这一单，不改默认出发地点。
/// 辅助功能大字档一排四个圆放不下，改成一行一个的列表（同默认出发地点页 ④）。
struct BookingStartPlacePicker: View {
    let places: [ResolvedPlace]
    /// `nil` = 当前定位。
    let selectedPlaceID: String?
    /// 设备坐标（WGS84）。`nil` = 拿不到可信定位，不写距离。
    let deviceLocation: CLLocationCoordinate2D?
    /// 卡底那句：「人民公园东门附近 · 见面点电话里再定」。
    let detail: String
    let onSelectCurrent: () -> Void
    let onSelect: (ResolvedPlace) -> Void
    let onAdd: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 4)
    private var usesList: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        GroupedCard {
            if usesList {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset) }
                    listRow(item)
                }
            } else {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        BlindStartPlaceCircleButton(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            isSelected: item.isSelected,
                            accessibilityLabel: item.accessibilityLabel,
                            accessibilityHint: item.accessibilityHint,
                            identifier: item.identifier,
                            selectedTag: BookingStartPlaceCopy.selectedTag,
                            action: item.action
                        )
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset)
            detailRow
        }
    }

    // MARK: 格子

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let icon: BlindStartPlaceIcon
        let isSelected: Bool
        let accessibilityLabel: String
        let accessibilityHint: String?
        let identifier: String
        let action: () -> Void
    }

    private var items: [Item] {
        let isCurrentSelected = selectedPlaceID == nil
        var items = [Item(
            id: "current",
            title: BlindStartPlaceCopy.currentLocation,
            subtitle: BlindStartPlaceCopy.currentLocationFollows,
            icon: .currentLocation,
            isSelected: isCurrentSelected,
            accessibilityLabel: isCurrentSelected
                ? "\(BlindStartPlaceCopy.currentLocation)，\(BookingStartPlaceCopy.selectedSpoken)"
                : "\(BlindStartPlaceCopy.currentLocation)，\(BlindStartPlaceCopy.currentLocationFollows)",
            accessibilityHint: isCurrentSelected ? nil : BookingStartPlaceCopy.pickHint,
            identifier: "matchFirstStartCurrent",
            action: onSelectCurrent
        )]
        for (index, place) in places.enumerated() {
            let isSelected = place.id == selectedPlaceID
            let meters = BlindStartPlaceDistance.meters(from: deviceLocation, to: place)
            items.append(Item(
                id: place.id,
                title: place.title,
                subtitle: meters.map { BlindStartPlaceDistance.text(meters: $0) },
                icon: .favorite(title: place.title),
                isSelected: isSelected,
                accessibilityLabel: isSelected
                    ? "\(place.title)，\(BookingStartPlaceCopy.selectedSpoken)"
                    : [place.title, meters.map { BlindStartPlaceDistance.spoken(meters: $0) }].compactMap { $0 }.joined(separator: "，"),
                accessibilityHint: isSelected ? nil : BookingStartPlaceCopy.pickHint,
                identifier: "matchFirstStartFavorite_\(index)",
                action: { onSelect(place) }
            ))
        }
        // 收藏满了（`FavoritePlaceStore.capacity`）就不给「添加」：添加会把最旧的一条挤掉，在约跑页上做这件事太隐蔽。
        if places.count < FavoritePlaceStore.capacity {
            items.append(Item(
                id: "add",
                title: usesList ? BlindStartPlaceCopy.addSpoken : BlindStartPlaceCopy.add,
                subtitle: nil,
                icon: .add,
                isSelected: false,
                accessibilityLabel: BlindStartPlaceCopy.addSpoken,
                accessibilityHint: "搜索地点并收藏",
                identifier: "matchFirstStartAdd",
                action: onAdd
            ))
        }
        return items
    }

    /// 大字档的一行：52pt 圆，选中行左侧一道主色竖条 + 主色「这次从这里」（同默认出发地点页 ④）。
    private func listRow(_ item: Item) -> some View {
        Button(action: item.action) {
            BlindFavoritePlaceRowLabel(
                title: item.title,
                subtitle: item.isSelected ? BookingStartPlaceCopy.selectedTag : item.subtitle,
                icon: item.icon,
                isSelected: false,
                prominent: true,
                iconDiameter: 52,
                subtitleIsDefaultTag: item.isSelected
            )
            .overlay(alignment: .leading) {
                if item.isSelected {
                    Rectangle()
                        .fill(AppColors.primary)
                        .frame(width: 4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint(item.accessibilityHint ?? "")
        .accessibilityAddTraits(item.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(item.identifier)
    }

    private var detailRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundColor(AppColors.Flow.secondaryText)
                .accessibilityHidden(true)
            Text(detail)
                .font(.footnote)
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("matchFirstStartDetail")
    }
}

enum BookingStartPlaceCopy {
    static let selectedTag = "这次从这里"
    static let selectedSpoken = "这次从这里出发"
    static let pickHint = "这次从这里出发，不改默认出发地点"
}
