import Foundation
import os

/// 向导里不碰状态的判定与换算。从 `VoiceOrderWizard.swift` 挪出来：那个文件超了 SwiftLint 行数上限，只许变短。
extension VoiceOrderWizard {
    /// 后端把未部署的端点回成 `errorCode: NOT_FOUND` 的业务信封（不是 nginx 裸 404）。
    /// 只认这一种：超时、鉴权过期、5xx 都可能是暂时的，不该被当成「功能不存在」。
    static func isEndpointMissing(_ error: Error) -> Bool {
        guard case APIError.serverError(let response) = error else { return false }
        return response.code == "NOT_FOUND"
    }

    /// 后端 #852：`/api/orders/voice/**` 对未实名盲人一律 403 `IDENTITY_NOT_VERIFIED`。
    /// 与 `isEndpointMissing` 同理只认这一个码：其余 403 / 5xx 仍按偶发失败处理。
    static func isIdentityRejection(_ error: Error) -> Bool {
        guard case APIError.serverError(let response) = error else { return false }
        return response.errorCode == .identityNotVerified
    }

    /// 契约允许的时长区间（`api_spec.yaml:2549`：`minimum: 10` / `maximum: 300`）。
    static let minimumDurationMinutes = 10
    static let maximumDurationMinutes = 300

    /// 语音说的分钟数**原样采用**，只在超出契约区间时夹到边界。
    ///
    /// 2026-08-06 之前这里是「就近 snap 到 6 个枚举档位」，于是「跑三个小时」变成两小时 ——
    /// 枚举存在的理由是选择器需要有限选项，而说话的人不需要选择器。契约本来就收 10–300。
    static func acceptedDurationMinutes(_ spoken: Int) -> Int {
        min(maximumDurationMinutes, max(minimumDurationMinutes, spoken))
    }

    /// 时长被夹到边界时要说的那句话；没动就返回 nil。
    ///
    /// **静默改动对听不见屏幕的人就是篡改**，这条红线不因为改动幅度变小而消失 ——
    /// 现在只有真的超出契约区间才会发生，但发生了就必须说。
    static func durationClampNotice(spokenMinutes: Int, accepted: Int) -> String? {
        guard accepted != spokenMinutes else { return nil }
        return "你说的是\(spokenMinutes)分钟，超出了可预约范围，本次按\(BlindBookingViewModel.durationText(forMinutes: accepted))预约。"
    }
}

private let identityRefreshLogger = Logger(subsystem: "com.culiu-tech.blindrun", category: "voice-order")

extension BlindBookingViewModel {
    /// 后端刚用 403 `IDENTITY_NOT_VERIFIED` 拒了语音解析，说明本地记的实名状态过期了。
    /// 重新拉一次盲人资料，下单页的实名门槛（`firstMissingGate`）和「直接下单」按钮就跟上了后端。
    ///
    /// 拉不到不影响已经念出的实名提示。最坏情况是「直接下单」还在：按下去会被 `POST /api/orders`
    /// 用同一个 403 拦住，并念 `ErrorCode.identityNotVerified` 的实名文案。
    func refreshIdentityAfterServerRejection() async {
        guard let appState else { return }
        let session = appState.sessionGeneration
        do {
            let profile = try await appState.profile.blindProfile()
            // 等待期间换了账号或退出登录：旧会话的资料不许写进新会话。
            guard appState.sessionGeneration == session else { return }
            appState.updateBlindProfile(profile)
        } catch {
            identityRefreshLogger.error(
                "实名被拒后刷新盲人资料失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
