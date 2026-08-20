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

    /// 仅用于把历史存量搬走后删掉。**新数据不再写这里。**
    private static let legacyDefaultsKey = "aidrun.favorite-start-places.v1"

    private static let fileName = "favorite-start-places.v1.json"

    @Published private(set) var places: [ResolvedPlace] = []

    private let directory: URL

    /// - Parameter directory: 单测传一个临时目录，别污染真机上用户自己的收藏。
    init(directory: URL = FavoritePlaceStore.defaultDirectory) {
        self.directory = directory
        places = Self.load(from: directory)
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

    // MARK: - 落盘位置

    /// **不是 `UserDefaults`。**
    ///
    /// 存的是 `title` + `addressText` + 5 位小数的经纬度（约 1 米）。一个视障用户的常去地点集合
    /// 直接就是「这个人什么时候会在哪」，泄露价值不比身份证号低 —— 而同一个仓库里，身份证号写着
    /// 「只在内存中短暂存在，不写入 `UserDefaults`、Keychain 或任何日志」
    /// （`BlindIdentityVerificationView.swift:25`），证书文件写着「不落 UserDefaults/Keychain」
    /// （`VolunteerCertificateUploadView.swift:22`）。`UserDefaults` 是 App 容器里的明文 plist，
    /// 没有 data protection class，且**进 iTunes / iCloud 备份**。
    ///
    /// 改落 Application Support 下的文件，两条属性缺一不可：
    /// - `.completeUnlessOpen`：静止时加密。不用 `.complete` 是因为它在锁屏后连已打开的句柄都读不了；
    ///   这份数据只在前台被读写，`UnlessOpen` 足够且不会制造锁屏期的静默失败。
    /// - `isExcludedFromBackup`：不进备份。这是 `UserDefaults` 拿不到的那一半。
    static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("AidRun", isDirectory: true)
    }()

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// 会话结束时清空。由 `AppState.performLocalSessionCleanup` 调用。
    ///
    /// 做成 static 而不是实例方法：这个 store 是 `BlindBookingView` 的 `@StateObject`
    /// （`BlindBookingView.swift:889`），`AppState` 手里没有它的引用，而登出时那个页面早已销毁。
    /// 顺带把历史存量那把明文 key 也删掉 —— 只搬家不删除等于把明文副本永远留在设备上。
    static func clearPersistedPlaces(
        directory: URL = FavoritePlaceStore.defaultDirectory,
        defaults: UserDefaults = .standard
    ) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    private static func load(from directory: URL) -> [ResolvedPlace] {
        let url = directory.appendingPathComponent(fileName)
        // 存量迁移：老版本写在 `UserDefaults` 里。搬过来之后**立刻删掉那把 key** ——
        // 留着就等于这次改动只是多了一份副本，明文那份照旧躺在备份里。
        if !FileManager.default.fileExists(atPath: url.path),
           let legacy = UserDefaults.standard.data(forKey: legacyDefaultsKey) {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            let migrated = (try? JSONDecoder().decode([ResolvedPlace].self, from: legacy)) ?? []
            if !migrated.isEmpty { write(migrated, to: directory) }
            return migrated
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        // 解不出就当没有收藏，**但不删那份文件** —— 下一次 `persist()` 才会覆盖它。
        // 这是本地便利数据，读失败的代价是用户少了几条快捷方式，不值得为它加一条错误提示；
        // 但也没有理由主动把用户的东西删掉。
        return (try? JSONDecoder().decode([ResolvedPlace].self, from: data)) ?? []
    }

    private static func write(_ places: [ResolvedPlace], to directory: URL) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        var dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dir.setResourceValues(resourceValues)
        try? data.write(
            to: directory.appendingPathComponent(fileName),
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    private func persist() {
        Self.write(places, to: directory)
    }
}
