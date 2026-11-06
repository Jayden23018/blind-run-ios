import SwiftUI

// MARK: - 常用地点列表（#817 定稿屏 ⑤）

/// 「默认出发地点 › 全部 N 个常用地点 ›」进来的完整列表，照苹果地图「9 Places ›」点进去的那一页。
///
/// - 点一行 = 设为默认出发地点（和资料库里点圆同一个动作：朗读并回首页）。
/// - 向左滑删除；读屏用户上下轻扫选「删除」操作（`swipeActions` 自动带出）。
///   **不弹二次确认**：iOS 左滑删除的惯例，删错了重新收藏一次即可，代价小（定稿说明）。
/// - 删掉的是默认地点时，自动改回当前定位并朗读。
///
/// 用系统 `List`：原生左滑删除只有它有。代价是分组圆角是系统的（约 10pt），不是稿上的 22pt。
struct BlindFavoritePlaceListPage: View {
    let places: [ResolvedPlace]
    let defaultID: String?
    let onSelect: (ResolvedPlace) -> Void
    let onDelete: (ResolvedPlace) -> Void

    var body: some View {
        List {
            Section {
                if places.isEmpty {
                    Text(BlindStartPlaceCopy.listEmpty)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                        .accessibilityIdentifier("blindFavoritePlaceListEmpty")
                }
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    row(place, index: index)
                }
            } header: {
                BlindStartPlaceSectionHeader(title: BlindStartPlaceCopy.listHeader(count: places.count))
                    .textCase(nil)
            } footer: {
                GroupedCardFootnote(text: BlindStartPlaceCopy.listFootnote)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColors.Flow.page)
        .accessibilityIdentifier("blindFavoritePlaceList")
        .navigationTitle(BlindStartPlaceCopy.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
    }

    private func row(_ place: ResolvedPlace, index: Int) -> some View {
        let isDefault = place.id == defaultID
        let address = place.addressText.nilIfBlank
        return Button { onSelect(place) } label: {
            BlindFavoritePlaceRowLabel(
                title: place.title,
                // 从「最近跑过」收藏的没有地址，只显示名字（定稿说明）。
                subtitle: address,
                icon: .favorite(title: place.title),
                isSelected: false,
                prominent: true,
                showsDefaultBadge: isDefault
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(AppColors.Flow.surface)
        // 分隔线照苹果从图标左缘画起，不是从文字起点。
        .alignmentGuide(.listRowSeparatorLeading) { _ in BlindFavoritePlaceRowLabel.dividerInset }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete(place) } label: {
                Text(BlindStartPlaceCopy.delete)
            }
            .tint(Color(uiColor: UIColor(rgb: 0xC4281C)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([place.title, address] + [isDefault ? BlindStartPlaceCopy.defaultSpoken : nil])
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityHint(isDefault ? "" : BlindStartPlaceCopy.setDefaultHint)
        .accessibilityAddTraits(isDefault ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("blindFavoritePlaceListRow_\(index)")
    }
}

/// 列表页的路由外壳：点一行写默认、朗读、回首页；删除写盘并朗读，留在本页。
struct BlindFavoritePlaceListRoute: View {
    @ObservedObject var favoritePlaces: FavoritePlaceStore
    @Binding var path: [BlindRunnerRoute]
    @EnvironmentObject private var speechService: SpeechService

    var body: some View {
        BlindFavoritePlaceListPage(
            places: favoritePlaces.places,
            defaultID: favoritePlaces.defaultPlace?.id,
            onSelect: { place in
                let didSave = favoritePlaces.setDefaultPlace(place)
                speechService.speak(didSave ? BlindStartPlaceCopy.changed(to: place.title) : BlindStartPlaceCopy.saveFailed)
                path.removeAll()
            },
            onDelete: { place in
                let wasDefault = favoritePlaces.remove(id: place.id)
                speechService.speak(BlindStartPlaceCopy.deleted(place.title, wasDefault: wasDefault))
            }
        )
    }
}
