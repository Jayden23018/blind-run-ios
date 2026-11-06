import SwiftUI

// MARK: - 添加常用地点（#807）

/// 首页「默认出发地点 › 添加常用地点」进来的一页。
///
/// 原来这里进的是整张约跑表单（定位卡、地图、收藏按钮、时间时长配速……），负责人 2026-11-06：
/// 「进入二级页面要填很多信息，就像进了另一个 App」。现在只有三样，从上到下：
/// 1. 「使用当前定位」—— 不添加任何地点，默认出发地点跟着人走（负责人同日加：不是所有都要添加）；
/// 2. 搜索框（苹果语音，和约跑页同一个 `VoiceTextField`），点一个结果就收藏并设为默认；
/// 3. 「最近跑过的地点」—— 已完成订单的起点，点一下同样收藏并设为默认（负责人同日加）。
///
/// 这一页不自己改收藏：选完交给首页（`onUseCurrentLocation` / `onPick`），首页写 `FavoritePlaceStore`、朗读、退回。
struct BlindFavoritePlaceAddPage: View {
    /// 默认出发地点现在是不是「当前定位」：是的话那一行打勾。
    let isUsingCurrentLocation: Bool
    /// 定位被拒或精确定位关着：仍可以选（打开定位后就能用），但副标题与朗读要说清现在拿不到。
    let isCurrentLocationUnavailable: Bool
    let onUseCurrentLocation: () -> Void
    let onPick: (ResolvedPlace) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var geocoder = AMapGeocodingService()

    @State private var keyword = ""
    @State private var results: [ResolvedPlace] = []
    @State private var isSearching = false
    /// 搜索没结果 / 失败那一句，上屏并朗读（不只靠 TTS，记忆 claimed-fallback-may-not-exist-in-release）。
    @State private var searchMessage: String?
    @State private var recentPlaces: [BlindRecentStartPlace] = []
    @State private var hasSpokenIntro = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                GroupedCard {
                    Button(action: onUseCurrentLocation) {
                        BlindFavoritePlaceRowLabel(
                            title: BlindFavoritePlaceAddCopy.currentLocationTitle,
                            subtitle: currentLocationSubtitle,
                            icon: .currentLocation,
                            isSelected: isUsingCurrentLocation
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BlindFavoritePlaceAddCopy.currentLocationTitle)
                    .accessibilityHint(currentLocationSubtitle)
                    .accessibilityAddTraits(isUsingCurrentLocation ? .isSelected : [])
                    .accessibilityIdentifier("blindFavoritePlaceUseCurrentLocation")
                }

                VoiceTextField(
                    title: BlindFavoritePlaceAddCopy.searchTitle,
                    placeholder: BlindFavoritePlaceAddCopy.searchPlaceholder,
                    text: $keyword,
                    speechInputService: speechInputService,
                    speechService: speechService,
                    speechField: .startPlaceSearch,
                    accessibilityLabel: BlindFavoritePlaceAddCopy.searchTitle,
                    accessibilityHint: "说出或输入地点名称，结束后自动搜索",
                    onRecognitionCompleted: { completion in
                        guard completion.field == .startPlaceSearch,
                              completion.reason.shouldTriggerSearchWithRecognizedText else { return }
                        let recognized = completion.recognizedText.trimmed
                        guard !recognized.isEmpty else { return }
                        keyword = recognized
                        Task { await search() }
                    },
                    onSubmit: { Task { await search() } }
                )

                if isSearching {
                    ProgressView(BlindFavoritePlaceAddCopy.searching)
                        .font(AppFonts.body())
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary)
                }

