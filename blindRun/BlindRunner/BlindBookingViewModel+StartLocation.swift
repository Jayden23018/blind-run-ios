import CoreLocation
import Foundation

extension BlindBookingViewModel {
    func refreshCurrentLocation(lockMapCenterIfNeeded: Bool = true) async {
        guard let locationService else { return }
        guard !locationService.isDenied else {
            // **这里什么都不写。** 降级告知由 `locationDegradationNotice` 在同一个区块的顶部
            // 整段承担（还多说了「关着定位会失去什么」那半句安全代价）；这里再写一句
            // 「请在下面搜索出发地点」，屏幕上就是同一段话的两个版本，短的那版还漏了后半句。
            //
            // 2026-09-08 之前这里写着那句短的，注释也已经写着「由降级告知统一承担」——
            // 代码没跟上注释。
            placeMessage = nil
            return
        }
        guard !locationService.isPreciseLocationOff else {
            // 同上：降级告知由 `locationDegradationNotice` 整段承担，这里不再写一句。
            // 清掉旧的解析结果 —— 用户中途关掉精确位置时，屏幕上不该还挂着上一次的「当前位置」。
            // **不在这里自动弹临时精确位置的系统框**，只由告知里那枚按钮触发：进页这一刻语音向导正在开场
            // （`onAppear` 里与本方法并发），系统框会抢走读屏焦点、打断向导 —— 与求助路径不自动弹是同一个理由。
            currentResolvedPlace = nil
            currentLocationAccuracyMeters = nil
            placeMessage = nil
            return
        }

        let coordinate = bookingCoordinate(from: locationService)
        // 记下这次解析用的那个样本的精度，而不是渲染时再去读 —— 卡片上的提示说的是「这个地址」的误差。
        currentLocationAccuracyMeters = locationService.isUsingDemoFallback
            ? nil
            : LocationAccuracyPolicy.metersIfWeak(locationService.latestDeviceSample)
        let fallbackPlace = ResolvedPlace(
            id: locationService.isUsingDemoFallback ? "demo-current" : "device-current",
            title: locationService.isUsingDemoFallback ? "当前位置（演示坐标）" : "当前位置",
            addressText: locationService.isUsingDemoFallback ? "北京市（演示位置）" : "当前位置",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: locationService.isUsingDemoFallback ? .demoDefault : .deviceLocation
        )

        guard let placeSearchProvider, !locationService.isUsingDemoFallback else {
            currentResolvedPlace = fallbackPlace
            updateAuxiliaryMapPlaceIfNeeded(to: fallbackPlace, lockMapCenterIfNeeded: lockMapCenterIfNeeded)
            if lockMapCenterIfNeeded {
                lockInitialAuxiliaryMapCenter(to: fallbackPlace.coordinate)
            }
            placeMessage = locationService.isUsingDemoFallback ? "定位暂不可用，正在使用演示坐标。" : nil
            return
        }

        isResolvingStartLocation = true
        let resolvedPlace = await placeSearchProvider.reverseGeocode(coordinate: coordinate)
        let finalPlace = resolvedPlace ?? fallbackPlace
        currentResolvedPlace = finalPlace
        updateAuxiliaryMapPlaceIfNeeded(to: finalPlace, lockMapCenterIfNeeded: lockMapCenterIfNeeded)
        if lockMapCenterIfNeeded {
            lockInitialAuxiliaryMapCenter(to: finalPlace.coordinate)
        }
        isResolvingStartLocation = false
        placeMessage = resolvedPlace == nil ? placeSearchProvider.lastErrorMessage : nil
    }

    /// 降级告知里「临时开启精确位置」按钮。这是申请临时精确位置的唯一入口（不在进页时自动弹）。
    func requestTemporaryPreciseLocation() {
        locationService?.requestTemporaryPreciseLocation(for: .bookingStartPoint)
    }

    /// 本页只念一次：精度在 50 米上下来回跳时，每次刷新都念会把用户淹没。
    ///
    /// 由卡片上那句提示的 `onAppear` 调，**不在 `refreshCurrentLocation` 里念**：后者与语音向导开场并发，
    /// 后到的一句会把向导提示从半句切断。语音态下表单整段不渲染，提示出现时向导一定不在说话。
    /// 判据读 `startPointAccuracyNotice`（与屏幕同一个值）：出发点不是当前位置时一个字也不念。
    func announceWeakStartPointAccuracyIfNeeded() {
        guard !hasAnnouncedWeakStartPointAccuracy, let notice = startPointAccuracyNotice else { return }
        hasAnnouncedWeakStartPointAccuracy = true
        speechService?.speak(notice)
    }

    func refreshCurrentLocationIfNeeded() async {
        guard selectedStartPlace == nil,
              !isResolvingStartLocation else { return }
        await refreshCurrentLocation(lockMapCenterIfNeeded: false)
    }

    func searchPlaces(triggeredBySpeech: Bool = false) async {
        guard let placeSearchProvider else { return }
        let keyword = placeSearchKeyword.trimmed
        guard !keyword.isEmpty else {
            placeSearchResults = []
            placeMessage = "请输入要搜索的地点。"
            speechService?.announce(placeMessage ?? "")
            return
        }

        isSearchingPlaces = true
        placeMessage = nil
        let results = await placeSearchProvider.searchPlaces(
            keyword: keyword,
            near: resolvedStartPlace?.coordinate
        )
        placeSearchResults = results
        isSearchingPlaces = false
        if results.isEmpty {
            placeMessage = placeSearchProvider.lastErrorMessage ?? "未搜索到相关地点。"
            searchResultFocusID = nil
            speechService?.announce(placeMessage ?? "")
        } else {
            let firstPlace = results[0]
            searchResultFocusID = firstPlace.id
            speechService?.announce("已找到 \(results.count) 个地点，第一个是 \(firstPlace.title)。")
        }
    }

