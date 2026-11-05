import CoreLocation
import Foundation

extension VoiceOrderWizard {
    // MARK: Confirm

    /// 读回之后用户说的那一句。**两档：本地整串直通，其余交后端。**
    ///
    /// 为什么不像后端建议的那样把本地词表整个撤掉（handoff N45 ④）：后端的确定性兜底跑在
    /// **服务端**，它挡不住网络。确认轮发一次 `/parse` 要 3.4~4.3 秒（每次都调大模型），
    /// 客户端超时 12 秒 —— 全流程最高频、最简单的那一句「确认」要等 4 秒才下单，网络一抖就
    /// 下不了单：用户刚才那一整句已经解析成功、槽位全在客户端手里，却因为一次确认往返失败被打回表单。
    /// 对看不见屏幕的人，那是把一次已经成功的语音下单在最后一步丢掉。
    ///
    /// 这**不是「两处各判一套」**：本地表是后端正则兜底的子集时，两者不可能给出不同结论。
    /// 这个子集关系由 `scripts/validate-voice-intent-words.mjs` 逐词对撞后端
    /// `VoiceSlotParser.java` 的 `INTENT_*` 正则钉住，本地表里出现一个后端判成别的意图的词就红。
    func handleConfirmCommand(_ transcript: String) async {
        // 第 1 档：本地整串命中 → 零延迟直通，一个字节都不发。
        switch Self.command(for: transcript) {
        case .confirm:
            await confirmBooking()
            return
        case .repeatBack:
            repeatReadback()
            return
        case .restart:
            restartFromFreeform()
            return
        case .unrecognized:
            break
        }

        // 第 2 档：其余一律交后端。方言、长句、「我想改时间」全在这一档 ——
        // 这正是「只能说确认或重说」那个二选一被打开的地方。
        await handleConfirmViaBackend(transcript)
    }

    private func handleConfirmViaBackend(_ transcript: String) async {
        enterParsing(saying: "正在识别，请稍候。")
        defer { isParsing = false }

        let sentSnapshot = confirmRoundSnapshot
        let parsed: ParseVoiceOrderResponse
        do {
            parsed = try await parseOrderResponse(transcript, current: sentSnapshot)
        } catch {
            if Self.isIdentityRejection(error) { return stopForIdentityRejection() }
            // **不再回「没听懂」** —— 这里失败的是网络，不是听力，说成没听懂会让用户去改说法，
            // 而改说法一点用都没有。本地那几个词仍然直通，所以「确认」这条出路没有被网络挡住，
            // 提示里必须把它说出来。
            // 缺关键槽位时「确认」不生效，不能教它（#558）；说缺什么。
            reask(with: missingRequiredSlotMessage ?? Self.confirmRoundNetworkFailureNotice)
            return
        }

        switch parsed.userIntent {
        case .confirm:
            // ⚠️ **不播后端的「这就为您下单」**：`/parse` 无副作用，那句话说的是一个还没发生的结果。
            // 沿用 `confirmBooking()` 里的「正在提交订单。」，进行时口径与 SOS 那条红线同源。
            await confirmBooking()
            return
        case .cancel:
            // 用户要退出，不是要改。**不重问**（后端此时 `needReask` 也是 false）。
            endSession(.cancelled)
            return
        case .restart:
            restartFromFreeform()
            return
        case .repeatBack:
            repeatReadback()
            return
        case .unknown, .none:
            break
        }

        if let target = parsed.correctionTarget {
            // 用户点名要改哪一项、还没给新值。播后端的定向追问语，再收一次音，
            // **`current` 一个字都不动** —— 后端说了本轮什么都没覆盖。
            //
            // 这一轮**不计入重问上限**：后端听懂了、用户也在正常推进，把「改三项」记成
            // 「三次没听清」会在第三项上把人降级到表单。真听不清仍然有界 ——
            // 用户接下来若沉默，`handle` 那条空转录路径走的还是 `reask`。
            promptAndListen(parsed.ttsText?.nilIfBlank ?? Self.fallbackCorrectionPrompt(for: target))
            return
        }

        if parsed.correctionUnclear == true {
            // 用户否定了读回但没说改哪一项。这一条**确实是没听懂**，计入上限。
            reask(with: parsed.ttsText?.nilIfBlank ?? "你想改哪一项？出发地、开始时间，还是时长？")
            return
        }

        // 🔴 **这一轮什么都没变，而后端还缺槽位 —— 不许再念一遍读回**（2026-08-18，后端 N97）。
        //
        // 走到这里未必是「用户给了新值」：`userIntent` / `correctionTarget` / `correctionUnclear`
        // 三个信号在 `missing` 非空时会被后端**一起压掉**（`correctionTarget` 至今仍要求 `missing` 为空）。
        // 而下面那条兜底会 `apply` 一份什么都没变的响应、再 `moveToConfirm` 把同一段读回**原样重念**，
        // 且 `moveToConfirm` 那道闸只数「连续两轮没拿到开始时间」—— 缺的是别的槽位时它一次都不触发
        // ⇒ **无限循环**。用户听到的就是「我说什么它都只把刚才那段再念一遍」。
        //
        // 这正是 2026-08-18 用户报的那条：确认轮只有本地直通词表里的那几个词管用，
        // 因为**只有它们不发这个请求**；说「对」「可以了」的人被永远关在读回里出不去。
        //
        // 判据用**槽位有没有真的变**而不是光看 `missing` 非空：用户说「结束地点改成五角场」时
        // 终点确实落进去了，那一轮该照常读回（内容会变，听得出来），不该被这条截胡。
        // 播后端那句追问（`missing` 非空时 `ttsText` 就是该项的追问语，正是本地拼不出来的东西），
        // 并**计入重问上限** —— 有上限才有出口，连着 3 次走不通时向导会交回表单。
        let unchanged = parsed.slotSnapshot == sentSnapshot
        if unchanged, let missing = parsed.missing, !missing.isEmpty {
            apply(parsed, spokenIn: transcript)
            reask(with: parsed.ttsText?.nilIfBlank ?? Self.confirmRoundNetworkFailureNotice)
            return
        }

        // 剩下的只有一种情况：用户给了新值，后端已经把它合进整单。落槽位、重念一遍。
        let notice = apply(parsed, spokenIn: transcript)
        moveToConfirm(notice: notice)
    }

