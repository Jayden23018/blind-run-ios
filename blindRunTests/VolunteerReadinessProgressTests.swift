import XCTest
@testable import blindRun

/// 滑块只在真能派单时说「接单中」。
///
/// 每条用例的输入都选在「错误实现会给出不同结果」的位置。
/// 被打回的两种实现：滑块只看开关（审计 V-6 的原样）、只看 `canDispatch` 不分原因。
final class VolunteerAvailabilityStatusTests: XCTestCase {
    private typealias Reason = VolunteerDispatchNotAvailableReason

    private func status(
        isAvailable: Bool,
        hasSummary: Bool = true,
        canDispatch: Bool? = false,
        reasons: [Reason] = [],
        explanation: String = "摘要说明"
    ) -> VolunteerAvailabilityStatus {
        VolunteerAvailabilityStatus.resolve(
            isAvailable: isAvailable,
            hasSummary: hasSummary,
            canDispatch: canDispatch,
            reasons: reasons,
            explanation: explanation
        )
    }

    // MARK: - 每一种不可派单原因

    func testNotVerifiedBlocksWhetherTheSwitchIsOnOrOff() {
        XCTAssertEqual(status(isAvailable: false, reasons: [.dispatchDisabled, .notVerified]), .blockedByCertificate)
        XCTAssertEqual(status(isAvailable: true, reasons: [.notVerified]), .blockedByCertificate)
    }

    func testTrainingIncompleteBlocksWhetherTheSwitchIsOnOrOff() {
        XCTAssertEqual(status(isAvailable: false, reasons: [.dispatchDisabled, .trainingIncomplete]), .blockedByTraining)
        XCTAssertEqual(status(isAvailable: true, reasons: [.trainingIncomplete]), .blockedByTraining)
    }

    func testCertificateComesBeforeTrainingWhenBothApply() {
        XCTAssertEqual(status(isAvailable: true, reasons: [.trainingIncomplete, .notVerified]), .blockedByCertificate)
    }

    func testDispatchDisabledAloneStillLetsThemSlideOpen() {
        XCTAssertEqual(status(isAvailable: false, reasons: [.dispatchDisabled]), .canOpen)
        XCTAssertEqual(status(isAvailable: false, reasons: [.dispatchDisabled, .offline]), .canOpen)
    }

    func testOfflineWhileSwitchedOnIsNotAccepting() {
        XCTAssertEqual(status(isAvailable: true, reasons: [.offline]), .notOnline)
    }

    func testUnrecognizedOrMissingReasonWhileSwitchedOnIsNotAccepting() {
        XCTAssertEqual(status(isAvailable: true, reasons: [.unknown]), .unavailable(explanation: "摘要说明"))
        XCTAssertEqual(status(isAvailable: true, reasons: []), .unavailable(explanation: "摘要说明"))
        XCTAssertEqual(status(isAvailable: true, canDispatch: nil, reasons: []), .unavailable(explanation: "摘要说明"))
    }

    // MARK: - 接单中

    func testOnlyAConfirmedDispatchCountsAsAccepting() {
        XCTAssertEqual(status(isAvailable: true, canDispatch: true), .accepting)
        XCTAssertFalse(status(isAvailable: true, reasons: [.offline]).isAccepting)
        XCTAssertFalse(status(isAvailable: true, hasSummary: false, canDispatch: nil).isAccepting)
    }

    func testSwitchedOffNeverCountsAsAcceptingEvenWithAStaleSummary() {
        XCTAssertEqual(status(isAvailable: false, canDispatch: true), .canOpen)
    }

    func testMissingOrStaleSummaryIsConfirmingNotAccepting() {
        XCTAssertEqual(status(isAvailable: true, hasSummary: false, canDispatch: nil), .confirming)
        XCTAssertEqual(status(isAvailable: true, reasons: [.dispatchDisabled, .offline]), .confirming)
    }

    func testSliderOpensOnlyForARegisteredVolunteerWithNothingBlockingThem() {
        XCTAssertTrue(VolunteerAvailabilityStatus.canOpen.allowsOpening(isRegistrationComplete: true))
        XCTAssertFalse(VolunteerAvailabilityStatus.canOpen.allowsOpening(isRegistrationComplete: false))
        XCTAssertFalse(VolunteerAvailabilityStatus.blockedByCertificate.allowsOpening(isRegistrationComplete: true))
        XCTAssertFalse(VolunteerAvailabilityStatus.blockedByTraining.allowsOpening(isRegistrationComplete: true))
    }

