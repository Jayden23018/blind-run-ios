//
//  AccessibilityAuditTests+Audit.swift
//  blindRunUITests
//
//  整页无障碍审计的共用 helper `audit(_:)` 与它的放行判据。
//  从 `AccessibilityAuditTests.swift` 挪出来（#480）：那个文件已超 3000 行，SwiftLint 棘轮不许再变长。
//

import XCTest

extension AccessibilityAuditTests {
    @available(iOS 17.0, *)
    func audit(_ app: XCUIApplication) throws {
        // iOS 侧七个审计类型**全部**启用。少一项就少一类缺陷，而少了哪一项从测试结果上
        // 完全看不出来 —— 用例照样报绿，绿的是剩下那几项。守卫 `a11y-audit-types`
        // 会拦住任何缺项（`scripts/hooks/guard.mjs`）。
        //
        // 2026-09-02 补进 `.textClipped` 与 `.trait`：此前这两项从未启用，而 `AccessibilityAuditTests.swift`
        // `:560-566` 的注释逐字宣称「审计里真正抓这件事的是 `.textClipped` 与 `.hitRegion`」，
        // 并把三条横屏用例定为「本仓库唯一能验横屏裁切的通道」⇒ 那三条长期在验另外五项，
        // 横屏裁切一次都没被检查过。`.trait` 同样是盲人端硬伤：按钮缺 `.button` trait 时
        // VoiceOver 不念「按钮」，用户不知道那是个能点的东西。
        // 陪跑员跑步页的底部栏是**叠在滚动内容上**的不透明栏（#227 的设计）。AX3 / 横屏下内容超过一屏时，
        // 滚到栏后面的卡片被整个挡住，可审计仍按它的坐标取像素 —— 取到的全是栏的底色，于是判「对比度不足」
        // （2026-09-27 真机：「跑者还没有发来节奏」那张卡，元素截图里只有栏的分隔线）。
        // 判据是几何不是文案：**整个落在栏上沿以下**的元素才放过，露出一截的照样审。
        // 2026-10-06（#349）盲人订单页的底栏同理：「求助与安全」那条是不透明栏，横屏下 v2 头卡把副文与信息卡
        // 推到它后面，元素截图里只有栏的红边与粉底（「系统正在派单，请稍候。」「时间」两条）。
        let occludingBarTop: OccludingBar? = {
            // 盲人通话页（#434）同一条底栏组件：B3 的安排单在「求助与安全」后面滚动。
            // 陪跑员首页底部的接单滑块（滑块后面压着徽章与「最近陪跑」，#515）。
            for id in ["volunteerRunningBottomBar", "blindOrderFlowBottomBar", "blindIntroCallBottomBar", "volunteerHomeBottomBar", "blindBookingBottomBar"] {
                let bar = app.descendants(matching: .any)[id].firstMatch
                // 栏自己的子元素（按钮、滑块）是看得见的，照常审计；只有压在栏后面的页面内容才算被遮挡。
                if bar.exists { return OccludingBar(top: bar.frame.minY, ownFrames: bar.descendants(matching: .any).allElementsBoundByIndex.map(\.frame)) }
            }
            // 悬浮标签栏同理：#605 删掉红条后，二级页下半截滚到它后面，元素截图里只有栏的毛玻璃。
            let tabBar = app.tabBars.firstMatch
            guard tabBar.exists else { return nil }
            return OccludingBar(top: tabBar.frame.minY, ownFrames: tabBar.descendants(matching: .any).allElementsBoundByIndex.map(\.frame))
        }()
        // 顶部同理：测试构建才有的 Mock 横幅（`ContentView` 里 `#if DEBUG` 那枚黄胶囊）字号可缩放，
        // AX4/AX5 下会长到导航栏上，把页面标题整个盖住 —— 2026-10-19 空闲时间页 AX5 暗色（#466），
        // 「空闲时间」标题报 Contrast failed，截图里那块只有横幅的黄底。横幅不进发布包。
        // 判据同样是几何：**整个落在横幅框内**的元素才放过。
        let mockBannerFrame: CGRect? = {
            let banner = app.descendants(matching: .any)["mockEnvironmentBanner"].firstMatch
            return banner.exists ? banner.frame : nil
        }()
        // 被屏幕边缘切掉一截的元素，`.contrast` 只拿露出来的那一条像素算对比度（#480）。
        // 2026-10-22 真机 iPhone 16 Pro / iOS 27.0.1、AX5，空闲时间页滚到底：「09:00 – 12:00」
        // frame (32, -62, 333, 63.3)，只露 1.3pt，报 Contrast failed；同一元素整个露出来时 6.65:1。
        // 换一个元素露 1.3pt（组标题）照样报，露 40pt 不报；单开 `.contrast` 时页面一动不动也照样报
        // ⇒ 不是「审计滚动途中取样」。会滚页面的是 `.dynamicType` 与 `.textClipped`（单开它们，
        // 页面被滚回顶部、什么都不报）—— 所以七项合审时失败附件的 App Screenshot 停在顶部，
        // 回调里读到的 frame 也是滚动之后的，与取样时对不上。
        //
        // 因此分两遍：`.contrast` 单独先审（不滚动，回调里的 frame 就是取样时的位置，上面两条
        // 几何遮挡判据也才准），其余六项第二遍。审计时没有整个落在屏内的元素这一遍不下结论，
        // 记下来，最后逐个滚到整个露出再单审一次 —— 仍报才算失败，滚不出来直接 XCTFail。
        // **不放过任何一条**：真的对比度不足，整个露出来时照样报。
        let screen = app.frame
        var cutByScreenEdge: [(element: XCUIElement, label: String)] = []
        try app.performAccessibilityAudit(
            for: [
                .contrast // guard:allow a11y-audit-types —— 对比度单独一遍（#480），其余六项在下一遍，两遍合起来是全集
            ]
        ) { issue in
            // 先走原有的遮挡 / 白名单放行，放不掉的才看是否被屏幕边缘切掉。
            if self.isAllowedAuditIssue(issue, occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame) {
                return true
            }
            if let element = issue.element {
                let frame = element.frame
                if !frame.isEmpty, !Self.isShownAsFullyAsPossible(frame, on: screen) {
                    let label = element.label
                    print("[AUDIT-partial] \(label) frame=\(frame) 没有整个落在屏内（\(screen)），整个露出后再审")
                    cutByScreenEdge.append((element, label))
                    return true
                }
            }
            return self.isIgnoredAuditIssue(issue, occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame)
        }
        try app.performAccessibilityAudit(
            for: [
                .dynamicType, .elementDetection, .hitRegion, // guard:allow a11y-audit-types —— .contrast 在上一遍（#480）
                .sufficientElementDescription, .textClipped, .trait
            ]
        ) { issue in
            self.isIgnoredAuditIssue(issue, occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame)
        }
        for cut in cutByScreenEdge {
            try recheckContrastFullyOnScreen(
                cut.element, label: cut.label, in: app,
                occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame
            )
        }
    }

