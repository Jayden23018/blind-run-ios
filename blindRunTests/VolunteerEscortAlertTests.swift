import CoreLocation
import XCTest
@testable import blindRun

/// 志愿者端屏 4 / 屏 5：同步指标、紧急强提醒、距离分档。
///
/// 这一片的共同主题是**「不知道就说不知道」**。志愿者会拿屏幕上的字去做真实决定
/// （往哪个方向找人、要不要打 110、对方还撑不撑得住），所以每一条编出来的信息
/// 都比缺一条更贵。下面每一条用例钉的都是某个「我们其实不知道」的位置。
@MainActor
final class VolunteerEscortAlertTests: XCTestCase {

    // MARK: - 求助告警里的坐标

    /// 告警里的坐标必须**一路带到客户端并归一到 GCJ-02**。
    ///
    /// `EMERGENCY_VOLUNTEER_ALERT` 是全链路里唯一带受助者坐标的消息
    /// （`websocket-protocol.md:546`），其余 `EMERGENCY_*` 走 `APP_NOTIFICATION` 信封、
    /// 连 `eventId` 都没有。丢掉它，屏 5 就只剩一句「暂时收不到他的位置」——
    /// 而后端明明发了。
    func testVolunteerAlertCarriesTheRunnerCoordinate() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.emergencyAlert(Self.alert(lat: 39.9042, lng: 116.4074)))
        await Task.yield()

        let event = coordinator.latestSafetyEvent
        XCTAssertEqual(event?.kind, .emergencyVolunteerAlert)
        let located = try? XCTUnwrap(event?.coordinate)
        XCTAssertEqual(located?.coordinate.latitude ?? 0, 39.9042, accuracy: 0.000001)
        XCTAssertEqual(located?.coordinate.longitude ?? 0, 116.4074, accuracy: 0.000001)
        // 后端给的就是 GCJ-02（`websocket-protocol.md:20` 的坐标系约定）。
        // 归一化标成别的体系会让下游再转一次，凭空多出几百米偏移。
        XCTAssertEqual(located?.system, .gcj02Backend)
    }

    /// 🔴 **只有纬度的「位置」不是位置。**
    ///
    /// 契约里 `gpsLat` / `gpsLng` 各自可空。把半个坐标当成有效值，下游
    /// `DistanceCalculator` 会拿经度 0（几内亚湾）去算距离 —— 屏 5 上会出现一个
    /// 看起来完全正常、实际上指向大西洋的「距你较远」。
    func testHalfACoordinateIsTreatedAsNoCoordinate() async {
        for (lat, lng) in [(39.9042, nil as Double?), (nil as Double?, 116.4074), (nil, nil)] {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: .volunteer)

            service.simulateIncomingEventForTesting(.emergencyAlert(Self.alert(lat: lat, lng: lng)))
            await Task.yield()

            XCTAssertNil(
                coordinator.latestSafetyEvent?.coordinate,
                "lat=\(String(describing: lat)) lng=\(String(describing: lng)) 被当成了有效坐标"
            )
        }
    }

    /// 坐标要落到志愿者真正读的那个对象上（`EmergencyCoordinator.volunteerAlert`），
    /// 不是只停在中转的事件里。
    func testCoordinatorHandsTheCoordinateToTheVolunteerAlert() {
        let coordinator = EmergencyCoordinator()
        let located = BackendCoordinateNormalizer.backend(latitude: 39.9042, longitude: 116.4074)

        coordinator.apply(
            RealtimeSafetyEvent(
                eventID: "77",
                orderID: 4242,
                kind: .emergencyVolunteerAlert,
                displayText: "被陪同者触发了紧急求助",
                speechText: "被陪同者触发了紧急求助",
                timestamp: nil,
                coordinate: located
            )
        )

        XCTAssertEqual(coordinator.volunteerAlert?.eventID, 77)
        XCTAssertEqual(coordinator.volunteerAlert?.coordinate?.system, .gcj02Backend)
        XCTAssertEqual(
            coordinator.volunteerAlert?.coordinate?.coordinate.latitude ?? 0,
            39.9042,
            accuracy: 0.000001
        )
        XCTAssertFalse(coordinator.volunteerAlert?.isAcknowledged ?? true)
    }

    // MARK: - 距离分档

    /// 🔴 紧急那一屏的距离**分档，不给精确值**。
    ///
    /// 这是两台手机各自 GPS 读数之差，城市里单台误差就可达十几米。设计稿上印的
    /// 「距你约 8 米」会让志愿者以为对方就在手边、抬头没看见就开始怀疑数据，
    /// 而真正该做的是往那个方向找。
    ///
    /// **取值刻意压在档位边界上**：随手取 5 米和 500 米的话，把 30 米那条线改成 50
    /// 用例照样绿 —— 那样的用例分辨不出门槛被挪过。三个档对应三种完全不同的动作：
    /// 抬头找人 / 往那边走 / 边走边打电话。
    func testProximityBandsChangeExactlyAtTheThresholds() {
        XCTAssertEqual(DistanceCalculator.proximityBand(0), "就在附近")
        XCTAssertEqual(DistanceCalculator.proximityBand(29.9), "就在附近")
        XCTAssertEqual(DistanceCalculator.proximityBand(30), "约几十米")
        XCTAssertEqual(DistanceCalculator.proximityBand(149.9), "约几十米")
        XCTAssertEqual(DistanceCalculator.proximityBand(150), "几百米外")
        XCTAssertEqual(DistanceCalculator.proximityBand(999.9), "几百米外")
        XCTAssertEqual(DistanceCalculator.proximityBand(1_000), "较远")
        XCTAssertEqual(DistanceCalculator.proximityBand(50_000), "较远")

        // 四档必须两两不同 —— 合并任意两档，上面那些断言里就有一条会红，
        // 但「分档还剩几个」这件事本身也值得直说。
        let bands = Set([0, 100, 500, 5_000].map { DistanceCalculator.proximityBand(Double($0)) })
        XCTAssertEqual(bands.count, 4)

        // 反向锁：接驳用的精确读数**没有被这次改动动过**。
        // 志愿者按地图找人时要的是「80 米」，不是「约几十米」。
        XCTAssertEqual(DistanceCalculator.formattedDistance(80), "80 米")
    }

    // MARK: - 「多久之前」

    /// 「X 秒前」读的是**本机收到的时刻**，不是后端时间戳。
    ///
    /// 两端时钟差几秒到几分钟时，用后端时间会让屏幕上出现「-40 秒前」，
    /// 或者凭空多出的「3 分钟前」—— 而志愿者正据此判断
    /// 「这事刚发生，还是我漏看了很久」。
    func testElapsedCopyNeverGoesNegativeAndSwitchesToMinutes() {
        XCTAssertEqual(EmergencySafetyCopy.volunteerAlertElapsed(seconds: -5), "0 秒前")
        XCTAssertEqual(EmergencySafetyCopy.volunteerAlertElapsed(seconds: 0), "0 秒前")
        XCTAssertEqual(EmergencySafetyCopy.volunteerAlertElapsed(seconds: 59), "59 秒前")
        XCTAssertEqual(EmergencySafetyCopy.volunteerAlertElapsed(seconds: 60), "1 分钟前")
        XCTAssertEqual(EmergencySafetyCopy.volunteerAlertElapsed(seconds: 185), "3 分钟前")
    }

    // MARK: - 屏 5 的文案红线

    /// 🔴 **屏 5 不许出现「客服已接入」这类话。**
    ///
    /// 设计稿上写着「2 秒前 · 客服已接入」，而志愿者端**无从知道**这件事：
    /// `EMERGENCY_VOLUNTEER_ALERT` 的字段里没有客服状态（`websocket-protocol.md:546`），
    /// 而 `GET /api/emergency/active` 角色限 `BLIND`，志愿者调不了。
    ///
    /// 写上去不是小瑕疵：它造的是「已经有人在处理了」的安心感，
    /// 而那份安心感可能是假的，会让现场唯一在场的人晚几分钟才自己打 110。
    func testVolunteerAlertCopyNeverClaimsAnyoneIsAlreadyHandlingIt() {
        let copy = [
            EmergencySafetyCopy.volunteerAlertTitle(name: "李明"),
            EmergencySafetyCopy.volunteerAlertTitle(name: nil),
            EmergencySafetyCopy.volunteerAlertCallTitle(name: "李明"),
            EmergencySafetyCopy.volunteerAlertAcknowledgeTitle,
            EmergencySafetyCopy.volunteerAlertAcknowledgeFootnote,
            EmergencySafetyCopy.volunteerAlertAcknowledgeHint,
            EmergencySafetyCopy.volunteerAlertNoDismissNotice,
            EmergencySafetyCopy.volunteerAlertLocationUnknown,
            EmergencySafetyCopy.volunteerAlertLocationResolving,
            EmergencySafetyCopy.volunteerAlertElapsed(seconds: 2),
        ]
        // 「已接入」「已受理」：客服到底接没接手，这一侧读不到。
        // 「已通知」「已送达」：短信是事务提交后异步发的，全仓红线。
        let forbidden = ["已接入", "已受理", "已通知", "已送达", "已收到短信", "已报警"]
        for line in copy {
            for claim in forbidden {
                XCTAssertFalse(
                    line.contains(claim),
                    "志愿者端求助文案宣称了一件它无从知道的事：在「\(line)」里发现「\(claim)」"
                )
            }
        }
    }

    /// 「位置共享」那一行的措辞。
    ///
    /// 客户端判的只是「最近一条位置更新还新不新鲜」—— 那可能是对方进了地下通道、
    /// 也可能是他关了权限，**两者我们分不出来**。说成「已断开」像是在陈述一个已经查明的
    /// 事实，志愿者会据此做判断（比如认为对方故意关了共享）。
    func testStaleLocationIsDescribedAsTemporaryNotAsDisconnected() {
        XCTAssertEqual(EmergencySafetyCopy.volunteerPeerLocationStale, "暂时收不到")
        XCTAssertFalse(EmergencySafetyCopy.volunteerPeerLocationStale.contains("断开"))
        XCTAssertFalse(EmergencySafetyCopy.volunteerPeerLocationStale.contains("关闭"))
    }

    /// 志愿者确认之后，「他的状态」必须回到正常。
    ///
    /// 不回落的表现是整段陪跑都顶着红色的「求助中」——
    /// 而那会让一个**新的**求助在视觉上完全淹没掉。
    func testAcknowledgedAlertStopsCountingAsAnOngoingEmergency() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.acknowledgeEmergencyResult = .success(
            VolunteerEmergencyAcknowledgement(success: true, eventId: 77, action: "NEED_HELP")
        )
        coordinator.apply(
            RealtimeSafetyEvent(
                eventID: "77",
                orderID: 4242,
                kind: .emergencyVolunteerAlert,
                displayText: "被陪同者触发了紧急求助",
                speechText: "被陪同者触发了紧急求助",
                timestamp: nil,
                coordinate: nil
            )
        )
        XCTAssertEqual(coordinator.volunteerAlert?.isAcknowledged, false)

        let succeeded = await coordinator.acknowledgeAsVolunteer(eventID: 77, safety: safety)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.volunteerAlert?.isAcknowledged, true)
    }

    /// 🔴 **志愿者按完「我在他身边」之后，那一行不许写「正常」。**
    ///
    /// code review 抓到的：原实现只有两档，确认之后这一行立刻变回「正常」、圆点变绿，
    /// 志愿者扫一眼得到的结论是「这事过去了」。而他按的那一下只是告诉客服
    /// 「现场有人了」——求助本身仍然是开的，同一屏上另一句话就写着
    /// 「这条求助只有他本人或客服能撤销」。
    ///
    /// 这与屏 5 刻意不写「客服已接入」是同一条红线：**不知道的事不许说**，
    /// 「已经结束」同样是一件我们不知道的事。
    ///
    /// 也不能继续顶着红色的「求助中」—— 那会让一个**新的**求助在视觉上完全淹没掉。
    /// 所以必须是三档。
    func testAcknowledgedStatusSaysNeitherNormalNorStillAlarming() {
        let normal = EmergencySafetyCopy.volunteerPeerStatusNormal
        let alarming = EmergencySafetyCopy.volunteerPeerStatusEmergency
        let acknowledged = EmergencySafetyCopy.volunteerPeerStatusAcknowledged

        XCTAssertEqual(Set([normal, alarming, acknowledged]).count, 3, "三档必须互不相同")
        XCTAssertNotEqual(acknowledged, normal, "确认之后写「正常」= 宣称求助已经结束")
        XCTAssertNotEqual(acknowledged, alarming)

        // 而且这一档也不许宣称客服已经在处理到什么程度 —— 志愿者端读不到那个状态。
        for claim in ["已接入", "已受理", "已解决", "已结束"] {
            XCTAssertFalse(
                acknowledged.contains(claim),
                "「\(acknowledged)」宣称了一件志愿者端无从知道的事：\(claim)"
            )
        }
    }

    // MARK: - Fixtures

    private static func alert(lat: Double?, lng: Double?) -> WSEmergencyVolunteerAlert {
        WSEmergencyVolunteerAlert(
            type: WSMessageType.emergencyVolunteerAlert.rawValue,
            eventId: 77,
            orderId: 4242,
            userId: 1,
            message: "您陪伴的盲人用户触发了紧急求助",
            ttsText: "盲人用户触发了紧急求助",
            priority: "HIGH",
            gpsLat: lat,
            gpsLng: lng,
            timestamp: "2026-09-15T14:30:00"
        )
    }
}