    func testOnlyQualificationReasonsBlockOpening() {
        XCTAssertTrue(VolunteerAvailabilityStatus.blockedByCertificate.blocksOpening)
        XCTAssertTrue(VolunteerAvailabilityStatus.blockedByTraining.blocksOpening)
        XCTAssertFalse(VolunteerAvailabilityStatus.canOpen.blocksOpening)
        XCTAssertFalse(VolunteerAvailabilityStatus.notOnline.blocksOpening)
    }

    // MARK: - 说明文案

    func testEveryBlockedStateNamesTheReasonAndWhereToGo() {
        let cases: [(VolunteerCertificateDisplayState, String)] = [
            (.notSubmitted, "还没上传证书"),
            (.pending, "证书审核中"),
            (.rejected, "证书未通过审核"),
            (.statusUnavailable, "还没通过资质审核")
        ]
        for (certificate, expected) in cases {
            let notice = VolunteerAvailabilityStatus.blockedByCertificate
                .notice(certificate: certificate, isAlternativeIdentityPath: false)
            XCTAssertEqual(notice?.title, "暂不能接单")
            XCTAssertEqual(notice?.detail, "\(expected)，点这里看进度")
        }
        XCTAssertEqual(
            VolunteerAvailabilityStatus.blockedByTraining
                .notice(certificate: .approved, isAlternativeIdentityPath: false)?.detail,
            "还没完成必修培训，点这里看进度"
        )
    }

    func testAlternativePathIsNeverToldAboutACertificate() {
        let notice = VolunteerAvailabilityStatus.blockedByCertificate
            .notice(certificate: .notSubmitted, isAlternativeIdentityPath: true)
        XCTAssertEqual(notice?.detail, "还没上传身份材料，点这里看进度")
    }

    func testAcceptingAndCanOpenHaveNothingToExplain() {
        XCTAssertNil(VolunteerAvailabilityStatus.accepting.notice(certificate: .approved, isAlternativeIdentityPath: false))
        XCTAssertNil(VolunteerAvailabilityStatus.canOpen.notice(certificate: .approved, isAlternativeIdentityPath: false))
    }

    func testNoNoticeClaimsToBeAcceptingOrders() {
        let states: [VolunteerAvailabilityStatus] = [
            .blockedByCertificate, .blockedByTraining, .confirming, .notOnline,
            .unavailable(explanation: "摘要说明")
        ]
        for state in states {
            let notice = state.notice(certificate: .pending, isAlternativeIdentityPath: false)
            XCTAssertNotNil(notice, "\(state) 必须说明原因")
            XCTAssertFalse(notice?.spoken.contains("接单中") ?? true, "\(state) 不许说接单中")
        }
    }

}

/// 总进度不把没做完的事说成做完了。
final class VolunteerReadinessProgressTests: XCTestCase {
    private typealias Reason = VolunteerDispatchNotAvailableReason

    private let faceApproved = VolunteerRegistrationStatus(
        registrationCompleted: true,
        canAcceptOrders: false,
        idVerifyStatus: "APPROVED",
        faceVerifyStatus: "APPROVED"
    )

    private func progress(
        registration: VolunteerRegistrationStatus?,
        certificate: VolunteerCertificateDisplayState = .notSubmitted,
        reason: String? = nil,
        dispatchReasons: [Reason]? = [.notVerified, .trainingIncomplete]
    ) -> VolunteerReadinessProgress {
        VolunteerReadinessProgress.resolve(
            registration: registration,
            certificate: certificate,
            certificateRejectionReason: reason,
            dispatchReasons: dispatchReasons
        )
    }

    private func step(_ kind: VolunteerReadinessProgress.StepKind, in progress: VolunteerReadinessProgress) -> VolunteerReadinessProgress.Step {
        progress.steps.first { $0.kind == kind }!
    }

    func testFreshlyVerifiedNewcomerStillHasThreeStepsLeft() {
        let result = progress(registration: faceApproved)

        XCTAssertEqual(result.steps.map(\.kind), [.identity, .face, .certificate, .review, .training])
        XCTAssertEqual(result.steps.map(\.state), [.done, .done, .actionNeeded, .waiting, .actionNeeded])
        XCTAssertEqual(result.title, "还差 3 步才能接单")
        XCTAssertNil(result.subtitle, "标题已经说完了，不再写一行")
        XCTAssertFalse(result.spoken.contains("注册完成"))
        XCTAssertFalse(result.spoken.contains("无需课程"))
    }

