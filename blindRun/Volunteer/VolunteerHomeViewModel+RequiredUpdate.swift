import Foundation

extension VolunteerHomeViewModel {
    /// 必须更新的弹窗出现时关掉接单开关（#668，负责人 2026-11-04）。
    ///
    /// 与 `VolunteerLocationConsentRevocation` 同一做法：**先等服务端关成功**，再翻本地开关。
    /// 关不掉就不翻 —— 开关显示关着而服务端继续派单，比显示开着更糟。
    ///
    /// - Returns: `nil` = 没什么可关的（开关本来就关着、别的开关请求在途、任务被取消），弹窗不该说「已暂停」。
    func pauseDispatchForRequiredUpdate(appState: AppState) async -> AppUpdateGate.DispatchPause? {
        guard isAvailable, !isUpdatingAvailability else { return nil }
        isUpdatingAvailability = true
        defer { isUpdatingAvailability = false }
        do {
            try await appState.orders.setDispatchStatus(wantsDispatch: false)
        } catch is CancellationError {
            return nil
        } catch {
            if let error = error as? APIError { _ = appState.handleAuthenticatedAPIError(error) }
            return .failed
        }
        if let existing = appState.volunteerProfile {
            appState.updateVolunteerProfile(VolunteerProfileResponse(
                name: existing.name,
                verificationStatus: existing.verificationStatus,
                adminReviewStatus: existing.adminReviewStatus,
                registrationStep: existing.registrationStep,
                canAcceptOrders: existing.canAcceptOrders,
                isAvailable: false,
                wantsDispatch: false,
                availableTimeSlots: existing.availableTimeSlots,
                acceptsGuideDog: existing.acceptsGuideDog,
                paceRange: existing.paceRange
            ))
        }
        // `isAvailable` 的 didSet 同步 `AppState.volunteerWantsDispatch`，位置上报跟着停。
        isAvailable = false
        return .paused
    }
}
