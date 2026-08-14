import Combine
import Foundation

/// 盲人端「常用出发地点」的本地存储。
///
/// **为什么值得存**：说地名是这条流程里最容易出错的一步，而且错得没有征兆。真机上出过
/// 在深圳南山说「阳光棕榈园」被定位到广东其它城市、说「前海万象」被定位到**海南**
/// （`openspec/changes/disambiguate-same-name-start-place`）。根因在「地名 → 坐标」那一段：
/// 同名 POI 满地都是，而看不见屏幕的人只能靠读回那一句话去判断对不对。
///
/// 收藏保存的是**已经解析好的坐标**，不是地名。再次使用时走 `selectPlace(_:)` 直接落到
/// `selectedStartPlace`，「地名 → 坐标」这一段整段不发生 —— 于是那类错误在常去的地点上
/// 概率归零，而常去的地点恰恰占了绝大多数次下单。
///
/// **纯本地，不与后端同步。** 后端没有这个能力，等它就等于这一版不做；而这份数据换设备丢了
/// 的代价只是重搜一次。要做云端同步是另一件事（要契约、要冲突合并、要账号迁移）。
@MainActor
final class FavoritePlaceStore: ObservableObject {

    /// 对标滴滴关怀版的常用地址条数。上限存在的理由不是存储成本，是**朗读成本** ——
    /// 读屏用户要从头听到尾才能选中最后一条，20 条的列表等于没有列表。
    static let capacity = 10

    private static let storageKey = "aidrun.favorite-start-places.v1"

    @Published private(set) var places: [ResolvedPlace] = []

    private let defaults: UserDefaults

    /// - Parameter defaults: 单测传一个临时 suite，别污染真机上用户自己的收藏。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        places = Self.load(from: defaults)
    }

    /// 这个地点是不是已经收藏过了。判据是坐标不是名字 —— 同一个点用不同关键词搜出来，
    /// 高德给的 `title` 可能不同（「朝阳公园南门」/「朝阳公园(南门)」），
    /// 按名字判会让同一个点被收藏两遍，而两条读起来几乎一样的记录对读屏用户是纯噪音。
    func contains(_ place: ResolvedPlace) -> Bool {
        places.contains { $0.id == Self.identifier(for: place) }
    }

    /// 收藏一个地点。已存在则不重复添加，超出上限时挤掉最旧的一条。
    ///
    /// - Returns: 真的写进去了吗。`false` 表示「已经收藏过」或「这个地点不允许收藏」。
    @discardableResult
    func add(_ place: ResolvedPlace) -> Bool {
        // 演示坐标绝不落盘。它是一个北京的固定点，收藏之后看起来和真实收藏一模一样，
        // 而下一次用它下单就是把志愿者派到一个用户从没去过的地方（AGENTS.md §6 同一条口径：
        // demo 坐标不得当作真实位置使用）。
        guard place.source != .demoDefault else { return false }
        // 没有名字的地点收藏了也认不出来 —— 列表里一排「当前位置」等于没收藏。
        guard !place.title.trimmed.isEmpty else { return false }
        guard !contains(place) else { return false }

        var updated = places
        updated.insert(Self.normalized(place), at: 0)
        if updated.count > Self.capacity {
            updated.removeLast(updated.count - Self.capacity)
        }
        places = updated
        persist()
        return true
    }

    func remove(id: String) {
        guard places.contains(where: { $0.id == id }) else { return }
        places.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Persistence

    /// 收藏记录的稳定标识：坐标本身。
    ///
    /// **不能沿用 `ResolvedPlace.id`** —— 语音解析出来的地点 id 恒为 `"voice-resolved"`
    /// （`BlindBookingViewModel.applyVoiceResolvedStartPlace`），收藏两个就撞成同一个 id，
    /// `ForEach` 会只渲染一条、删除会删错行。
    ///
    /// 保留 5 位小数（约 1.1 米）：同一个 POI 两次搜索返回的坐标可能有末位抖动，
    /// 不截断会让同一个地点被收藏两遍。
    private static func identifier(for place: ResolvedPlace) -> String {
        String(format: "favorite-%.5f,%.5f", place.latitude, place.longitude)
    }

    private static func normalized(_ place: ResolvedPlace) -> ResolvedPlace {
        ResolvedPlace(
            id: identifier(for: place),
            title: place.title.trimmed,
            addressText: place.addressText.trimmed,
            latitude: place.latitude,
            longitude: place.longitude,
            source: place.source
        )
    }

    private static func load(from defaults: UserDefaults) -> [ResolvedPlace] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        // 解不出就当没有收藏，**但不清除那份数据** —— 下一次 `persist()` 才会覆盖它。
        // 这是本地便利数据，读失败的代价是用户少了几条快捷方式，不值得为它加一条错误提示；
        // 但也没有理由主动把用户的东西删掉。
        return (try? JSONDecoder().decode([ResolvedPlace].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