    /// 确认轮回传给后端的 `current`。
    ///
    /// 底座是 `lastParsed.slotSnapshot`（**只从响应派生**，理由见
    /// `ParseVoiceOrderResponse.slotSnapshot` 上那段红线），但起点在这里要补一手。
    ///
    /// 🔴 **为什么必须补**（2026-08-18，后端 N97）：起点解析不出来时我们**本地回落当前位置**，
    /// 而快照只从响应派生 ⇒ 坐标进不去 `current` ⇒ 后端每一轮都报 `missing:[ADDRESS]` ⇒
    /// 它按「槽位没齐无从确认」把 `userIntent` 和 `correctionTarget` 一起压成 null ⇒
    /// 用户说什么都拿不到信号。而读回**已经把这个起点念出来了**（`startPointSummary`
    /// 开头就是「使用设备当前位置。」），用户听到并认可了它，此刻它就是一个已确认槽位。
    ///
    /// ⚠️ **只补起点，`plannedStartTime` 一个字都不许补** —— 那条红线原样保留：
    /// `appointmentTime` 的初值是 `Date()`，补它会把用户从没说过的时刻当成已确认发出去
    /// （`testCurrentNeverCarriesAnAppointmentTimeTheUserNeverSpoke` 钉着这一点）。
    /// 两者的区别是**读回里念没念过**：起点念了，时间在没抽到时明说「预约时间还没说。」。
    ///
    /// ⚠️ 地址与坐标**整组一起补**，绝不拆开 —— 拆开会拼出「新地址 + 旧坐标」，
    /// 读回念的是一个地方、实际派到另一个地方，而盲人完全听不出来（后端 `Slots.fillFrom` 同款约束）。
    ///
    /// 🚨 **只在响应里一个地名都没有时才补**（判据是 `address` 而不是坐标）。
    /// 「说了一个地名但高德查不到」时响应里**有地名、没坐标**（`addressUnresolved == true`），
    /// 那种情况**绝不能**拿当前位置顶掉它 —— 用户说的是「从老王家门口出发」，
    /// 静默换成设备当前位置就是**把人约到错误的起点**，而他全程听不出来。
    /// 那一路照旧让后端继续报 `missing:[ADDRESS]` 并追问（`apply` 里那句
    /// `startAddressUnresolvedNotice` 也会一起念出来），出口由上面那条 `missing` 分支给。
    private var confirmRoundSnapshot: VoiceSlotSnapshot? {
        guard let base = lastParsed?.slotSnapshot else { return nil }
        // 响应里已经有地名 = 要么后端解析出来了、要么用户说了个查不到的地名。两种都不许覆盖。
        guard base.address?.nilIfBlank == nil else { return base }
        guard let place = bookingViewModel?.resolvedStartPlace,
              let address = bookingViewModel?.resolvedStartLocationDescription.nilIfBlank else {
            return base
        }
        return VoiceSlotSnapshot(
            plannedStartTime: base.plannedStartTime,
            durationMinutes: base.durationMinutes,
            address: address,
            latitude: place.latitude,
            longitude: place.longitude,
            endAddress: base.endAddress,
            endLatitude: base.endLatitude,
            endLongitude: base.endLongitude,
            hasGuideDog: base.hasGuideDog,
            pacePreference: base.pacePreference,
            specialNotes: base.specialNotes,
            // 🔴 必须带：「明天早上」这类半句话通常**没说起点**，正好走进上面这条「补设备位置」的路 ——
            // 这里漏掉它，后端就收不到半句时间，用户答「九点」会被静默读成今天 9 点（#508）。
            partialStartTime: base.partialStartTime
        )
    }

