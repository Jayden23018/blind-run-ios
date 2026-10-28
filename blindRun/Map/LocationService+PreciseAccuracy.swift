import CoreLocation
import Foundation

// 临时精确位置：等用户回答（#547）。单独成文件：`LocationService.swift` 超长，在 SwiftLint 棘轮上，不许再长。
// 这里读不到 `private` 成员；要用的几样由 `LocationService.swift` 单独给出
// （`requestTemporaryFullAccuracyFromSystem(for:)`、`managerAccuracyAuthorization` 和 DEBUG 区的 4 个测试接缝）。
extension LocationService {
    /// 同 `requestTemporaryPreciseLocation(for:)`，但等到有回答才返回；返回时「精确位置」是否**仍然关着**。
    ///
    /// SDK（`CLLocationManager.h`）：用户回答了弹窗，completion 带 nil；系统决定不弹（App 在后台、已有精确位置、
    /// 用途键不在 Info.plist 等）时带一个 NSError —— 两种都会回调，所以用户点「保持关闭」之后调用方立刻就能降级，
    /// 不必空等超时。completion 与代理回调在同一个 runloop 上（这里是主线程）。
    /// 回调之后直接读 manager 的精度授权并同步进来：授权回调可能晚于 completion 到达，不同步的话调用方紧接着读到的还是旧值。
    /// 超时由调用方负责：completion 照 SDK 说总会来，但求助不赌这一点。
    func requestTemporaryPreciseLocationAndWaitForAnswer(for purpose: PreciseLocationPurpose) async -> Bool {
        guard isPreciseLocationOff else { return false }
        await waitForTemporaryPreciseLocationAnswer(purpose)
        applyAccuracyAuthorization(systemAccuracyAuthorization)
        return isPreciseLocationOff
    }

    private func waitForTemporaryPreciseLocationAnswer(_ purpose: PreciseLocationPurpose) async {
        #if DEBUG
        if interceptsTemporaryPreciseLocationForTesting {
            // 接缝打开时它只记账、不碰 `CLLocationManager`；回答由 `answerTemporaryPreciseLocationForTesting` 给。
            requestTemporaryPreciseLocation(for: purpose)
            await withCheckedContinuation { pendingTemporaryPreciseAnswersForTesting.append($0) }
            return
        }
        #endif
        await requestTemporaryFullAccuracyFromSystem(for: purpose)
    }

    /// 系统此刻的精度授权（不是发布出去的 `accuracyAuthorization`，那份要等授权回调才更新）。
    private var systemAccuracyAuthorization: CLAccuracyAuthorization {
        #if DEBUG
        if let systemAccuracyAuthorizationForTesting { return systemAccuracyAuthorizationForTesting }
        #endif
        return managerAccuracyAuthorization
    }

    #if DEBUG
    /// 替用户回答临时精确位置弹窗：`allowed` = 点了允许，再放行所有在等回答的申请。
    ///
    /// 只改「系统此刻的精度授权」，不动发布出去的状态 —— 与真机上 completion 先于授权回调到达是同一个顺序，
    /// 所以「回调后同步」那一步做没做，用例分得出来（#595 审查 A1）。
    /// 用 `simulatePreciseLocationOffForTesting` 钉过开关的用例，开关跟着回答一起改：钉住的开关优先于精度授权。
    func answerTemporaryPreciseLocationForTesting(allowed: Bool) {
        systemAccuracyAuthorizationForTesting = allowed ? .fullAccuracy : .reducedAccuracy
        if pinsPreciseLocationOffForTesting { simulatePreciseLocationOffForTesting(!allowed) }
        let pending = pendingTemporaryPreciseAnswersForTesting
        pendingTemporaryPreciseAnswersForTesting = []
        pending.forEach { $0.resume() }
    }
    #endif
}