    /// 审计时被屏幕边缘切掉一截的元素：滚到整个露出，单审一次 `.contrast`，只认它自己的那一条（#480）。
    /// 其他元素这一遍不判：第一遍时在屏内的已经判过；第一遍时整个在屏外的，这次 `audit` 不保证判到
    ///（要覆盖它们，就把页面滚到那里再调一次 `audit`）。
    @available(iOS 17.0, *)
    private func recheckContrastFullyOnScreen(
        _ element: XCUIElement, label: String, in app: XCUIApplication,
        occludingBarTop: OccludingBar?, mockBannerFrame: CGRect?
    ) throws {
        let screen = app.frame
        // 回调给的元素绑定的是那一个无障碍元素；`List` 复用行之后它会消失，这时按文案找回来。
        var element = element
        if !element.exists {
            print("[AUDIT-partial] 「\(label)」原元素已不在（行被复用），按文案找同名元素复审")
            element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        // 页面可见的部分到底栏上沿为止：露在屏内却压在栏后面，取到的是栏的颜色（#515，最大字号下元素高 408pt）。
        let visibleArea = CGRect(
            x: screen.minX, y: screen.minY, width: screen.width,
            height: (occludingBarTop?.top ?? screen.maxY) - screen.minY
        )
        var swipes = 0
        while element.exists, swipes < Self.maxSwipesToRevealCutElement {
            let frame = element.frame
            if Self.isShownAsFullyAsPossible(frame, on: visibleArea) { break }
            // 差多少拖多少、按住再拖（不带惯性）：整页 `swipeUp` 一次跨度比高个子元素的余量大，
            // 会在「从底下露出」与「甩出顶部」之间来回振荡（#515，AX5 下 408pt 高的培训卡说明）。
            let shift = frame.maxY > visibleArea.maxY ? -(frame.maxY - visibleArea.maxY + 24) : (-frame.minY + 24)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: shift < 0 ? 0.7 : 0.3))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: shift)))
            swipes += 1
        }
        guard element.exists, Self.isShownAsFullyAsPossible(element.frame, on: visibleArea) else {
            XCTFail("""
            「\(label)」审计时被屏幕边缘切掉一截，滚了 \(Self.maxSwipesToRevealCutElement) 次也没能整个露出来 \
            —— 它的对比度没有被判定过（#480）
            """)
            return
        }
        waitUntilSettled(element)
        let target = element
        try app.performAccessibilityAudit(
            for: [
                .contrast // guard:allow a11y-audit-types —— 只复审一个元素的对比度（#480），其余六项 audit 里已审
            ]
        ) { issue in
            guard let other = issue.element, other.identifier == target.identifier,
                  other.label == target.label, other.frame == target.frame else { return true }
            return self.isIgnoredAuditIssue(issue, occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame)
        }
    }

    /// 复审时最多滑几次去把被切掉的元素整个露出来（#480）。
    private static let maxSwipesToRevealCutElement = 4

    /// 元素在屏内露得是否已经「尽可能完整」：每个方向上露出的长度 ≥ min(元素长度, 屏幕长度)。
    /// 比屏幕还高 / 还宽的元素铺满那个方向就算，否则它永远判不了（#480）。
    private static func isShownAsFullyAsPossible(_ frame: CGRect, on screen: CGRect) -> Bool {
        let visible = frame.intersection(screen)
        guard !visible.isNull else { return false }
        return visible.width >= min(frame.width, screen.width) - 0.5
            && visible.height >= min(frame.height, screen.height) - 0.5
    }

    /// `audit` 的放行判据：返回 `true` 表示这一条不算失败；不放行时打出 `[AUDIT]` 那一行。
    @available(iOS 17.0, *)
    private func isIgnoredAuditIssue(
        _ issue: XCUIAccessibilityAuditIssue, occludingBarTop: OccludingBar?, mockBannerFrame: CGRect?
    ) -> Bool {
        if isAllowedAuditIssue(issue, occludingBarTop: occludingBarTop, mockBannerFrame: mockBannerFrame) {
            return true
        }
        // 审计失败只报一句「Contrast failed」，**不说是哪个元素** —— 2026-08-14 为定位一次
        // 对比度失败，加打印、重跑、再删，白花了两轮真机。留着，失败日志里直接就有。
        print("""
        [AUDIT] \(issue.auditType) id=\(issue.element?.identifier ?? "") label=\(issue.element?.label ?? "") \
        frame=\(issue.element?.frame ?? .zero) \(issue.detailedDescription)
        """)
        return false
    }

    /// 遮挡与白名单：几何上看不见的、或白名单里的元素，返回 `true`。
    @available(iOS 17.0, *)
    private func isAllowedAuditIssue(
        _ issue: XCUIAccessibilityAuditIssue, occludingBarTop: OccludingBar?, mockBannerFrame: CGRect?
    ) -> Bool {
        if issue.auditType == .contrast, let bar = occludingBarTop, let frame = issue.element?.frame,
           frame.minY >= bar.top - 0.5, !bar.ownFrames.contains(frame) {
            let top = bar.top
            print("[AUDIT-occluded] \(issue.element?.label ?? "") frame=\(frame) 在底部栏（上沿 \(top)）后面，不可见")
            return true
        }
        if issue.auditType == .contrast, let banner = mockBannerFrame,
           issue.element?.identifier != "mockEnvironmentBanner",
           let frame = issue.element?.frame, !frame.isEmpty, banner.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
            print("[AUDIT-occluded] \(issue.element?.label ?? "") frame=\(frame) 在 Mock 横幅（\(banner)）下面，不可见")
            return true
        }
        // 高德地图图层无法承载有意义的 label，且它已被显式降权为辅助内容
        // （视觉可以铺满，读屏遍历顺序必须操作优先）。这是唯一的白名单项 ——
        // 每加一条都要写清为什么，否则白名单会慢慢把审计架空。
        let identifier = issue.element?.identifier ?? ""
        let label = issue.element?.label ?? ""
        return Self.auditIgnoredIdentifiers.contains(identifier) || Self.auditIgnoredLabels.contains(label)
    }

    /// 审计白名单。**每加一条都要写清为什么，否则白名单会慢慢把审计架空。**
    private static let auditIgnoredIdentifiers: Set<String> = [
        // 高德地图图层无法承载有意义的 label，且它已被显式降权为辅助内容
        // （视觉可以铺满，读屏遍历顺序必须操作优先）。
        //
        // `blindRunnerHomeAuxiliaryMap` 已于 2026-08-14（`30b0770`）随「盲人首页装饰地图对读屏隐藏」
        // 一起删除，不再需要白名单 —— 死条目会让人以为这一项还在被放行。
        "blindBookingAuxiliaryMap",
        "mapPlaceholder"
    ]

    /// 上面两个地图的替身：缺高德 key 时（UI 测试构建**永远**缺）渲染的占位图。
    ///
    /// **按文案而不是 identifier 认它**：`MapPlaceholderView` 上确实挂了
    /// `accessibilityIdentifier("mapPlaceholder")`，但审计穿透 `children: .combine`
    /// 报的是内部那几个 `Text`，它们的 identifier 是空字符串 —— 只按 id 白名单放不掉。
    ///
    /// 2026-08-14 加：地图从 300 压到 200pt 后它开始报 `Contrast failed`，而它用的是
    /// `.label` on `.secondarySystemBackground`（约 19:1）—— **颜色没问题**，是文字位置
    /// 变了之后审计的采样结果变了。放行的理由不是「颜色达标」，而是：它只在缺 key 时出现，
    /// 生产构建走真地图；且这几句话是给开发者看的，不是盲人用户的界面。
    ///
    /// 按文案匹配意味着**改文案会让白名单失效**。那是想要的行为：文案变了就该重新审一次。
    private static let auditIgnoredLabels: Set<String> = [
        "地图服务暂不可用",
        "请配置高德地图 API Key",
        "参考 LocalConfig.xcconfig.example 创建配置文件",
        "地图服务暂不可用，请配置高德地图 API Key"
    ]
}

/// 底部不透明栏：上沿以下、又不是栏自己子元素的，算被栏挡住（`isAllowedAuditIssue`）。
struct OccludingBar {
    let top: CGFloat
    /// 栏里每个子元素的 frame。审计点名的元素与其中之一重合 = 栏自己的内容（看得见），照常审。
    let ownFrames: [CGRect]
}