    func testCertificateAndTrainingStepsPointToWhereToResolveThem() {
        let result = progress(registration: faceApproved)

        XCTAssertEqual(step(.certificate, in: result).destination, .certificateUpload)
        XCTAssertEqual(step(.training, in: result).destination, .training)
        XCTAssertNil(step(.review, in: result).destination)
    }

    func testPendingReviewCountsTheCertificateAsSubmittedButNotTheReview() {
        let result = progress(registration: faceApproved, certificate: .pending, dispatchReasons: [.notVerified])

        XCTAssertEqual(step(.certificate, in: result).state, .done)
        XCTAssertEqual(step(.review, in: result).state, .inReview)
        XCTAssertEqual(result.remainingCount, 1)
    }

    func testEverythingDoneTellsThemToOpenTheSwitch() {
        let result = progress(registration: faceApproved, certificate: .approved, dispatchReasons: [.dispatchDisabled])

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.title, "接单前的步骤都完成了")
        XCTAssertEqual(result.subtitle, VolunteerAvailabilityCopy.goOpenItHint)
    }

    /// 开关开着只是不在线时，再叫他去开开关就是错的引导。
    func testOpenTheSwitchIsOnlySaidWhenTheSwitchIsOff() {
        let online = progress(registration: faceApproved, certificate: .approved, dispatchReasons: [.offline])

        XCTAssertTrue(online.isComplete)
        XCTAssertNil(online.subtitle)
    }

    /// 证书接口说通过、派单摘要说没通过：不能说都完成了，否则他在滑块和这一页之间来回打转。
    func testApprovedCertificateThatDispatchStillRejectsIsNotCountedAsDone() {
        let result = progress(registration: faceApproved, certificate: .approved, dispatchReasons: [.notVerified])

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(step(.review, in: result).state, .unknown)
    }

    func testApprovedGuidanceDoesNotClaimTheyCanAcceptOrdersYet() {
        for alternative in [false, true] {
            let line = VolunteerCertificateDisplayState.approved.guidance(isAlternativeIdentityPath: alternative)
            XCTAssertFalse(line.contains("现在可以接单"), line)
            XCTAssertTrue(line.contains("完成必修培训后"), line)
        }
    }

    func testRejectionWithoutAReasonNeverLeavesTheStepBlank() {
        let status = VolunteerRegistrationStatus(
            registrationCompleted: false,
            idVerifyStatus: "REJECTED",
            faceVerifyStatus: "REJECTED"
        )
        let result = progress(registration: status)

        XCTAssertEqual(step(.identity, in: result).detail, "暂时看不到具体原因。请核对后重新提交身份信息。")
        XCTAssertEqual(step(.face, in: result).detail, "暂时看不到具体原因。请重新认证。")
    }

    func testRejectionShowsTheBackendReason() {
        let result = progress(registration: faceApproved, certificate: .rejected, reason: " 证书照片看不清 ")

        XCTAssertEqual(step(.review, in: result).state, .rejected)
        XCTAssertEqual(step(.review, in: result).detail, "未通过原因：证书照片看不清")
        XCTAssertEqual(step(.certificate, in: result).destination, .certificateUpload)
    }

    func testRejectionWithoutAReasonSaysSoAndNamesThePartner() {
        for blank in [nil, "", "  "] as [String?] {
            let detail = step(.review, in: progress(registration: faceApproved, certificate: .rejected, reason: blank)).detail
            XCTAssertEqual(detail, VolunteerCertificateCopy.rejectionFallback)
        }
        XCTAssertTrue(VolunteerCertificateCopy.rejectionFallback.contains("一束光助盲跑团"))
    }

    func testIdentityAndFaceRejectionsShowTheBackendReason() {
        let status = VolunteerRegistrationStatus(
            registrationCompleted: false,
            stepDetails: VolunteerRegistrationStepDetails(
                idVerifyStatus: "REJECTED",
                faceVerifyStatus: "REJECTED",
                idVerifyRejectionReason: "身份证姓名与号码不一致，请核对后重新提交",
                faceVerifyRejectionReason: "未检测到人脸"
            )
        )
        let result = progress(registration: status)

        XCTAssertEqual(step(.identity, in: result).state, .rejected)
        XCTAssertEqual(step(.identity, in: result).detail, "身份证姓名与号码不一致，请核对后重新提交")
        XCTAssertEqual(step(.face, in: result).state, .rejected)
        XCTAssertEqual(step(.face, in: result).detail, "未检测到人脸")
        XCTAssertEqual(status.identityRejectionNotice, "身份信息未通过核验：身份证姓名与号码不一致，请核对后重新提交")
        XCTAssertEqual(status.faceRejectionNotice, "活体认证未通过：未检测到人脸")
    }

    func testRejectionNoticesStayQuietWhenNothingWasRejected() {
        XCTAssertNil(faceApproved.identityRejectionNotice)
        XCTAssertNil(faceApproved.faceRejectionNotice)
    }

    func testDecliningFaceIsNotShownAsFailureAndAsksForIdentityMaterial() {
        let declined = VolunteerRegistrationStatus(
            registrationCompleted: true,
            idVerifyStatus: "APPROVED",
            faceVerifyStatus: "DECLINED"
        )
        let result = progress(registration: declined)

        XCTAssertEqual(step(.face, in: result).state, .done)
        XCTAssertEqual(step(.face, in: result).statusText, "已改用人工审核")
        XCTAssertEqual(step(.certificate, in: result).title, "身份材料")
        XCTAssertFalse(result.spoken.contains("一束光"), "替代路径不要证书，不能提一束光证书")
    }

    func testLegacyAccountsWithoutAnIdentityResultCountAsDoneOnceRegistered() {
        let legacy = VolunteerRegistrationStatus(
            registrationCompleted: true,
            idVerifyStatus: "NOT_STARTED",
            faceVerifyStatus: "APPROVED"
        )
        XCTAssertEqual(step(.identity, in: progress(registration: legacy)).state, .done)
    }

    func testAnyFailedReadShowsUnknownAndClaimsNothing() {
        let noRegistration = progress(registration: nil)
        XCTAssertEqual(step(.identity, in: noRegistration).state, .unknown)
        XCTAssertEqual(step(.face, in: noRegistration).state, .unknown)

        let noCertificate = progress(registration: faceApproved, certificate: .statusUnavailable)
        XCTAssertEqual(step(.certificate, in: noCertificate).state, .unknown)
        XCTAssertEqual(step(.review, in: noCertificate).state, .unknown)

        let noSummary = progress(registration: faceApproved, certificate: .approved, dispatchReasons: nil)
        XCTAssertEqual(step(.training, in: noSummary).state, .unknown)
        XCTAssertFalse(noSummary.isComplete)
        XCTAssertEqual(noSummary.title, "暂时无法确认全部进度")
    }

    // MARK: - 证书文案

    func testCertificateCopyNamesTheIssuerAndInventsNoContactDetails() {
        XCTAssertEqual(VolunteerCertificateCopy.requirement, "请上传一束光助盲跑团颁发的证书。")
        XCTAssertEqual(VolunteerCertificateCopy.noCertificateHelp, "还没有证书？请联系一束光助盲跑团。")
        // 只看 ASCII：`isNumber` 会把「一束光」的「一」也算成数字。
        let digits = VolunteerCertificateCopy.noCertificateHelp.filter { $0.isASCII && $0.isNumber }
        XCTAssertTrue(digits.isEmpty, "一束光的联系方式还没有，文案里不许出现号码")
    }

    func testRejectedGuidanceOnTheCertificatePageCarriesTheReason() {
        XCTAssertEqual(
            VolunteerCertificateDisplayState.rejected.guidance(isAlternativeIdentityPath: false, rejectionReason: "证书已过期"),
            "资质证书未通过审核，当前无法接单。未通过原因：证书已过期。修改后可以重新上传。"
        )
        XCTAssertEqual(
            VolunteerCertificateDisplayState.rejected.guidance(isAlternativeIdentityPath: false, rejectionReason: nil),
            "资质证书未通过审核，当前无法接单。\(VolunteerCertificateCopy.rejectionFallback)"
        )
        XCTAssertEqual(
            VolunteerCertificateDisplayState.pending.guidance(isAlternativeIdentityPath: false, rejectionReason: "旧原因"),
            VolunteerCertificateDisplayState.pending.guidanceMessage,
            "不在驳回态时不许带出旧原因"
        )
    }

    /// 后端还没给这个字段时必须能解码，给了之后要读得到。
    func testVerificationStatusDecodesWithAndWithoutARejectionReason() throws {
        let decoder = JSONDecoder()
        let without = try decoder.decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"status":"REJECTED"}"#.utf8)
        )
        XCTAssertNil(without.rejectionReason)
        let with = try decoder.decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"status":"REJECTED","rejectionReason":"证书已过期"}"#.utf8)
        )
        XCTAssertEqual(with.rejectionReason, "证书已过期")
    }
}
