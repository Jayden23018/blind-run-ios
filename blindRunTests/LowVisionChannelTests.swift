import XCTest
@testable import blindRun

/// 低视力用户的视觉/触觉通道。
///
/// 这两块此前是全空白，而 `VisionLevel.LOW_VISION` 在数据模型里是一等公民 ——
/// 低视力是目标用户，不是边缘情况。
///
/// 这里钉的是**能被算出来的那部分**：颜色对比度是纯数值，触觉映射是穷举分支。
/// 剩下的（横屏布局、Dynamic Type 放开后会不会裁切）只有真机
/// `blindRunUITests/AccessibilityAuditTests` 能验，本文件不冒充覆盖它们。
final class LowVisionChannelTests: XCTestCase {

    // MARK: - 对比度

    /// WCAG 1.4.3 正文阈值。大字与 UI 部件是 3:1，但本 App 的语义色同时用在两类文本上，
    /// 按严的那条卡 —— 放宽到 3.0 就等于允许「只有标题读得清」。
    private static let minimumContrast: Double = 4.5

    /// 每个语义色要在**四种组合**下都达标。
    ///
    /// 只测「亮色 on 纯白」是不够的：`secondarySystemBackground` 在亮色下是 #F2F2F7、
    /// 暗色下是 #1C1C1E，而本 App 的状态卡、错误条大量压在次级背景上 ——
    /// 那才是对比度最紧的地方（实测 `success` 在亮/次级底上只剩 4.54）。
    private static let backgrounds: [(name: String, light: UInt32, dark: UInt32)] = [
        ("systemBackground", 0xFFFFFF, 0x000000),
        ("secondarySystemBackground", 0xF2F2F7, 0x1C1C1E),
    ]

    func testEverySemanticColorClearsTheBodyTextContrastThresholdInBothAppearances() {
        XCTAssertFalse(AppColors.tones.isEmpty, "调色板是空的，这条用例会假通过")

        for (name, tone) in AppColors.tones {
            for background in Self.backgrounds {
                let lightRatio = Self.contrastRatio(tone.light, background.light)
                XCTAssertGreaterThanOrEqual(
                    lightRatio, Self.minimumContrast,
                    "亮色模式 \(name) 压在 \(background.name) 上只有 \(String(format: "%.2f", lightRatio)):1"
                )

                let darkRatio = Self.contrastRatio(tone.dark, background.dark)
                XCTAssertGreaterThanOrEqual(
                    darkRatio, Self.minimumContrast,
                    "暗色模式 \(name) 压在 \(background.name) 上只有 \(String(format: "%.2f", darkRatio)):1"
                )
            }
        }
    }

