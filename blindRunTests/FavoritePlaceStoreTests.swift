import XCTest
@testable import blindRun

/// 常用出发地点的本地存储。
///
/// 这块存在的理由是消灭「地名 → 坐标」那一段：真机上出过在深圳南山说「阳光棕榈园」
/// 被定位到广东其它城市、说「前海万象」被定位到**海南**
/// （`openspec/changes/disambiguate-same-name-start-place`）。收藏保存的是**已解析好的坐标**，
/// 所以断言全部围绕「坐标有没有被原样保住」和「什么东西不许被收藏」。
@MainActor
final class FavoritePlaceStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        // 每条用例一个独立临时目录：真机上那份收藏是用户自己的，测试不许碰。
        // 从 `UserDefaults(suiteName:)` 换成目录，是因为这份数据已经从明文 plist 搬到了
        // Application Support 下的受保护文件（见 `FavoritePlaceStore.defaultDirectory`）。
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aidrun.tests.favorites.\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    // MARK: - 核心：坐标必须原样保住

    /// 收藏的全部价值在于**下次不用再解析地名**，所以坐标必须逐位存回来。
    /// 这条一旦红，收藏就退化成了一个书签，用户还是会被派到海南去。
    func testKeepsTheResolvedCoordinateExactly() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "阳光棕榈园", latitude: 22.53291, longitude: 113.93041))

        let saved = try! XCTUnwrap(store.places.first)
        XCTAssertEqual(saved.latitude, 22.53291, accuracy: 0.000001)
        XCTAssertEqual(saved.longitude, 113.93041, accuracy: 0.000001)
        XCTAssertEqual(saved.title, "阳光棕榈园")
    }

    func testSurvivesAcrossStoreInstances() {
        let first = FavoritePlaceStore(directory: directory)
        first.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))

        let reopened = FavoritePlaceStore(directory: directory)
        XCTAssertEqual(reopened.places.count, 1)
        XCTAssertEqual(reopened.places.first?.title, "朝阳公园南门")
        XCTAssertEqual(reopened.places.first?.latitude ?? 0, 39.9342, accuracy: 0.000001)
    }

    // MARK: - 不许收藏的东西

    /// 演示坐标是一个北京的固定点。收藏之后它和真实收藏长得一模一样，
    /// 下一次用它下单就是把志愿者派到用户从没去过的地方。
    func testRejectsDemoFallbackCoordinates() {
        let store = FavoritePlaceStore(directory: directory)
        let added = store.add(makePlace(
            title: "当前位置（演示坐标）",
            latitude: 39.9042,
            longitude: 116.4074,
            source: .demoDefault
        ))

        XCTAssertFalse(added)
        XCTAssertTrue(store.places.isEmpty)
    }

    /// 没有名字的地点收藏了也认不出来 —— 列表里一排空行等于没收藏。
    func testRejectsPlacesWithoutATitle() {
        let store = FavoritePlaceStore(directory: directory)
        XCTAssertFalse(store.add(makePlace(title: "   ", latitude: 39.9, longitude: 116.4)))
        XCTAssertTrue(store.places.isEmpty)
    }

    // MARK: - 去重

    /// 判据是坐标不是名字：同一个点用不同关键词搜出来，高德给的 `title` 可能不同
    /// （「朝阳公园南门」/「朝阳公园(南门)」），按名字判会让同一个点存两遍，
    /// 而两条读起来几乎一样的记录对读屏用户是纯噪音。
    func testDeduplicatesByCoordinateNotByTitle() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))
        let second = store.add(makePlace(title: "朝阳公园(南门)", latitude: 39.9342, longitude: 116.4740))

        XCTAssertFalse(second)
        XCTAssertEqual(store.places.count, 1)
    }

    /// 同一个 POI 两次搜索返回的坐标可能有末位抖动，5 位小数（约 1.1 米）以内算同一个点。
    func testTinyCoordinateJitterCountsAsTheSamePlace() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.934200, longitude: 116.474000))
        let jittered = store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342001, longitude: 116.4740002))

        XCTAssertFalse(jittered)
        XCTAssertEqual(store.places.count, 1)
    }

    /// 相隔一条街的两个点是**两个**地点，不能被去重吃掉。
    func testDifferentPlacesAreBothKept() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))
        store.add(makePlace(title: "朝阳公园西门", latitude: 39.9351, longitude: 116.4702))

        XCTAssertEqual(store.places.count, 2)
    }

    /// 语音解析出来的地点 id 恒为 `voice-resolved`。沿用它当收藏标识会让两条收藏撞成一个 id，
    /// `ForEach` 只渲染一条、删除删错行。
    func testVoiceResolvedPlacesGetDistinctIdentifiers() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(id: "voice-resolved", title: "人民广场", latitude: 31.2304, longitude: 121.4737))
        store.add(makePlace(id: "voice-resolved", title: "五角场", latitude: 31.2989, longitude: 121.5079))

        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(Set(store.places.map(\.id)).count, 2, "两条收藏的 id 撞在了一起")
    }

    // MARK: - 上限与顺序

    /// 上限不是存储成本，是**朗读成本**：读屏用户要从头听到尾才能选中最后一条。
    func testEvictsTheOldestBeyondCapacity() {
        let store = FavoritePlaceStore(directory: directory)
        for index in 0..<(FavoritePlaceStore.capacity + 3) {
            store.add(makePlace(
                title: "地点\(index)",
                latitude: 39.9 + Double(index) / 1000,
                longitude: 116.4
            ))
        }

        XCTAssertEqual(store.places.count, FavoritePlaceStore.capacity)
        // 最新的在最前面，被挤掉的是最早那几条。
        XCTAssertEqual(store.places.first?.title, "地点\(FavoritePlaceStore.capacity + 2)")
        XCTAssertFalse(store.places.contains { $0.title == "地点0" })
    }

    // MARK: - 删除

    func testRemoveDropsOnlyTheTargetedPlace() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "人民广场", latitude: 31.2304, longitude: 121.4737))
        store.add(makePlace(title: "五角场", latitude: 31.2989, longitude: 121.5079))
        let doomed = try! XCTUnwrap(store.places.first { $0.title == "人民广场" })

        store.remove(id: doomed.id)

        XCTAssertEqual(store.places.map(\.title), ["五角场"])
        XCTAssertEqual(FavoritePlaceStore(directory: directory).places.map(\.title), ["五角场"], "删除没有落盘")
    }

    func testRemovingAnUnknownIdentifierChangesNothing() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "人民广场", latitude: 31.2304, longitude: 121.4737))

        store.remove(id: "favorite-0.00000,0.00000")

        XCTAssertEqual(store.places.count, 1)
    }

    // MARK: - contains

    func testContainsMatchesTheSameSpotRegardlessOfTitle() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))

        XCTAssertTrue(store.contains(makePlace(title: "别的名字", latitude: 39.9342, longitude: 116.4740)))
        XCTAssertFalse(store.contains(makePlace(title: "朝阳公园南门", latitude: 40.0, longitude: 116.4740)))
    }

    // MARK: - 损坏数据

    /// 解不出就当没有收藏，**但不主动清掉用户那份数据**。
    func testCorruptedPayloadDegradesToAnEmptyListWithoutWipingIt() {
        let file = directory.appendingPathComponent("favorite-start-places.v1.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("not json".utf8).write(to: file)

        let store = FavoritePlaceStore(directory: directory)

        XCTAssertTrue(store.places.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - F5：不再落明文 UserDefaults，且登出必须清掉

    /// 收藏的是「这个人什么时候会在哪」。`UserDefaults` 是 App 容器里的明文 plist、
    /// 没有 data protection class、**且进 iTunes / iCloud 备份**。
    /// 这条钉住：写入之后那把老 key 上一个字节都不许有。
    func testPlacesNeverLandInUserDefaults() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "阳光棕榈园", latitude: 22.53291, longitude: 113.93041))

        XCTAssertNil(
            UserDefaults.standard.data(forKey: "aidrun.favorite-start-places.v1"),
            "常用地点不许再落明文 UserDefaults"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("favorite-start-places.v1.json").path
            )
        )
    }

    /// 存量迁移：老版本写在 `UserDefaults` 里的收藏要搬过来，**并且把明文那份删掉**。
    /// 只搬不删等于这次改动只是多了一份副本，明文那份照旧躺在备份里。
    func testLegacyUserDefaultsPayloadIsMigratedAndThenErased() {
        let legacy = [makePlace(title: "五角场", latitude: 31.2989, longitude: 121.5069)]
        UserDefaults.standard.set(try! JSONEncoder().encode(legacy), forKey: "aidrun.favorite-start-places.v1")
        defer { UserDefaults.standard.removeObject(forKey: "aidrun.favorite-start-places.v1") }

        let store = FavoritePlaceStore(directory: directory)

        XCTAssertEqual(store.places.map(\.title), ["五角场"], "存量收藏必须搬过来")
        XCTAssertNil(
            UserDefaults.standard.data(forKey: "aidrun.favorite-start-places.v1"),
            "搬完必须把明文那份删掉，否则等于只是多了一份副本"
        )
        XCTAssertEqual(FavoritePlaceStore(directory: directory).places.map(\.title), ["五角场"], "迁移结果没落盘")
    }

    /// 迁移必须「先写成功、再删旧的」。
    ///
    /// 反过来（先删后写）有一个真实的数据丢失窗口：`write` 内部每一步都可能失败，
    /// 而旧的那份已经删了 —— 当次会话还看得见收藏（内存里有），下次冷启动两边都读不到。
    /// 这里把目标目录做成一个**同名普通文件**，`createDirectory` 必然失败，逼出写失败那条路。
    func testMigrationKeepsTheLegacyCopyWhenTheNewFileCannotBeWritten() throws {
        let legacy = [makePlace(title: "五角场", latitude: 31.2989, longitude: 121.5069)]
        let payload = try JSONEncoder().encode(legacy)
        UserDefaults.standard.set(payload, forKey: "aidrun.favorite-start-places.v1")
        defer { UserDefaults.standard.removeObject(forKey: "aidrun.favorite-start-places.v1") }

        // 目标目录的位置上放一个文件：目录建不出来，写必然失败。
        let blocked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aidrun.tests.blocked.\(UUID().uuidString)")
        try Data("occupied".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let store = FavoritePlaceStore(directory: blocked)

        XCTAssertEqual(store.places.map(\.title), ["五角场"], "本次会话仍应看得见收藏")
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: "aidrun.favorite-start-places.v1"),
            "新文件没写成功时必须保留旧的那份，否则用户的收藏两边都没了"
        )
    }

    /// 换账号登录后，上一个人的常去地点不该原样留在这台设备上。
    /// `AppState.performLocalSessionCleanup` 调的就是这个静态方法。
    func testSessionCleanupErasesBothTheFileAndTheLegacyKey() {
        let store = FavoritePlaceStore(directory: directory)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))
        UserDefaults.standard.set(Data("legacy".utf8), forKey: "aidrun.favorite-start-places.v1")

        FavoritePlaceStore.clearPersistedPlaces(directory: directory, defaults: .standard)

        XCTAssertTrue(FavoritePlaceStore(directory: directory).places.isEmpty, "登出后收藏必须清空")
        XCTAssertNil(UserDefaults.standard.data(forKey: "aidrun.favorite-start-places.v1"))
    }

    // MARK: - Helpers

    private func makePlace(
        id: String = "poi",
        title: String,
        latitude: Double,
        longitude: Double,
        source: LocationSource = .manual
    ) -> ResolvedPlace {
        ResolvedPlace(
            id: id,
            title: title,
            addressText: "\(title)地址",
            latitude: latitude,
            longitude: longitude,
            source: source
        )
    }
}
