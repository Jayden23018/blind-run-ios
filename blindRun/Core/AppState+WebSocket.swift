import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - WebSocket (Private)

    /// 根据当前 token 和角色连接 WebSocket（mock 环境跳过）
    func connectWebSocketIfNeeded() {
        #if DEBUG
        if currentEnvironment == .mock, Self.uiTestConfiguresEscortSessionWithoutWebSocket() {
            liveEscortCoordinator.configure(identityKey: sessionIdentityKey, role: activeRole, webSocketService: nil)
        }
        #endif
        #if DEBUG || DEMO
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] == "1" {
            return
        }
        #endif

        guard currentEnvironment != .mock,
              AppBuildChannel.current.allows(currentEnvironment),
              let token = accessToken,
              let role = activeRole,
              role != .unset,
              let baseURL = currentEnvironment.baseURL else {
            return
        }

        let wsRole: WSRole = (role == .blind) ? .blind : .volunteer

        // 如果已有连接先断开
        webSocketService?.disconnect()

        let service = WebSocketService()
        webSocketService = service
        service.connect(baseURL: baseURL, token: token, role: wsRole)
    }

    #if DEBUG
    /// UI 用例专用（#414）：Mock 下没有 WebSocket，协调器只在 `webSocketService` 的 didSet 里拿身份与角色，
    /// 同行会话（含同行态的位置轨迹同意页）在 Mock 里根本不跑。打开它就在这里补配一次身份与角色、不连 WS。
    /// 只给专测同行会话的用例开：默认打开会让每条停在出发 / 汇合 / 跑步中的用例底部多一条「网络已中断」横幅并播报。
    static func uiTestConfiguresEscortSessionWithoutWebSocket(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["AIDRUN_UI_TEST_RESET_STATE"] == "1"
            && environment["AIDRUN_UI_TEST_MOCK_ESCORT_SESSION"] == "1"
    }
    #endif

    /// 断开 WebSocket 并清除引用
    func disconnectWebSocket() {
        webSocketService?.disconnect()
        webSocketService = nil
    }
}
