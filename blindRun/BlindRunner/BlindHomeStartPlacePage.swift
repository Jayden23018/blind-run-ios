import CoreLocation
import SwiftUI

/// 选择默认出发地点。选中后之后的约跑默认从这里出发。
///
/// #817 照苹果地图搜索面板的「资料库」重做（定稿 `docs/ui/mockups/start-place-library-20261106/`）。从上到下：
/// 1. 「现在默认从这里出发」只读卡 —— 读屏进页第一句就知道现在用的是哪里，不用逐个听到「已选定」那一个；
/// 2. 「常用地点」卡：一排 60pt 圆（当前定位 / 各收藏 / 添加），4 列，多了换行不横滑（横滑会把收藏藏到屏幕外）；
///    有收藏时卡底「全部 N 个常用地点 ›」进列表页（可删除）；
/// 3. 「最近跑过的地点」：点一行 = 收藏并设为默认，和「添加常用地点」页同一个动作。没跑过不显示。
///
/// 辅助功能大字档（`isAccessibilitySize`）一排四个圆放不下，改成一行一个的列表。
/// 按字号档切换，不用 `ViewThatFits`（它在两页上让字号审计误判过，记忆 viewthatfits-fails-dynamic-type-audit）。
struct BlindHomeStartPlacePage: View {
    let places: [ResolvedPlace]
    let selectedID: String?
    /// 设备当前坐标（WGS84）。nil = 拿不到可信定位，收藏不写距离。
    let deviceLocation: CLLocationCoordinate2D?
    let isCurrentLocationUnavailable: Bool
    let onSelect: (ResolvedPlace?) -> Void
    let onAddFavorite: () -> Void
    let onShowAllFavorites: () -> Void
    let onPickRecent: (ResolvedPlace) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recentPlaces: [BlindRecentStartPlace] = []

