import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSSafetyHubTests: XCTestCase, EmergencySOSTestSupport {

    /// 求助中心的**顺序与可见性**。
    ///
    /// 这是安全路径上的位置记忆：盲人靠「往下第几个」找选项，顺序会变的菜单等于没有位置记忆。
    /// 而弹层的内容单测够不着、UI 测试只有真机一条通道 —— 所以判据被抽成
    /// `BlindActiveRunSafetyHubOption.options`，弹层由它驱动，这条用例钉的就是弹层真正用的那份。
    func testSafetyHubOptionOrderIsFixedAndOnlyMissingNumbersRemoveItems() {
        let contact = EmergencyContactResponse(
            id: 1,
            name: "妈妈",
            phone: "13812345678",
            relationship: "家人",
            isPrimary: true
        )

        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.options(volunteerPhone: "13900000000", primaryContact: contact),
            [.contactVolunteer, .announceLocation, .askQuestion,
             .callPrimaryContact, .callMedical, .callPolice, .triggerEmergency]
        )

        // 没有联系人：**只少那一项**，其余各项的相对次序一个不动。
        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.options(volunteerPhone: "13900000000", primaryContact: nil),
            [.contactVolunteer, .announceLocation, .askQuestion, .callMedical, .callPolice, .triggerEmergency]
        )

        // 还没有志愿者号码（或号码拼不出 tel:）同理。
        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.options(volunteerPhone: nil, primaryContact: contact),
            [.announceLocation, .askQuestion, .callPrimaryContact, .callMedical, .callPolice, .triggerEmergency]
        )

        // 空白号码等同于没有号码 —— 后端在某些状态下会把这个字段留空。
        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.options(volunteerPhone: "  ", primaryContact: nil),
            [.announceLocation, .askQuestion, .callMedical, .callPolice, .triggerEmergency]
        )

        // 云端求助那一项**永远在**，且永远是最后一个 —— 它是这一层唯一走后端的动作，
        // 位置固定才谈得上位置记忆。
        for volunteerPhone in [nil, "13900000000"] {
            for primaryContact in [nil, contact] {
                let options = BlindActiveRunSafetyHubOption.options(
                    volunteerPhone: volunteerPhone,
                    primaryContact: primaryContact
                )
                XCTAssertEqual(options.last, .triggerEmergency)
                XCTAssertTrue(options.contains(.announceLocation))
                XCTAssertTrue(options.contains(.askQuestion))
                XCTAssertTrue(options.contains(.callMedical))
                XCTAssertTrue(options.contains(.callPolice))
            }
        }
    }

    /// 🔴 **三个拨号项没有被折进一个二级「紧急呼叫」入口。**
    ///
    /// 设计稿上求助中心是 2×2 四格（联系志愿者 / 播报位置 / 问一句 / 人工客服），
    /// 照着做就得把「拨打联系人 / 120 / 110」收进第四格后面 —— 而那会让跑步途中拨 120
    /// 从一跳变成两跳。`AGENTS.md` §6 把 120 列成与 110 并列的常驻入口，
    /// 理由恰恰是「念得出来而按不到等于没有」；多一层菜单就是那句话的另一种写法。
    ///
    /// 这条用例钉的是**格子数由选项决定**，不由设计稿的行数决定：
    /// 谁要凑 2×2，它会红，并读到上面这段理由。
    func testDialingOptionsStayOneTapAwayInsteadOfCollapsingIntoAFourthTile() {
        let contact = EmergencyContactResponse(
            id: 1,
            name: "妈妈",
            phone: "13812345678",
            relationship: "家人",
            isPrimary: true
        )
        let tiles = BlindActiveRunSafetyHubOption.tiles(
            volunteerPhone: "13900000000",
            primaryContact: contact
        )

        // 拨号三项各自是一格，都在第一层。
        XCTAssertTrue(tiles.contains(.callPrimaryContact))
        XCTAssertTrue(tiles.contains(.callMedical))
        XCTAssertTrue(tiles.contains(.callPolice))
        XCTAssertGreaterThan(tiles.count, 4, "凑成 2×2 只能靠把拨号折进二级入口")

        // 云端求助**不是方格**：它是弹层底部整条的红胶囊，与其余各项既不同层级也不同后果。
        XCTAssertFalse(tiles.contains(.triggerEmergency))

        // 联系人与 120 / 110 的先后与首页那套逐项一致 —— 用户记住的是「往下第二个是 120」。
        let dialing = tiles.filter { [.callPrimaryContact, .callMedical, .callPolice].contains($0) }
        XCTAssertEqual(dialing, [.callPrimaryContact, .callMedical, .callPolice])
    }

    /// 「分享实时位置给家人」迁进求助中心（设计稿 §3.5），且**排在最后一格**。
    ///
    /// 迁移的理由是功能丢失，不是布局偏好：四步骨架换掉了
    /// `BlindOrderStatusView.trackingContent`，而那条列表里挂着这个功能唯一的入口
    /// （`runPlanShareSection`）—— `offersRunPlanShare` 恰好覆盖骨架那四态。
    ///
    /// 🔴 **排最后**是位置记忆那条硬约束的延续：拨号三项的下标一个都不许动。
    /// 插在中间的表现不会有任何东西报错 —— 只是某天用户按「往下第五个」拨 110，
    /// 按到的是分享。
    func testLiveShareTileIsAppendedLastAndNeverDisplacesTheDialingTiles() {
        let contact = EmergencyContactResponse(
            id: 1,
            name: "妈妈",
            phone: "13812345678",
            relationship: "家人",
            isPrimary: true
        )

        let withoutShare = BlindActiveRunSafetyHubOption.tiles(
            volunteerPhone: "13900000000",
            primaryContact: contact,
            offersLiveShare: false
        )
        let withShare = BlindActiveRunSafetyHubOption.tiles(
            volunteerPhone: "13900000000",
            primaryContact: contact,
            offersLiveShare: true
        )

        XCTAssertFalse(withoutShare.contains(.shareLiveLocation), "终态不该摆一个必然 409 的格子")
        XCTAssertEqual(withShare.last, .shareLiveLocation)
        // 逐项相同的前缀 = 既有各格的下标一个都没动。
        XCTAssertEqual(Array(withShare.dropLast()), withoutShare)

        // 云端求助仍然不是方格，也仍然是 `options` 的最后一项 —— 分享插在它之前。
        let options = BlindActiveRunSafetyHubOption.options(
            volunteerPhone: "13900000000",
            primaryContact: contact,
            offersLiveShare: true
        )
        XCTAssertEqual(options.last, .triggerEmergency)
        XCTAssertFalse(withShare.contains(.triggerEmergency))

        // 标题随「分享中」翻面 —— 告知页逐字承诺了「你可以随时停止分享」，
        // 这一格必须能变成「停止」，否则那句承诺在这一层里不成立。
        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.shareLiveLocation.title(contactName: nil, isLiveSharing: false),
            RunPlanLiveShareCopy.buttonTitle
        )
        XCTAssertEqual(
            BlindActiveRunSafetyHubOption.shareLiveLocation.title(contactName: nil, isLiveSharing: true),
            RunPlanLiveShareCopy.stopButtonTitle
        )
    }

    /// 🔴 **非 `IN_PROGRESS` 那一档的副标题与收起按钮必须换掉，不能只加一句提示。**
    ///
    /// 「跑步仍在记录」「收起，返回跑步」是为陪跑执行屏写的。骨架那四态
    /// **没有任何跑步在记录**，退回去看到的也是订单页而不是跑步屏 ——
    /// 而 header 是 `.combine` 合成**一个**无障碍元素的，那半句错话会和同一段里的
    /// 「陪跑还没开始」连成一句自相矛盾的播报，中间没有停顿让人判断哪半句算数。
    ///
    /// 这条是 2026-09-16 code review 抓到的：当轮只加了新提示、没换旧的两句。
    func testSafetyHubCopyDoesNotClaimARunIsUnderwayBeforeItStarts() {
        XCTAssertEqual(
            EmergencySafetyCopy.hubSubtitle(for: .cloudTrigger),
            EmergencySafetyCopy.hubSubtitle
        )
        XCTAssertEqual(
            EmergencySafetyCopy.hubDismissTitle(for: .cloudTrigger),
            EmergencySafetyCopy.hubDismissTitle
        )

        // `.localCall` 那一档：三处都不许出现「跑步」。
        let beforeTheRun = [
            EmergencySafetyCopy.hubSubtitle(for: .localCall),
            EmergencySafetyCopy.hubDismissTitle(for: .localCall),
            EmergencySafetyCopy.hubDismissHint(for: .localCall),
        ]
        for copy in beforeTheRun {
            XCTAssertFalse(
                copy.contains("跑步"),
                "陪跑还没开始，这句话却在说跑步：\(copy)"
            )
            XCTAssertFalse(copy.isEmpty)
        }

        // 反向：云端那一档**必须**保留「跑步仍在记录」。把两档都改成中性文案也能让上面全绿，
        // 而那会丢掉执行屏上那句话唯一要回答的问题（「我的跑步是不是停了」）。
        XCTAssertTrue(EmergencySafetyCopy.hubSubtitle(for: .cloudTrigger).contains("跑步"))
    }

    /// 🔴 **求助中心底部那条在非 `IN_PROGRESS` 必须降级为本地拨号。**
    ///
    /// 2026-09-16 起这一层不再只从陪跑执行屏进入 —— 四步骨架的底部也有一枚「求助与安全」，
    /// 而那四态（匹配 / 约好 / 出发 / 汇合）**一个都不是 `IN_PROGRESS`**。
    /// 云端求助两端都只在 `IN_PROGRESS` 开放（`AGENTS.md` §6），所以在那四态走云端的
    /// 真实结果是：`beginCountdown` 在资格 guard 落 `.failed`、`startEmergencyCountdown`
    /// 因此不弹全屏，而骨架那一屏没有 `EmergencyStatusNotice` 的渲染点 ——
    /// **屏幕零变化、一个字也不播**。
    ///
    /// ⚠️ **这条用例钉的是判据本身，不是「订单页真的走了它」。**
    /// `BlindHomeSOSMode.resolve` 是纯函数，本轮一行未改 —— 把
    /// `BlindOrderStatusView` 的 `mode:` 改回写死 `.cloudTrigger`，这条**照样全绿**。
    /// 接线那一半只有 UI 用例
    /// `AccessibilityAuditTests.testSafetyHubOutsideTheActiveRunOffersLocalDialInsteadOfCloudSOS`
    /// 能看见（真机唯一通道）。
    ///
    /// 留着它的价值是**穷举**：逐个骨架态过一遍，谁把某一态放进云端就红 ——
    /// 而 UI 用例只走得到种子订单那一态。两条互补，都不可省。
    ///
    /// 写清这件事是因为初稿的注释声称它钉住了「订单页也走它」，那是假的 ——
    /// 而一条**声称自己守住了某件事、实际守不住**的用例，比没有用例更糟：
    /// 它的绿灯会替一个不存在的保证背书（记忆 `claimed-fallback-may-not-exist-in-release`）。
    func testSafetyHubDowngradesToLocalCallOutsideOfTheActiveRun() {
        let skeletonStatuses: [RunOrderStatus] = [
            .pendingMatch, .pendingIntroCall, .rematching,
            .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived,
        ]

        for status in skeletonStatuses {
            let order = OrderDetailResponse.preview(status: status)
            XCTAssertEqual(
                BlindHomeSOSMode.resolve(order: order, role: .blind),
                .localCall,
                "\(status) 不是 IN_PROGRESS，云端求助发不出去；底部那条必须是本地拨号"
            )
        }

        // 反向：陪跑进行中才是云端那条。少了这一半，把 `resolve` 改成恒 `.localCall`
        // 也能让上面全绿 —— 而那会把唯一真能发出求助的状态一起降级掉。
        XCTAssertEqual(
            BlindHomeSOSMode.resolve(
                order: OrderDetailResponse.preview(status: .inProgress),
                role: .blind
            ),
            .cloudTrigger
        )
    }

    /// 长按进度的震动节奏。
    ///
    /// **这是「用户凭什么知道自己按够了没」的唯一依据** —— 看不见屏幕的人按住一个红块时，
    /// 屏幕上的进度动画对他不存在。手势本身单测够不着，所以把节奏抽成纯数据钉在这里。
    ///
    /// 两条不变式都不是形式主义：
    /// - **必须渐强**。强度不变的话「按住中」和「已经按够」听起来一模一样。
    /// - **每一拍都要严格早于 3 秒**。踩在 3.0 上那一拍会和触发同时发生，
    ///   用户感到的是「一下重震」，而不是渐强到触发 —— 那正好把进度反馈变成了噪音。
    func testLongPressHapticRampGrowsAndLandsBeforeTheTrigger() {
        let ramp = SafetyLongPress.hapticRamp
        XCTAssertFalse(ramp.isEmpty, "没有任何进度反馈，等于让盲人盲按 3 秒")
        XCTAssertEqual(SafetyLongPress.duration, 3, "副标题里印的是 3 秒，常量必须是同一个")

        for (previous, next) in zip(ramp, ramp.dropFirst()) {
            XCTAssertLessThan(previous.elapsed, next.elapsed, "节奏必须按时间排序")
            XCTAssertLessThan(previous.intensity, next.intensity, "强度必须渐强，否则听不出进度")
        }
        for step in ramp {
            XCTAssertGreaterThanOrEqual(step.elapsed, 0)
            XCTAssertLessThan(
                step.elapsed,
                SafetyLongPress.duration,
                "落在 \(step.elapsed) 的这一拍不早于触发时刻，会和触发撞在一起"
            )
            XCTAssertGreaterThan(step.intensity, 0)
            XCTAssertLessThanOrEqual(step.intensity, 1, "UIImpactFeedbackGenerator 的强度上限是 1")
        }
    }

    /// 「播报我的位置」拿不到位置时**说拿不到，不编**。
    ///
    /// 这一句会被用户逐字转述给 110 / 120 —— 一个猜出来的地名比没有地名危险得多。
    func testLocationAnnouncementNeverInventsAPlace() {
        let unknown = EmergencySafetyCopy.locationAnnouncement(nil)
        XCTAssertTrue(unknown.contains("定位不到"))
        // 拿不到位置时必须给出**下一步**，否则盲人听完只知道失败、不知道该做什么。
        XCTAssertTrue(unknown.contains("110") || unknown.contains("120"))

        // 空白字符串等同于没有 —— 逆地理返回空 `title` 时不能念出「你现在在附近」。
        XCTAssertEqual(EmergencySafetyCopy.locationAnnouncement("   "), unknown)

        XCTAssertEqual(EmergencySafetyCopy.locationAnnouncement("人民公园"), "你现在在人民公园附近。")
    }

    /// 120 必须是**能按的**，不能只作为文字出现在状态提示里。
    ///
    /// 这个 App 的用户在跑步：摔倒、扭伤、心脏不适对应的是急救而不是报警。
    /// 2026-09-08 之前全仓只有 `policeNumber`，「110或120」只出现在播报文案里 ——
    /// 对看不见屏幕的人，念得出来而按不到等于没有。
    func testMedicalEmergencyNumberIsDialableNotJustSpoken() throws {
        XCTAssertEqual(EmergencyDialer.medicalNumber, "120")
        XCTAssertEqual(
            EmergencyDialer.telURL(for: EmergencyDialer.medicalNumber)?.absoluteString,
            "tel://120"
        )
        XCTAssertNotEqual(EmergencyDialer.medicalNumber, EmergencyDialer.policeNumber)

        // 没有主联系人时的提示要把两个号都说出来，否则用户以为只剩报警一条路。
        XCTAssertTrue(EmergencySafetyCopy.homeCallNoContactHint.contains("120"))
        XCTAssertTrue(EmergencySafetyCopy.homeCallNoContactHint.contains("110"))
    }
}
