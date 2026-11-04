//
//  MockAPIClient+VerificationSeed.swift
//  blindRun
//
//  资质证书审核状态的 UI 用例覆盖（`AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS`）。从 `MockAPIClient.swift` 的种子段挪出。
//

import Foundation

extension MockAPIClient {
    /// Mock 只允许后端真实存在的四个取值，未知覆盖值一律忽略。
    func applyUITestVerificationStatusOverride() {
        guard let override = ProcessInfo.processInfo.environment["AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS"] else { return }
        let parsed = VolunteerCertificateStatus.parse(override)
        guard parsed != .unknown else { return }
        volunteerVerificationStatus = parsed
        // 证书没过审的真实陪跑员是「注册走完、还不能接单」（后端 `registrationCompleted` 与 `canAcceptOrders` 正交）：
        // 他进得了标签栏，从「我的」打开资质证书页。不设步骤位的话注册状态跟着证书状态推成「没走完」，
        // 根路由就停在认证页，证书页的四态 UI 根本够不着（#700）。
        // `STEP_4_TRAINING`：注册算走完，但 `canAcceptOrders` 只认 `STEP_4_COMPLETED`，仍不能接单。
        if parsed != .approved, volunteerProfile != nil {
            volunteerRegistrationStepCode = "STEP_4_TRAINING"
        }
    }
}