    func handlePlaceSearchSpeechCompletion(_ completion: SpeechInputCompletion) async {
        guard completion.field == .startPlaceSearch,
              completion.reason.shouldTriggerSearchWithRecognizedText else { return }
        let recognizedText = completion.recognizedText.trimmed
        guard !recognizedText.isEmpty else { return }
        placeSearchKeyword = recognizedText
        await searchPlaces(triggeredBySpeech: true)
    }

    /// - Parameter announce: 语音向导会自己播报后端返回的确认文案，这时把这里的播报关掉，
    ///   否则同一件事被念两遍 —— 对语速调到 14 字/秒的读屏用户，重复播报是最伤的干扰。
    func selectPlace(_ place: ResolvedPlace, announce: Bool = true) {
        // 起点换人了，上一轮语音的朗读形态立刻作废。
        // 不清的话，用户从表单搜索里挑了别的地点，读回念的还是上一句语音抽到的 POI 名 ——
        // 屏幕上显示 A、耳朵里听到 B，而看不见屏幕的人只有耳朵那一路。
        // `applyVoiceResolvedStartPlace` 在调用本方法**之后**再写入自己的那一份。
        voiceStartAddressShort = nil
        selectedStartPlace = place
        auxiliaryMapPlace = place
        auxiliaryMapCenter = place.coordinate
        placeSearchKeyword = place.title
        placeSearchResults = []
        searchResultFocusID = nil
        placeMessage = "已选择出发地点：\(place.title)。"
        if announce {
            speechService?.speak("已选择出发地点，\(place.title)。")
        }
    }

    /// 语音向导解析出的起点。坐标来自 `POST /api/orders/voice/resolve-address`，**已是 GCJ-02**，
    /// 与表单路径（高德 POI）同一坐标系，直接落进同一个 `selectedStartPlace`，下游一视同仁。
    ///
    /// 与表单路径的差别值得记一笔：POI 搜索给候选列表让用户挑，语音只给一个点。重名地点的消歧
    /// 责任因此完全落在后端，前端能做的只有把地址读回去让用户确认 —— 向导正是这么做的。
    /// - Parameter spokenAddress: 后端 `addressShort` —— **只喂读回**，不进下单请求也不上屏。
    ///   `nil` 时读回退回完整地址。
    func applyVoiceResolvedStartPlace(
        address: String,
        spokenAddress: String? = nil,
        latitude: Double,
        longitude: Double
    ) {
        let place = ResolvedPlace(
            id: "voice-resolved",
            title: address,
            addressText: address,
            latitude: latitude,
            longitude: longitude,
            source: .manual
        )
        selectPlace(place, announce: false)
        // 必须在 `selectPlace` 之后 —— 它会把这一份清空（见那里的注释）。
        voiceStartAddressShort = spokenAddress?.nilIfBlank
    }

    /// 语音说「重说」时把上一轮抽到的槽位清干净。
    ///
    /// 不清的话，新的一句里没提到的项会留着旧值，而读回照样把它念出来 ——
    /// 用户会以为那是他这次说的。对听不见屏幕的人，这种「上一轮的残留」无从察觉。
    ///
    /// **不碰 `appointmentTime`**：它没有「未设置」这个状态（初值就是 `Date()`），
    /// 「这一轮有没有真的抽到时间」由 `VoiceOrderWizard.didCaptureStartTime` 记着，
    /// 读回只在那个标志为真时才念具体时刻。
    func resetVoiceFilledSlots() {
        // 重说之后回到用户设的默认地点，不能悄悄退回当前定位。
        selectedStartPlace = defaultStartPlace
        // 跟着起点一起清 —— 留着会让下一轮读回念上一句话里的地名。
        voiceStartAddressShort = nil
        // 终点尤其不能留：屏幕上没有任何终点控件，用户重说一遍之后没有任何**视觉**线索
        // 能让他发现上一轮的终点还挂着，只有读回会念出来 —— 而那时他已经在准备说「确认」了。
        endPlace = nil
        duration = .none
        exactDurationMinutes = nil
        routeNotes = ""
        specialNotes = ""
        pacePreference = .noPreference
        routePreference = .noPreference
        hasGuideDogThisRun = nil
    }

    private func updateAuxiliaryMapPlaceIfNeeded(
        to place: ResolvedPlace,
        lockMapCenterIfNeeded: Bool
    ) {
        guard selectedStartPlace == nil else { return }
        guard let currentMapPlace = auxiliaryMapPlace else {
            auxiliaryMapPlace = place
            if lockMapCenterIfNeeded {
                lockInitialAuxiliaryMapCenter(to: place.coordinate)
            }
            return
        }

        if currentMapPlace.source == .demoDefault && place.source != .demoDefault {
            auxiliaryMapPlace = place
            auxiliaryMapCenter = place.coordinate
            return
        }

        let distance = CLLocation(latitude: currentMapPlace.latitude, longitude: currentMapPlace.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        if distance >= Self.auxiliaryMapMarkerRefreshDistanceMeters {
            auxiliaryMapPlace = place
        }
    }

    private func lockInitialAuxiliaryMapCenter(to coordinate: CLLocationCoordinate2D) {
        guard auxiliaryMapCenter == nil else { return }
        auxiliaryMapCenter = coordinate
    }
}
