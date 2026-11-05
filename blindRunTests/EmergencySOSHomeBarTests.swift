import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSHomeBarTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - 首页 SOS 条：模式判定与拨号

    /// 首页那条求助按钮在**没有进行中订单**时绝不能走云端 —— `POST /api/emergency/trigger`
    /// 两端都只在 `IN_PROGRESS` 开放且必须带 `orderId`（`AGENTS.md` §6）。
    ///
    /// 这条判据此前只存在于 View 的私有属性里，而真机 UI 测试通道起不来（code 74），
    /// 等于完全没有覆盖。抽成 `BlindHomeSOSMode.resolve` 就是为了能在这里钉住。
    func testHomeSOSBarOnlyUsesTheCloudPathDuringInProgress() {
        XCTAssertEqual(
            BlindHomeSOSMode.resolve(order: Self.makeOrder(status: .inProgress), role: .blind),
            .cloudTrigger
        )

        // 每一个非 IN_PROGRESS 的状态都必须降级成本地拨号，包括「志愿者已到达」这种
        // 看起来很接近服务中、最容易被误判的一档。
        for status in RunOrderStatus.allCases where status != .inProgress {
            XCTAssertEqual(
                BlindHomeSOSMode.resolve(order: Self.makeOrder(status: status), role: .blind),
                .localCall,
                "\(status) 不得走云端求助"
            )
        }
    }

    func testHomeSOSBarFallsBackToLocalCallWithoutAnOrderOrRole() {
        XCTAssertEqual(BlindHomeSOSMode.resolve(order: nil, role: .blind), .localCall)
        XCTAssertEqual(
            BlindHomeSOSMode.resolve(order: Self.makeOrder(status: .inProgress), role: nil),
            .localCall
        )
    }

    /// 号码里的空格/横线不过滤就会拼出无效 `tel://` URL，而无效 URL 的表现是「点了没反应」——
    /// 对盲人端就是事故：他以为电话正在拨出，其实什么都没发生。
    func testDialerKeepsOnlyDigitsAndRefusesEmptyNumbers() {
        XCTAssertEqual(EmergencyDialer.telURL(for: "138 0000 0000")?.absoluteString, "tel://13800000000")
        XCTAssertEqual(EmergencyDialer.telURL(for: "138-0000-0000")?.absoluteString, "tel://13800000000")
        XCTAssertEqual(EmergencyDialer.telURL(for: EmergencyDialer.policeNumber)?.absoluteString, "tel://110")

        XCTAssertNil(EmergencyDialer.telURL(for: nil))
        XCTAssertNil(EmergencyDialer.telURL(for: ""))
        XCTAssertNil(EmergencyDialer.telURL(for: "   "))
        XCTAssertNil(EmergencyDialer.telURL(for: "未填写"))
    }

    /// 🚨 **掩码串一律拼不出 `tel:` URL。** 2026-08-11 那个真实缺陷的机器守卫。
    ///
    /// 在这道闸之前，判据只有「取完数字位还剩不剩」，于是 `138****1234` **拼得出**
    /// `tel://1381234` —— 不是空号，是一个七位的、可能真打给别人的号码，
    /// 而界面上看不出任何异常。此前唯一的防线是「拨号入口只读明文那个字段」，
    /// 靠人记，而它有 15 个调用点、已经失效过一次。
    ///
    /// **两个方向都要断**，否则这条闸随时会被写成「凡是含非数字就拒」而悄悄拦掉明文号：
    /// 后端下发的明文号可能带空格或横线（上一条用例正断着这个），
    /// 而 110 / 120 只有三位 —— 任何按长度判的闸都会把它们一起拦掉。
    func testDialerRefusesMaskedNumbersButKeepsFormattedPlainOnes() {
        // 拒：掩码串（半角与全角）。
        XCTAssertNil(EmergencyDialer.telURL(for: "138****1234"))
        XCTAssertNil(EmergencyDialer.telURL(for: "139＊＊＊＊9001"))
        // 掩码那一半也可能出现在带前后缀的串里。
        XCTAssertNil(EmergencyDialer.telURL(for: "王* 138****1234"))
        // 真实来源对撞：`maskPhone` 出来的东西一律拨不出去。
        XCTAssertNil(EmergencyDialer.telURL(for: EmergencyContactResponse.maskPhone("13900139001")))

        // 放行：带格式化字符的明文号，以及三位急救号 —— 这两条是这道闸的误报面。
        XCTAssertEqual(EmergencyDialer.telURL(for: "138 0000 0001")?.absoluteString, "tel://13800000001")
        XCTAssertEqual(EmergencyDialer.telURL(for: "+86 138-0000-0001")?.absoluteString, "tel://8613800000001")
        XCTAssertEqual(EmergencyDialer.telURL(for: EmergencyDialer.medicalNumber)?.absoluteString, "tel://120")
    }

    /// 测试期拦截：开着时不真的拨、但要留痕；关掉时必须照常拨出去。
    ///
    /// **后半条和前半条一样重要。** 这道拦截如果把生产路径也吞了，盲人按下「拨打110」
    /// 会毫无反应 —— 那正是 `telURL` 只取数字要防的那种事故，只是换了个来源。
    /// `AGENTS.md` §6 限定它只能影响 DEBUG 构建。
    func testDialIsInterceptedOnlyWhileTheUITestSwitchIsOn() throws {
        let url = try XCTUnwrap(EmergencyDialer.telURL(for: EmergencyDialer.policeNumber))
        let wasBlocked = EmergencyDialer.isDialBlockedForUITesting
        defer { EmergencyDialer.isDialBlockedForUITesting = wasBlocked }
        EmergencyDialer.resetBlockedDialCountForTesting()

        var dialed: [URL] = []
        EmergencyDialer.isDialBlockedForUITesting = true
        EmergencyDialer.dial(url) { dialed.append($0) }
        XCTAssertEqual(dialed, [])
        XCTAssertEqual(
            EmergencyDialer.blockedDialCount,
            1,
            "拦截必须留痕，否则测试证明不了「按下去确实要拨」"
        )

        EmergencyDialer.isDialBlockedForUITesting = false
        EmergencyDialer.dial(url) { dialed.append($0) }
        XCTAssertEqual(dialed, [url], "开关关掉后必须照常拨出去")
        XCTAssertEqual(EmergencyDialer.blockedDialCount, 1)
    }

    /// 启动环境判定。默认认的是 UI 测试的启动标记，不是那个专用键 ——
    /// 本仓库有四处 `launchEnvironment` 装配，要求每处都记得加一行是挡不住的。
    func testDialBlockDefaultsToOnForAnyUITestLaunchEnvironment() {
        XCTAssertTrue(EmergencyDialer.resolveDialBlock(from: ["AIDRUN_UI_TEST_RESET_STATE": "1"]))
        XCTAssertTrue(EmergencyDialer.resolveDialBlock(from: [EmergencyDialer.uiTestBlockEnvironmentKey: "1"]))

        // 显式关掉优先于启动标记：将来真要有用例验拨号，得留这个出口。
        XCTAssertFalse(EmergencyDialer.resolveDialBlock(from: [
            "AIDRUN_UI_TEST_RESET_STATE": "1",
            EmergencyDialer.uiTestBlockEnvironmentKey: "0"
        ]))

        // 手动跑 App（没有任何 UI 测试变量）绝不能被拦。
        XCTAssertFalse(EmergencyDialer.resolveDialBlock(from: [:]))
    }

    /// 本地拨号分支的文案必须说清「App 不会代你发送求助」。
    /// 缺了这句，盲人按完只会听见拨号音之外的沉默，并合理地以为求助已经发出去了。
    func testLocalCallCopySaysTheAppSendsNothing() {
        // 两种语境一条都不能漏。漏掉的那一条不会有任何运行时症状：弹窗照常弹，只是话说错了。
        for context in [EmergencyCallContext.homeIdle, .cloudFailed] {
            XCTAssertTrue(
                context.dialogMessage.contains("不会代你发送求助"),
                "\(context) 的弹窗正文没说清 App 什么都没发出去"
            )
            XCTAssertTrue(
                context.accessibilityHint.contains("不会代你发送求助"),
                "\(context) 的读屏提示没说清 App 什么都没发出去"
            )
        }

        // 第一句是两种语境唯一的区别，也是盲人判断「我刚才那一下发生了什么」的唯一依据。
        // 共用一句等于把「求助已失败」和「求助从没按过」说成同一件事。
        let messages = Set([EmergencyCallContext.homeIdle, .cloudFailed].map(\.dialogMessage))
        XCTAssertEqual(messages.count, 2, "两种语境的第一句必须各不相同")

        // 「一键求助」在本 App 里专指云端求助，本地拨号分支不得复用这四个字。
        XCTAssertFalse(EmergencySafetyCopy.homeCallTitle.contains(EmergencySafetyCopy.title))

        // 原来第三种语境 `inProgress` 扛的那条不变式 —— 「这不是一键求助，什么都还没发出去」——
        // 现在由求助中心的第一句扛。它比原来更要紧：那一层的第一项是「联系志愿者」这种无害动作，
        // 用户按下红块之后最需要先知道的就是**什么都还没发生**。
        XCTAssertTrue(
            EmergencySafetyCopy.hubDialogMessage.contains("还没有发送求助"),
            "求助中心的第一句必须先说清什么都还没发出去"
        )
        // 求助中心的标题不得叫「一键求助」—— 那四个字专指云端那条链路，
        // 而打开这个菜单一个字节都没发出去。
        XCTAssertFalse(EmergencySafetyCopy.hubTitle.contains(EmergencySafetyCopy.title))
        // ⛔ 逐字锁定的二次确认文案不许被挪用成菜单正文（`AGENTS.md` §6 的二次确认不减一步）。
        XCTAssertNotEqual(EmergencySafetyCopy.hubDialogMessage, EmergencySafetyCopy.confirmationMessage)
        XCTAssertFalse(EmergencySafetyCopy.hubDialogMessage.contains("确认进入求助状态"))
    }
}
