import Foundation

/// 下单提交。约跑页（`BlindMatchFirstBookingView`）和语音向导的「确认」都走这一个出口。
extension BlindBookingViewModel {
    func submit() async -> OrderResponse? {
        guard let appState, locationService != nil else { return nil }
        // 出发地点缺失要在 makeCreateOrderRequest 之后单独报，所以这里跳过 .startPoint。
        if let gate = firstMissingGate, gate != .startPoint {
            return fail(message(for: gate))
        }

        isSubmitting = true
        errorMessage = nil

        guard let request = makeCreateOrderRequest() else {
            isSubmitting = false
            return fail("请选择出发地点。")
        }

        do {
            let response = try await appState.orders.createOrder(request)
            isSubmitting = false
            speechService?.resetLastStatus()
            speechService?.speak("订单提交成功，系统正在为你派单。")
            return response
        } catch let error as APIError {
            isSubmitting = false
            if error.endsSession {
                return nil
            }
            return reject(error, appState: appState)
        } catch {
            isSubmitting = false
            return fail("提交失败，请重试。")
        }
    }

    /// 后端拒绝下单。**已选的内容一概不动**，用户只改被拒的那一项。
    ///
    /// 受控公开的三个码（#667）念后端原话（`prefersServerMessage`，里面有开放城市 / 可预约时段）。
    /// 暂不接受预约 → 换什么都没用。入口闸门（`BlindBookingLaunchScopeGate`）当场换成告知页并念这句，
    /// 这里不念：告知页出现时的播报会把它切断（记忆 later-speak-silently-cuts-the-earlier-one）。
    private func reject(_ error: APIError, appState: AppState) -> OrderResponse? {
        let message = error.localizedMessage
        guard error.errorCode == .orderServiceNotOpen else { return fail(message) }
        errorMessage = message
        appState.noteBookingServiceNotOpen(message: message)
        return nil
    }

    private func fail(_ message: String) -> OrderResponse? {
        errorMessage = message
        speechService?.speakError(message)
        return nil
    }
}
