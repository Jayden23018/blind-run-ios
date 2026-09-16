import Combine
import CoreLocation
import XCTest
@testable import blindRun

/// SOS trigger, gating, failure branches, and the truthfulness rules around emergency-contact copy.
@MainActor
final class EmergencySOSTests: XCTestCase {

    // MARK: - Truthfulness regression

    /// The single most important assertion in this file.
    ///
    /// The backend pushes `EMERGENCY_CONTACT_NOTIFIED` synchronously inside the trigger transaction
    /// (`EmergencyService.java:370-373`) while the SMS is only sent afterwards by
    /// `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` (`EmergencyContactNotifier.java:60-62`),
    /// and a send failure is broadcast to CS alone (`:126-135`) — never corrected to the blind
    /// runner. There is therefore no point in *this* branch at which the app knows a contact received
    /// an SMS. A blind user decides whether to seek help another way based on this copy, so claiming
    /// delivery is not a wording preference; it is telling someone in danger that help is coming.
    ///
    /// Since 2026-07-31 exactly one branch is allowed to claim delivery —
    /// `EMERGENCY_CONTACT_SMS_DELIVERED`, which is backed by a carrier receipt. It is asserted
    /// separately below and deliberately excluded here; every other state stays progressive.
    func testNoEmergencyCopyClaimsAnSMSWasDelivered() {
        let forbidden = ["联系人已收到短信", "已收到短信", "已通知家属", "已通知你的联系人", "短信已送达"]
        var allCopy = [
            EmergencySafetyCopy.contactNotified,
            EmergencySafetyCopy.triggeredAcknowledged,
            EmergencySafetyCopy.noContact,
            EmergencySafetyCopy.volunteerTimeout,
            EmergencySafetyCopy.locating,
            EmergencySafetyCopy.submitting,
            EmergencySafetyCopy.locationUnavailable(.permissionDenied),
            EmergencySafetyCopy.locationUnavailable(.locationUnavailable),
            EmergencySafetyCopy.locationUnavailable(nil),
            EmergencySafetyCopy.failure(nil),
            EmergencySafetyCopy.cooldown(retryAfterSeconds: 42),
            EmergencySafetyCopy.cooldown(retryAfterSeconds: nil),
            EmergencySafetyCopy.accessibilityLabel,
            EmergencySafetyCopy.accessibilityHint,
            // 2026-07-31 新增的一批，同样受这条红线约束（送达回执那一条除外，见下一个用例）。
            EmergencySafetyCopy.triggeredByVolunteer,
            EmergencySafetyCopy.contactNotifyFailed,
            EmergencySafetyCopy.volunteerAcknowledged,
            EmergencySafetyCopy.cancelOwnerSucceeded,
            EmergencySafetyCopy.cancelOwnerFailed(nil),
            EmergencySafetyCopy.volunteerAlertNotice,
            // 2026-08-04 补：这两条是客服解除/误触收尾，晚于本用例加入，一直没被收进清单。
            // 结果 `closedFalseAlarm` 长期写着「紧急联系人已收到解除通知」—— 解除短信走的是和求助短信
            // 同一条异步路径，没有运营商回执，这就是本红线的同类违规。由 scripts/hooks/guard.mjs 抓出。
            EmergencySafetyCopy.closedResolved,
            EmergencySafetyCopy.closedFalseAlarm,
            // 2026-08-07 补：首页 SOS 条在非 IN_PROGRESS 时的本地拨号分支。
            // 这条分支 App 一个字节都没发出去，所以它比任何一条都更不能有「已通知」的味道。
            EmergencySafetyCopy.homeCallTitle,
            EmergencySafetyCopy.homeCallAccessibilityLabel,
            EmergencySafetyCopy.homeCallAccessibilityHint,
            EmergencySafetyCopy.homeCallDialogMessage,
            EmergencySafetyCopy.homeCallPoliceTitle,
            EmergencySafetyCopy.homeCallNoContactHint,
            EmergencySafetyCopy.homeCallContactTitle(name: "妈妈"),
            EmergencySafetyCopy.homeCallContactTitle(name: nil),
            // 2026-08-20 补：云端求助失败后的本地拨号兜底（F7）。同样一个字节都没发出去。
            EmergencySafetyCopy.cloudFailedCallAccessibilityHint,
            EmergencySafetyCopy.cloudFailedCallDialogMessage,
            // 2026-09-15 补：陪跑中的求助中心（取代了原来的 `inProgressCall*` 那一组）。
            EmergencySafetyCopy.hubDialogMessage,
            EmergencySafetyCopy.hubAccessibilityHint,
            EmergencySafetyCopy.hubAccessibilityLabel,
            EmergencySafetyCopy.hubTitle,
            EmergencySafetyCopy.hubSubtitle,
            EmergencySafetyCopy.hubEntrySubtitle,
            EmergencySafetyCopy.hubDismissTitle,
            EmergencySafetyCopy.hubTriggerSubtitle,
            EmergencySafetyCopy.hubTriggerAccessibilityHint,
            EmergencySafetyCopy.hubContactVolunteerTitle,
            EmergencySafetyCopy.hubAnnounceLocationTitle,
            EmergencySafetyCopy.hubAskQuestionTitle,
            EmergencySafetyCopy.emergencyAccessibilityActionName,
            // 倒计时（屏 3）与求助已发出（屏 3b）。倒计时那三秒**什么都还没发生**，
            // 所以它比任何一条都更不能有「已通知」的味道。
            EmergencySafetyCopy.countdownTitle,
            EmergencySafetyCopy.countdownCancelTitle,
            EmergencySafetyCopy.countdownCancelAccessibilityHint,
            EmergencySafetyCopy.countdownCancelled,
            EmergencySafetyCopy.countdown(secondsRemaining: 3),
            EmergencySafetyCopy.countdown(secondsRemaining: 0),
            EmergencySafetyCopy.sentTitle,
            EmergencySafetyCopy.sentCallMedicalHint,
            EmergencySafetyCopy.sentCallPoliceHint,
            EmergencySafetyCopy.retrySendTitle,
            EmergencySafetyCopy.retrySendAccessibilityHint,
            EmergencySafetyCopy.sendingTitle,
            EmergencySafetyCopy.unsentTitle,
            EmergencySafetyCopy.cancelledTitle,
            EmergencySafetyCopy.volunteerPeerStatusAcknowledged,
            EmergencySafetyCopy.locationAnnouncement(nil),
            EmergencySafetyCopy.locationAnnouncement("人民公园"),
            EmergencySafetyCopy.homeCallMedicalTitle
        ]
        allCopy.append(contentsOf: EmergencyEventStatus.allCases.map(EmergencySafetyCopy.submitted))
        // 求助中心每一格的标题与小字。**用 `allCases` 而不是手写清单** —— 手写的那份
        // 会在新增一格时被漏掉，而这条红线最常见的破法就是「晚加进来的那条没人收进清单」
        // （`closedFalseAlarm` 就是这么漏了半年，见上面 2026-08-04 那条注释）。
        // 倒计时列的那三条「即将发生的事」。**全部必须是进行时或将来时** ——
        // 短信是事务提交后异步发的、失败也从不回告盲人，所以 App 永远不能说「已经通知了谁」。
        allCopy.append(contentsOf: EmergencySafetyCopy.countdownPendingEffects)
        // `isLiveSharing` 两档都要过：分享那一格的标题与小字随它变，只查一档会漏掉
        // 「停止分享」那半边 —— 而它同样是对外文案。
        for option in BlindActiveRunSafetyHubOption.allCases {
            for isLiveSharing in [false, true] {
                allCopy.append(option.title(contactName: "妈妈", isLiveSharing: isLiveSharing))
                allCopy.append(option.title(contactName: nil, isLiveSharing: isLiveSharing))
                allCopy.append(EmergencySafetyCopy.hubTileSubtitle(
                    option,
                    contactName: "妈妈",
                    isLiveSharing: isLiveSharing
                ))
                allCopy.append(EmergencySafetyCopy.hubTileSubtitle(
                    option,
                    contactName: nil,
                    isLiveSharing: isLiveSharing
                ))
            }
        }

        for copy in allCopy {
            for claim in forbidden {
                XCTAssertFalse(
                    copy.contains(claim),
                    "SOS copy must never claim SMS delivery — found “\(claim)” in “\(copy)”"
                )
            }
        }
    }

