import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardGoldenCorpusTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 逐项修改已删除（2026-08-06）
    //
    // 原来这里有四条用例覆盖「改地点 / 改时间 / 改时长」那条逐项流程：needReask 不推进、
    // 连续三次听不清降级、解析结果回填、取整要念出来。逐项修改随 `.restart` 一起删掉之后，
    // 它们测的代码已经不存在。等价保障都在整句轮那几条上：
    //   · 回填 → testFreeformUtteranceFillsAllThreeSlotsInASingleRequest
    //   · 取整播报 → testFreeformAnnouncesDurationRounding
    //   · 连续失败降级 → testRepeatedSilenceEventuallyFallsBackToTheForm
    //   · needReask 不当错误 → testFreeformTreatsMissingSlotsAsDefaultsAndNeverReasks

    /// 语音说多少就是多少，只在超出契约区间（10–300）时夹到边界。
    ///
    /// 原来是「就近 snap 到 6 个枚举档位」，于是「跑三个小时」变成两小时 ——
    /// 枚举存在的理由是选择器需要有限选项，而说话的人不需要选择器。
    func testSpokenDurationIsTakenLiterallyAndOnlyClampedToTheContractRange() {
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(180), 180, "三个小时不该被砍成两小时")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(40), 40, "40 分钟不该被抬到 45")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(300), 300)
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(400), 300, "超出契约上限夹到 300")
        XCTAssertEqual(VoiceOrderWizard.acceptedDurationMinutes(5), 10, "低于契约下限夹到 10")
    }

    /// 时长文案按精确分钟数生成，不套枚举档位名。
    func testDurationTextReadsTheExactMinutes() {
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 180), "3 小时")
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 150), "2 小时 30 分钟")
        XCTAssertEqual(BlindBookingViewModel.durationText(forMinutes: 40), "40 分钟")
    }

    // MARK: - 与后端黄金语料对齐

    // 后端 `demo/docs/voice-golden-corpus.json` 的 iOS 侧镜像，**五族 115 条全覆盖**。
    //
    // 锁的是 **Mock 不许比真实解析器松或紧**：Mock 认得的说法真机上也要认得，Mock 认不得的
    // （语料里 `source: "llm"` 那几条）在开发期就该走到 `needReask` 分支，否则向导的重问路径
    // 永远没被走过，上真机才发现是死的。
    //
    // 镜像清单本身在 `VoiceGoldenCorpusMirror.swift`（2026-10-28 挪出，#528），
    // `scripts/validate-golden-corpus.mjs` 读的是那个文件；这里只放断言。

    /// 语料的时间基准。START_TIME 的期望值全是相对它算出的绝对时间戳，
    /// 不钉住基准就验不出「过去的钟点滚次日」这条规则。
    private static let corpusNow = "2026-07-24T10:00:00"

    private func withCorpusClock(_ body: () -> Void) {
        MockAPIClient.voiceClockForTesting = DateFormatter.aidRunBackendLocalDateTime.date(from: Self.corpusNow)
        defer { MockAPIClient.voiceClockForTesting = nil }
        body()
    }

    func testMockDurationParsingMatchesTheBackendGoldenCorpus() {
        // 镜像清单在 `VoiceGoldenCorpusMirror.durationRegex`（DURATION regex）。
        let regexCases = VoiceGoldenCorpusMirror.durationRegex

        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceMinutes(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected) 分钟"
            )
        }

        // 镜像清单在 `VoiceGoldenCorpusMirror.durationLlm`（DURATION llm）。
        for transcript in VoiceGoldenCorpusMirror.durationLlm {
            XCTAssertNil(
                MockAPIClient.mockVoiceMinutes(in: transcript),
                "「\(transcript)」在 Mock 里不该被解析出数值"
            )
        }
    }

    /// START_TIME 13 条。这一族是 2026-08-06 才补上镜像的 —— 补之前 Mock 只认 5 个钟点、
    /// 落点恒定是「明天」，10 条 regex 只对得上 3 条：说「今天八点半」被念成明天，
    /// 说「下午三点」「半小时后」直接走重问，而线上这三种都解得出。
    func testMockStartTimeParsingMatchesTheBackendGoldenCorpus() {
        withCorpusClock {
            // 镜像清单在 `VoiceGoldenCorpusMirror.startTimeRegex`（START_TIME regex）。
            let regexCases = VoiceGoldenCorpusMirror.startTimeRegex
            for testCase in regexCases {
                let parsed = MockAPIClient.mockVoiceStartTime(in: testCase.transcript)
                XCTAssertEqual(
                    parsed.map(MockAPIClient.mockBackendLocalDateTime),
                    testCase.expected,
                    "Mock 与黄金语料漂移：「\(testCase.transcript)」（now=\(Self.corpusNow)）应为 \(testCase.expected)"
                )
            }

            // 镜像清单在 `VoiceGoldenCorpusMirror.startTimeLlm`（START_TIME llm）。
            for transcript in VoiceGoldenCorpusMirror.startTimeLlm {
                XCTAssertNil(
                    MockAPIClient.mockVoiceStartTime(in: transcript),
                    "「\(transcript)」在 Mock 里不该被解析出时间"
                )
            }

            // 镜像清单在 `VoiceGoldenCorpusMirror.startTimeNone`（START_TIME none）。
            for transcript in VoiceGoldenCorpusMirror.startTimeNone {
                XCTAssertNil(
                    MockAPIClient.mockVoiceStartTime(in: transcript),
                    "「\(transcript)」里没有时间表达，不该被解析出时刻"
                )
            }
        }
    }

    /// 「八点半」滚次日这条规则单独再锁一次 —— 它是这一族里唯一**依赖 now** 的行为，
    /// 上面那张表只要基准写错就会整体失效，而这条会指名道姓地失败。
    func testAClockTimeAlreadyPastTodayRollsToTomorrowUnlessTodayIsSpoken() {
        withCorpusClock {
            let rolled = MockAPIClient.mockVoiceStartTime(in: "八点半")
            XCTAssertEqual(
                rolled.map(MockAPIClient.mockBackendLocalDateTime), "2026-07-25T08:30:00",
                "now=10:00 时「八点半」必须滚到次日：返回今天 08:30 会被提前量校验判成「太近了」，"
                    + "而用户压根没打算约今天"
            )
            XCTAssertEqual(
                MockAPIClient.mockVoiceStartTime(in: "今天八点半").map(MockAPIClient.mockBackendLocalDateTime),
                "2026-07-24T08:30:00",
                "显式说了「今天」就不该滚 —— 那是用户的明确选择，该由提前量校验去拒绝"
            )
        }
    }

    /// 语料之外的两处回归（2026-10-02 #294 审查）。都是「说了 X，读回念成别的」的静默错读：
    /// 1. 「明早/明晚」是日期词，紧挨数字的「早/晚」不能当程度副词（「早一点」「晚一点」）拦掉 ——
    ///    否则「明晚十一点」缩到末位读成 1 点再 +12 = 13:00，「明晚八点」则整句认输。
    ///    守卫本身（「慢1点」「晚一点跑」不造出时刻）由上面的 none 清单继续钉着。
    /// 2. 「两个半钟头」归一成「两个半小时」后不能落进「半小时」→ 30，要读成 150。
    func testDateWordPrefixDoesNotTripTheDegreeGuardAndNHalfHoursKeepsTheIntegerPart() {
        withCorpusClock {
            let cases: [(transcript: String, expected: String)] = [
                ("明晚十一点", "2026-07-25T23:00:00"),
                ("明早十一点", "2026-07-25T11:00:00"),
                ("明晚八点", "2026-07-25T20:00:00"),
                ("明早八点半", "2026-07-25T08:30:00"),
                ("明晚八点一刻", "2026-07-25T20:15:00")
            ]
            for testCase in cases {
                XCTAssertEqual(
                    MockAPIClient.mockVoiceStartTime(in: testCase.transcript).map(MockAPIClient.mockBackendLocalDateTime),
                    testCase.expected,
                    "「\(testCase.transcript)」（now=\(Self.corpusNow)）应为 \(testCase.expected)"
                )
            }
            // 没有日期词时守卫照旧：「晚一点跑」的「一点」不许被放行成 1 点。
            XCTAssertNil(MockAPIClient.mockVoiceStartTime(in: "晚一点跑"))
        }
        XCTAssertEqual(MockAPIClient.mockVoiceMinutes(in: "跑两个半钟头"), 150)
        XCTAssertEqual(MockAPIClient.mockVoiceMinutes(in: "跑3个半小时"), 210)
        XCTAssertEqual(MockAPIClient.mockVoiceMinutes(in: "跑半个钟头"), 30)
    }

    /// #297：语料没覆盖、但后端有明确行为的三类形状。共同根因是 Mock 把同一份词表 / 判据手抄了多份、
    /// 数字又只读一半 —— 每一类都挑**一个落在两种实现之间的取值**（旧实现读出另一个值，而不是只多一次追问）。
    func testMockStaysAlignedWithTheBackendOnShapesTheCorpusDoesNotCover() {
        // ① 日期词表同源：地址 span 的「像时间」判据要和解析处认同一批日期词。
        //    「明早」在后端 TIME_LIKE 里，Mock 漏了 → 「明早」被当地名送去地理编码。
        XCTAssertNil(MockAPIClient.mockVoiceAddressSpan(in: "从明早出发跑一个小时"))
        XCTAssertNil(MockAPIClient.mockVoiceAddressSpan(in: "从明晚出发跑一个小时"))
        XCTAssertEqual(MockAPIClient.mockVoiceAddressSpan(in: "从人民广场出发跑一个小时"), "人民广场")

        // ② 时长按后端的模式顺序解析：小时后面紧跟的分钟 / 半不能丢。
        let durations: [(String, Int)] = [
            ("跑两小时三十分钟", 150), ("跑1小时30分钟", 90), ("跑一小时十分钟", 70),
            ("跑一小时半", 90), ("跑两个小时半", 150), ("跑两个半小时", 150),
            // 「零五」= 5；三位数分钟后端 `\d{1,2}` 不并（退回只算小时）。
            ("跑一小时零五分钟", 65), ("跑一小时100分钟", 60),
            // 同句两个时长：取最左的（后端正则最左匹配），不是按后缀列表顺序先试「个小时」。
            ("跑两小时，不对，三个小时", 120), ("跑一小时，不对，两个小时", 60)
        ]
        for (transcript, expected) in durations {
            XCTAssertEqual(MockAPIClient.mockVoiceMinutes(in: transcript), expected, "「\(transcript)」")
        }

        withCorpusClock {
            // ②' 「半小时后」前面有「个」或数字时那个「半」属于「N个半」，不是 30 分钟后。
            //    后端对「一个半小时后」返回 empty（走兜底），Mock 照样不认，而不是读成 30 分钟后。
            XCTAssertNil(MockAPIClient.mockVoiceStartTime(in: "一个半小时后"))
            XCTAssertNil(MockAPIClient.mockVoiceStartTime(in: "两个半小时后"))
            XCTAssertEqual(
                MockAPIClient.mockVoiceStartTime(in: "半小时后").map(MockAPIClient.mockBackendLocalDateTime),
                "2026-07-24T10:30:00"
            )

            // ③ 守卫拒绝的是整个数，不是缩到末位再读：「十一」被拒后不许退成「一」。
            //    后端不认「今晚/今早」（不在日期词里，「晚/早」按程度副词挡掉）→ empty；
            //    Mock 只对齐成同样的拒绝，真正支持它是后端功能。
            for transcript in ["今晚十一点", "今晚11点", "今早十一点", "今晚八点", "晚十一点"] {
                XCTAssertNil(
                    MockAPIClient.mockVoiceStartTime(in: transcript),
                    "「\(transcript)」后端不认，Mock 不许读成别的钟点"
                )
            }
            // 「明晚」的 +12 看的是原话里有没有这个词，不是第一个命中的日期词：
            // 「不是明天，是明晚八点」先命中「明天」，按后者判会丢 +12 读成 08:00（差 12 小时）。
            XCTAssertEqual(
                MockAPIClient.mockVoiceStartTime(in: "不是明天，是明晚八点").map(MockAPIClient.mockBackendLocalDateTime),
                "2026-07-25T20:00:00"
            )
            // 日期词表里的「明早 / 明晚」不受影响（上一个用例已钉 十一/八/八点半/一刻）。
            XCTAssertEqual(
                MockAPIClient.mockVoiceStartTime(in: "明晚十二点").map(MockAPIClient.mockBackendLocalDateTime),
                "2026-07-25T12:00:00"
            )
        }
    }

    /// ADDRESS 9 条。语料只断言**剥壳抽取**，不断言地理编码结果（语料 `_address_note`）：
    /// 抽出「五角场」而 Mock 的地点表里查不到坐标，正是线上「抽到 span 但正向编码失败」的同形场景。
    func testMockAddressSpanExtractionMatchesTheBackendGoldenCorpus() {
        // 镜像清单在 `VoiceGoldenCorpusMirror.addressRegex`（ADDRESS regex）。
        let regexCases = VoiceGoldenCorpusMirror.addressRegex
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceAddressSpan(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应抽出「\(testCase.expected)」"
            )
        }

        // 镜像清单在 `VoiceGoldenCorpusMirror.addressLlm`（ADDRESS llm）。
        for transcript in VoiceGoldenCorpusMirror.addressLlm {
            XCTAssertNil(
                MockAPIClient.mockVoiceAddressSpan(in: transcript),
                "「\(transcript)」不该被抽出地名"
            )
        }
    }

    /// GUIDE_DOG 6 条。`nil`（没提）与 `false`（明确不带）必须分得开 ——
    /// 这个字段进派单硬过滤，混淆会让登记了导盲犬的用户被静默按「不带」派单。
    func testMockGuideDogExtractionMatchesTheBackendGoldenCorpus() {
        // 镜像清单在 `VoiceGoldenCorpusMirror.guideDogRegex`（GUIDE_DOG regex）。
        let regexCases = VoiceGoldenCorpusMirror.guideDogRegex
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoiceGuideDog(in: testCase.transcript),
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected)"
            )
        }

        // 后两条是 🔴 **正反问句**（语料 `_guide_dog_question_note`，后端 N43）：
        // 用户在**点名要改这一项**，不是在答，所以和「压根没提」一样必须是 nil。
        //
        // 它同时长得像肯定和否定（「带不带导盲犬」里既有「不带导盲犬」也有「带…导盲犬」），
        // 所以**只挡一边没用** —— 后端实测给否定加前置守卫之后，肯定那条立刻从第二个「带」字
        // 重新匹配上，值从 false 翻成 true，一样是凭空造的。必须整句先判问句、命中即返回 nil。
        //
        // 这不是边角情况：语音的定点修改会**主动引导用户说出这类句子**
        // （`correctionTarget = GUIDE_DOG` 的定向追问）。
        // 镜像清单在 `VoiceGoldenCorpusMirror.guideDogNone`（GUIDE_DOG none）。
        for transcript in VoiceGoldenCorpusMirror.guideDogNone {
            XCTAssertNil(
                MockAPIClient.mockVoiceGuideDog(in: transcript),
                "「\(transcript)」不是在答带不带导盲犬，必须是 nil 而不是 false —— nil 才会回落档案默认值"
            )
        }
    }

    /// PACE 8 条。
    func testMockPaceExtractionMatchesTheBackendGoldenCorpus() {
        // 镜像清单在 `VoiceGoldenCorpusMirror.paceRegex`（PACE regex）。
        let regexCases = VoiceGoldenCorpusMirror.paceRegex
        for testCase in regexCases {
            XCTAssertEqual(
                MockAPIClient.mockVoicePace(in: testCase.transcript)?.rawValue,
                testCase.expected,
                "Mock 与黄金语料漂移：「\(testCase.transcript)」应为 \(testCase.expected)"
            )
        }

        // 镜像清单在 `VoiceGoldenCorpusMirror.paceNone`（PACE none）。
        for transcript in VoiceGoldenCorpusMirror.paceNone {
            XCTAssertNil(
                MockAPIClient.mockVoicePace(in: transcript),
                "「\(transcript)」没提配速，必须是 nil"
            )
        }
    }

    /// 语料里的每个真实时长都必须**原样保留**。
    ///
    /// 原来这条验的是「取整落点不荒唐（偏差不超过 30 分钟）」—— 那是取整还存在时的将就写法。
    /// 取整删掉之后，正确的断言是零偏差：语料里没有一条超出契约区间，所以一条都不该被改动。
    func testEveryCorpusDurationSurvivesUnchanged() {
        for minutes in [20, 30, 40, 60, 80, 90, 120] {
            XCTAssertEqual(
                VoiceOrderWizard.acceptedDurationMinutes(minutes), minutes,
                "\(minutes) 分钟被改动了 —— 语料里的时长全在 10~300 内，不该有任何夹取"
            )
        }
    }
}
