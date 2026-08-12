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
            .pendingAccept: .success,
            .driverEnRoute: .success,
            .driverArrived: .success,
            .inProgress: .success,
            .completed: .success,
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