    /// The contact-notified state is progressive tense and explicitly says receipt is unconfirmed.
    func testContactNotifiedCopyStatesReceiptIsUnconfirmed() {
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("正在联系"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("尚未确认对方是否收到"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotified.contains("110"))
    }

    /// 送达回执是唯一允许说完成时的一段，而且必须仍然与「已发起」那一段可区分 ——
    /// 两段听起来一样的话，这条回执链路等于没接。
    func testOnlyTheCarrierReceiptBranchMayClaimDelivery() {
        XCTAssertTrue(EmergencySafetyCopy.contactSmsDelivered.contains("已收到"))
        XCTAssertNotEqual(EmergencySafetyCopy.contactSmsDelivered, EmergencySafetyCopy.contactNotified)
        XCTAssertFalse(
            EmergencySafetyCopy.contactSmsDelivered.contains("尚未确认"),
            "运营商已确认送达之后不该再说尚未确认"
        )
        // 投递失败必须说得比「未确认」更重，并直接给出替代求助方式。
        XCTAssertTrue(EmergencySafetyCopy.contactNotifyFailed.contains("没有收到"))
        XCTAssertTrue(EmergencySafetyCopy.contactNotifyFailed.contains("110"))
        XCTAssertTrue(EmergencySOSState.contactNotifyFailed.isFailure)
        XCTAssertFalse(EmergencySOSState.contactSmsDelivered.isFailure)
    }

    /// 后端 2026-07-31 起按订单参与方归属事件，志愿者代触发不再把告警回推给他自己，
    /// 于是志愿者入口可以开 —— 但仍然只在服务进行中，和盲人侧同一个门槛。
    func testVolunteerEmergencyEntryIsEnabledOnlyDuringService() {
        XCTAssertTrue(RunOrderStatus.inProgress.canVolunteerTriggerEmergency)
        XCTAssertTrue(RunOrderStatus.inProgress.canTriggerEmergency(as: .volunteer))
        for status in RunOrderStatus.allCases where status != .inProgress {
            XCTAssertFalse(
                status.canVolunteerTriggerEmergency,
                "\(status) 不该出现志愿者求助入口"
            )
        }
        XCTAssertFalse(RunOrderStatus.inProgress.canTriggerEmergency(as: .unset))
    }

    /// 志愿者只有「确认需要帮助」一个动作。`FALSE_ALARM` 在后端是硬 403，客户端连表达它的类型都不该有。
    func testVolunteerAcknowledgementCopyOffersNoDismissAction() {
        XCTAssertEqual(EmergencySafetyCopy.volunteerNeedHelpButtonTitle, "确认需要帮助")
        XCTAssertFalse(EmergencySafetyCopy.volunteerNeedHelpButtonTitle.contains("误触"))
        XCTAssertEqual(
            ErrorCode.emergencyVolunteerCannotDismiss.localizedMessage,
            "志愿者无权撤销求助，请确认对方是否需要帮助。"
        )
        // 撤销权只在受助者本人手里，且入口文案要说清代价（会给家属补一条解除短信）。
        XCTAssertTrue(EmergencySafetyCopy.cancelOwnerConfirmation.contains("解除短信"))
    }

    /// `POST /api/emergency/trigger` 的回执 status 自 2026-07-31 收敛为两个值；
    /// `VOLUNTEER_NOTIFIED` 不再出现。枚举值保留只为兼容历史数据与未知值兜底。
    func testTriggerReceiptStatusesStillDecodeIncludingRetiredValues() {
        XCTAssertEqual(EmergencyEventStatus(rawValue: "CONTACT_NOTIFIED"), .contactNotified)
        XCTAssertEqual(EmergencyEventStatus(rawValue: "PENDING"), .pending)
        XCTAssertEqual(EmergencyEventStatus(rawValue: "VOLUNTEER_NOTIFIED"), .volunteerNotified)
        XCTAssertNil(EmergencyEventStatus(rawValue: "SOMETHING_NEW"))
        XCTAssertTrue(EmergencyEventStatus.falseAlarm.isTerminal)
    }

    /// Every state that means "help is not on the way yet" must point at 110.
    func testTerminalAndFailureCopyAlwaysOffersTheEmergencyNumber() {
        let states: [EmergencySOSState] = [
            .acknowledged(.volunteerNotified),
            .acknowledged(.contactNotified),
            .acknowledged(.csHandling),
            .acknowledged(.unknown),
            .unsentNoLocation(.permissionDenied),
            .unsentNoLocation(.locationUnavailable),
            .unsentNoLocation(nil),
            .failed("网络异常"),
            .cooldown(retryAfterSeconds: 30)
        ]
        for state in states {
            XCTAssertTrue(state.message?.contains("110") == true, "missing 110 guidance in \(state)")
        }
    }

    /// F7：求助发不出去时，屏幕上必须有一个**能按的东西**，而不只是一段说明文字。
    ///
    /// `BlindHomeSOSBar` 的兜底拨号按钮完全由 `state.isFailure` 驱动，所以这里把每个状态逐个钉住。
    /// 新增一个失败态却落到非失败那一侧时，兜底按钮会静默消失 —— 屏幕上看不出任何差别，
    /// 只有真正按下求助键的人才会发现，而那时已经晚了。
    func testEveryFailedSOSStateOffersTheLocalCallFallback() {
        let failures: [EmergencySOSState] = [
            .unsentNoLocation(nil),
            .unsentNoLocation(.permissionDenied),
            .unsentNoLocation(.locationUnavailable),
            .failed("网络异常"),
            .cooldown(retryAfterSeconds: nil),
            .cooldown(retryAfterSeconds: 30),
            .contactNotifyFailed
        ]
        for state in failures {
            XCTAssertTrue(state.isFailure, "\(state) 没被判成失败，首页兜底拨号按钮不会出现")
        }
        let nonFailures: [EmergencySOSState] = [
            .idle, .locating, .submitting,
            .acknowledged(.contactNotified),
            .contactSmsDelivered,
            .cancelledByOwner
        ]
        for state in nonFailures {
            XCTAssertFalse(state.isFailure, "\(state) 不是失败，不该露出兜底拨号入口")
        }
    }

    /// 兜底弹窗复用首页那条本地拨号 UI，但**第一句不能共用**：`homeCall*` 的开头是
    /// 「当前没有进行中的陪跑」，而这条分支恰恰发生在陪跑进行中、刚按过求助键的时候。
    func testCloudFailureCallCopyDoesNotDenyTheRunInProgress() {
        let copies = [
            EmergencySafetyCopy.cloudFailedCallDialogMessage,
            EmergencySafetyCopy.cloudFailedCallAccessibilityHint
        ]
        for copy in copies {
            XCTAssertFalse(copy.contains("没有进行中"), "陪跑正在进行时不能说没有进行中的陪跑：\(copy)")
            XCTAssertTrue(copy.contains("不会代你发送求助"), "必须说清 App 什么都没发出去：\(copy)")
            XCTAssertTrue(copy.hasPrefix("求助没有发出去"), "第一句要先说没发出去：\(copy)")
        }
        XCTAssertNotEqual(
            EmergencySafetyCopy.cloudFailedCallDialogMessage,
            EmergencySafetyCopy.homeCallDialogMessage
        )
    }

    /// A failure must lead with 未发出: for a blind user the first words decide the next action.
    func testFailureCopyLeadsWithNotSent() {
        XCTAssertTrue(EmergencySafetyCopy.locationUnavailable(.permissionDenied).hasPrefix("求助未发出"))
        XCTAssertTrue(EmergencySafetyCopy.locationUnavailable(nil).hasPrefix("求助未发出"))
        XCTAssertTrue(EmergencySafetyCopy.failure("服务器错误").hasPrefix("求助未发出"))
        XCTAssertTrue(EmergencySafetyCopy.failure(nil).contains("网络异常"))
    }

    func testConfirmationCopyMatchesTheMandatedTextExactly() {
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage,
            "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
        )
        // 盲人侧读到的仍然是**逐字**这一句 —— 志愿者那一句是追加，不是改写。
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage(for: .runner),
            EmergencySafetyCopy.confirmationMessage
        )
    }

    /// 🔴 志愿者按下求助**撤销不了**（后端对志愿者的 `FALSE_ALARM` 恒 403
    /// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`），而二次确认此前没说这件事 ——
    /// 漏掉的正是这个动作最不可逆的那一半后果，也就是二次确认存在的理由。
    ///
    /// 断言挑的是**能区分三种实现**的取值：
    /// - 正确实现：志愿者那份是「原文 + 追加句」
    /// - 「两侧共用一句」的旧实现：撞第一条断言
    /// - 「志愿者侧改写了原文」的实现：撞第二条（AGENTS §6 的 verbatim 会被破坏）
    func testVolunteerConfirmationSpellsOutThatItCannotBeTakenBack() {
        let volunteer = EmergencySafetyCopy.confirmationMessage(for: .volunteer)

        XCTAssertTrue(
            volunteer.contains("只有跑者本人或客服能撤销"),
            "志愿者按下去撤销不了，这件事必须在按之前说：\(volunteer)"
        )
        // verbatim 的那一句**整句仍在**，只是后面多了一句。
        XCTAssertTrue(
            volunteer.hasPrefix(EmergencySafetyCopy.confirmationMessage),
            "AGENTS.md §6 钉死的那句不得被改写，只能追加：\(volunteer)"
        )
        // 🚩 不许反过来把「你可以撤销」说给志愿者听 —— 那是一句他做不到的承诺。
        XCTAssertFalse(volunteer.contains("你可以撤销"))
    }

    // MARK: - 求助状态的刷新机制

    /// `EmergencyActionSection` 用 `@ObservedObject` 跟随 coordinator 重绘，**前提是 coordinator
    /// 真的会在状态变化时发布**。这条断言就是把那个前提钉住。
    ///
    /// 为什么值得单独一条：`AppState.emergencyCoordinator` 是 `let` 不是 `@Published`，
    /// `AppState` 也没有转发子对象的 `objectWillChange`。所以求助状态的刷新**完全**依赖
    /// 「显示它的那个视图自己订阅 coordinator」这一条链路。一旦 `state` 不再是 `@Published`，
    /// 屏幕会静默停在旧值 —— 盲人听到的是过期结论（还在念「正在发送」而其实已经失败），
    /// 而这正是 `AGENTS.md` §6「每一种结果都必须可见且可听地如实告知」要挡的事。
    /// 编译不会报错，UI 也不会崩，只有这条用例会红。
    func testCoordinatorPublishesWhenSosStateChanges() async {
        let coordinator = EmergencyCoordinator()
        var emissions = 0
        let cancellable = coordinator.objectWillChange.sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        // 非 IN_PROGRESS 直接落到 finish(.failed)，是最短的一条真实状态变化路径。
        await coordinator.trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .blind,
            userID: 7,
            safety: FakeSafetyService(),
            locate: { Self.coordinate() }
        )

        XCTAssertGreaterThan(
            emissions,
            0,
            "coordinator 必须在状态变化时发布，否则订阅它的求助区块会静默停在旧值"
        )
        XCTAssertTrue(coordinator.state.isFailure)
    }

    // MARK: - Trigger: eligibility

    func testTriggerIsRejectedOutsideInProgress() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(safety.calls.isEmpty, "no request may be sent outside IN_PROGRESS")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 2026-08-01 起志愿者可以代盲人发起求助。
    ///
    /// 这条用例原先断言的是「志愿者角色一律拒绝」—— 那是后端把事件挂在**触发者**身上时的止血：
    /// 志愿者按下去，告警回推给他自己、盲人收不到、升级的是志愿者的紧急联系人。后端已改成按订单
    /// 参与方归属事件（handoff 2026-07-31），门槛随之放开，断言跟着改成「服务进行中放行、其余拒绝」。
    /// 留这段说明是因为下一个读到它的人会问「为什么曾经写死拒绝」。
    func testVolunteerMayTriggerDuringServiceButNotOutsideIt() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED"))

        let allowed = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .volunteer,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertFalse(allowed.isFailure)
        XCTAssertEqual(safety.calls.count, 1, "服务进行中，志愿者代触发必须真的发出去")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 77)

        // 服务之外仍然不放行：与盲人侧同一个 IN_PROGRESS 门槛，不因为角色不同而放宽。
        let blocked = await EmergencyCoordinator().trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .volunteer,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(blocked.isFailure)
        XCTAssertEqual(safety.calls.count, 1, "非服务中状态不得再发一次请求")
    }

    // MARK: - Trigger: GPS gate

    func testStrictGpsGateSendsNothingWithoutACoordinate() async {
        XCTAssertFalse(
            EmergencyCoordinator.allowsSubmissionWithoutLocation,
            "the strict gate is the shipped default until product/safety approve degradation"
        )
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { nil },
            locationFailureReason: { .permissionDenied }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(.permissionDenied))
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(safety.calls.isEmpty)
        XCTAssertTrue(outcome.message.contains("设置"), "must guide the user to Settings")
    }

    /// F12：定位失败的两种成因，下一步动作完全不同。把「室内没信号」说成「去开权限」，
    /// 是让一个正处在紧急状态的盲人去翻一个根本没关的开关。
    func testNoLocationCopySplitsPermissionFromSignalLoss() async {
        let denied = EmergencySafetyCopy.locationUnavailable(.permissionDenied)
        XCTAssertTrue(denied.contains("定位权限"))
        XCTAssertTrue(denied.contains("设置"))

        for reason: LocationError? in [.locationUnavailable, .timeout, nil] {
            let signalLost = EmergencySafetyCopy.locationUnavailable(reason)
            XCTAssertFalse(
                signalLost.contains("设置"),
                "权限没问题时不该把人支去翻设置（reason=\(String(describing: reason))）"
            )
            XCTAssertTrue(signalLost.contains("开阔处"))
            XCTAssertTrue(signalLost.hasPrefix("求助未发出"))
            XCTAssertTrue(signalLost.contains("110"))
        }

        // 默认不传 reason 时走通用支，不许退回原来那句「请在设置中允许定位」。
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { nil }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(nil))
        XCTAssertFalse(outcome.message.contains("设置"))
    }

    /// A device WGS-84 sample must never be uploaded raw; only the value already normalized at the
    /// single backend boundary is accepted.
    func testUnconvertedDeviceCoordinateIsTreatedAsNoLocation() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let raw = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            system: .wgs84Device,
            capturedAt: Date()
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { raw }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(nil))
        XCTAssertTrue(safety.calls.isEmpty)
    }

    // MARK: - 倒计时（屏 3）

    /// 🔴 **倒计时这三秒里，一个字节都不许发给后端。**
    ///
    /// 这不是性能取舍，是安全取舍。后端 `POST /api/emergency/trigger` 是**触发即升级**：
    /// 紧急联系人在那一个请求里就被通知（异步发短信），撤销会再补一条解除短信，
    /// 而冷却 60 秒是**按触发者计**的（`demo/docs/api_spec.yaml:2242`）。
    /// 所以「先发再撤」的真实代价是：每一次误触都惊动家人两次，
    /// **并在随后的 60 秒里锁死真正的求助**（429）。
    ///
    /// 这条用例读的是 `safety.calls` 的长度 —— 它是「到底有没有发出去」的唯一客观判据。
    @MainActor
    func testCountdownSendsNothingBeforeItReachesZero() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }

        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertTrue(coordinator.state.isCountingDown, "按下之后没有进倒计时")
        XCTAssertTrue(coordinator.state.isBusy, "倒计时期间必须挡住重复触发")
        XCTAssertFalse(coordinator.state.isFailure, "倒计时不是失败态，不该被染成错误色")

        // 数一秒，仍然什么都没发。
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(safety.calls.isEmpty, "倒计时还没结束就把求助发出去了：\(safety.calls)")

        XCTAssertTrue(coordinator.cancelCountdown(), "取消倒计时应当返回成功")
        XCTAssertEqual(coordinator.state, .idle)

        // 取消之后再等过原本的归零时刻 —— 任务真的停了，而不是只把状态改了。
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        XCTAssertTrue(safety.calls.isEmpty, "取消之后求助仍然发出去了：\(safety.calls)")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 归零之后必须真的发出去。
    ///
    /// **和上一条是一对，缺一条另一条就没意义**：只验「倒计时中不发」的话，
    /// 一个永远不发的实现照样通过。
    @MainActor
    func testCountdownFiresTheTriggerOnceItReachesZero() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 900, status: "CONTACT_NOTIFIED")
        )

        var spoken: [String] = []
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) },
            announce: { spoken.append($0) }
        )

        // 3 秒倒计时 + 一点余量给归零后那一次 await。
        try? await Task.sleep(nanoseconds: 4_500_000_000)

        XCTAssertEqual(safety.calls.count, 1, "归零之后没有恰好发一次：\(safety.calls)")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 900)
        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))

        // 每一秒都得说一次，而且每一句都要带「可以取消」——
        // 看不见屏幕的人不会知道屏幕下方有个取消按钮，除非有人一直在告诉他。
        let countdownLines = spoken.filter { $0.contains("秒后发出") }
        XCTAssertEqual(countdownLines.count, EmergencyCoordinator.countdownSeconds)
        for line in countdownLines {
            XCTAssertTrue(line.contains("取消"), "这一句没告诉用户还能取消：\(line)")
        }
        XCTAssertEqual(spoken.first, EmergencySafetyCopy.countdownTitle, "进倒计时那一刻没有播报")
    }

    /// 倒计时期间再按一下**不该叠出第二个倒计时，也不该把倒计时重新计到 3**。
    ///
    /// ⚠️ 2026-09-15 code review 指出这条用例原本**分辨不出**它宣称守的东西：
    /// 三次调用挤在同一瞬间，而 `beginCountdown` 开头有一句 `countdownTask?.cancel()`——
    /// 于是把 `.countingDown` 从 `isBusy` 里拿掉（也就是「第二次按重启倒计时」这个
    /// 被打回的实现）之后，最后仍然只剩一个任务在跑，`safety.calls.count` 照样是 1。
    ///
    /// 现在把三次按下**拉开 1.2 秒**，并数「还有 3 秒」这句播报出现了几次：
    /// 正确实现只念一次（后两次被 `isBusy` 挡掉），重启实现会念三次。
    @MainActor
    func testSecondPressDuringCountdownNeitherResendsNorRestartsTheCountdown() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 901, status: "CONTACT_NOTIFIED")
        )
        let order = Self.makeOrder(status: .inProgress)
        var spoken: [String] = []
        let press = {
            coordinator.beginCountdown(
                order: order,
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) },
                announce: { spoken.append($0) }
            )
        }

        press()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        press()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        press()

        try? await Task.sleep(nanoseconds: 3_500_000_000)

        XCTAssertEqual(safety.calls.count, 1, "连按三下发出了 \(safety.calls.count) 条求助")
        let restarts = spoken.filter { $0 == EmergencySafetyCopy.countdown(secondsRemaining: 3) }
        XCTAssertEqual(
            restarts.count,
            1,
            "倒计时被重新计到 3 了 \(restarts.count) 次 —— 每按一下就多拖 3 秒，而这三秒里没人来救"
        )
    }

    // MARK: - 屏 3 / 3b 的标题（code review A2 / A3）

    /// 🔴 **顶部那句大标题必须与此刻的真实状态一致。**
    ///
    /// code review 抓到的原缺陷：`.locating` / `.submitting` 落进 `else` 分支，
    /// 于是在**一个字节都还没发出去**的那最长约 20 秒里（等定位 5 秒 + 请求超时 15 秒），
    /// 屏幕顶部 44pt 的红色大标题写着「求助已发出」，正文写着「正在获取当前位置」。
    /// 标题带 `.isHeader`，VoiceOver 滑到页首听到的就是这句。
    ///
    /// 这条用例**逐状态穷举**，而不是只挑两三个 —— `testNoEmergencyCopyClaimsAnSMSWasDelivered`
    /// 扫的是字符串常量，扫不到一个 `if/else` 的取值，那正是它漏掉这个缺陷的原因。
    func testScreenTitleNeverClaimsSentBeforeAnythingWasSent() {
        let notSentYet: [EmergencySOSState] = [
            .countingDown(secondsRemaining: 3),
            .locating,
            .submitting,
            .unsentNoLocation(nil),
            .unsentNoLocation(.permissionDenied),
            .failed("网络异常"),
            .cooldown(retryAfterSeconds: 42),
        ]
        for state in notSentYet {
            let title = EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: false)
            XCTAssertNotEqual(
                title,
                EmergencySafetyCopy.sentTitle,
                "\(state) 时一个字节都还没发出去，标题却写着「\(title)」"
            )
        }

        // 还在路上的两态：**进行时**，不能是将来时的承诺、也不能是完成时。
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .locating, hasActiveEvent: false), EmergencySafetyCopy.sendingTitle)
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .submitting, hasActiveEvent: false), EmergencySafetyCopy.sendingTitle)

        // 失败三态：**不许回落成「即将发出」**。那是一句将来时的承诺，而这条求助已经死了，
        // 必须靠用户自己按「再发一次求助」。
        for state in [EmergencySOSState.unsentNoLocation(nil), .failed("网络异常"), .cooldown(retryAfterSeconds: 1)] {
            XCTAssertEqual(
                EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: false),
                EmergencySafetyCopy.unsentTitle,
                "\(state) 的标题应当直说没发出去"
            )
        }

        // 真的发出去了的才准用完成时。`contactNotifyFailed` 也在内：
        // 失败的是**通知联系人**，求助本身已经发出去了。
        for state in [EmergencySOSState.acknowledged(.contactNotified), .contactSmsDelivered, .contactNotifyFailed] {
            XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: state, hasActiveEvent: true), EmergencySafetyCopy.sentTitle)
        }

        XCTAssertEqual(
            EmergencySafetyCopy.screenTitle(for: .cancelledByOwner, hasActiveEvent: false),
            EmergencySafetyCopy.cancelledTitle
        )
        // `.idle` 只由「有没有事件」决定，不猜。
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .idle, hasActiveEvent: true), EmergencySafetyCopy.sentTitle)
        XCTAssertEqual(EmergencySafetyCopy.screenTitle(for: .idle, hasActiveEvent: false), EmergencySafetyCopy.unsentTitle)
    }

    // MARK: - 警报音与震动（code review A10）

    /// 倒计时每一秒**恰好**响一次、震一次。
    ///
    /// ⚠️ code review 指出 `EmergencyAlarm.observerForTesting` / `playerForTesting` 此前
    /// 只被装成 no-op、一条断言都没有，而它们的存在理由被逐字写在实现里：
    /// 「没有断言的实现，和不存在的实现在下一个人眼里是一样的 ——
    /// 而这是盲人判断「倒计时开始了没有」的唯一非视觉信号」。
    ///
    /// 屏幕上那个圆环对一个戴着骨传导耳机、手机绑在腰上的跑者不存在；
    /// 声音和震动**就是**倒计时本身。
    @MainActor
    func testCountdownSoundsAndVibratesOncePerSecond() async {
        var ticks: [EmergencyAlarm.Kind] = []
        var vibrations = 0
        EmergencyAlarm.observerForTesting = { ticks.append($0) }
        EmergencyHaptics.observerForTesting = { _ in vibrations += 1 }
        defer { Self.teardownAlarmObservers() }

        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 903, status: "CONTACT_NOTIFIED")
        )
        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        try? await Task.sleep(nanoseconds: 4_500_000_000)

        XCTAssertEqual(
            ticks.count,
            EmergencyCoordinator.countdownSeconds,
            "倒计时响了 \(ticks.count) 声，应当是每秒一声共 \(EmergencyCoordinator.countdownSeconds) 声"
        )
        XCTAssertEqual(vibrations, EmergencyCoordinator.countdownSeconds, "震动次数和声音对不上")
        // 用的是倒计时那一声，不是连续警报 —— 后者是志愿者端强提醒用的，会一直循环。
        XCTAssertTrue(ticks.allSatisfy { $0 == .countdownTick })
    }

    /// 🔴 **同一种警报音始终是同一个播放器对象。**
    ///
    /// 这条不是优化，是防崩：2026-08-16 `RecordingCue` 曾经「每次发声 new 一个播放器、
    /// 覆盖同一个静态槽」，于是上一声还在播时就被释放，音频队列随后把
    /// `-[AVAudioPlayer finishedPlaying:]` 派回主线程、打在已被复用的内存上 ——
    /// 真机表现是**崩在任意一条与音频无关的用例上**
    /// （记忆 `finishedplaying-crash-means-player-freed-not-delegate`）。
    ///
    /// 倒计时这一声每秒触发一次、而一声只有 0.17 秒，**正是同一个形状**。
    @MainActor
    func testEmergencyAlarmReusesOnePlayerPerKind() throws {
        // 这条要真的建播放器，所以不能装 observer（装了就被接管、一个播放器都不会创建）。
        EmergencyAlarm.observerForTesting = nil
        EmergencyHaptics.observerForTesting = { _ in }
        defer { Self.teardownAlarmObservers() }

        EmergencyAlarm.countdownTick()
        let first = try XCTUnwrap(
            EmergencyAlarm.playerForTesting(.countdownTick),
            "第一次触发之后没有留下播放器 —— 出了作用域就停，提示音等于没响"
        )
        EmergencyAlarm.countdownTick()
        let second = try XCTUnwrap(EmergencyAlarm.playerForTesting(.countdownTick))

        XCTAssertTrue(
            first === second,
            "同一种警报音换了播放器对象 —— 上一声还在播时被释放，就是那次 use-after-free 的形状"
        )
        EmergencyAlarm.stopAll()
    }

    /// 🔴 **会话边界必须掐掉在飞的倒计时。**
    ///
    /// 漏掉这一条的后果很具体：上一个账号退出登录三秒之后，那个求助**照样发出去**，
    /// 而且带的是新登录账号的 token —— 事件会挂在错误的人身上，短信发给错误的家属。
    @MainActor
    func testResetCancelsAnInFlightCountdown() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 902, status: "CONTACT_NOTIFIED")
        )

        coordinator.beginCountdown(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        XCTAssertTrue(coordinator.state.isCountingDown)

        coordinator.reset()
        XCTAssertEqual(coordinator.state, .idle)

        try? await Task.sleep(nanoseconds: 4_500_000_000)
        XCTAssertTrue(safety.calls.isEmpty, "退出登录之后那个倒计时仍然把求助发了出去：\(safety.calls)")
    }

    /// 发不出去的状态**不该白数三秒**。那三秒里用户以为求助在路上。
    @MainActor
    func testCountdownIsRefusedOutsideInProgress() async {
        let (coordinator, safety) = Self.makeCountdownFixture()
        defer { Self.teardownAlarmObservers() }

        for status in RunOrderStatus.allCases where status != .inProgress {
            coordinator.reset()
            coordinator.beginCountdown(
                order: Self.makeOrder(status: status),
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
            )
            XCTAssertFalse(
                coordinator.state.isCountingDown,
                "\(status) 不能发起求助，却进了倒计时"
            )
            XCTAssertTrue(coordinator.state.isFailure, "\(status) 下按求助没有给出任何失败反馈")
        }
        XCTAssertTrue(safety.calls.isEmpty)
    }

    /// 没在倒计时的时候取消是**空操作**，不是「撤销已经发出的求助」。
    ///
    /// 两个动作打的是完全不同的后端：取消倒计时零请求，撤销求助走
    /// `PUT /api/emergency/{id}/cancel` 并给联系人补发解除短信。混掉的表现是
    /// 「我只是想收起这一屏，结果把一个真的求助撤了」。
    @MainActor
    func testCancellingWhenNotCountingDownDoesNothing() {
        let coordinator = EmergencyCoordinator()
        XCTAssertFalse(coordinator.cancelCountdown())
        XCTAssertEqual(coordinator.state, .idle)
    }

    // MARK: - 发送失败后的对账（阶段 4）

    /// 🔴 **一个会说谎的失败**：请求在服务端处理完了、响应在回程丢了（弱网、切基站、
    /// 后台挂起），客户端只看见 `网络异常`。那一刻屏幕上写着「求助未发出」，
    /// 而家属的短信其实已经在路上 —— 盲人会据此以为没人知道他出事了。
    ///
    /// 修法是**去问一句**，不是重发：`GET /api/emergency/active` 按契约原文是
    /// 「事件 id 与当前状态的唯一权威来源」，而且是只读的。
    @MainActor
    func testFailedSendAsksTheBackendWhetherItActuallyLanded() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
        // 后端其实收到了：事件真的存在。
        safety.activeEmergencyResult = .success(Self.openEventEnvelope(id: 808))
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(coordinator.activeEvent?.eventID, 808)
        XCTAssertFalse(outcome.isFailure, "求助其实已经生效，界面却还在说「未发出」")
        XCTAssertFalse(outcome.message.contains("未发出"))
    }

    /// 429 冷却是**最强的一条「刚才那条真的发出去了」的证据**：后端按触发者 SETNX 占位，
    /// 命中它几乎只可能是我们自己刚刚那一条占的。
    ///
    /// 不对账的话用户听到的是「刚刚已经发送过求助，请 42 秒后再试」——
    /// 那句话听起来像被拒绝，而实际上求助正在生效。
    @MainActor
    func testCooldownIsReconciledIntoAnActiveEmergencyNotARejection() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(
            APIError.rateLimited(RateLimitInfo(message: "刚刚已经发送过求助", retryAfterSeconds: 42))
        )
        safety.activeEmergencyResult = .success(Self.openEventEnvelope(id: 809))
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(coordinator.activeEvent?.eventID, 809)
        XCTAssertFalse(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("秒后再试"))
    }

    /// 反向锁：**对账不许制造救援状态**。
    ///
    /// 后端说没有未结束的事件（或这一侧压根没有查询权限，比如志愿者），
    /// 失败就还是失败 —— 屏幕上必须留着「未发出」和那个拨 120 的入口。
    /// 这条比上面两条更要紧：上面两条错了是少说一句，这条错了是**把没发出的求助说成发出了**。
    @MainActor
    func testReconciliationNeverInventsRescueStateWhenNothingIsOpen() async {
        for activeResult in [
            Result<EmergencyActiveEnvelope, Error>.success(
                EmergencyActiveEnvelope(success: true, data: nil)
            ),
            // 查询本身也失败（断网时这才是最常见的情形）。
            .failure(URLError(.notConnectedToInternet)),
        ] {
            let safety = FakeSafetyService()
            safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
            safety.activeEmergencyResult = activeResult
            let coordinator = Self.makeRecoverableCoordinator(safety: safety)

            let outcome = await coordinator.trigger(
                order: Self.makeOrder(status: .inProgress),
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
            )

            XCTAssertNil(coordinator.activeEvent, "后端没有未结束的事件，却造出了一个")
            XCTAssertTrue(outcome.isFailure, "求助没发出去，界面却不再说「未发出」")
            XCTAssertTrue(coordinator.state.isFailure, "失败态没保住，拨 120 的入口会跟着消失")
        }
    }

    /// 🔴 **手里还攥着一个旧事件、而新的这次发送失败了。**
    ///
    /// 这是本组里唯一一条真正会出事的路径，也是上面那条用例**盖不住**的：
    /// 对账发现后端其实已经没有未结束的事件（旧的被客服解除了），于是它会
    /// 顺手把本地那个陈旧事件清掉、状态归 `.idle` —— 而 `.idle` 的 `message` 是 `nil`。
    ///
    /// 如果这时候直接把「对账之后的状态」当成结果返回，用户按下求助之后
    /// **屏幕上什么都不会多出来、耳朵里也一个字都听不到**：既没有「未发出」，
    /// 也没有那个拨 120 的入口。对看不见屏幕的人，这与「按了没反应」不可区分。
    ///
    /// 2026-09-15 验红时发现：把 `reconcile` 里那道 `guard activeEvent != nil` 去掉，
    /// 上面那条用例照样绿 —— 它从一个干净的 coordinator 出发，走不到这条分支。
    /// 这条用例就是为补那个洞写的。
    @MainActor
    func testFailureIsStillAnnouncedEvenWhenReconciliationClearsAStaleEvent() async {
        let safety = FakeSafetyService()
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        // 先制造一个「手里攥着旧事件」的现实状态：上一次求助成功过。
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 700, status: "CONTACT_NOTIFIED")
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        XCTAssertEqual(coordinator.activeEvent?.eventID, 700)

        // 现在：旧事件已被客服解除（后端说没有未结束的），而新的这次发送失败了。
        safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
        safety.activeEmergencyResult = .success(EmergencyActiveEnvelope(success: true, data: nil))

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertNil(coordinator.activeEvent, "陈旧事件没被清掉，界面会顶着一个早就结束的求助")
        XCTAssertTrue(outcome.isFailure, "新的这次发送失败了，却没有作为失败播报出去")
        XCTAssertFalse(
            outcome.message.isEmpty,
            "按下求助之后一个字都没说 —— 对看不见屏幕的人，这与「按了没反应」不可区分"
        )
        XCTAssertTrue(outcome.message.contains("未发出"))
    }

    /// 对账**只在失败路径上发生**。成功那条不许多打一次查询 ——
    /// 触发响应里已经带了 `eventId` 和状态，再查一次是纯浪费，而这条链路上每一次
    /// 往返都发生在一个人正在出事的时候。
    @MainActor
    func testSuccessfulSendDoesNotPayForAnExtraQuery() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 810, status: "CONTACT_NOTIFIED")
        )
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
    }

    @MainActor
    private static func makeRecoverableCoordinator(safety: FakeSafetyService) -> EmergencyCoordinator {
        let coordinator = EmergencyCoordinator()
        // `refreshActiveEvent` 只在装了 provider 时才会去问 —— 志愿者那一侧刻意装不上
        // （`GET /api/emergency/active` 角色限 BLIND），所以对账在那一侧天然是空操作。
        coordinator.observe(AppRealtimeCoordinator(notificationDuration: 60)) { safety }
        return coordinator
    }

    /// 用**解码**造 fixture，不用逐字段构造。
    ///
    /// 这个类型的字段是后端契约的形状（`status` 还刻意是 `String` 而不是枚举，
    /// 见它自己的注释），逐字段写死会在后端加字段时全线红 ——
    /// 而那种红说明不了任何事，只会让下一个人把用例改成将就。
    private static func openEventEnvelope(id: Int64) -> EmergencyActiveEnvelope {
        let json = """
        {"success":true,"code":200,"data":{
          "id":\(id),"orderId":4242,"userId":7,
          "triggeredAt":"2026-09-15T14:30:00","triggerType":"BUTTON",
          "status":"CONTACT_NOTIFIED","hasGpsLocation":true}}
        """
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! APIPayloadDecoder.decodePayload(
            EmergencyActiveEnvelope.self,
            from: Data(json.utf8),
            decoder: JSONDecoder()
        )
    }

    /// 倒计时的替身接缝：跑测时不该真的在办公室里拉响警报，也不该真的震。
    @MainActor
    private static func makeCountdownFixture() -> (EmergencyCoordinator, FakeSafetyService) {
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
        return (EmergencyCoordinator(), FakeSafetyService())
    }

    @MainActor
    private static func teardownAlarmObservers() {
        EmergencyAlarm.observerForTesting = nil
        EmergencyHaptics.observerForTesting = nil
    }

    func testSuccessfulTriggerSendsOrderAndGcj02Coordinate() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 512, status: "VOLUNTEER_NOTIFIED"))

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        // 打的是不是 `POST /api/emergency/trigger` 由
        // `SafetyServiceTests.testTriggerEmergencyPostsTheRequestBody` 守，这里只管
        // 「coordinator 有没有把订单和那份 GCJ-02 坐标原样交下去」。
        XCTAssertEqual(safety.calls.count, 1)
        XCTAssertEqual(safety.lastTriggerRequest?.orderId, 4242)
        XCTAssertEqual(safety.lastTriggerRequest?.gpsLat ?? 0, 39.915, accuracy: 0.000001)
        XCTAssertEqual(safety.lastTriggerRequest?.gpsLng ?? 0, 116.404, accuracy: 0.000001)

        XCTAssertEqual(coordinator.state, .acknowledged(.volunteerNotified))
        XCTAssertEqual(coordinator.activeEvent?.eventID, 512)
        XCTAssertEqual(coordinator.activeEvent?.orderID, 4242)
        XCTAssertEqual(coordinator.activeEvent?.userID, 7)
        XCTAssertFalse(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("短信"))
    }

    // MARK: - Trigger: result gating

    /// HTTP 200 alone is not an acknowledgement — `success: false` is a failure.
    func testUnsuccessfulStructuredBodyIsAFailure() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: false, eventId: 1, status: "PENDING"))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testDecodingFailureLeavesSosUnsent() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(APIError.decodingError(TriggerStubError.decoding))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(outcome.message.hasPrefix("求助未发出"))
        XCTAssertNil(coordinator.activeEvent)
    }

    /// Backend cooldown is `RateLimitException(60)` → 429 `TOO_MANY_REQUESTS` with
    /// `retryAfterSeconds` + a `Retry-After` header (`GlobalExceptionHandler.java:218-231`).
    func testCooldownSurfacesTheRetryDelay() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(APIError.rateLimited(RateLimitInfo(message: "请求过于频繁", retryAfterSeconds: 47)))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertEqual(coordinator.state, .cooldown(retryAfterSeconds: 47))
        XCTAssertTrue(outcome.message.contains("47"))
        XCTAssertNil(coordinator.activeEvent)
    }

    func testConcurrentTapsSendOnlyOneRequest() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING"))
        safety.triggerDelayNanoseconds = 200_000_000

        let order = Self.makeOrder(status: .inProgress)
        // A slow fix acquisition is the realistic window for a second tap: the runner hears nothing
        // yet and presses again. The guard must already be armed during `.locating`, not only once
        // the request is in flight.
        async let first = coordinator.trigger(
            order: order,
            role: .blind,
            userID: 7,
            safety: safety,
            locate: {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return Self.coordinate()
            }
        )
        // 这里原本是单次 `await Task.yield()` 然后立刻断言。**那是 flaky 的**：一次 yield 只保证
        // 当前任务让出一次，不保证 `trigger` 已经跑到 `state = .locating`。单跑本套件永远绿，
        // 和另外三套一起跑（77 条）时会间歇性红成 `("idle") is not equal to ("locating")` ——
        // 2026-08-12 实测同一份代码、同一条命令，一次 76/77、一次 77/77。
        //
        // 改成有界自旋。断言的意图一个字没变（「`.locating` 期间守卫就必须已经武装」），
        // 变的只是不再假设一次 yield 足够：真回归时状态永远不会变成 `.locating`，
        // 循环空转到超时，断言照样红。
        var spins = 0
        while coordinator.state != .locating && spins < 100 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(coordinator.state, .locating, "the button must show progress while locating")

        let second = await coordinator.trigger(
            order: order, role: .blind, userID: 7, safety: safety, locate: { Self.coordinate() }
        )
        _ = await first

        XCTAssertEqual(safety.calls.count, 1, "a double tap must not send two SOS requests")
        XCTAssertTrue(second.state.isBusy)
    }

    // MARK: - Realtime follow-ups

    func testContactNotifiedEventAdvancesTheActiveEvent() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))

        XCTAssertEqual(coordinator.activeEvent?.status, .contactNotified)
        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
        XCTAssertEqual(coordinator.state.message, EmergencySafetyCopy.contactNotified)
    }

    func testEventForAnotherOrderIsIgnored() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified, orderID: 999))

        XCTAssertEqual(coordinator.activeEvent?.status, .volunteerNotified)
    }

    func testSafetyEventWithoutAnActiveEmergencyIsIgnored() {
        let coordinator = EmergencyCoordinator()
        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testResetClearsEverythingAtSessionBoundaries() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "PENDING"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertNotNil(coordinator.activeEvent)

        coordinator.reset()

        XCTAssertNil(coordinator.activeEvent)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.repeatStatusSuffix)
    }

    // MARK: - Backend copy substitution

    /// The backend template body ("已通知紧急联系人{contactName}") must never reach the user.
    func testEmergencyEventTypesMapToLocalCopyNotBackendBody() {
        let mapped: [(String, RealtimeSafetyEvent.Kind, String)] = [
            ("EMERGENCY_TRIGGERED", .emergencyTriggered, EmergencySafetyCopy.triggeredAcknowledged),
            ("EMERGENCY_CONTACT_NOTIFIED", .emergencyContactNotified, EmergencySafetyCopy.contactNotified),
            ("EMERGENCY_NO_CONTACT", .emergencyNoContact, EmergencySafetyCopy.noContact),
            ("EMERGENCY_VOLUNTEER_TIMEOUT", .emergencyVolunteerTimeout, EmergencySafetyCopy.volunteerTimeout)
        ]
        for (eventType, expectedKind, expectedCopy) in mapped {
            XCTAssertEqual(AppRealtimeCoordinator.emergencyKind(forEventType: eventType), expectedKind)
            XCTAssertEqual(AppRealtimeCoordinator.emergencyCopy(for: expectedKind), expectedCopy)
        }
        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "SERVICE_STARTED"))
    }

    // MARK: - Contract shape

    /// Shape comes from `EmergencyController.java:34-38`, which returns a bare `Map` rather than the
    /// usual `ApiResponse` envelope; `api_spec.yaml:1024-1030` only says `type: object`.
    func testTriggerResponseDecodesTheControllerShape() throws {
        let json = Data(#"{"success":true,"eventId":512,"status":"VOLUNTEER_NOTIFIED"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventId, 512)
        XCTAssertEqual(decoded.eventStatus, .volunteerNotified)
    }

    /// A status this client cannot name must degrade to `.unknown`, never to a rescue claim.
    func testUnrecognisedStatusDegradesToUnknown() throws {
        let json = Data(#"{"success":true,"eventId":1,"status":"SOMETHING_NEW"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventStatus, .unknown)
        XCTAssertFalse(EmergencySafetyCopy.submitted(.unknown).contains("已通知"))
    }

    /// Guards against drift from backend `entity/EmergencyStatus.java`.
    func testEmergencyStatusMirrorsTheBackendEnum() {
        let backendNames: Set<String> = [
            "PENDING", "VOLUNTEER_NOTIFIED", "VOLUNTEER_CONFIRMED",
            "CS_HANDLING", "CONTACT_NOTIFIED", "RESOLVED", "FALSE_ALARM"
        ]
        let clientNames = Set(EmergencyEventStatus.allCases.map(\.rawValue)).subtracting(["UNKNOWN"])
        XCTAssertEqual(clientNames, backendNames)
        XCTAssertTrue(EmergencyEventStatus.resolved.isTerminal)
        XCTAssertTrue(EmergencyEventStatus.falseAlarm.isTerminal)
        XCTAssertFalse(EmergencyEventStatus.contactNotified.isTerminal)
    }

    // MARK: - Fixtures

    /// `nonisolated` so it can be called from the detached `locate` closure in the concurrency test.
    nonisolated private static func coordinate(
        latitude: Double = 39.9,
        longitude: Double = 116.4
    ) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            system: .gcj02Backend,
            capturedAt: Date()
        )
    }

    private static func safetyEvent(
        kind: RealtimeSafetyEvent.Kind,
        orderID: Int64? = nil,
        coordinate: LocatedCoordinate? = nil
    ) -> RealtimeSafetyEvent {
        RealtimeSafetyEvent(
            eventID: "msg-1",
            orderID: orderID,
            kind: kind,
            displayText: "ignored",
            speechText: "ignored",
            timestamp: nil,
            coordinate: coordinate
        )
    }

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

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4242,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: "13800000000",
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}

// MARK: - Test Doubles
//
// 替身是 `FakeSafetyService`（`blindRunTests/FakeSafetyService.swift`）。原先这里那个
// `EmergencyAPIClientStub` 是个 `APIClientProtocol` 桩，按 path 分支决定返回什么 ——
// 于是「什么条件下才该发出请求」这个判定同时活在被测代码和替身里，而它正是 §6 的红线本身。

/// 只用来喂 `APIError.decodingError` 一个底层错误。
private enum TriggerStubError: Error { case decoding }
