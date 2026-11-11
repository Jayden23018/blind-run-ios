import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSTruthfulnessTests: XCTestCase, EmergencySOSTestSupport {

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
            "陪跑员不能撤销求助，请确认对方是否需要帮助。"
        )
        // 撤销权只在受助者本人手里，且入口文案要说清代价（会给家属补一条解除短信）。
        XCTAssertTrue(EmergencySafetyCopy.cancelOwnerConfirmation.contains("解除短信"))
    }

    /// 求助没结案时结束服务被 409（后端 issue #387 ③）。志愿者点「撤销」恒 403，
    /// 所以文案只能指向跑者本人或客服，绝不能叫他自己去撤销。
    func testFinishBlockedByActiveEmergencyPointsAwayFromTheVolunteer() throws {
        let code = try XCTUnwrap(ErrorCode(rawValue: "ORDER_HAS_ACTIVE_EMERGENCY"))
        let copy = code.localizedMessage
        XCTAssertTrue(copy.contains("跑者本人"), copy)
        XCTAssertTrue(copy.contains("客服"), copy)
        XCTAssertFalse(copy.contains("撤销求助"), copy)
        XCTAssertFalse(copy.contains("再试"), copy)
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
    /// 订单页的兜底拨号按钮完全由 `state.isFailure` 驱动，所以这里把每个状态逐个钉住。
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
}
