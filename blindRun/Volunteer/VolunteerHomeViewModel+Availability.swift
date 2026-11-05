import SwiftUI

extension VolunteerHomeViewModel {
    /// - Returns: 这次真的开始改开关了（发出了请求）。被「正在改」或同意闸挡下时为 false。
    @discardableResult
    func setAvailability(_ value: Bool) -> Bool {
        guard !isUpdatingAvailability, let appState else { return false }
        // #368：开始为派单持续上报位置之前，先要本机有志愿者位置轨迹的单独同意。
        // 没有就盖同意页：开关不翻、不发请求、不弹系统授权框。
        if value, !appState.hasLocationTrackConsent(.volunteerLocationTrack) {
            trackConsentRequest = .turnOn
            return false
        }

        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
        return true
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil

        do {
            try await appState.orders.setDispatchStatus(wantsDispatch: value)
            let existingProfile = appState.volunteerProfile
                let profile = VolunteerProfileResponse(
                    name: existingProfile?.name,
                    verificationStatus: existingProfile?.verificationStatus,
                    adminReviewStatus: existingProfile?.adminReviewStatus,
                    registrationStep: existingProfile?.registrationStep,
                    canAcceptOrders: existingProfile?.canAcceptOrders,
                    isAvailable: value,
                    wantsDispatch: value,
                    availableTimeSlots: existingProfile?.availableTimeSlots,
                acceptsGuideDog: existingProfile?.acceptsGuideDog,
                paceRange: existingProfile?.paceRange
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                isUpdatingAvailability = false
                return
            }
            // `try?` 是迁移前就有的：开关本身已经切成功并播报过了，这一步只是把摘要刷新一下，
            // 拿不到不改变「已上线 / 已下线」这个既成事实。
            if let summary = try? await appState.orders.dispatchSummary() {
                apply(summary: summary)
            }
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }

    func apply(profile: VolunteerProfileResponse?) {
        guard let profile else { return }
        nickname = profile.name ?? ""
        isAvailable = profile.isAvailable ?? false
        requestTrackConsentIfStandbyResumesWithoutIt()
    }

    /// 服务端说还在接单、而本机没有同意记录（重装、换手机、在安卓上同意过）：先问，再恢复待命。
    /// 后端不存这项同意，所以「服务端开着」不等于「同意过」。
    ///
    /// #420：等首份摘要到了再判 —— 摘要才说得出手上有没有同行态的单，而同行态的单要问同一件事
    /// （根部 `EscortTrackConsentOverlay`）。那边要问就让给那边，同一个问题只问一次；那边的回答经
    /// `escortTrackConsentQuestion` 回到这里。`configure` 时用缓存的个人资料判的话，会先闪出一张再收起。
    func requestTrackConsentIfStandbyResumesWithoutIt() {
        guard isAvailable,
              !isUpdatingAvailability,
              !declinedResumeTrackConsent,
              trackConsentRequest == nil,
              dispatchSummary != nil,
              let appState,
              !appState.liveEscortCoordinator.needsTrackConsentForActiveOrder,
              !appState.hasLocationTrackConsent(.volunteerLocationTrack) else { return }
        trackConsentRequest = .resumeStandby
    }

    /// 同行态的同意页在问同一件事（#420）。
    /// - 开始问：手上这张让开（单在这张弹着的时候被推进了同行态）。
    /// - 拒绝：也算拒绝恢复待命（负责人 2026-10-15 定）—— 开关开着就替他关掉，滑块上方留下那句后果，
    ///   但**不念**：根部横幅正在念这一单的后果，后到的 `speak` 会把它切断。
    func escortTrackConsentQuestion(_ event: LiveEscortSessionCoordinator.TrackConsentQuestionEvent) {
        switch event {
        case .asked(let purpose):
            guard purpose == .volunteerLocationTrack else { return }
            trackConsentRequest = nil
        case .declined(let purpose):
            guard purpose == .volunteerLocationTrack else { return }
            declinedResumeTrackConsent = true
            // 开关正在改（`setAvailability` 被挡下）时不写这句：开关没关，「没有开始接单」就是假话。
            guard isAvailable, setAvailability(false) else { return }
            trackConsentDeclinedNotice = purpose.declinedFeedback
        }
    }

    /// 同意页上按了「同意共享位置」。`requestLocationPermission` 由视图传入 ——
    /// 系统授权框挪到这一刻弹（告知在前），view model 不持有定位服务。
    func agreeTrackConsent(requestLocationPermission: () -> Void) {
        guard let request = trackConsentRequest, let appState else { return }
        trackConsentRequest = nil
        trackConsentDeclinedNotice = nil
        declinedResumeTrackConsent = false
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        requestLocationPermission()
        switch request {
        case .turnOn:
            // 只在开关真的开始打开时才进接单主页，否则会进到一个「开关其实没开」的接单主页。
            entersDispatchHubAfterTrackConsent = setAvailability(true)
        case .resumeStandby:
            // 开关本来就开着，不用 PUT；立刻补报一次，不等下一拍刷新循环。
            Task { [weak self] in
                guard let self else { return }
                await self.reportLocationThenRefreshSummary(
                    currentLocation: self.currentLocationProvider(),
                    locationAuthorized: self.locationAuthorizedProvider()
                )
            }
        }
    }

    /// 同意页上按了「先不同意」。拒绝是完整的答案，不追问。
    func declineTrackConsent() {
        guard let request = trackConsentRequest else { return }
        trackConsentRequest = nil
        if request == .resumeStandby {
            declinedResumeTrackConsent = true
            if isAvailable { setAvailability(false) }
        }
        let notice = PrivacyConsentPurpose.volunteerLocationTrack.declinedFeedback
        trackConsentDeclinedNotice = notice
        speechService?.speak(notice)
    }
}