                if let searchMessage {
                    Text(searchMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .accessibilityIdentifier("blindFavoritePlaceSearchMessage")
                }

                if !results.isEmpty {
                    placeGroup(
                        title: BlindFavoritePlaceAddCopy.resultsHeader(count: results.count),
                        rows: results.map { (place: $0, subtitle: $0.addressText.nilIfBlank, icon: BlindStartPlaceIcon.searchResult) },
                        identifier: "blindFavoritePlaceResults"
                    )
                } else if !recentPlaces.isEmpty {
                    placeGroup(
                        title: BlindFavoritePlaceAddCopy.recentHeader,
                        rows: recentPlaces.map { (place: $0.place, subtitle: $0.usedOnText, icon: BlindStartPlaceIcon.recent) },
                        identifier: "blindFavoritePlaceRecent"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(BlindFavoritePlaceAddCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .task {
            if !hasSpokenIntro {
                hasSpokenIntro = true
                speechService.speak(BlindFavoritePlaceAddCopy.intro)
            }
            await loadRecentPlaces()
        }
        .onDisappear {
            VoiceDictationButton.stopRecording(.startPlaceSearch, on: speechInputService)
        }
    }

    private var currentLocationSubtitle: String {
        isCurrentLocationUnavailable
            ? BlindFavoritePlaceAddCopy.currentLocationUnavailableSubtitle
            : BlindFavoritePlaceAddCopy.currentLocationSubtitle
    }

    private func placeGroup(
        title: String,
        rows: [(place: ResolvedPlace, subtitle: String?, icon: BlindStartPlaceIcon)],
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .accessibilityAddTraits(.isHeader)
            GroupedCard {
                ForEach(Array(rows.enumerated()), id: \.element.place.id) { index, row in
                    if index > 0 {
                        GroupedCardDivider(leadingInset: BlindFavoritePlaceRowLabel.dividerInset)
                    }
                    Button { onPick(row.place) } label: {
                        BlindFavoritePlaceRowLabel(
                            title: row.place.title,
                            subtitle: row.subtitle,
                            icon: row.icon,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel([row.place.title, row.subtitle].compactMap { $0 }.joined(separator: "，"))
                    .accessibilityHint(BlindFavoritePlaceAddCopy.pickHint)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func search() async {
        let trimmed = keyword.trimmed
        guard !trimmed.isEmpty else {
            searchMessage = BlindFavoritePlaceAddCopy.emptyKeyword
            speechService.speakError(BlindFavoritePlaceAddCopy.emptyKeyword)
            return
        }
        guard !isSearching else { return }
        isSearching = true
        searchMessage = nil
        let found = await geocoder.searchPlaces(keyword: trimmed, near: locationService.currentLocation)
        isSearching = false
        results = found
        if let first = found.first {
            speechService.announce(BlindFavoritePlaceAddCopy.foundAnnouncement(count: found.count, first: first.title))
        } else {
            let message = geocoder.lastErrorMessage ?? BlindFavoritePlaceAddCopy.noResults
            searchMessage = message
            speechService.speakError(message)
        }
    }

    /// 拿不到就不显示这一组，其余照常可用：这是锦上添花，不该挡住搜索。
    private func loadRecentPlaces() async {
        guard let orders = try? await appState.orders.myOrders().content else { return }
        recentPlaces = BlindRecentStartPlace.from(orders)
    }
}

// MARK: - 首页路由外壳

/// 首页「默认出发地点」页的路由外壳：选中后写默认、朗读、回首页。
/// #807 从 `BlindRunnerHomeView.swift` 挪来（那个文件超了 SwiftLint 的 1000 行上限）。
/// #817 起页面照苹果地图「资料库」：多了「全部 N 个常用地点 ›」和「最近跑过的地点」两个入口。
struct BlindHomeStartPlaceRoute: View {
    @ObservedObject var favoritePlaces: FavoritePlaceStore
    @Binding var path: [BlindRunnerRoute]
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    private var isLocationUnavailable: Bool { locationService.isDenied || locationService.isPreciseLocationOff }

    var body: some View {
        BlindHomeStartPlacePage(
            places: favoritePlaces.places,
            selectedID: favoritePlaces.defaultPlace?.id,
            // 拿不到可信定位时不写「离你 X 公里」（定稿：拿不到定位不写）。
            deviceLocation: isLocationUnavailable ? nil : locationService.currentLocation,
            isCurrentLocationUnavailable: isLocationUnavailable,
            onSelect: { place in
                let didSave = favoritePlaces.setDefaultPlace(place)
                speechService.speak(didSave ? BlindStartPlaceCopy.changed(to: place?.title ?? BlindStartPlaceCopy.currentLocation) : BlindStartPlaceCopy.saveFailed)
                path.removeAll()
            },
            onAddFavorite: {
                // 开场白由新页自己念（#807），这里不再说「请搜索出发地点，然后收藏它」。
                path = [.addFavoritePlace]
            },
            onShowAllFavorites: { path.append(.favoritePlaceList) },
            onPickRecent: { place in
                // 和「添加常用地点」页点最近一行同一个动作：收藏并设为默认（定稿 ①A 说明）。
                if BlindFavoritePlaceAdoption.collectAndSetDefault(place, store: favoritePlaces, speech: speechService) {
                    path.removeAll()
                }
            }
        )
    }
}

/// 「收藏这个地点并设为默认出发地点」。添加页的搜索结果 / 最近一行、默认出发地点页的最近一行共用。
enum BlindFavoritePlaceAdoption {
    /// - Returns: 收藏并设默认都成了吗。成了调用方回首页；没成已经朗读了原因，留在原页。
    @MainActor
    static func collectAndSetDefault(_ place: ResolvedPlace, store: FavoritePlaceStore, speech: SpeechService) -> Bool {
        store.add(place)
        guard let stored = store.storedPlace(matching: place) else {
            speech.speakError("没能收藏\(place.title)，请换一个地点再试。")
            return false
        }
        guard store.setDefaultPlace(stored) else {
            // 收藏已经存下了，只是没设成默认：照实说，别让人以为没收藏上。
            speech.speakError("已收藏\(stored.title)，但没能设为默认出发地点，请在默认出发地点里再选一次。")
            return false
        }
        speech.speak("已收藏\(stored.title)，之后默认从这里出发。")
        return true
    }
}

/// 「添加常用地点」页的路由外壳（#807）：不再进约跑表单。选完在这里写收藏、设默认、朗读并回首页。
struct BlindFavoritePlaceAddRoute: View {
    @ObservedObject var favoritePlaces: FavoritePlaceStore
    @Binding var path: [BlindRunnerRoute]
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    private var isLocationUnavailable: Bool { locationService.isDenied || locationService.isPreciseLocationOff }

    var body: some View {
        BlindFavoritePlaceAddPage(
            isUsingCurrentLocation: favoritePlaces.defaultPlace == nil,
            isCurrentLocationUnavailable: isLocationUnavailable,
            onUseCurrentLocation: useCurrentLocation,
            onPick: pick
        )
    }

    private func useCurrentLocation() {
        guard favoritePlaces.setDefaultPlace(nil) else {
            speechService.speakError(BlindStartPlaceCopy.saveFailed)
            return
        }
        speechService.speak(
            isLocationUnavailable
                ? "默认出发地点已改为当前定位。现在拿不到定位，打开定位后才能用。"
                : "默认出发地点已改为当前定位。"
        )
        path.removeAll()
    }

    private func pick(_ place: ResolvedPlace) {
        if BlindFavoritePlaceAdoption.collectAndSetDefault(place, store: favoritePlaces, speech: speechService) {
            path.removeAll()
        }
    }
}

// MARK: - 行

/// 彩色圆形图标 + 名称 + 灰字副标题（#817 起照苹果地图「最近」列表：30pt 圆，原来是 32pt 圆角方块）。
/// 图标只是装饰，读屏不念。可点区由 `contentShape` 撑满整行，高度不低于 64pt。
///
/// 「添加常用地点」页用默认参数，版式与改版前一样；「默认出发地点」页与「常用地点」列表页
/// 传 `prominent`（粗标题、行高 72，稿子 `.rw`）、最大字号时传 `iconDiameter: 52`。
struct BlindFavoritePlaceRowLabel: View {
    /// 分隔线照苹果从图标左缘画起（稿子 `.rw+.rw{border-top}`，`margin-left:16px`）。
    static let dividerInset: CGFloat = GroupedCardMetrics.rowHorizontalPadding
    /// 稿子 `.rw{min-height:72px}`。
    static let prominentMinHeight: CGFloat = 72

    let title: String
    let subtitle: String?
    let icon: BlindStartPlaceIcon
    let isSelected: Bool
    var prominent = false
    var iconDiameter: CGFloat = 30
    /// 副标题是「默认」时用主色加粗（最大字号列表里的选中行，稿 ④）。
    var subtitleIsDefaultTag = false
    var showsDefaultBadge = false

    var body: some View {
        // 稿子 `.ri{margin-right:13px}`（最大字号 14）；添加页沿用改版前的 12，版式不动。
        HStack(spacing: iconDiameter > 30 ? 14 : (prominent ? 13 : 12)) {
            BlindStartPlaceIconCircle(icon: icon, diameter: iconDiameter)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(prominent ? .headline : AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleIsDefaultTag ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundColor(subtitleIsDefaultTag ? AppColors.primary : AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if showsDefaultBadge {
                BlindStartPlaceDefaultBadge()
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: prominent ? Self.prominentMinHeight : AppTouchTarget.blindPrimary,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

// MARK: - 最近跑过的地点

/// 已完成订单的起点。只取已完成的单：取消了的单从没真的在那儿跑过。
struct BlindRecentStartPlace: Identifiable, Equatable {
    let place: ResolvedPlace
    let usedOn: Date?

    var id: String { place.id }

    static let limit = 5

    var usedOnText: String? {
        usedOn.map { "\(Self.dayFormatter.string(from: $0))跑过" }
    }

    /// 新的在前；同一个地名只留最近一次；没有地名或坐标的单跳过。
    static func from(_ orders: [OrderDetailResponse], limit: Int = limit) -> [BlindRecentStartPlace] {
        let candidates: [BlindRecentStartPlace] = orders.compactMap { order in
            guard order.status == .completed,
                  let address = order.startAddress?.nilIfBlank,
                  let latitude = order.startLatitude,
                  let longitude = order.startLongitude else { return nil }
            let place = ResolvedPlace(
                id: "recent-\(order.orderId)",
                title: address,
                addressText: "",
                latitude: latitude,
                longitude: longitude,
                source: .manual
            )
            return BlindRecentStartPlace(place: place, usedOn: order.plannedStart?.backendLocalDate)
        }
        let sorted = candidates.sorted { ($0.usedOn ?? .distantPast) > ($1.usedOn ?? .distantPast) }
        var seen = Set<String>()
        var unique: [BlindRecentStartPlace] = []
        for item in sorted where seen.insert(item.place.title).inserted {
            unique.append(item)
            if unique.count == limit { break }
        }
        return unique
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

// MARK: - 文案

enum BlindFavoritePlaceAddCopy {
    static let title = "添加常用地点"
    static let intro = "添加常用地点。可以使用当前定位，也可以说出或输入地点名称搜索，下面还有最近跑过的地点。"
    static let currentLocationTitle = "使用当前定位"
    static let currentLocationSubtitle = "每次从你所在的位置出发，不用添加"
    static let currentLocationUnavailableSubtitle = "现在拿不到定位，打开定位后才能用"
    static let searchTitle = "搜索地点"
    static let searchPlaceholder = "说出或输入地点名称"
    static let searching = "正在搜索"
    static let emptyKeyword = "请先说出或输入要搜索的地点。"
    static let noResults = "没有找到这个地点，换个说法再试一次。"
    static let recentHeader = "最近跑过的地点"
    static let pickHint = "收藏并设为默认出发地点"

    static func resultsHeader(count: Int) -> String { "找到 \(count) 个地点，点一个就收藏" }

    static func foundAnnouncement(count: Int, first: String) -> String {
        "找到 \(count) 个地点，第一个是\(first)。"
    }
}