    /// 语音态那块占满内容区的蓝底，验的方向和上面那条**相反**：它是背景，白字压在它上面。
    ///
    /// 所以它不在 `AppColors.tones` 里 —— 硬塞进去会得到一条方向反了的断言
    /// （暗色值 `#0B4DA2` 压在纯黑上只有 2.6:1，会把一个正确的取值判成不达标）。
    ///
    /// 暗色**不能**沿用 `primary` 的 `#0A84FF`：白字压上去只有 3.38:1。这条用例就是
    /// 挡住「顺手复用 primary」那一步的地方 —— 那是改这块底色时最自然的第一反应。
    func testVoiceStageSurfaceKeepsWhiteTextReadable() {
        let white: UInt32 = 0xFFFFFF
        let tone = AppColors.voiceStageSurfaceTone

        let lightRatio = Self.contrastRatio(white, tone.light)
        XCTAssertGreaterThanOrEqual(
            lightRatio, Self.minimumContrast,
            "亮色模式下白字压在语音态蓝底上只有 \(String(format: "%.2f", lightRatio)):1"
        )

        let darkRatio = Self.contrastRatio(white, tone.dark)
        XCTAssertGreaterThanOrEqual(
            darkRatio, Self.minimumContrast,
            "暗色模式下白字压在语音态蓝底上只有 \(String(format: "%.2f", darkRatio)):1"
        )

        // 验红：被拒掉的那个候选值必须真的算不过，否则上面两条断言可能是在一个恒真的公式上通过。
        XCTAssertLessThan(
            Self.contrastRatio(white, 0x0A84FF), Self.minimumContrast,
            "systemBlue 当大面积底色时白字不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    /// 志愿者「可服务」已开启时那条绿色状态条，白字压在它上面。
    ///
    /// 它是首屏**底部唯一的常驻控件** —— 读不清等于「我到底开没开」这件事没有视觉答案，
    /// 而那正是低视力志愿者最需要一眼确认的一件事。
    ///
    /// 暗色**不能**沿用 `success` 的 `#30D158`：白字压上去只有 2.02:1。
    /// 这条用例就是挡住「顺手复用 success」那一步的地方 —— 那是画一条绿色状态条时
    /// 最自然的第一反应（本轮实现时第一版就是那么写的）。
    func testAvailabilityOnSurfaceKeepsWhiteTextReadable() {
        let white: UInt32 = 0xFFFFFF
        let tone = AppColors.availabilityOnSurfaceTone

        let lightRatio = Self.contrastRatio(white, tone.light)
        XCTAssertGreaterThanOrEqual(
            lightRatio, Self.minimumContrast,
            "亮色模式下白字压在可服务状态条上只有 \(String(format: "%.2f", lightRatio)):1"
        )

        let darkRatio = Self.contrastRatio(white, tone.dark)
        XCTAssertGreaterThanOrEqual(
            darkRatio, Self.minimumContrast,
            "暗色模式下白字压在可服务状态条上只有 \(String(format: "%.2f", darkRatio)):1"
        )

        // 验红：被拒掉的那个候选值必须真的算不过，否则上面两条断言可能是在一个恒真的公式上通过。
        XCTAssertLessThan(
            Self.contrastRatio(white, 0x30D158), Self.minimumContrast,
            "success 的暗色值当大面积底色时白字不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    /// 陪跑进行中那一屏铺满的深灰底。方向同上：它是背景，白字与次级灰字压在它上面。
    ///
    /// 🔴 **它亮暗两套同值**（全 App 唯一一处不跟随系统外观），所以「亮色模式下它仍然是深灰」
    /// 这件事必须被钉住 —— 一旦有人把它改成跟随系统，亮色模式下白字就压在白底上，
    /// 而那一屏只有三个数字，等于整屏空白。对低视力用户，那条通道就是全部。
    func testActiveRunSurfaceKeepsItsTextReadableInBothAppearances() {
        let tone = AppColors.activeRunSurfaceTone
        XCTAssertEqual(tone.light, tone.dark, "这块底色刻意不跟随系统外观，两套必须同值")

        let white: UInt32 = 0xFFFFFF
        let primaryRatio = Self.contrastRatio(white, tone.light)
        XCTAssertGreaterThanOrEqual(
            primaryRatio, Self.minimumContrast,
            "白色主数字压在陪跑中底色上只有 \(String(format: "%.2f", primaryRatio)):1"
        )

        // 指标标签用的是专门调过的次级灰，不是 `textSecondary`。
        let secondary = AppColors.activeRunSecondaryTextTone
        XCTAssertEqual(secondary.light, secondary.dark, "同底色，次级文字也不跟随系统外观")
        let secondaryRatio = Self.contrastRatio(secondary.light, tone.light)
        XCTAssertGreaterThanOrEqual(
            secondaryRatio, Self.minimumContrast,
            "指标标签压在陪跑中底色上只有 \(String(format: "%.2f", secondaryRatio)):1"
        )

        // 验红：`textSecondary` 的亮色档正是这里最自然的「顺手复用」，而它算不过。
        // 没有这条，上面两条断言可能是在一条恒真的公式上通过。
        XCTAssertLessThan(
            Self.contrastRatio(AppColors.tones.first { $0.name == "textSecondary" }!.tone.light, tone.light),
            Self.minimumContrast,
            "textSecondary 的亮色档压在这块深灰底上不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    /// 陪跑中那块贴底的求助红块，验的是**块的边界**而不是块里的字。
    ///
    /// WCAG 1.4.11：用来识别控件边界的非文本内容要 3:1。这一块是那一屏**唯一**的控件，
    /// 边界看不见等于这屏没有可按的东西 —— 而这恰恰是对比度审计查不出来的那一类
    /// （它查的是文字对背景，不是色块对色块）。
    func testActiveRunSafetyBlockStaysDistinguishableFromItsSurface() {
        /// WCAG 1.4.11 的非文本阈值。
        let nonTextMinimum: Double = 3.0
        let surface = AppColors.activeRunSurfaceTone
        let block = AppColors.activeRunDestructiveTone

        XCTAssertEqual(block.light, block.dark, "底色固定，红块也不能跟随系统外观")

        let boundary = Self.contrastRatio(block.light, surface.light)
        XCTAssertGreaterThanOrEqual(
            boundary, nonTextMinimum,
            "求助红块与陪跑中底色只差 \(String(format: "%.2f", boundary)):1，块的边界会糊掉"
        )

        // 块里的白字按**大字**阈值（31pt 粗体）卡 3:1，不是正文的 4.5。
        let label = Self.contrastRatio(0xFFFFFF, block.light)
        XCTAssertGreaterThanOrEqual(
            label, nonTextMinimum,
            "求助两个字压在红块上只有 \(String(format: "%.2f", label)):1"
        )

        // 🔴 验红，也是这条用例被写下来的原因：`destructive` 的**亮色档**压在这块深灰底上
        // 只有 2.96:1 —— 就在 3:1 线下面一点。「顺手用 AppColors.destructive」是这里最自然的
        // 第一反应，而它差的那 0.04 用肉眼一定看不出来。
        XCTAssertLessThan(
            Self.contrastRatio(AppColors.tones.first { $0.name == "destructive" }!.tone.light, surface.light),
            nonTextMinimum,
            "destructive 的亮色档压在这块深灰底上不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    /// 这条是**验红**用的：把已知不达标的旧取值喂进同一个计算，必须算出不达标。
    ///
    /// 没有它，上面那条用例在计算公式写错时会静默全绿 —— 一个恒返回 21 的
    /// `contrastRatio` 能让所有断言通过。旧值取自换掉之前真实在用的 iOS 系统色。
    func testTheContrastFormulaActuallyRejectsTheOldSystemColors() {
        let oldSystemOrange: UInt32 = 0xFF9500
        let oldSystemGreen: UInt32 = 0x34C759
        let oldSystemBlue: UInt32 = 0x007AFF

        XCTAssertLessThan(Self.contrastRatio(oldSystemOrange, 0xFFFFFF), Self.minimumContrast)
        XCTAssertLessThan(Self.contrastRatio(oldSystemGreen, 0xFFFFFF), Self.minimumContrast)
        XCTAssertLessThan(Self.contrastRatio(oldSystemBlue, 0xFFFFFF), Self.minimumContrast)

        // 纯黑压纯白是公式的上界，21:1。算不出这个数就说明公式本身错了。
        XCTAssertEqual(Self.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }

    // MARK: - 触觉

    /// 触觉是语音的**冗余**通道，所以「哪些状态震」必须和「哪些状态播报」对齐 ——
    /// 除了 `pendingMatch`（下单流程自己已经给过反馈，再震一次是重复的）。
    func testEveryOrderStatusMakesAnExplicitHapticDecision() {
        let expected: [RunOrderStatus: HapticFeedback.Kind?] = [
            .pendingMatch: nil,
            // 有人想陪你跑，而且**需要你去打一通电话** —— 既是好消息又带着一个待办，
            // 正是该打断用户的时刻。
            .pendingIntroCall: .success,
            // 「有人接了你那张跨天单」是纯好消息，与 `.pendingAccept` 同档。
            .scheduledConfirmed: .success,
            .pendingAccept: .success,
            .driverEnRoute: .success,
            .driverArrived: .success,
            .inProgress: .success,
            // 🔴 2026-09-17 从 `.success` 换成 `.strong`（设计稿 ④「+ 强震一次」）。
            // 前面每一次推进都在说「下一步来了」，这一次说的是「结束了」——
            // 同一个波形分不出这层差别，而对看不见屏幕的人这是他确认跑完了的那条通道。
            .completed: .strong,
            .cancelled: .warning,
            .noVolunteer: .warning,
            .rematching: .warning,
            .unknown: .warning,
        ]

        // `.unknown` 不在 `allCases` 里（`OrderEnumLeniencyDecodingTests` 钉着这条），
        // 但它恰恰是最需要明确决策的一个 —— 后端加了新状态时用户落到的就是它。手动补上。
        let allStatuses = RunOrderStatus.allCases + [.unknown]
        XCTAssertEqual(
            Set(expected.keys), Set(allStatuses),
            "预期表与真实状态集不一致：漏掉的状态不会被断言，多出来的说明表过期了"
        )

        // 穷举而不是抽样：这个 switch 的价值就在于后端加状态时编译器逼一次决策，
        // 用例这边漏掉一个状态，那次决策就没人复核。
        for status in allStatuses {
            XCTAssertTrue(
                expected.keys.contains(status),
                "\(status) 是新状态，请在这里明确它该不该震，不要让它默认掉进 nil"
            )
            XCTAssertEqual(
                status.haptic, expected[status] ?? nil,
                "\(status) 的触觉语义与预期不符"
            )
        }
    }

    /// 「服务已完成」和「订单被取消」都会播报，但一个是好消息一个不是 ——
    /// 看不见屏幕的人靠震动的**语义差别**分辨，两者相同就等于没有信息。
    func testProgressAndSetbackDoNotShareTheSameHaptic() {
        XCTAssertNotEqual(RunOrderStatus.completed.haptic, RunOrderStatus.cancelled.haptic)
        XCTAssertNotEqual(RunOrderStatus.driverArrived.haptic, RunOrderStatus.noVolunteer.haptic)
    }

    // MARK: - WCAG 相对亮度

    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    private static func relativeLuminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
