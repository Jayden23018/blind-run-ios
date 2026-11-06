import CoreLocation
import Foundation

extension BlindBookingViewModel {
    // 下面几句定位告知原由旧四步表单显示。表单界面已删（#810），规格仍要求约跑页显示，约跑页还没接上（#813）。

    /// 定位权限被拒时的降级告知。**不是门槛** ——
    /// 它不阻止任何一步推进，理由见 `BlindBookingGate` 的注释。
    ///
    /// 两句话都必须留着：第一句说「还能怎么下单」（否则用户不知道有手动搜索这条路），
    /// 第二句说「关着定位会失去什么」。只说第一句是把一次安全降级说成无关紧要，
    /// 而这两件事都发生在陪跑过程中、盲人当场看不见也问不了。
    ///
    /// **`isDenied` 是参数，不读自己那个 `weak var locationService`。** 那条 weak 引用要等
    /// `configure(...)` 在 `.onAppear` 里赋值，而 `body` 先于 `onAppear` 求值；`configure` 写的又是
    /// 普通存储属性，不发布变化。拿实例属性当渲染条件的话，被拒的用户在第一帧看到的是
    /// 「当前位置」卡片，而且不保证会有第二帧来纠正。视图自己持有
    /// `@EnvironmentObject LocationService`，这个事实在它手上永远是新鲜的。
    ///
    /// 2026-09-08 之前这里是个实例属性，**没有任何 View 消费**（视图自己写了一遍
    /// `if locationService.isDenied`）—— 于是单测断的是一条不出货的分支。
    static func locationDegradationNotice(isDenied: Bool, isPreciseLocationOff: Bool = false) -> String? {
        if isDenied { return locationDeniedNotice }
        return isPreciseLocationOff ? preciseLocationOffNotice : nil
    }

    /// 「精确位置」关闭（#373）。与 `locationDeniedNotice` 同一套两句结构：还能怎么下单 + 关着会失去什么。
    ///
    /// 与被拒的差别是**当前位置拿得到、但不能用**：系统给的是区域代表点（约 5 公里），
    /// 把它当出发点 = 陪跑员去几公里外接人。所以这一档不显示「当前位置」卡片，`resolvedStartPlace` 也不认设备来源。
    static let preciseLocationOffNotice =
        "「精确位置」已关闭，系统只给大致位置，可能偏差几公里，所以不能用当前位置作为出发地点。"
        + "可以直接搜索地点或选常用地点作为出发地点，预约照常提交；也可以临时开启精确位置。"
        + "但陪跑过程中，紧急求助会因为拿不到准确位置发不出去，建议在系统设置里为助盲跑打开「精确位置」。"

    /// 精确授权下，当前位置的精度差于 `LocationAccuracyPolicy.weakAccuracyMeters`（室内 Wi-Fi 定位常见 65 米）。
    /// 照用，但要请用户核对 —— 下单页会把逆地理得到的地址念出来，这句话让他知道该认真听那一句。
    static func weakStartPointAccuracyNotice(meters: Double) -> String {
        "当前定位精度较低（误差约 \(Int(meters.rounded())) 米），出发地点可能有偏差。请核对上面的地址，或直接搜索出发地点。"
    }

    /// 当前位置卡片上那句核对提示。只在出发点确实来自当前位置时出现。
    var startPointAccuracyNotice: String? {
        guard selectedStartPlace == nil,
              resolvedStartPlace?.source == .deviceLocation,
              let meters = currentLocationAccuracyMeters else { return nil }
        return Self.weakStartPointAccuracyNotice(meters: meters)
    }

    static let locationDeniedNotice =
        "定位权限未开启，无法自动获取当前位置。可以直接搜索地点作为出发地点，预约照常提交。"
        + "但陪跑过程中陪跑员看不到你的实时位置，紧急求助也可能因为拿不到位置发不出去，建议在系统设置里开启定位。"

    var appointmentSummary: String {
        let timeText = DateFormatter.aidRunDisplayDateTime.string(from: appointmentTime)
        guard let problem = appointmentTimeProblem else {
            return "预约时间：\(timeText)。"
        }
        return "预约时间：\(timeText)。\(problem.message)"
    }

    var startPointSourceText: String {
        guard let place = resolvedStartPlace else {
            return "未识别到出发地点。"
        }
        switch place.source {
        case .deviceLocation:
            return selectedStartPlace == nil ? "使用设备当前位置。" : "已选择地点。"
        case .manual:
            return "已选择地点。"
        case .demoDefault:
            return "正在使用演示坐标，不代表真实会合点。"
        }
    }

