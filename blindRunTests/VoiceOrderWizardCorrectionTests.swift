import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardCorrectionTests: XCTestCase, VoiceOrderWizardTestSupport {

    /// 用户点名要改哪一项但没给值：播后端的定向追问语，**`current` 一个字都不动**。
    ///
    /// 这一轮**不计入重问上限** —— 后端听懂了、用户也在正常推进，把「改三项」记成
    /// 「三次没听清」会在第三项上把人降级到表单。而 `correctionUnclear`（只说了「不对」）
    /// 确实是没听懂，要计数。两者刻意不同。
    func testCorrectionTargetAsksTheTargetedFollowUpAndDoesNotCountAsAReask() async {
        let stub = VoiceOrderAPIClientStub()
        let first = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 24), durationMinutes: 60,
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737
        )
        stub.parseOrderResponses = [
            first,
            Self.parseResponse(
                plannedStartTime: first.plannedStartTime, durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
                needReask: true,
                ttsText: "好的，请说新的开始时间，比如「明天早上八点」",
                correctionTarget: .startTime
            )
        ]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")
        await wizard.submitTranscript("我想改一下时间")

        XCTAssertEqual(wizard.step, .confirm, "定向追问不换步骤，屏幕不在用户说话中途变样")
        XCTAssertEqual(wizard.reaskCount, 0, "改一项是正常推进，不是没听清")
        XCTAssertEqual(
            wizard.lastSpokenPrompt, "好的，请说新的开始时间，比如「明天早上八点」",
            "定向追问语只有后端拼得出来（读回措辞规则在后端），这一句必须原样播"
        )
        XCTAssertEqual(
            stub.parseRequests[1].current?.address, "上海市黄浦区人民广场",
            "点名那一轮不许清 current，否则下一句只说值就没有可继承的东西了"
        )
    }

    /// 只说「不对」、没说改哪一项：播消歧问句，并且**计入**重问上限 —— 这一条确实是没听懂。
    func testCorrectionUnclearCountsTowardTheReaskLimit() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(ttsText: "您想改哪一项？出发地、开始时间，还是时长？", correctionUnclear: true)
        ]
        let wizard = makeWizard(stub: stub, startingAt: .confirm, didCaptureStartTime: true)

        await wizard.submitTranscript("不对")

        XCTAssertEqual(wizard.reaskCount, 1)
        XCTAssertEqual(wizard.lastSpokenPrompt, "您想改哪一项？出发地、开始时间，还是时长？")
        XCTAssertEqual(wizard.step, .confirm)
    }

    /// 🔴 后端说还缺槽位、而这一轮什么都没变时，**不许把同一段读回原样再念一遍**（后端 N97）。
    ///
    /// 这是用户 2026-08-18 报的那条：「不说『确认』这两个字好像就识别不出来，
    /// 只是单纯识别之后重复说一遍一样的内容。」形状是这样的 ——
    /// `userIntent` / `correctionTarget` / `correctionUnclear` 三个信号在 `missing` 非空时
    /// 会被后端**一起压掉**，于是这一轮落到最后那条「剩下的只有一种情况：用户给了新值」的兜底，
    /// `apply` 一份什么都没变的响应、`moveToConfirm` 重念读回。而 `moveToConfirm` 那道闸
    /// 只数「连续两轮没拿到开始时间」，缺的是别的槽位时一次都不触发 ⇒ 无限循环。
    /// 本地直通词表里那几个词能下单，只是因为**它们根本不发这个请求**。
    ///
    /// 正确行为：播后端那句追问（本地拼不出来）+ **计入重问上限**（有上限才有出口）。
    func testBackendStillWantsASlotSoWeAskInsteadOfRepeatingTheReadback() async {
        let stub = VoiceOrderAPIClientStub()
        // 第 1 轮把整单立起来，但时长没抽到 —— 后端据此恒报 missing:[DURATION]。
        let first = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 24),
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            missing: [.duration]
        )
        // 第 2 轮：用户说了「对」，后端因 missing 非空把三个信号全压成 null，槽位一个字没变。
        let second = Self.parseResponse(
            plannedStartTime: first.plannedStartTime,
            address: first.address, latitude: first.latitude, longitude: first.longitude,
            missing: [.duration],
            needReask: true,
            ttsText: "没听清时长，请再说一次，比如“一个小时”"
        )
        stub.parseOrderResponses = [first, second]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发")
        let readback = wizard.lastSpokenPrompt ?? ""
        await wizard.submitTranscript("对")

        XCTAssertEqual(
            wizard.lastSpokenPrompt, "没听清时长，请再说一次，比如“一个小时”",
            "后端已经说了缺什么，播它 —— 原样重念读回是那个死循环的入口"
        )
        XCTAssertNotEqual(wizard.lastSpokenPrompt, readback, "复读同一段读回就是用户报的那个症状")
        XCTAssertEqual(wizard.reaskCount, 1, "必须计入上限：有上限才有出口，走不通时会交回表单")
        XCTAssertEqual(wizard.step, .confirm)
        XCTAssertNil(wizard.createdOrder)
    }

    /// 反过来：用户**真给了新值**那一轮不许被上面那条截胡 —— 哪怕 `missing` 仍然非空。
    ///
    /// 判据是「槽位有没有真的变」而不是光看 `missing` 非空。终点落进去了就该照常读回，
    /// 用户听得出内容变了；把它也拦成追问，等于用户改了东西却听不到任何反馈。
    func testANewValueStillGetsReadBackEvenWhileASlotIsStillMissing() async {
        let stub = VoiceOrderAPIClientStub()
        let first = Self.parseResponse(
            plannedStartTime: Self.backendTime(hoursFromNow: 24),
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            missing: [.duration]
        )
        let second = Self.parseResponse(
            plannedStartTime: first.plannedStartTime,
            address: first.address, latitude: first.latitude, longitude: first.longitude,
            missing: [.duration],
            ttsText: "没听清时长，请再说一次",
            endAddress: "五角场 邯郸路", endLatitude: 31.2990, endLongitude: 121.5140
        )
        stub.parseOrderResponses = [first, second]
        // ⚠️ 必须持有一个活着的 view model：wizard 侧是 `weak`，临时对象等于传 nil，
        // 而 `confirmPrompt(for:)` 拿不到它就**退回只念出路那句**，整单一个字都不会念出来。
        // 这条用例断言的正是「整单里有没有五角场」，所以少了这一行它必然失败，
        // 而失败信息看起来像是终点没落进去（同文件 :2492 有同款注释）。
        let bookingViewModel = BlindBookingViewModel()
        let wizard = makeWizard(stub: stub, bookingViewModel: bookingViewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发")
        await wizard.submitTranscript("结束地点改成五角场")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("五角场"), "用户改的终点必须念出来，否则他不知道改没改上：\(spoken)")
        XCTAssertEqual(wizard.reaskCount, 0, "这一轮用户在正常推进，不是没听清")
    }

    /// 🔴 起点回落到当前位置时，`current` 要带上**读回已经念过的**那个起点（后端 N97 的另一半）。
    ///
    /// 不带的话后端每一轮都报 `missing:[ADDRESS]`，于是按「槽位没齐无从确认」把
    /// `userIntent` 和 `correctionTarget` 一起压成 null —— 用户说什么都拿不到信号。
    /// 而读回开头就念了「使用设备当前位置。出发地点：⋯⋯」，用户听到并认可了它，
    /// 此刻它就是一个已确认槽位，和「用户从没说过的时间」性质完全不同
    /// （那条红线由 `testCurrentNeverCarriesAnAppointmentTimeTheUserNeverSpoke` 继续守着）。
    func testCurrentCarriesTheStartPlaceTheReadbackAlreadyAnnounced() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            // 只抽到时间，起点没抽出来 —— 客户端本地回落当前位置并在读回里念出来。
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24),
                durationMinutes: 60,
                missing: [.address]
            ),
            Self.parseResponse(ttsText: "您想改哪一项？", correctionUnclear: true)
        ]
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场 人民大道185号",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点跑一个小时")
        await wizard.submitTranscript("不对")

        let current = stub.parseRequests[1].current
        XCTAssertEqual(current?.latitude, 31.2304, "读回念过的起点坐标必须回传，否则后端永远认为缺 ADDRESS")
        XCTAssertEqual(current?.longitude, 121.4737)
        XCTAssertNotNil(current?.address?.nilIfBlank, "坐标和地址整组一起带，绝不拆开")
        XCTAssertEqual(current?.durationMinutes, 60, "补起点不该动其余槽位")
    }

    /// 🚨 反过来：用户说了一个**高德查不到的地名**时，绝不许拿当前位置把它顶掉。
    ///
    /// 那是「把人约到错误的起点」—— 用户说的是「从老王家门口出发」，静默换成设备当前位置，
    /// 而读回念的还是当前位置，他全程听不出来。这一路照旧让后端继续报 `missing:[ADDRESS]` 并追问。
    func testUnresolvableSpokenPlaceIsNeverOverwrittenByTheDeviceLocation() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            // 有地名、没坐标 = 用户说了但高德查不到。
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24),
                durationMinutes: 60,
                address: "老王家门口",
                missing: [.address],
                addressUnresolved: true
            ),
            // ⚠️ 追问轮的响应**不是空壳**。后端无状态，靠 `current` 把上一轮的槽位带回去，
            // 再把合并后的整单原样返回 —— 时间、时长、以及那个查不到坐标的地名都还在，
            // 变的只有 `missing` 与 `ttsText`。
            //
            // 写成空壳的话 `parsed.slotSnapshot != sentSnapshot`，确认轮会判成「用户给了新值」
            // 而落到兜底去复读读回 —— 那正是 N97 那个症状，于是这条用例测出来的是
            // 一个**它自己造出来的**假场景，而不是线上会发生的事。
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24),
                durationMinutes: 60,
                address: "老王家门口",
                missing: [.address],
                ttsText: "没找到“老王家门口”，请换个说法再说一次出发地点",
                addressUnresolved: true
            )
        ]
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场 人民大道185号",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        let wizard = makeWizard(stub: stub, bookingViewModel: viewModel, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从老王家门口出发跑一个小时")
        await wizard.submitTranscript("对")

        let current = stub.parseRequests[1].current
        XCTAssertEqual(current?.address, "老王家门口", "用户说的地名不许被当前位置顶掉")
        XCTAssertNil(current?.latitude, "查不到就是没坐标，别拿别处的坐标凑一组")
        XCTAssertEqual(
            wizard.lastSpokenPrompt, "没找到“老王家门口”，请换个说法再说一次出发地点",
            "这一路的出口是后端那句追问，不是复读读回"
        )
    }

    /// 后端往这两个枚举加值时**不许整条响应解不出来**。语音是盲人唯一的下单通道，
    /// 「点了没反应」在这条链路上就是事故（与 `RunOrderStatus` / `VoiceOrderMissingSlot` 同一条红线）。
    func testUnknownIntentAndCorrectionTargetValuesDecodeInsteadOfThrowing() throws {
        let json = """
        {"missing":[],"needReask":true,"ttsText":"好的",
         "userIntent":"POSTPONE","correctionTarget":"WEATHER","correctionUnclear":false}
        """
        let decoded = try JSONDecoder().decode(ParseVoiceOrderResponse.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.userIntent, .unknown)
        XCTAssertEqual(decoded.correctionTarget, .unknown)
    }

    /// 快照的构造口径：允许「有地址无坐标」（高德查不到时后端就是这么返回的，把它按旧的严格规则
    /// 校会把用户卡死在一个他自己解不开的循环里），但**反过来一律丢弃** —— 只有坐标没有文字地址
    /// 后端返 400，而那是客户端 bug，不是该在运行时发出去试试看的东西。
    func testSnapshotAllowsAnAddressWithoutCoordinatesButNeverTheReverse() {
        let unresolvedEnd = Self.parseResponse(
            address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737,
            endAddress: "老王家门口"
        ).slotSnapshot
        XCTAssertEqual(unresolvedEnd.endAddress, "老王家门口")
        XCTAssertNil(unresolvedEnd.endLatitude)

        let coordinatesOnly = Self.parseResponse(latitude: 31.2304, longitude: 121.4737).slotSnapshot
        XCTAssertNil(coordinatesOnly.address)
        XCTAssertNil(coordinatesOnly.latitude, "只有坐标没有地名一律整组丢弃")
        XCTAssertNil(coordinatesOnly.longitude)
    }

    /// 读回结尾必须**教用户可以只改一项**。看不见屏幕的人不会自己发现这个能力，
    /// 不教就等于没做 —— 这与「白名单必须和系统教用户说的话一致」是同一条规矩的另一半。
    func testConfirmOutroTeachesThatASingleItemCanBeChanged() async {
        let stub = VoiceOrderAPIClientStub()
        stub.parseOrderResponses = [
            Self.parseResponse(
                plannedStartTime: Self.backendTime(hoursFromNow: 24), durationMinutes: 60,
                address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737
            )
        ]
        let wizard = makeWizard(stub: stub, startingAt: .freeform)

        await wizard.submitTranscript("明天早上八点从人民广场出发跑一个小时")

        let spoken = wizard.lastSpokenPrompt ?? ""
        XCTAssertTrue(spoken.contains("确认"), "读回教的词必须在本地白名单里：\(spoken)")
        XCTAssertTrue(spoken.contains("重说"), "整句重说仍然是一条出路：\(spoken)")
        XCTAssertTrue(spoken.contains("要改哪一项直接说"), "定点修改必须被念出来：\(spoken)")
    }
}
