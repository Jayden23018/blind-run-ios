import CoreLocation
import Foundation

extension VoiceOrderWizard {
    // MARK: Disambiguate start place

    /// 进候选消歧轮。`prompt` 用后端的 `ttsText`（候选的名称/行政区/距离只有它知道），
    /// 缺了才本地兜一句 —— 兜底那句念不出距离，是降级不是等价物。
    func moveToDisambiguation(_ candidates: [AddressCandidate], prompt: String?, notice: String?) {
        reaskCount = 0
        // 时长夹取之类的提示**不在这一轮说**，留到读回：候选已经占满了纯听觉能记住的约 3 项，
        // 再往前面塞一句会把序数挤出记忆。挑完由 `moveToConfirm` 原样带出去。
        pendingNotice = notice
        step = .disambiguateStart(
            candidates: candidates,
            prompt: prompt?.nilIfBlank ?? Self.localCandidatePrompt(candidates)
        )
        askCurrentStep()
    }

    /// 后端 `ttsText` 缺失时的本地兜底播报。**格式跟着后端走**（「找到N个地点，请说第几个。」+ 逐条），
    /// 否则两条路径教用户说的话不一样，而他只学得会先听到的那一种。
    static func localCandidatePrompt(_ candidates: [AddressCandidate]) -> String {
        let body = candidates.enumerated()
            .map { "\(ordinalWords[$0.offset])，\($0.element.name)。" }
            .joined()
        return "找到\(candidates.count)个地点，请说第几个。" + body
    }

    /// 用户在消歧轮说的那一句。**全本地判定。**
    func chooseCandidate(from candidates: [AddressCandidate], saying transcript: String) {
        // 出口优先：被一批他听不明白的候选卡住时，「重说」必须随时能退出去。
        // 复用确认轮那张表，不另写一份 —— 教给用户的词只有一套才记得住。
        if Self.command(for: transcript) == .restart {
            restartFromFreeform()
            return
        }
        guard let index = Self.ordinalIndex(in: transcript, count: candidates.count) else {
            reaskCount += 1
            if reaskCount >= Self.maximumReasksPerSlot {
                // 三次没挑出来**不把人丢回表单**（那是其余轮次的降级方式）：这里手上已经有一个
                // 可用的最佳猜测，而读回会把它念出来、用户仍然可以说「重说」。
                // 但**必须说出「按第一个来」** —— 静默取第一条正是这轮改动要消灭的那个失败。
                applyCandidate(candidates[0], notice: Self.pickedFirstCandidateNotice)
                return
            }
            // ⚠️ **不能图省事用 `promptAndListen`**：它开头就把 `reaskCount` 清零
            // （那是给定向追问用的「不计入重问上限」路径）。用在这里，上面那个上限永远数不到，
            // 挑不出来的用户就被**永远关在候选列表里** —— 又一个没有出口的循环。
            speak("没听清是第几个。请说「第一个」或者「第二个」，要重新讲就说「重说」。")
            if let field = step.speechField {
                listen(for: field)
            }
            return
        }
        applyCandidate(candidates[index], notice: pendingNotice)
    }

    static let pickedFirstCandidateNotice = "没听清是第几个，先按第一个来。"

    private func applyCandidate(_ candidate: AddressCandidate, notice: String?) {
        bookingViewModel?.applyVoiceResolvedStartPlace(
            address: candidate.readbackAddress,
            // 候选的 `name` 就是 POI 名，与后端 `addressShort` 同一档 —— 读回念它。
            spokenAddress: candidate.name,
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )
        // 快照必须跟着换：确认轮会把 `lastParsed.slotSnapshot` 当 `current` 发回 `/parse`，
        // 不换的话后端按旧快照把起点继承成第一条，读回念的又变回最佳猜测 ——
        // 用户刚挑的那一下就白挑了，而且没有任何提示。
        lastParsed = lastParsed?.replacingStartPlace(with: candidate)
        moveToConfirm(notice: notice)
    }

