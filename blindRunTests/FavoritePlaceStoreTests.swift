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

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // 每条用例一个独立 suite：`.standard` 是真机上用户自己的收藏，测试不许碰。
        suiteName = "aidrun.tests.favorites.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - 核心：坐标必须原样保住

    /// 收藏的全部价值在于**下次不用再解析地名**，所以坐标必须逐位存回来。
    /// 这条一旦红，收藏就退化成了一个书签，用户还是会被派到海南去。
    func testKeepsTheResolvedCoordinateExactly() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "阳光棕榈园", latitude: 22.53291, longitude: 113.93041))

        let saved = try! XCTUnwrap(store.places.first)
        XCTAssertEqual(saved.latitude, 22.53291, accuracy: 0.000001)
        XCTAssertEqual(saved.longitude, 113.93041, accuracy: 0.000001)
        XCTAssertEqual(saved.title, "阳光棕榈园")
    }

    func testSurvivesAcrossStoreInstances() {
        let first = FavoritePlaceStore(defaults: defaults)
        first.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))

        let reopened = FavoritePlaceStore(defaults: defaults)
        XCTAssertEqual(reopened.places.count, 1)
        XCTAssertEqual(reopened.places.first?.title, "朝阳公园南门")
        XCTAssertEqual(reopened.places.first?.latitude ?? 0, 39.9342, accuracy: 0.000001)
    }

    // MARK: - 不许收藏的东西

    /// 演示坐标是一个北京的固定点。收藏之后它和真实收藏长得一模一样，
    /// 下一次用它下单就是把志愿者派到用户从没去过的地方。
    func testRejectsDemoFallbackCoordinates() {
        let store = FavoritePlaceStore(defaults: defaults)
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
        let store = FavoritePlaceStore(defaults: defaults)
        XCTAssertFalse(store.add(makePlace(title: "   ", latitude: 39.9, longitude: 116.4)))
        XCTAssertTrue(store.places.isEmpty)
    }

    // MARK: - 去重

    /// 判据是坐标不是名字：同一个点用不同关键词搜出来，高德给的 `title` 可能不同
    /// （「朝阳公园南门」/「朝阳公园(南门)」），按名字判会让同一个点存两遍，
    /// 而两条读起来几乎一样的记录对读屏用户是纯噪音。
    func testDeduplicatesByCoordinateNotByTitle() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))
        let second = store.add(makePlace(title: "朝阳公园(南门)", latitude: 39.9342, longitude: 116.4740))

        XCTAssertFalse(second)
        XCTAssertEqual(store.places.count, 1)
    }

    /// 同一个 POI 两次搜索返回的坐标可能有末位抖动，5 位小数（约 1.1 米）以内算同一个点。
    func testTinyCoordinateJitterCountsAsTheSamePlace() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.934200, longitude: 116.474000))
        let jittered = store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342001, longitude: 116.4740002))

        XCTAssertFalse(jittered)
        XCTAssertEqual(store.places.count, 1)
    }

    /// 相隔一条街的两个点是**两个**地点，不能被去重吃掉。
    func testDifferentPlacesAreBothKept() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))
        store.add(makePlace(title: "朝阳公园西门", latitude: 39.9351, longitude: 116.4702))

        XCTAssertEqual(store.places.count, 2)
    }

    /// 语音解析出来的地点 id 恒为 `voice-resolved`。沿用它当收藏标识会让两条收藏撞成一个 id，
    /// `ForEach` 只渲染一条、删除删错行。
    func testVoiceResolvedPlacesGetDistinctIdentifiers() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(id: "voice-resolved", title: "人民广场", latitude: 31.2304, longitude: 121.4737))
        store.add(makePlace(id: "voice-resolved", title: "五角场", latitude: 31.2989, longitude: 121.5079))

        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(Set(store.places.map(\.id)).count, 2, "两条收藏的 id 撞在了一起")
    }

    // MARK: - 上限与顺序

    /// 上限不是存储成本，是**朗读成本**：读屏用户要从头听到尾才能选中最后一条。
    func testEvictsTheOldestBeyondCapacity() {
        let store = FavoritePlaceStore(defaults: defaults)
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
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "人民广场", latitude: 31.2304, longitude: 121.4737))
        store.add(makePlace(title: "五角场", latitude: 31.2989, longitude: 121.5079))
        let doomed = try! XCTUnwrap(store.places.first { $0.title == "人民广场" })

        store.remove(id: doomed.id)

        XCTAssertEqual(store.places.map(\.title), ["五角场"])
        XCTAssertEqual(FavoritePlaceStore(defaults: defaults).places.map(\.title), ["五角场"], "删除没有落盘")
    }

    func testRemovingAnUnknownIdentifierChangesNothing() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "人民广场", latitude: 31.2304, longitude: 121.4737))

        store.remove(id: "favorite-0.00000,0.00000")

        XCTAssertEqual(store.places.count, 1)
    }

    // MARK: - contains

    func testContainsMatchesTheSameSpotRegardlessOfTitle() {
        let store = FavoritePlaceStore(defaults: defaults)
        store.add(makePlace(title: "朝阳公园南门", latitude: 39.9342, longitude: 116.4740))

        XCTAssertTrue(store.contains(makePlace(title: "别的名字", latitude: 39.9342, longitude: 116.4740)))
        XCTAssertFalse(store.contains(makePlace(title: "朝阳公园南门", latitude: 40.0, longitude: 116.4740)))
    }

    // MARK: - 损坏数据

    /// 解不出就当没有收藏，**但不主动清掉用户那份数据**。
    func testCorruptedPayloadDegradesToAnEmptyListWithoutWipingIt() {
        defaults.set(Data("not json".utf8), forKey: "aidrun.favorite-start-places.v1")

        let store = FavoritePlaceStore(defaults: defaults)

        XCTAssertTrue(store.places.isEmpty)
        XCTAssertNotNil(defaults.data(forKey: "aidrun.favorite-start-places.v1"))
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
