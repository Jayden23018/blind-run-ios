import SwiftUI

extension BlindOrderStatusViewModel {
    // MARK: - 把这一单的志愿者设为固定搭档

    /// 查一次「这位志愿者收藏过没有」。**只在 `COMPLETED` 且后端给了 `volunteerId` 时调**。
    ///
    /// 为什么要多打一次 `/api/blind/favorite-volunteers`：`OrderDetailResponse` 只说这一单是谁陪的，
    /// 说不出「他是不是我的固定搭档」。没有这一次查询，按钮只能恒显示「设为固定搭档」，
    /// 对已经收藏过的搭档就是一句假话。
    ///
    /// 失败一律静默（同 `loadExistingReview`）：这是主路径之外的一块附属动作，
    /// 拿不到的唯一后果是整块不出现，不值得打断服务播报。
    func loadFavoriteStateIfNeeded() async {
        guard let order, let appState,
              order.status == .completed,
              let volunteerId = order.volunteerId else { return }
        do {
            let favorites = try await appState.incentive.blindFavoriteVolunteers()
            isVolunteerFavorited = favorites.contains { $0.volunteerId == volunteerId }
        } catch {
            isVolunteerFavorited = nil
        }
    }

    /// `PUT /api/blind/favorite-volunteers/{volunteerId}` —— 幂等，恒 204。
    ///
    /// **只做添加，不做取消。** 取消收藏在设置页的固定搭档列表里，那里看得到全部搭档；
    /// 在一张订单详情上给「取消收藏」，用户取消的是一段跨越很多次跑步的关系，
    /// 而他眼前只有其中一次的上下文。
    func addVolunteerToFavorites() async {
        guard let order, let appState, let volunteerId = order.volunteerId else { return }
        let name = order.volunteerName?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
        isUpdatingFavorite = true
        favoriteErrorMessage = nil
        defer { isUpdatingFavorite = false }
        do {
            try await appState.incentive.addBlindFavoriteVolunteer(volunteerId: volunteerId)
            isVolunteerFavorited = true
            let notice = PartnerStreakCopy.favoriteAdded(name)
            favoriteNotice = notice
            // 盲人端：结果必须念出来。屏幕上那行字是看得见的一半，播报是听得见的那一半。
            speechService?.speak(notice)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            // 两个收藏专属错误码（`FAVORITE_VOLUNTEER_NOT_ELIGIBLE` / `..._LIMIT_EXCEEDED`）
            // 的文案已经挂在 `ErrorCode.localizedMessage:289-292` 上，这里不再映射一遍 ——
            // 映射第二份的代价是两处文案迟早分叉，而分叉的那一半没有任何东西会报警。
            let message = error.localizedMessage
            favoriteErrorMessage = message
            speechService?.speakError(message)
        } catch {
            favoriteErrorMessage = PartnerStreakCopy.favoriteFailed
            speechService?.speakError(PartnerStreakCopy.favoriteFailed)
        }
    }
}
