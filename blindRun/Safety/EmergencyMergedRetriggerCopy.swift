import Foundation

// 单独成文件：`SafetyModule.swift` 已超 SwiftLint 的长度上限，CI 棘轮不许它再变长。
extension EmergencySafetyCopy {
    /// 再次触发被后端并进未结案的那条求助（`EmergencySOSState.mergedIntoOpenEvent`）。
    /// 项目负责人 2026-10-22 批准的原句（blind-run-backend#843）。
    /// 🔴 **不提家属短信**：原事件还在 `PENDING` 时，后端这次才第一次去通知家属，
    /// 说「不会再收到」就是假话；说「已通知」又违反 `AGENTS.md` §6。客服那半句用进行时。
    static let mergedIntoOpenEvent =
        "这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。\(emergencyCallReminder)"
}
