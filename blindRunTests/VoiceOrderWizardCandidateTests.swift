import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardCandidateTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 起点候选消歧（N48）

    /// 序数判定全在本地，不发一个字节。这几条就是它的全部契约。
    func testOrdinalIndexRecognisesSpokenOrdinals() {
        XCTAssertEqual(VoiceOrderWizard.ordinalIndex(in: "第一个", count: 3), 0)
        XCTAssertEqual(VoiceOrderWizard.ordinalIndex(in: "第二个", count: 3), 1)
        XCTAssertEqual(
            VoiceOrderWizard.ordinalIndex(in: "第三个吧", count: 3), 2,
            "句尾语气词要被 normalizedCommand 剥掉"
        )
        XCTAssertEqual(
            VoiceOrderWizard.ordinalIndex(in: "第2个", count: 3), 1,
            "识别器在不同 iOS 版本上可能吐阿拉伯数字"
        )
        XCTAssertNil(VoiceOrderWizard.ordinalIndex(in: "确认", count: 3))
        XCTAssertNil(VoiceOrderWizard.ordinalIndex(in: "", count: 3))
    }

    /// `count` 是护栏：只念了 2 个就不许认「第三个」—— 那是让用户挑一个不存在的地点。
    func testOrdinalIndexRejectsOrdinalBeyondCandidateCount() {
        XCTAssertNil(VoiceOrderWizard.ordinalIndex(in: "第三个", count: 2))
        XCTAssertEqual(VoiceOrderWizard.ordinalIndex(in: "第二个", count: 2), 1)
    }

    /// 存进订单的地址要和后端平铺 `address` 同一形态（POI 名 + 街道地址）。
    /// 形态不一致的话，下游按空格切 POI 名的 `spokenAddress` 会切错。
    func testCandidateReadbackAddressMirrorsBackendShape() {
        XCTAssertEqual(Self.candidate("五角场", address: "邯郸路").readbackAddress, "五角场 邯郸路")
        XCTAssertEqual(Self.candidate("五角场").readbackAddress, "五角场")
        XCTAssertEqual(
            Self.candidate("邯郸路1号", address: "邯郸路1号").readbackAddress, "邯郸路1号",
            "名称里已经含街道时不要拼两遍"
        )
    }

    /// 只有一个候选不该把人拉进消歧轮 ——「只有一个结果还问你选哪个」是纯粹的多一轮。
    func testSingleCandidateDoesNotTriggerDisambiguation() {
        let response = Self.parseResponse(candidates: [Self.candidate("阳光棕榈园")])
        XCTAssertNil(response.startCandidatesToDisambiguate)
    }

    /// 端到端：三个候选 → 进消歧轮并念后端文案 → 说「第二个」→ 起点落到第二条 → 回读回轮。
    func testMultipleCandidatesEnterDisambiguationThenSecondIsApplied() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 20),
            durationMinutes: 60,
            address: "阳光棕榈园",
            latitude: 22.5333,
            longitude: 113.9300,
            needReask: true,
            ttsText: "找到3个地点，请说第几个。第一个，阳光棕榈园，南山区，距您400米。",
            candidates: [
                Self.candidate("阳光棕榈园"),
                Self.candidate("阳光棕榈园北门", latitude: 22.5400, longitude: 113.9350),
                Self.candidate("阳光棕榈园东区", latitude: 22.5310, longitude: 113.9280)
            ]
        )]
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel)

        await wizard.submitTranscript("明天早上八点从阳光棕榈园出发跑一个小时")

        guard case .disambiguateStart(let candidates, _) = wizard.step else {
            return XCTFail("三个候选没有进消歧轮，step=\(wizard.step)")
        }
        XCTAssertEqual(candidates.count, 3)
        XCTAssertTrue(
            (wizard.lastSpokenPrompt ?? "").contains("请说第几个"),
            "候选列表只有后端拼得出，必须念它的 ttsText：\(wizard.lastSpokenPrompt ?? "")"
        )

        await wizard.submitTranscript("第二个")

        XCTAssertEqual(wizard.step, .confirm, "挑完就该回读回轮")
        XCTAssertEqual(bookingViewModel.resolvedStartPlace?.title, "阳光棕榈园北门")
        XCTAssertEqual(bookingViewModel.resolvedStartPlace?.latitude, 22.5400)
    }

    /// 🔴 挑完必须换掉快照。
    ///
    /// 不换的话确认轮把旧 `current` 发回后端，起点被继承成**第一条**，读回念的又变回最佳猜测 ——
    /// 用户刚挑的那一下白挑了，而且没有任何提示。
    func testChosenCandidateReplacesSnapshotSentBackAsCurrent() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 20),
                durationMinutes: 60,
                address: "阳光棕榈园",
                latitude: 22.5333,
                longitude: 113.9300,
                candidates: [
                    Self.candidate("阳光棕榈园"),
                    Self.candidate("阳光棕榈园北门", latitude: 22.5400, longitude: 113.9350)
                ]
            ),
            // 确认轮那一次 /parse 的回包，内容不重要，这条用例只看请求里带了什么
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 20),
                durationMinutes: 60,
                address: "阳光棕榈园北门",
                latitude: 22.5400,
                longitude: 113.9350
            )
        ]
        let wizard = makeWizard(stub: stub)

        await wizard.submitTranscript("明天早上八点从阳光棕榈园出发跑一个小时")
        await wizard.submitTranscript("第二个")
        // 一句本地表接不住的话，确认轮才会真的发请求
        await wizard.submitTranscript("这样就挺好的麻烦你了")

        XCTAssertEqual(stub.parseRequests.count, 2, "确认轮应该发了第二次 /parse")
        XCTAssertEqual(
            stub.parseRequests.last?.current?.address, "阳光棕榈园北门",
            "回传的 current 还是最佳猜测，用户挑的那一下被丢了"
        )
        XCTAssertEqual(stub.parseRequests.last?.current?.latitude, 22.5400)
    }

    /// 三次挑不出来**不把人丢回表单**（那是其余轮次的降级方式）：手上已经有可用的最佳猜测，
    /// 读回会念出来、用户仍可以说「重说」。但**必须说出「按第一个来」** ——
    /// 静默取第一条正是这轮改动要消灭的那个失败。
    func testThreeFailedPicksFallBackToFirstCandidateOutLoud() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 20),
            durationMinutes: 60,
            address: "阳光棕榈园",
            latitude: 22.5333,
            longitude: 113.9300,
            candidates: [Self.candidate("阳光棕榈园"), Self.candidate("阳光棕榈园北门")]
        )]
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel)

        await wizard.submitTranscript("明天早上八点从阳光棕榈园出发跑一个小时")
        for _ in 0..<VoiceOrderWizard.maximumReasksPerSlot {
            await wizard.submitTranscript("嗯这个那个")
        }

        XCTAssertEqual(wizard.step, .confirm, "不该丢回表单")
        XCTAssertNil(wizard.fallbackMessage)
        XCTAssertEqual(bookingViewModel.resolvedStartPlace?.title, "阳光棕榈园")
        XCTAssertTrue(
            (wizard.lastSpokenPrompt ?? "").contains(VoiceOrderWizard.pickedFirstCandidateNotice),
            "替用户挑了却没说，那就是静默取第一条：\(wizard.lastSpokenPrompt ?? "")"
        )
    }

    /// 消歧轮里「重说」必须能退出去 —— 被一批他听不明白的候选卡住时那是唯一出路。
    func testRestartWordExitsDisambiguation() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 20),
            durationMinutes: 60,
            address: "阳光棕榈园",
            latitude: 22.5333,
            longitude: 113.9300,
            candidates: [Self.candidate("阳光棕榈园"), Self.candidate("阳光棕榈园北门")]
        )]
        let wizard = makeWizard(stub: stub)

        await wizard.submitTranscript("明天早上八点从阳光棕榈园出发跑一个小时")
        await wizard.submitTranscript("重说")

        XCTAssertEqual(wizard.step, .freeform)
    }

    /// 说了地名但没查到时，读回前必须先说出来。
    ///
    /// 不说的话读回念的是「当前位置」，而用户明明说了一个地名 —— 静默落回就是把人约到错误的起点，
    /// 他全程听不出来。后端 2026-08-10 起不再拿全国范围的正向编码兜底，这条会变常见。
    func testUnresolvedStartAddressIsAnnouncedBeforeReadback() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 20),
            durationMinutes: 60,
            address: "老王家门口",
            missing: [.address],
            needReask: true,
            addressUnresolved: true
        )]
        // 必须持有一个活着的 view model：wizard 侧是 weak，临时对象等于传 nil，
        // 而 `confirmPrompt(for:)` 拿不到它就退回只念出路那句，读回整段根本不会拼出来
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel)

        await wizard.submitTranscript("明天早上八点从老王家门口出发跑一个小时")

        XCTAssertEqual(wizard.step, .confirm)
        XCTAssertTrue(
            (wizard.lastSpokenPrompt ?? "").contains(VoiceOrderWizard.unresolvedStartNotice(hasFallback: false)), // 没定位（#558）
            "听见了地名却没查到，读回却只字未提：\(wizard.lastSpokenPrompt ?? "")"
        )
    }

    // MARK: - 坐标送得上去吗（N48 的根因）

    /// 🔴 **N48 的根因回归。** 站着不动 60 秒之后，语音下单的请求里**还有没有坐标**。
    ///
    /// 用户真机报的是「定位开着，在深圳说的地名却定位到海南」。链路上不是定位坏了 ——
    /// 预约页要的（`requestsLocationUpdates(.blindBooking)`）是**持续**定位，而非陪跑模式下 `distanceFilter = 10`，
    /// 站着不动 Core Location 就不推新样本；语音下单恰恰是站着说完一整句，说完常已超过
    /// `latestBackendSample` 默认的 15 秒新鲜度门 ⇒ 闭包返回 nil ⇒ 请求不带坐标 ⇒
    /// 后端只能做全国范围解析。
    ///
    /// 两侧都断言，这条用例才说得清 bug 是什么：默认门会丢掉坐标，放宽后的门不会。
    /// 只断言「放宽后能拿到」的话，有人把 `freshness: 300` 顺手清理回默认值也不会红。
    func testAStaleDeviceSampleStillReachesTheParseRequest() async {
        let locationService = LocationService()
        locationService.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 22.5333, longitude: 113.9300),
            capturedAt: Date().addingTimeInterval(-60)
        )

        // 默认 15 秒门：这就是 N48 里坐标消失的那一步。
        XCTAssertNil(
            locationService.latestBackendSample(),
            "60 秒前的样本本来就该被默认门拒掉 —— 这条用例的前提没了，下面两条断言就不成立"
        )
        XCTAssertNotNil(
            locationService.latestBackendSample(freshness: 300),
            "放宽后的门必须放行，否则语音下单又回到「没有坐标」"
        )

        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse()]
        let wizard = makeWizard(
            stub: stub,
            // 与 `BlindBookingView` 里那一处逐字相同 —— 测的是那个调用点，不是一个理想化的闭包。
            currentCoordinate: { locationService.latestBackendSample(freshness: 300) }
        )

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertEqual(stub.parseRequests.count, 1)
        XCTAssertNotNil(
            stub.parseRequests[0].latitude,
            "站了一分钟就把坐标丢了，后端只能做全国范围解析 —— 这正是把人约到海南的那一步"
        )
        XCTAssertNotNil(stub.parseRequests[0].longitude)
    }

    /// 坐标必须**成对**送，且只送后端坐标系的真实采样。
    ///
    /// 只送一半后端返 400；而演示坐标混进来会把人约到另一座城市 —— 后者由
    /// `LocatedCoordinate.system` 挡着，Demo / UI 测试的定位路径压根产不出设备采样。
    func testNoCoordinateIsSentWhenThereIsNoRealDeviceSample() async {
        let locationService = LocationService()
        // 真机上 Core Location 几毫秒就回调，裸 `LocationService()` 的「无定位」活不过一次 runloop。
        locationService.simulateMissingDeviceLocationForTesting()

        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [Self.parseResponse()]
        let wizard = makeWizard(
            stub: stub,
            currentCoordinate: { locationService.latestBackendSample(freshness: 300) }
        )

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        XCTAssertNil(stub.parseRequests[0].latitude, "没有真实采样就一个坐标都不许编")
        XCTAssertNil(stub.parseRequests[0].longitude)
    }
}
