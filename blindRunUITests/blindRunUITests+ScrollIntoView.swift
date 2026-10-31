import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `PrivacyAuthorizationUITests`）。
extension blindRunUITests {
    /// 底部常驻栏（`safeAreaInset(edge: .bottom)`）画在滚动内容之上：落在它下面的控件
    /// `isHittable` 仍然是 `true`，但触点会被钳到栏上。
    ///
    /// 2026-08-14 因此在盲人首页误触常驻求助条、差点拨出 110（`a68bed4`）；2026-08-22 二分
    /// 确认它自 `30b0770` 起复发（`docs/review/ui-test-red-triage-20260822.md`）。当时的判据
    /// 只问「在屏幕矩形内」—— 真机 402×874 上「重复当前状态」在 y 763–827、求助条在 y 772–836，
    /// 中心点 795 落在 `insetBy(dy: 44)` 给出的 44…830 里，于是 helper 一次都没滚就返回了。
    ///
    /// ponytail: 固定 112pt，不去查每个底栏的真实高度 —— 那要按 identifier 逐个登记，而全仓有
    /// 9 处 `safeAreaInset(edge: .bottom)`，登记表必然漏掉下一个。代价是在没有底栏的页面多滚
    /// 一两下（无害）。真要精确时再改成按 identifier 取底栏 frame。
    /// （盲人首页实测底栏顶边 772，874 − 772 = 102，这里留 10pt 余量。）
    private static let persistentBottomBarInset: CGFloat = 112

    /// 把控件滚进「真正能点」的区域。
    ///
    /// 判据是「中心点在可见区内 **且** 整个 frame 不越过可见区底边」：只判中心点会放过
    /// 下半截被底栏盖住的控件 —— 那正是上面那次误触的成因。用中心点而不是 `isHittable`：
    /// 禁用态的按钮永远不 hittable，用它会让上限用例白白滑满 `maxSwipes` 次。
    ///
    /// 返回是否真的滚到位。**底部有常驻栏的页面必须断言返回值** —— 否则滚不动时这里静默放弃，
    /// 接下来的 `tap()` 打在别的控件上，报出来的错和真因毫无关系。
    @discardableResult
    func scrollElementIntoView(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 5) -> Bool {
        let appFrame = app.frame
        guard !appFrame.isNull, !appFrame.isEmpty else { return false }
        let top = appFrame.minY + 44
        let bottom = min(
            appFrame.maxY - Self.persistentBottomBarInset,
            measuredBottomBarTop(app) ?? .greatestFiniteMagnitude
        )
        guard bottom > top else { return false }
        let visibleArea = CGRect(x: appFrame.minX, y: top, width: appFrame.width, height: bottom - top)

        func isUncovered() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            guard !frame.isNull, !frame.isEmpty else { return false }
            return visibleArea.contains(CGPoint(x: frame.midX, y: frame.midY))
                && frame.maxY <= visibleArea.maxY
        }

        for _ in 0..<maxSwipes {
            if isUncovered() { return true }
            guard element.exists else { return false }
            scrollableSurface(app).swipeUp()
        }
        return isUncovered()
    }

    /// 量得到真实高度的底栏，返回它的顶边；量不到返回 `nil`（退回固定的 112pt）。
    ///
    /// 🔴 **为什么这个不能只靠上面那个常量**：112 是照盲人首页的底栏（实测 102pt）定的，
    /// 而志愿者「我」首屏底部那条可服务 CTA 在**已开启**时轨道里是两行字（主文案 + 副提示），
    /// AX5 下更高 —— 实测远超 112。常量偏小的后果不是「多滚一下」，
    /// 而是 helper 认为控件已经露出来了、直接返回 true，接着 `tap()` 打在底栏上。
    /// 那正是 2026-08-14 差点拨出 110 的同一个形状。
    ///
    /// 盲人标签页同理：求助条叠在标签栏上方之后顶边是 723（874 − 723 = 151pt），比 112 高 39pt。
    /// 一行的底边压在 723–762 之间时 helper 判「已露出」，触点其实在求助条上，弹出「紧急呼叫」单
    /// （记忆 `ui-test-tap-lands-on-persistent-sos-bar`）。
    ///
    /// ponytail: 只登记**已知会超过 112pt 的**那两个，不做全量登记表 ——
    /// 上面那条注释说得对，登记表必然漏掉下一个。这里漏掉的会退回旧行为，不会变得更糟。
    private func measuredBottomBarTop(_ app: XCUIApplication) -> CGFloat? {
        ["volunteerAvailabilitySlider", "blindRunnerHomeSOSBar"]
            .map { app.descendants(matching: .any)[$0].firstMatch }
            .filter { $0.exists }
            .map(\.frame)
            .filter { !$0.isNull && !$0.isEmpty }
            .map(\.minY)
            .min()
    }
}
