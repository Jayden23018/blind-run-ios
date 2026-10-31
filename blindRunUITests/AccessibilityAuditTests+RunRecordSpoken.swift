import XCTest

/// 单独成文件：`AccessibilityAuditTests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `+RecoveryFailed`）。
extension AccessibilityAuditTests {
    // MARK: 跑后记录无障碍走查（阶段 7）

    /// HANDOFF 第 7 节：四个界面上读屏念到的每一句都不带掩码星号（外放的读屏会念成「陈星号」）；
    /// 跑者页屏幕与读屏都不出现 `6'15"`（HANDOFF 5.3）。
    /// 扫的是整棵树而不是逐个元素断言：新加的元素漏了星号，不用有人想起来补断言也会红。
    @MainActor
    func testRunRecordScreensNeverSpeakMaskStarsAndRunnerNeverShowsPrimePace() throws {
        var app = launchVolunteerHome(extraEnvironment: Self.recordsSeed)
        openRecordsTab(app, title: "陪跑记录")
        assertNothingSpokenCarriesAMask(app, screen: "陪跑员记录 tab", swipes: 2)
        app.terminate()

        app = launchVolunteerHome(extraEnvironment: Self.recordsSeed)
        openVolunteerRunRecordDetail(app)
        assertNothingSpokenCarriesAMask(app, screen: "陪跑员详情", swipes: 8)
        app.terminate()

        app = launchBlindHome(emptyOrders: false, extraEnvironment: Self.recordsSeed)
        openRecordsTab(app, title: "跑步记录")
        assertNothingSpokenCarriesAMask(app, screen: "跑者记录 tab", swipes: 2)
        app.terminate()

        app = launchBlindHome(emptyOrders: false, extraEnvironment: Self.recordsSeed)
        _ = openRunnerRunRecordDetail(app)
        // 讲述的文字稿点开才在树里，一并扫。
        let listen = app.buttons["runnerRunRecordListen"]
        if listen.isHittable { listen.tap(); listen.tap() }
        assertNothingSpokenCarriesAMask(app, screen: "跑者详情", swipes: 8)
        for _ in 0..<8 { app.swipeDown() }
        var primes: [String] = []
        for page in 0...8 {
            if page > 0 { app.swipeUp() }
            // 这一条连屏幕上的字一起查（被合并进父元素的也算），所以不按「读屏叶子」剪枝。
            primes += strings(in: try app.snapshot(), spokenOnly: false).filter { text in
                text.contains { "'\"′″’”".contains($0) }
            }
        }
        XCTAssertTrue(primes.isEmpty, "跑者页出现了撇号配速：\(Set(primes))")
    }

    @MainActor
    private func assertNothingSpokenCarriesAMask(_ app: XCUIApplication, screen: String, swipes: Int) {
        var spoken: Set<String> = []
        for page in 0...swipes {
            if page > 0 { app.swipeUp() }
            guard let snapshot = try? app.snapshot() else { continue }
            spoken.formUnion(strings(in: snapshot, spokenOnly: true))
        }
        // 自检：只读到 App 名说明扫描没走进树里，这条用例就是空转（#247 验红时发现过一次）。
        XCTAssertGreaterThan(spoken.count, 1, "\(screen)：扫描没读到任何元素")
        let leaks = spoken.filter { $0.contains("*") || $0.contains("＊") }
        XCTAssertTrue(leaks.isEmpty, "\(screen)：读屏会念出掩码星号：\(leaks)")
    }

    /// 取快照里的 label / value。`spokenOnly` 时近似读屏看到的：一个带 label 的元素
    /// （按钮、`.ignore` 合并出来的元素）只念它自己的 label，不往里看 —— XCUITest 看得见被合并的子文字，
    /// 读屏看不见（记忆 list-rows-false-dynamic-type-audit）。导航栏本身不念，只念栏里的元素。
    private func strings(in snapshot: XCUIElementSnapshot, spokenOnly: Bool) -> [String] {
        var found = [snapshot.label]
        if let value = snapshot.value as? String { found.append(value) }
        // 导航栏元素的 label / identifier 是 `navigationTitle` 原串，读屏不停在栏上。
        if spokenOnly && snapshot.elementType == .navigationBar { found = [] }
        // 根节点 Application 的 label 是 App 名，它和 Window 都只是容器：停在这里等于什么都没扫。
        let isContainer = [.application, .window, .navigationBar].contains(snapshot.elementType)
        // 静态文本也算：`children: .ignore` 的头部卡片在树里是 StaticText，读屏不进它的子元素。
        let mergesChildren = spokenOnly && !snapshot.label.isEmpty && !isContainer
        if mergesChildren { return found.filter { !$0.isEmpty } }
        return (found + snapshot.children.flatMap { strings(in: $0, spokenOnly: spokenOnly) }).filter { !$0.isEmpty }
    }
}