    /// 下单真正用的时长。语音说了精确值就用精确值，否则用选择器那一档。
    var resolvedDurationMinutes: Int? {
        exactDurationMinutes ?? duration.minutes
    }

    /// 读回与复核用的时长文案。**按精确分钟数生成**，不套枚举的 `displayName` ——
    /// 说了三个小时就该念「3 小时」，不是念一个最接近的档位名。
    var resolvedDurationText: String? {
        guard let minutes = resolvedDurationMinutes else { return nil }
        return Self.durationText(forMinutes: minutes)
    }

    /// 这一单**实际会被提交**的结束时刻。
    ///
    /// 用户没说时长时它是 `开始 + AppConstants.Timing.defaultBookingDurationMinutes`。
    /// 那个兜底不是无害的：后端 `+15min` 推 `ORDER_OVERDUE`、`+60min` 自动完成订单，
    /// 分享链接的有效期也跟着它。所以它必须能被读出来（见 `plannedEndSummary`），
    /// 而不是只活在 `makeCreateOrderRequest` 里。
    var plannedEndDate: Date {
        let minutes = resolvedDurationMinutes ?? AppConstants.Timing.defaultBookingDurationMinutes
        return appointmentTime.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 结束时刻的读回 / 展示文案。**两种情况说的话必须不一样。**
    ///
    /// 🚨 说了时长那一支只念时刻；**没说时长那一支必须交代「这个数是系统补的」** ——
    /// 用户从没同意过它，而服务开始后他会听到「预计 X 结束」（`blindRunnerAnnouncement`），
    /// 过了 15 分钟还会收到一条「可能失联」级别的提示。不说清来源，那条提示对他就是没来由的。
    ///
    /// 分钟数与实际提交用的是同一个常量，不写死 60 —— 写死会在产品调整兜底时长的那天
    /// 变成一句骗人的话（与 `appointmentTimeHint` 那条同源）。
    var plannedEndSummary: String {
        let timeText = DateFormatter.aidRunDisplayDateTime.string(from: plannedEndDate)
        guard resolvedDurationMinutes == nil else {
            return "预计 \(timeText) 结束。"
        }
        let fallback = Self.durationText(forMinutes: AppConstants.Timing.defaultBookingDurationMinutes)
        return "没有说跑多久，按 \(fallback) 计，预计 \(timeText) 结束。"
    }

    static func durationText(forMinutes minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) 分钟"
        case (_, 0): return "\(hours) 小时"
        default: return "\(hours) 小时 \(remainder) 分钟"
        }
    }

    /// 读回里那句出发地点。**念 `spokenStartLocationDescription` 而不是完整地址** ——
    /// 见 `voiceStartAddressShort` 与后端 `api_spec.yaml:3032`。
    var startPointSummary: String {
        guard resolvedStartPlace != nil else { return "出发地点还没有确定。" } // 定位不可用时等不到当前位置（#558）
        return "\(startPointSourceText)出发地点：\(spokenStartLocationDescription.nilIfBlank ?? "正在获取当前位置")。"
    }

    /// `resolvedStartLocationDescription` 的朗读版：底座换成 POI 名，**补充说明照旧带着**。
    ///
    /// 补充说明是用户自己敲进去的会合提示（「我在 A 口外侧等候」），
    /// 它不属于「门牌号那种听完无从判断」的东西，砍掉反而丢信息。
    var spokenStartLocationDescription: String {
        guard let short = voiceStartAddressShort?.nilIfBlank else {
            return resolvedStartLocationDescription
        }
        let supplement = startLocationDescription.trimmed
        if supplement.isEmpty || short.contains(supplement) {
            return short
        }
        return "\(short)；补充：\(supplement)"
    }

    /// 终点读回。**必须紧挨着 `startPointSummary` 念**，别塞进选填需求那一段。
    ///
    /// 起终点由大模型抽取，抽反了（「从五角场跑到人民广场」听成反过来）只有读回能被用户发现，
    /// 而两句挨着才听得出反没反 —— 中间隔着预约时间就听不出来了。后端 `api_spec.yaml:2843`
    /// 也是拿读回当这条防线的。
    ///
    /// 没有终点时返回空串：`nil` 的语义是「用户未指定」，多说一句「本次没有结束地点」
    /// 会让人以为系统漏听了他没说过的话。
    var endPointSummary: String {
        guard let endPlace else { return "" }
        if endPlace.isUnresolved {
            // 查不到坐标仍然照下单（后端允许「有地址无坐标」），但**必须说出来**：
            // 不说，盲人会以为终点已经定准了，而实际上志愿者拿到的只是一个地名。
            return "结束地点：\(endPlace.spokenAddress)。这个地点没能定位到，陪跑员会看到这个名字。"
        }
        return "结束地点：\(endPlace.spokenAddress)。"
    }

    /// 不用括号：全角「）」收尾会被真机审计误判为文字被裁（记忆 text-clipped-audit-trailing-fullwidth-paren）。
    static let profileDefaultPaceSuffix = "，资料里的默认"

    /// 资料里的默认配速（#797）。`nil` = 资料没设，或设的是「无偏好」。
    ///
    /// **只用于显示，不写进 `pacePreference`。** 下单不带配速时后端本来就回落到它
    /// （契约 `CreateOrderRequest.pacePreference`），所以订单不会错；缺的只是用户听不出会用哪个配速。
    /// 抄进 `pacePreference` 会让确认页和它的播报把它当成「这次选的」，
    /// 与 `resetVoiceFilledSlots` 防「上一轮残留被当成这次说的」是同一类问题。
    var profileDefaultPace: PacePreference? {
        guard let pace = appState?.blindProfile?.defaultPace?.selectable,
              pace != .noPreference else { return nil }
        return pace
    }

    var optionalReviewItems: [BookingReviewItem] {
        var items: [BookingReviewItem] = []
        if let routeNotes = routeNotes.nilIfBlank {
            items.append(BookingReviewItem(id: "routeNotes", title: "路线备注", value: routeNotes))
        }
        if let durationText = resolvedDurationText {
            items.append(BookingReviewItem(id: "duration", title: "预计时长", value: durationText))
        }
        if pacePreference != .noPreference {
            items.append(BookingReviewItem(id: "pace", title: "配速偏好", value: pacePreference.displayName))
        } else if let profileDefaultPace {
            items.append(BookingReviewItem(
                id: "pace",
                title: "配速偏好",
                value: "\(profileDefaultPace.displayName)\(Self.profileDefaultPaceSuffix)"
            ))
        }
        if routePreference != .noPreference {
            items.append(BookingReviewItem(id: "route", title: "路线偏好", value: routePreference.displayName))
        }
        // `false` 也要念。用户说了「今天不带导盲犬」却在读回里一个字听不到，
        // 与"我们没听懂"无从区分 —— 而这一项进派单硬过滤，听不出来的代价是候选池被改了。
        if let hasGuideDogThisRun {
            items.append(BookingReviewItem(
                id: "guideDog",
                title: "导盲犬",
                value: hasGuideDogThisRun ? "本次携带" : "本次不带"
            ))
        }
        if let specialNotes = specialNotes.nilIfBlank {
            items.append(BookingReviewItem(id: "specialNotes", title: "特殊说明", value: specialNotes))
        }
        return items
    }

    var optionalNeedsSpeechSummary: String {
        let items = optionalReviewItems
        guard !items.isEmpty else {
            return "没有填写选填跑步需求。"
        }
        return items.map { "\($0.title)：\($0.value)" }.joined(separator: "。") + "。"
    }

    var resolvedStartLocationDescription: String {
        guard let place = resolvedStartPlace else { return "" }
        let baseAddress = place.addressText.trimmed.isEmpty ? place.title : place.addressText.trimmed
        let supplement = startLocationDescription.trimmed
        if supplement.isEmpty {
            return baseAddress
        }
        if baseAddress.contains(supplement) {
            return baseAddress
        }
        return "\(baseAddress)；补充：\(supplement)"
    }

    var resolvedStartPlace: ResolvedPlace? {
        if let selectedStartPlace {
            return selectedStartPlace
        }
        // 「精确位置」关闭：设备来源一律不当出发点（#373），只认用户自己选的地点。
        guard locationService?.isPreciseLocationOff != true else { return nil }
        if let currentResolvedPlace {
            return currentResolvedPlace
        }
        guard let locationService else { return nil }
        guard locationService.currentLocation != nil || allowsDemoFallbackAsStartPoint else { return nil }
        let coordinate = bookingCoordinate(from: locationService)
        return ResolvedPlace(
            id: locationService.isUsingDemoFallback ? "demo-current" : "device-current",
            title: locationService.isUsingDemoFallback ? "当前位置（演示坐标）" : "当前位置",
            addressText: locationService.isUsingDemoFallback ? "北京市（演示位置）" : "当前位置",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: locationService.isUsingDemoFallback ? .demoDefault : .deviceLocation
        )
    }
}