    /// 「确认」这条路的唯一出口 —— 本地直通与后端 `CONFIRM` 都走它，缺槽位的拦截只有一份。
    private func confirmBooking() async {
        // 缺关键槽位时「确认」不生效 —— 用户没说过时间，不能凭一句「确认」就派单。
        // 读回结尾已经念过原因（`missingRequiredSlotMessage`），这里再说一次是因为
        // 用户可能是听完很久才开的口，中间隔了多少秒我们不知道。
        if let blocked = missingRequiredSlotMessage {
            reask(with: blocked)
            return
        }
        // 起点在读回之后才有（定位晚到）或换了：用户没听过这个起点，先重念再确认（#558）。
        if let viewModel = bookingViewModel, viewModel.resolvedStartPlace?.id != readBackStartPlaceID { return repeatReadback() }
        await submitConfirmedBooking()
    }

    /// 「再念一遍」。重播上一整段读回，不改任何槽位、不计重问。
    private func repeatReadback() {
        reaskCount = 0
        askCurrentStep()
    }

    /// 后端 `ttsText` 缺失时的定向追问兜底。正常情况下用不到 —— 后端保证 `correctionTarget`
    /// 非 null 时 `ttsText` 是该项的追问语；这里只防「字段在、文案空」那种线上偶发。
    private static func fallbackCorrectionPrompt(for target: VoiceCorrectionTarget) -> String {
        switch target {
        case .startAddress: return "好的，请说新的出发地点。"
        case .endAddress: return "好的，请说新的结束地点。"
        case .startTime: return "好的，请说新的开始时间，比如「明天早上八点」。"
        case .duration: return "好的，请说新的时长，比如「跑一个小时」。"
        case .guideDog: return "好的，请说这次带不带导盲犬。"
        case .pace: return "好的，请说这次的配速偏好。"
        case .notes: return "好的，请说要给陪跑员的备注。"
        case .unknown: return "好的，请说新的内容。"
        }
    }

    /// 从头再说一遍。**必须把上一轮抽到的槽位清干净**，否则新的一句没提到的项会留着旧值，
    /// 而读回照样把它念出来 —— 用户会以为那是他这次说的。
    func restartFromFreeform() {
        reaskCount = 0
        lastUtterance = nil
        pendingNotice = nil
        didCaptureStartTime = false
        // `current` 也要清 —— 留着它，用户「重说」的那一整句会被后端和上一轮的旧槽位合并，
        // 于是他这次没提的东西又原样回来了，而屏幕上一个字都不会变。
        lastParsed = nil
        bookingViewModel?.resetVoiceFilledSlots()
        step = .freeform
        askCurrentStep()
    }

    /// 用户说了「确认」：走既有的提交路径。
    ///
    /// 提交失败时不重来一遍语音 —— `BlindBookingViewModel.submit()` 已经播报并写好了 `errorMessage`，
    /// 把表单停在确认步骤，用户可以听着错误原因手动重试，这比在语音里重放一遍失败更可控。
    private func submitConfirmedBooking() async {
        // 先落 isRunning，再取 viewModel：停止录音的完成回调会再进一次 `handle`，那里靠 isRunning 挡住。
        // 顺序反过来的话，拿不到 viewModel 时向导会一直显示在跑、麦克风也不放。
        isRunning = false
        speechInputService?.stopRecognition()
        guard let bookingViewModel else { return }
        enterParsing(saying: "正在提交订单。")
        defer { isParsing = false }

        if let response = await bookingViewModel.submit() {
            createdOrder = response
        }
    }
}