    /// 「第二个」→ 1。认不出返回 nil。
    ///
    /// **汉字这一路是实测过的，不是假设**（2026-08-06，记在 `demo/docs/handoff.md:2072-2088`）：
    /// 「第一个」「第二个」「第三个」「就第二个吧」「选第三个」「我要第一个」**12/12 全对**，
    /// 且加不加 `contextualStrings` 偏置**逐字相同** —— 渲染出来的是汉字「第二个」，
    /// **不是**「第2个」。所以本地表按汉字整串匹配是对的。
    /// 专门测这一条，是因为本仓库被同一个坑咬过：「八点钟」被识别器渲染成 `8:00`。
    ///
    /// ⚠️ **那批数据是合成音频**。真实人声（尤其户外）召回会掉，但**渲染形式**这一条是稳的 ——
    /// 所以下面的阿拉伯数字写法不是「防版本漂移」（我们没有那种证据），
    /// 而纯粹是零成本的超集：这几个串不可能是别的意思，收下不花任何东西。
    /// 词表门禁只要求「后端念的每个词本地都认得」，本地多认几种不违反它。
    ///
    /// `count` 是护栏：只认真实存在的那几条。念了 2 个却认「第三个」等于让用户挑一个不存在的地点。
    static func ordinalIndex(in transcript: String, count: Int) -> Int? {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return nil }
        for (index, forms) in ordinalForms.enumerated() where index < count {
            if forms.contains(where: normalized.contains) { return index }
        }
        return nil
    }

    /// 播报用的序数词，下标即候选下标。与后端 `VoiceOrderService.ORDINALS` 同一套写法。
    static let ordinalWords = ["第一个", "第二个", "第三个"]

    /// ⚠️ 外层顺序即判定优先级，别按字典序重排：「第二个」不含任何 index 0 的写法，
    /// 所以从前往后扫是安全的；但把「第一」放到「第二个」后面就会先命中错的那条。
    private static let ordinalForms: [[String]] = [
        ["第一个", "第1个", "第一", "第1", "头一个"],
        ["第二个", "第2个", "第二", "第2"],
        ["第三个", "第3个", "第三", "第3"]
    ]

    /// 把一次解析结果落到 view model 上。**整句轮与确认轮共用这一份** ——
    /// 跨轮修正之后确认轮也会拿到完整的合并结果，两处各写一遍迟早有一边漏掉一个槽位
    /// （这正是三个可选槽位曾经被静默丢掉的成因）。
    ///
    /// - Returns: 需要在下一次读回前先说的一句话（目前只有时长夹取），没有就是 nil。
    ///
    /// - Parameter transcript: 本轮的原话。备注要靠它验「是不是用户自己说的」，见下面那段。
    @discardableResult
    func apply(_ parsed: ParseVoiceOrderResponse, spokenIn transcript: String) -> String? {
        // 快照留给下一轮的 `current`。**必须在这里存**，而不是只在整句轮存：
        // 用户连改两项时，第二轮要继承的是第一轮**合并后**的结果。
        lastParsed = parsed

        // 时间**跟着响应走**，不是只置真不置假。跨轮继承下第 2 轮响应里时间还在，
        // 标志位就该还是真；而 `RESTART` 之后响应里没有时间，就该翻回假。
        if let raw = parsed.plannedStartTime, let date = raw.backendLocalDate {
            bookingViewModel?.appointmentTime = date
            didCaptureStartTime = true
        } else {
            didCaptureStartTime = false
        }
        if let place = parsed.resolvedStartPlace {
            bookingViewModel?.applyVoiceResolvedStartPlace(
                address: place.address,
                // 读回念 POI 名，下单仍带完整地址 —— 后端 `api_spec.yaml:3032` 明确的分工。
                spokenAddress: parsed.spokenStartAddress,
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
        // 终点整体赋值（**含 nil**），不写 `if let`：本轮没说终点就该清空。
        //
        // 起点写成 `if let` 是对的 —— 抽不出起点有正当默认（当前位置），保留上一轮反而更糟。
        // 终点没有默认值，留着上一轮的就是凭空多出一个用户这次没说过的目的地，
        // 而屏幕上没有任何终点控件能让他察觉。
        //
        // 接了 `current` 之后这行**变得更对**：后端会把上一轮的终点继承回来，
        // 所以「整体赋值」不再等于「只改时间就把终点擦了」。
        bookingViewModel?.endPlace = parsed.resolvedEndPlace

        var notice: String?
        if let minutes = parsed.durationMinutes {
            let accepted = Self.acceptedDurationMinutes(minutes)
            bookingViewModel?.exactDurationMinutes = accepted
            notice = Self.durationClampNotice(spokenMinutes: minutes, accepted: accepted)
        }

        // 三个可选槽位。**抽到才写，抽不出保留原值** —— 与终点那行的「整体赋值含 nil」刻意相反。
        //
        // 分界不是「必填 / 选填」，是**屏幕上有没有对应控件**：终点没有任何控件，用户察觉不到
        // 上一轮的残留；这三项都有（开关、两个 Picker、文本框），而且读回会把它们念出来，
        // 所以留着用户自己填过的值是对的，清掉反而是替他撤销。
        //
        // ⚠️ 在此之前这三项**解出来就被丢掉了**：模型层 2026-08-04 就接了，向导一直没消费。
        // 后果是静默的 —— 用户说「带导盲犬」，读回不提，而 `hasGuideDogThisRun` 进派单**硬过滤**，
        // 候选池按档案默认值筛，盲人全程听不出来。
        if let hasGuideDog = parsed.hasGuideDog {
            // `false` 原样落，不塌缩成 nil：见 `BlindBookingViewModel.hasGuideDogThisRun`。
            bookingViewModel?.hasGuideDogThisRun = hasGuideDog
        }
        if let pace = parsed.pacePreference {
            bookingViewModel?.pacePreference = pace
        }
        if let notes = parsed.specialNotes?.nilIfBlank {
            // 后端**声称**非 nil 时是用户原话的子串（改写过的备注在后端就被丢弃了），
            // 但这条声称我们自己验一遍：备注是原样展示给志愿者、并被当成盲人本人的话读的，
            // 模型编出来的「我行动不便」会直接误导对方，而盲人看不见屏幕、核对不了。
            // 这正是 spec 里 `Parser returns rewritten text` 那条场景 ——
            // 校验外部响应是信任边界的义务，不是对后端不信任。
            //
            // ⚠️ 判据里的 `== 已有值` 分支不能省：跨轮修正时后端会把上一轮的备注从 `current`
            // 继承回来，而这一轮的原话是「时间改成九点」—— 只比对本轮 transcript
            // 会把一条用户真说过的备注当成伪造删掉。
            let alreadyHeld = bookingViewModel?.specialNotes.nilIfBlank
            if notes == alreadyHeld || transcript.contains(notes) {
                bookingViewModel?.specialNotes = notes
            } else {
                // 丢弃不静默：读回不念它，用户听得出备注没了，可以说「重说」。
                // 但排查时要能看见它发生过 —— 静默降级是本仓库的一类反复缺陷。
                ClientFlowDiagnostics.record(event: "rewritten_notes_discarded", operation: "voice-parse")
            }
        }

        // 「说了一个地点，但我们没查到」—— **必须说出来**，而且要和上面那条一起说，不是二选一。
        //
        // 起点解析不出时读回念的是「当前位置」（`startPointSummary` 的默认值），
        // 而用户明明说了一个地名 —— 静默落回当前位置就是**把人约到错误的起点**，他全程听不出来。
        // `addressUnresolved` 正是为了让客户端分得开「压根没说起点」和「说了但没查到」。
        //
        // ⚠️ 后端 2026-08-10 起不再拿全国范围的正向编码兜底（那条路曾把深圳说的地名解析到海南），
        // 所以这个 `true` 会**变常见** —— 在此之前它几乎不出现，接不接看不出差别。
        if parsed.resolvedStartPlace == nil, parsed.addressUnresolved == true {
            let hasFallback = bookingViewModel?.resolvedStartPlace != nil // 没有可用起点就不说「按当前位置来」（#558）
            notice = [notice, Self.unresolvedStartNotice(hasFallback: hasFallback, isChosenPlace: bookingViewModel?.selectedStartPlace != nil)].compactMap { $0 }.joined()
        }
        return notice
    }

    // `isEndpointMissing` / `isIdentityRejection` 与时长换算在 `VoiceOrderWizard+ServerReplies.swift`；
    // 读回前的提示文案（`parseFailureNotice` 等）在 `VoiceOrderWizard+SpokenCopy.swift`。

    /// - Parameter notice: 需要先说一句再读回的话（例如时长被取整）。**必须和读回拼成同一段**，
    ///   分两次 `speak` 会让 `lastSpokenPrompt` 只剩后一句，「重复一遍」就再也念不到取整提示了 ——
    ///   对听不见屏幕的人，念不到等于没发生。
    func moveToConfirm(notice: String? = nil) {
        reaskCount = 0

        // 连着两轮都没拿到开始时间就交回表单，**不许再让人重说**。
        //
        // 这是「时间抽不出就不许确认」那条规则的必要配套。少了它，只要解析这一环是坏的，
        // 用户就落进一个没有出口的圈：说一整句 → 抽不出时间 → 不给确认 → 「请说重说」→
        // 重说 → 还是抽不出 → 无限循环。2026-08-06 手测就是这么卡住的：用户第二遍明确说了时间，
        // 仍然抽不到。
        //
        // ⚠️ **2026-08-18 更正**：原来这里举的例子是「`/api/orders/voice/parse` 在生产上恒 404」，
        // 那条已经不成立 —— 生产 `GET /v3/api-docs` 里列着该端点，对它发无鉴权请求收到的也是
        // **后端自己的** 401 JSON（说明确实被代理到 Spring Boot 并由它处理）。这道闸依然要留着，
        // 但它防的是「解析这一环坏了」这个类别，不是那个具体的、已经不存在的故障。
        //
        // 对看不见屏幕的人，一个没有出口的循环比一条错误信息糟得多 —— 他没有别的方式发现
        // 这条路根本走不通。（同类的第二个循环在 `handleConfirmViaBackend` 的 `missing` 分支上，
        // 2026-08-18 补的那道 —— 这道闸看不住它，因为它只数「没拿到开始时间」的轮次。）
        if didCaptureStartTime {
            roundsWithoutStartTime = 0
        } else {
            roundsWithoutStartTime += 1
            if roundsWithoutStartTime >= Self.maximumRoundsWithoutStartTime {
                // 端点不存在时重说多少遍都不会好，仍交回表单；只是没听清就停在语音面板（#502）。
                if parseIsUnavailable {
                    fallBack(reason: "语音下单服务暂时不可用")
                } else {
                    endSession(.notUnderstood)
                }
                return
            }
        }

        step = .confirm
        pendingNotice = notice
        askCurrentStep()
    }
}