    /// 稿子 `.lib{grid-template-columns:repeat(4,1fr)}`。
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 4)

    private var selectedPlace: ResolvedPlace? { places.first { $0.id == selectedID } }
    private var usesList: Bool { dynamicTypeSize.isAccessibilitySize }
    private var rowIconDiameter: CGFloat { usesList ? 52 : 30 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                currentDefaultSection
                    .padding(.top, 10)

                sectionHeader(BlindStartPlaceCopy.libraryHeader)
                librarySection

                if !recentPlaces.isEmpty {
                    sectionHeader(BlindStartPlaceCopy.recentHeader)
                    recentSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(BlindStartPlaceCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        // 页面变长了，二级页藏标签栏，免得最后一行被盖住（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .task { await loadRecentPlaces() }
    }

    /// 稿子 `.sh{margin:22px 16px 9px}`：上一卡底到标题 22，标题到卡 9。
    private func sectionHeader(_ title: String) -> some View {
        BlindStartPlaceSectionHeader(title: title)
            .padding(.top, 22)
            .padding(.bottom, 9)
    }

    // MARK: - 现在默认从这里出发

    private var currentDefaultTitle: String { selectedPlace?.title ?? BlindStartPlaceCopy.currentLocation }

    private var currentDefaultSubtitle: String? {
        guard let selectedPlace else {
            return isCurrentLocationUnavailable
                ? BlindFavoritePlaceAddCopy.currentLocationUnavailableSubtitle
                : BlindStartPlaceCopy.currentLocationEveryTime
        }
        return selectedPlace.addressText.nilIfBlank
    }

    /// 只读，整块一个读屏元素（稿子读屏第 2 条「现在默认从这里出发：X，地址」），不是按钮。
    private var currentDefaultSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            BlindStartPlaceSectionHeader(title: BlindStartPlaceCopy.currentDefaultHeader)
            GroupedCard {
                BlindFavoritePlaceRowLabel(
                    title: currentDefaultTitle,
                    // 稿 ④：最大字号时只留名字，地址省掉，免得一张卡占半屏。
                    subtitle: usesList ? nil : currentDefaultSubtitle,
                    icon: selectedPlace.map { BlindStartPlaceIcon.favorite(title: $0.title) } ?? .currentLocation,
                    isSelected: false,
                    prominent: true,
                    iconDiameter: rowIconDiameter
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(BlindStartPlaceCopy.currentDefaultHeader)："
                + [currentDefaultTitle, currentDefaultSubtitle].compactMap { $0 }.joined(separator: "，")
        )
        .accessibilityIdentifier("blindStartPlaceCurrentDefault")
    }

    // MARK: - 常用地点

    /// 资料库里的一格：当前定位、某个收藏、添加。
    private struct LibraryItem: Identifiable {
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

    private var libraryItems: [LibraryItem] {
        let isCurrentSelected = selectedPlace == nil
        var items = [LibraryItem(
            id: "current",
            title: BlindStartPlaceCopy.currentLocation,
            subtitle: BlindStartPlaceCopy.currentLocationFollows,
            icon: .currentLocation,
            isSelected: isCurrentSelected,
            accessibilityLabel: isCurrentSelected
                ? "\(BlindStartPlaceCopy.currentLocation)，\(BlindStartPlaceCopy.defaultSpoken)"
                : "\(BlindStartPlaceCopy.currentLocation)，\(BlindStartPlaceCopy.currentLocationFollows)",
            accessibilityHint: isCurrentSelected ? nil : BlindStartPlaceCopy.setDefaultHint,
            identifier: "blindStartPlaceCurrentLocation",
            action: { onSelect(nil) }
        )]
        for (index, place) in places.enumerated() {
            let isSelected = place.id == selectedID
            let meters = BlindStartPlaceDistance.meters(from: deviceLocation, to: place)
            items.append(LibraryItem(
                id: place.id,
                title: place.title,
                subtitle: meters.map(BlindStartPlaceDistance.text(meters:)),
                icon: .favorite(title: place.title),
                isSelected: isSelected,
                accessibilityLabel: isSelected
                    ? "\(place.title)，\(BlindStartPlaceCopy.defaultSpoken)"
                    : [place.title, meters.map(BlindStartPlaceDistance.spoken(meters:))].compactMap { $0 }.joined(separator: "，"),
                accessibilityHint: isSelected ? nil : BlindStartPlaceCopy.setDefaultHint,
                identifier: "blindStartPlaceFavorite_\(index)",
                action: { onSelect(place) }
            ))
        }
        items.append(LibraryItem(
            id: "add",
            // 圆下只有 80pt 宽，写「添加」；最大字号的列表整行够宽，写全「添加常用地点」。
            title: usesList ? BlindStartPlaceCopy.addSpoken : BlindStartPlaceCopy.add,
            subtitle: nil,
            icon: .add,
            isSelected: false,
            accessibilityLabel: BlindStartPlaceCopy.addSpoken,
            accessibilityHint: "搜索地点并收藏",
            identifier: "blindHomeAddFavoritePlace",
            action: onAddFavorite
        ))
        return items
    }

    private var librarySection: some View {
        GroupedCard {
            if usesList {
                ForEach(Array(libraryItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset) }
                    libraryRow(item)
                }
            } else {
                // 稿子 `.lib{padding:16px 6px 6px;row-gap:14px}`。
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                    ForEach(libraryItems) { item in
                        BlindStartPlaceCircleButton(
                            title: item.title,
                            subtitle: item.subtitle,
                            icon: item.icon,
                            isSelected: item.isSelected,
                            accessibilityLabel: item.accessibilityLabel,
                            accessibilityHint: item.accessibilityHint,
                            identifier: item.identifier,
                            action: item.action
                        )
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            // 没有收藏时不出「全部」行（稿 ②）。
            if !places.isEmpty {
                GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset)
                allFavoritesRow
            }
        }
    }

    /// 最大字号时的一行（稿 ④）：52pt 圆，选中行左侧一道主色竖条 + 主色「默认」。
    private func libraryRow(_ item: LibraryItem) -> some View {
        Button(action: item.action) {
            BlindFavoritePlaceRowLabel(
                title: item.title,
                subtitle: item.isSelected ? BlindStartPlaceCopy.defaultTag : item.subtitle,
                icon: item.icon,
                isSelected: false,
                prominent: true,
                iconDiameter: rowIconDiameter,
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

    /// 稿子 `.foot`：17pt，右边浅灰 `›`。可见约 56pt，可点区按盲人端下限做到 64pt。
    private var allFavoritesRow: some View {
        Button(action: onShowAllFavorites) {
            HStack(spacing: 8) {
                Text(BlindStartPlaceCopy.allFavorites(count: places.count))
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    // 占满左侧宽度。用 `Spacer` 顶开时审计会把后面跟图标的字判成「可能被裁」（同 `BlindHomeQuickRow`）。
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(.leading, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BlindStartPlaceCopy.allFavorites(count: places.count))
        .accessibilityIdentifier("blindStartPlaceAllFavorites")
    }

    // MARK: - 最近跑过的地点

    private var recentSection: some View {
        GroupedCard {
            ForEach(Array(recentPlaces.enumerated()), id: \.element.id) { index, recent in
                if index > 0 { GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset) }
                Button { onPickRecent(recent.place) } label: {
                    BlindFavoritePlaceRowLabel(
                        title: recent.place.title,
                        subtitle: recent.usedOnText,
                        icon: .recent,
                        isSelected: false,
                        prominent: true,
                        iconDiameter: rowIconDiameter
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel([recent.place.title, recent.usedOnText].compactMap { $0 }.joined(separator: "，"))
                .accessibilityHint(BlindFavoritePlaceAddCopy.pickHint)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindStartPlaceRecent")
    }

    /// 拿不到就不显示这一组，其余照常可用（同「添加常用地点」页）。
    private func loadRecentPlaces() async {
        guard let orders = try? await appState.orders.myOrders().content else { return }
        recentPlaces = BlindRecentStartPlace.from(orders)
    }
}
