import CoreLocation
import XCTest
@testable import blindRun

/// 盲人端「问一句」的意图判定与答句。录音、播报、拨号那一层在 `VoiceStatusQuerySession`，
/// 这里只钉纯逻辑 —— 它刻意被抽成纯函数，就是为了这一组用例不需要真机硬件。
@MainActor
final class VoiceStatusQueryTests: XCTestCase {

    // MARK: - 四个意图各至少 3 种说法

    func testDistanceIntentMatchesCommonPhrasings() {
        for utterance in ["志愿者还有多远", "他到哪了？", "什么时候到", "快到了吗", "还有多久到"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .distance,
                "「\(utterance)」应判为问距离"
            )
        }
    }

    func testStatusIntentMatchesCommonPhrasings() {
        for utterance in ["现在什么状态", "到哪一步了", "接单了吗", "怎么样了", "什么情况"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .status,
                "「\(utterance)」应判为问状态"
            )
        }
    }

    func testScheduleIntentMatchesCommonPhrasings() {
        for utterance in ["几点开始", "什么时候开始", "在哪儿集合", "出发地点是哪里", "预约时间是多少"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .schedule,
                "「\(utterance)」应判为问时间地点"
            )
        }
    }

    func testCallIntentMatchesCommonPhrasings() {
        for utterance in ["打电话给志愿者", "给他打个电话", "帮我拨号", "联系志愿者", "志愿者电话是多少"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .callVolunteer,
                "「\(utterance)」应判为要打电话"
            )
        }
    }

    /// 判定顺序的两条硬约束。写死成用例是因为它们只在**词表相互包含**时才出错，
    /// 而词表以后一定会被人加词。
    func testMoreSpecificPhrasesWinOverTheirSubstrings() {
        // 「到哪一步」包含「到哪」：status 必须排在 distance 前面。
        XCTAssertEqual(VoiceStatusQuery.classify("到哪一步了"), .status)
        XCTAssertEqual(VoiceStatusQuery.classify("他到哪了"), .distance)
        // 「什么时候到」包含「什么时候」：distance 必须排在 schedule 前面。
        XCTAssertEqual(VoiceStatusQuery.classify("什么时候到"), .distance)
        XCTAssertEqual(VoiceStatusQuery.classify("什么时候开始"), .schedule)
    }

    // MARK: - 破坏性动作一律拒绝

    func testCancellationWordsAreBlockedInsteadOfFallingBackToTheFullAnnouncement() {
        for utterance in ["取消订单", "帮我取消", "我不跑了", "退单"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .blockedDestructive,
                "「\(utterance)」必须落到显式拒绝，不能落进整段兜底"
            )
        }
    }

    /// 「打电话取消订单」里两张表都命中。**破坏性词必须先判** ——
    /// 反过来的话它会被当成拨号意图，而拨号是会真的打出去的。
    func testDestructiveWordsWinOverDialing() {
        XCTAssertEqual(VoiceStatusQuery.classify("打电话取消订单"), .blockedDestructive)
    }

    func testBlockedDestructiveAnswerPointsAtTheOnScreenButtonAndDoesNothingElse() {
        let answer = VoiceStatusQuery.answer(
            intent: .blockedDestructive,
            order: Self.makeOrder(status: .pendingAccept),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertEqual(answer.speech, "取消需要在屏幕上确认，请找取消订单按钮。")
        XCTAssertNil(answer.pendingAction)
    }

    // MARK: - 听不懂：整段 + 可问清单

    func testUnrecognizedTranscriptFallsBackToTheFullAnnouncementAndTeachesWhatToAsk() {
        let answer = VoiceStatusQuery.answer(
            intent: .unrecognized,
            order: Self.makeOrder(status: .driverEnRoute),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "志愿者已出发，正在前往出发地点。"
        )
        XCTAssertTrue(
            answer.speech.hasPrefix("志愿者已出发，正在前往出发地点。"),
            "整段状态必须还在，实际：\(answer.speech)"
        )
        XCTAssertTrue(
            answer.speech.hasSuffix(VoiceStatusQuery.askableHint),
            "末尾必须追加可问清单，实际：\(answer.speech)"
        )
        XCTAssertNil(answer.pendingAction)
    }

    func testUnrelatedChitchatIsUnrecognizedRatherThanGuessed() {
        for utterance in ["今天天气怎么", "帮我放首歌", "哈哈哈"] {
            XCTAssertEqual(
                VoiceStatusQuery.classify(utterance),
                .unrecognized,
                "「\(utterance)」不该被猜成某个意图"
            )
        }
    }

    func testEmptyTranscriptIsUnrecognized() {
        XCTAssertEqual(VoiceStatusQuery.classify(""), .unrecognized)
        XCTAssertEqual(VoiceStatusQuery.classify("  \n "), .unrecognized)
    }

    // MARK: - 边界：没有进行中的订单

    func testWithoutAnActiveOrderEveryIntentSaysSoAndTeachesWhatToAsk() {
        for intent in [
            VoiceStatusIntent.distance, .status, .schedule, .callVolunteer, .blockedDestructive, .unrecognized
        ] {
            let answer = VoiceStatusQuery.answer(
                intent: intent,
                order: nil,
                volunteerCoordinate: Self.volunteerCoordinate,
                fallbackAnnouncement: ""
            )
            XCTAssertEqual(
                answer.speech,
                "当前没有进行中的预约。 \(VoiceStatusQuery.askableHint)",
                "\(intent) 在无订单时的答句不对"
            )
            XCTAssertNil(answer.pendingAction, "\(intent) 在无订单时不得留下待办动作")
        }
    }

    // MARK: - 边界：问距离但当下没有距离

    /// 「暂时没有这个信息」是不够的：盲人要能分清「功能坏了」和「现在就没这个数据」。
    /// 所以每条都断言**原因**和**当前状态**同时在。
    func testDistanceWithoutAVolunteerExplainsWhyAndGivesTheCurrentStatus() {
        let answer = VoiceStatusQuery.answer(
            intent: .distance,
            order: Self.makeOrder(status: .pendingMatch),
            volunteerCoordinate: Self.volunteerCoordinate,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains("还没有志愿者接单"), answer.speech)
        XCTAssertTrue(answer.speech.contains(RunOrderStatus.pendingMatch.displayName), answer.speech)
        XCTAssertFalse(answer.speech.contains("整段状态"), "空数据不该降级去念整段")
    }

    func testDistanceDuringServiceSaysTheNumberIsMeaninglessRatherThanMissing() {
        let answer = VoiceStatusQuery.answer(
            intent: .distance,
            order: Self.makeOrder(status: .inProgress),
            volunteerCoordinate: Self.volunteerCoordinate,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains("已经在一起"), answer.speech)
        XCTAssertTrue(answer.speech.contains(RunOrderStatus.inProgress.displayName), answer.speech)
    }

    /// 坐标过期由调用方判（状态页有过期清理、首页自己判新鲜度），过期就传 nil。
    /// **传 nil 时绝不能念上一次的距离** —— 对听不见屏幕的人，旧距离就是假数据。
    func testStaleVolunteerCoordinateIsReportedAsUnavailableNotAsAnOldDistance() {
        let answer = VoiceStatusQuery.answer(
            intent: .distance,
            order: Self.makeOrder(status: .driverEnRoute),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains("暂时收不到志愿者位置"), answer.speech)
        XCTAssertFalse(answer.speech.contains("米"), "不许念出任何距离数字：\(answer.speech)")
        XCTAssertFalse(answer.speech.contains("公里"), "不许念出任何距离数字：\(answer.speech)")
    }

    func testDistanceIsSpokenWhenAFreshVolunteerCoordinateExists() {
        let order = Self.makeOrder(status: .driverEnRoute)
        let expected = order.volunteerDistanceToStartText(from: Self.volunteerCoordinate)
        XCTAssertNotNil(expected, "夹具本身要算得出距离，否则这条用例什么都没测")
        let answer = VoiceStatusQuery.answer(
            intent: .distance,
            order: order,
            volunteerCoordinate: Self.volunteerCoordinate,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertEqual(answer.speech, "志愿者\(expected ?? "")。")
        XCTAssertFalse(answer.speech.contains("整段状态"), "问距离就只念距离，不念整段")
    }

    // MARK: - 状态与时间地点

    func testStatusAnswerIsTheStatusNamePlusItsBlindRunnerDescription() {
        let answer = VoiceStatusQuery.answer(
            intent: .status,
            order: Self.makeOrder(status: .driverArrived),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertEqual(
            answer.speech,
            "\(RunOrderStatus.driverArrived.displayName)。\(RunOrderStatus.driverArrived.blindRunnerDescription)"
        )
    }

    func testScheduleAnswerCarriesBothTheTimeAndTheStartAddress() {
        let order = Self.makeOrder(status: .pendingAccept, plannedStart: "2026-08-09T08:30:00")
        let answer = VoiceStatusQuery.answer(
            intent: .schedule,
            order: order,
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains(order.plannedStartForAnnouncement ?? "<无>"), answer.speech)
        XCTAssertTrue(answer.speech.contains(order.startAddressForAnnouncement), answer.speech)
    }

    func testScheduleAnswerSaysTheTimeIsMissingRatherThanInventingOne() {
        let answer = VoiceStatusQuery.answer(
            intent: .schedule,
            order: Self.makeOrder(status: .pendingAccept, plannedStart: nil),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains("预约时间还没有记录"), answer.speech)
        XCTAssertTrue(answer.speech.contains("测试出发点"), answer.speech)
    }

    // MARK: - 拨号

    /// 语音路径复用与屏幕按钮相同的三个条件。这一组逐状态钉住「什么时候不许拨号」。
    func testDialingIsOnlyOfferedInTheSameStatusesAsTheOnScreenCallButton() {
        // `.unknown` 一并跑：它是后端加了本客户端不认识的状态时的落点，
        // 那一刻语音路径必须照样答得出话、且绝不拨号。
        for status in RunOrderStatus.allCases + [.unknown] {
            let answer = VoiceStatusQuery.answer(
                intent: .callVolunteer,
                order: Self.makeOrder(status: status),
                volunteerCoordinate: nil,
                fallbackAnnouncement: "整段状态"
            )
            if status.offersVolunteerCall {
                XCTAssertEqual(
                    answer.pendingAction,
                    .confirmDialVolunteer(phone: "13800000000"),
                    "\(status) 应该允许拨号"
                )
            } else if status == .pendingIntroCall {
                // 唯一的例外，而且是刻意的：这一态**确实有一通该打的电话**，
                // 只是号码走通话专用接口（`IntroCallEndpoint.view`）、不在 `volunteerPhone` 上，
                // 所以 `offersVolunteerCall` 判 false。通用那句「现在还不能打电话给志愿者」
                // 在这里是**错的** —— 能打，只是语音这条路暂时不接。
                // 对看不见屏幕的人，说「不能打」而不说去哪打就是死路，所以要求它指回屏幕。
                XCTAssertNil(answer.pendingAction, "语音不得替盲人拨通话磨合的号码")
                XCTAssertTrue(
                    answer.speech.contains("订单状态页"),
                    "要把人指回屏幕上那个按钮：\(answer.speech)"
                )
                XCTAssertTrue(
                    answer.speech.contains(status.displayName),
                    "\(status) 要带上当前状态：\(answer.speech)"
                )
            } else {
                XCTAssertNil(answer.pendingAction, "\(status) 不得拨号")
                XCTAssertTrue(
                    answer.speech.contains("现在还不能打电话给志愿者"),
                    "\(status) 要说清为什么不能打：\(answer.speech)"
                )
                XCTAssertTrue(
                    answer.speech.contains(status.displayName),
                    "\(status) 要带上当前状态：\(answer.speech)"
                )
            }
        }
    }

    func testDialingRecitesTheNumberDigitByDigitAndAsksForConfirmation() {
        let answer = VoiceStatusQuery.answer(
            intent: .callVolunteer,
            order: Self.makeOrder(status: .driverEnRoute),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertTrue(answer.speech.contains("1 3 8 0 0 0 0 0 0 0 0"), "号码要逐位念：\(answer.speech)")
        XCTAssertTrue(answer.speech.contains("确认"), "必须教用户怎么确认：\(answer.speech)")
        XCTAssertEqual(answer.pendingAction, .confirmDialVolunteer(phone: "13800000000"))
    }

    /// `OrderDetailResponse` 里没有 `volunteerName` 字段，复述只能说号码 —— 不许编姓名。
    func testMissingVolunteerPhoneRefusesToDialAndSaysWhy() {
        for phone in [nil, "", "   "] as [String?] {
            let answer = VoiceStatusQuery.answer(
                intent: .callVolunteer,
                order: Self.makeOrder(status: .driverArrived, volunteerPhone: phone),
                volunteerCoordinate: nil,
                fallbackAnnouncement: "整段状态"
            )
            XCTAssertNil(answer.pendingAction, "号码是 \(phone ?? "nil") 时不得拨号")
            XCTAssertTrue(answer.speech.contains("还没有拿到志愿者的电话号码"), answer.speech)
            XCTAssertTrue(answer.speech.contains(RunOrderStatus.driverArrived.displayName), answer.speech)
        }
    }

    /// 号码里一个数字都没有时 `EmergencyDialer.telURL` 会返回 nil，拨了也是「点了没反应」。
    func testUndialableNumberIsRefusedBeforeItBecomesASilentNoOp() {
        let answer = VoiceStatusQuery.answer(
            intent: .callVolunteer,
            order: Self.makeOrder(status: .inProgress, volunteerPhone: "暂无"),
            volunteerCoordinate: nil,
            fallbackAnnouncement: "整段状态"
        )
        XCTAssertNil(answer.pendingAction)
        XCTAssertTrue(answer.speech.contains("暂时不能拨号"), answer.speech)
    }

    // MARK: - 拨号确认

    /// 与下单确认同一张白名单：单音节应答词（好 / 行 / 对 / 是）**不算确认** ——
    /// 陪跑场景里旁边的人正好说了这几个字，就会拨出一通用户没打算打的电话。
    func testDialConfirmationUsesTheSameWhitelistAsOrderConfirmation() {
        for utterance in ["确认", "确认吧", "没问题", "就这样"] {
            XCTAssertTrue(VoiceStatusQuery.isDialConfirmed(utterance), "「\(utterance)」应视为确认")
        }
        for utterance in ["不用了", "算了", "好", "行", "对", "是", "不确认", ""] {
            XCTAssertFalse(VoiceStatusQuery.isDialConfirmed(utterance), "「\(utterance)」不得视为确认")
        }
    }

    /// 没确认时必须说出「没拨」这件事，静默收场等于让盲人不知道刚才发生了什么。
    func testDialCancellationCopySaysThatNothingWasDialed() {
        XCTAssertTrue(VoiceStatusQuery.dialCancelledSpeech.contains("取消"))
        XCTAssertTrue(VoiceStatusQuery.dialCancelledSpeech.contains("拨号"))
    }

    // MARK: - 边界：这一轮什么都没听到

    /// 没说话 ≠ 没听懂。空识别一律不回答，让 `SpeechInputService` 那句「未检测到声音」留在场上 ——
    /// 当成 `unrecognized` 去念整段，是拿一段 15~25 秒的播报回答一次没说出口的提问。
    func testSilentRoundIsNotAnsweredAtAll() {
        let silent = SpeechInputCompletion(
            field: .voiceStatusQuery,
            recognizedText: "",
            reason: .silenceTimeout(hadDetectedSound: false)
        )
        XCTAssertFalse(VoiceStatusQuery.shouldAnswer(silent))

        // 说了话但只有空白，同样不算说过话。
        XCTAssertFalse(VoiceStatusQuery.shouldAnswer(SpeechInputCompletion(
            field: .voiceStatusQuery,
            recognizedText: "   ",
            reason: .finalResult
        )))

        // 授权失败走 `.error`：那一轮 `startRecognition` 已经播过「麦克风不可用」，不再叠一层。
        XCTAssertFalse(VoiceStatusQuery.shouldAnswer(SpeechInputCompletion(
            field: .voiceStatusQuery,
            recognizedText: "",
            reason: .error
        )))

        // 正常说完的一轮当然要答。
        XCTAssertTrue(VoiceStatusQuery.shouldAnswer(SpeechInputCompletion(
            field: .voiceStatusQuery,
            recognizedText: "志愿者还有多远",
            reason: .finalResult
        )))
        // 用户说完自己按停也是一轮有效提问。
        XCTAssertTrue(VoiceStatusQuery.shouldAnswer(SpeechInputCompletion(
            field: .voiceStatusQuery,
            recognizedText: "几点开始",
            reason: .manual
        )))
    }

    // MARK: - 可问清单

    /// 清单是**教用户怎么问**的，所以里面每一句都必须真的能被判出意图。
    /// 两边任一处改词而另一处没跟，用户照着念就不生效。
    func testEveryExampleInTheHintActuallyMatchesAnIntent() {
        XCTAssertEqual(VoiceStatusQuery.classify("志愿者还有多远"), .distance)
        XCTAssertEqual(VoiceStatusQuery.classify("几点开始"), .schedule)
        XCTAssertEqual(VoiceStatusQuery.classify("打电话给志愿者"), .callVolunteer)
        for example in ["志愿者还有多远", "几点开始", "打电话给志愿者"] {
            XCTAssertTrue(
                VoiceStatusQuery.askableHint.contains(example),
                "清单里少了「\(example)」，与上面的断言对不上"
            )
        }
    }

    // MARK: - Fixtures

    /// 出发点与志愿者坐标分开，保证 `volunteerDistanceToStartText` 真的算得出一个数。
    private static let startCoordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    private static let volunteerCoordinate = CLLocationCoordinate2D(latitude: 31.2350, longitude: 121.4800)

    private static func makeOrder(
        status: RunOrderStatus,
        plannedStart: String? = "2026-08-09T08:30:00",
        volunteerPhone: String? = "13800000000"
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 7_001,
            status: status,
            startAddress: "测试出发点",
            startLatitude: startCoordinate.latitude,
            startLongitude: startCoordinate.longitude,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: volunteerPhone,
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
