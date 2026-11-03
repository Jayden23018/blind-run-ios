import XCTest
@testable import blindRun

/// 版本比较与拦截判定（#526）。这里写错的后果是所有人进不了 App，所以「不拦」的分支逐项钉住。
@MainActor
final class AppUpdatePolicyTests: XCTestCase {
    private static let url = URL(string: "https://apps.apple.com/cn/app/aidrun")!
    private static let target = AppUpdateTarget(version: "1.2.0", url: url)

    private func requirements(
        min: String? = nil,
        latest: String? = nil,
        url: String? = "https://apps.apple.com/cn/app/aidrun"
    ) -> AppVersionResponse {
        AppVersionResponse(iosMinSupportedVersion: min, iosLatestVersion: latest, iosUpdateUrl: url)
    }

    // MARK: 版本比较

    func testEqualVersionsAreNotLower() throws {
        let version = try XCTUnwrap(AppVersionNumber("1.2.0"))
        XCTAssertFalse(version < version)
        XCTAssertEqual(version, try XCTUnwrap(AppVersionNumber("1.2.0")))
    }

    /// 工程的 `MARKETING_VERSION` 是两段，后端下发三段。逐元素比较数组时 `1.0` 会小于 `1.0.0`，所有人都会被拦。
    func testMissingTrailingSegmentCountsAsZero() throws {
        let short = try XCTUnwrap(AppVersionNumber("1.0"))
        let long = try XCTUnwrap(AppVersionNumber("1.0.0"))
        XCTAssertFalse(short < long)
        XCTAssertFalse(long < short)
        XCTAssertEqual(short, long)
    }

    func testOneStepLowerIsLower() throws {
        let lower = try XCTUnwrap(AppVersionNumber("1.2.0"))
        let higher = try XCTUnwrap(AppVersionNumber("1.2.1"))
        XCTAssertLessThan(lower, higher)
        XCTAssertFalse(higher < lower)
    }

    /// 按字符串比较时 `"1.10" < "1.9"`，结果相反。
    func testMultiDigitSegmentComparesAsANumber() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersionNumber("1.9")), try XCTUnwrap(AppVersionNumber("1.10")))
        XCTAssertLessThan(try XCTUnwrap(AppVersionNumber("1.9.9")), try XCTUnwrap(AppVersionNumber("1.10.0")))
    }

    func testEarlierSegmentOutranksLaterOnes() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersionNumber("1.9.9")), try XCTUnwrap(AppVersionNumber("2.0")))
    }

    func testUnparsableVersionsAreRejected() {
        let bad: [String?] = [nil, "", " ", "1.", ".1", "1..2", "v1.2", "1.2.0-beta", "+1.2", "-1.2", "１.２", "99999999999999999999.0"]
        for raw in bad {
            XCTAssertNil(AppVersionNumber(raw), "\(raw ?? "nil") 不该解析成版本号")
        }
    }

    // MARK: 版本判定

    func testVersionEqualToBothRequirementsIsUpToDate() {
        let verdict = AppUpdatePolicy.verdict(
            currentVersion: "1.2.0",
            requirements: requirements(min: "1.2.0", latest: "1.2.0")
        )
        XCTAssertEqual(verdict, .upToDate)
    }

    func testBelowMinimumIsRequired() {
        let verdict = AppUpdatePolicy.verdict(
            currentVersion: "1.1.9",
            requirements: requirements(min: "1.2.0", latest: "1.3.0")
        )
        XCTAssertEqual(verdict, .required(Self.target))
    }

    func testAtMinimumBelowLatestIsOptional() {
        let verdict = AppUpdatePolicy.verdict(
            currentVersion: "1.1.0",
            requirements: requirements(min: "1.1.0", latest: "1.2.0")
        )
        XCTAssertEqual(verdict, .optional(Self.target))
    }

    func testRequestFailureNeverBlocks() {
        XCTAssertEqual(AppUpdatePolicy.verdict(currentVersion: "1.0", requirements: nil), .upToDate)
    }

    func testEveryFieldNullNeverBlocks() {
        let verdict = AppUpdatePolicy.verdict(currentVersion: "1.0", requirements: requirements(url: nil))
        XCTAssertEqual(verdict, .upToDate)
    }

    func testMissingMinimumStillOffersLatest() {
        let verdict = AppUpdatePolicy.verdict(currentVersion: "1.0", requirements: requirements(latest: "1.2.0"))
        XCTAssertEqual(verdict, .optional(Self.target))
    }

    func testUnparsableMinimumDoesNotBlockAndLatestStillWorks() {
        let verdict = AppUpdatePolicy.verdict(
            currentVersion: "1.0",
            requirements: requirements(min: "2.0-rc", latest: "1.2.0")
        )
        XCTAssertEqual(verdict, .optional(Self.target))
    }

    func testUnparsableCurrentVersionNeverBlocks() {
        for current in [nil, "", "dev"] as [String?] {
            let verdict = AppUpdatePolicy.verdict(currentVersion: current, requirements: requirements(min: "9.0"))
            XCTAssertEqual(verdict, .upToDate)
        }
    }

    /// 全屏页没有更新按钮等于把人锁死，所以缺地址时最低版本也不拦。
    func testMissingUpdateUrlNeverBlocks() {
        let verdict = AppUpdatePolicy.verdict(currentVersion: "1.0", requirements: requirements(min: "2.0", url: nil))
        XCTAssertEqual(verdict, .upToDate)
    }

    func testOnlyHttpsUpdateUrlsAreOpened() {
        for bad in ["http://apps.apple.com/app", "itms-apps://apps.apple.com/app", "javascript:alert(1)", "", "https://"] {
            let verdict = AppUpdatePolicy.verdict(currentVersion: "1.0", requirements: requirements(min: "2.0", url: bad))
            XCTAssertEqual(verdict, .upToDate, bad)
        }
    }

    // MARK: 呈现判定

    func testRequiredShowsTheGateOnlyWhenThereIsKnownToBeNoOrder() {
        XCTAssertEqual(
            AppUpdatePolicy.presentation(verdict: .required(Self.target), orderPresence: .none, dismissedVersion: nil),
            .requiredGate(Self.target)
        )
    }

    func testRequiredNeverCoversAnOrderOrAnUnknownState() {
        for presence in [AppUpdateOrderPresence.active, .unknown] {
            XCTAssertEqual(
                AppUpdatePolicy.presentation(verdict: .required(Self.target), orderPresence: presence, dismissedVersion: nil),
                .none
            )
        }
    }

    /// 强制更新不能靠关闭绕过：记录里有这个版本时全屏页照样出现。
    func testDismissedVersionDoesNotSuppressTheRequiredGate() {
        XCTAssertEqual(
            AppUpdatePolicy.presentation(verdict: .required(Self.target), orderPresence: .none, dismissedVersion: "1.2.0"),
            .requiredGate(Self.target)
        )
    }

    func testOptionalPromptStaysQuietDuringAnOrder() {
        for presence in [AppUpdateOrderPresence.active, .unknown] {
            XCTAssertEqual(
                AppUpdatePolicy.presentation(verdict: .optional(Self.target), orderPresence: presence, dismissedVersion: nil),
                .none
            )
        }
    }

    func testOptionalPromptHonoursTheDismissedVersionOnly() {
        XCTAssertEqual(
            AppUpdatePolicy.presentation(verdict: .optional(Self.target), orderPresence: .none, dismissedVersion: "1.2.0"),
            .none
        )
        XCTAssertEqual(
            AppUpdatePolicy.presentation(verdict: .optional(Self.target), orderPresence: .none, dismissedVersion: "1.1.0"),
            .optionalPrompt(Self.target)
        )
    }

    func testResponseDecodesWithAndroidFieldsAndNulls() throws {
        let json = """
        {"success":true,"data":{"iosMinSupportedVersion":"1.0.0","iosLatestVersion":null,"iosUpdateUrl":null,\
        "androidMinSupportedVersion":"1.0.0","androidLatestVersion":null,"androidUpdateUrl":null}}
        """
        let response = try APIPayloadDecoder.decodePayload(AppVersionResponse.self, from: Data(json.utf8), decoder: JSONDecoder())
        XCTAssertEqual(response.iosMinSupportedVersion, "1.0.0")
        XCTAssertNil(response.iosLatestVersion)
    }

    // MARK: 文案红线

    func testRequiredReasonSaysTheAppWillNotSendHelp() {
        let reason = AppUpdateCopy.requiredReason(currentVersion: "1.0", targetVersion: "1.2.0")
        XCTAssertTrue(reason.contains("App 不会代你发送求助"))
        XCTAssertTrue(reason.contains("1.0"))
        XCTAssertTrue(reason.contains("1.2.0"))
    }

    /// 两端在这一页都只能走本地拨号。标题固定是「紧急呼叫」，第一句说清 App 不会代你发送求助。
    func testUpdateGateCallContextIsLocalDialForEveryRole() {
        for role in [UserRole.blind, .volunteer, .unset, nil] as [UserRole?] {
            let message = EmergencyCallContext.updateRequired(role: role).dialogMessage
            XCTAssertTrue(message.contains("App 不会代你发送求助"), "\(String(describing: role))")
        }
        XCTAssertEqual(EmergencySafetyCopy.homeCallTitle, "紧急呼叫")
    }

    /// 这一页只在没有订单时出现。两端的判定在没有订单时都必须落到本地拨号，改了这里要回来看那一页。
    func testBothEndsResolveToLocalDialWithoutAnOrder() {
        for role in [UserRole.blind, .volunteer, .unset, nil] as [UserRole?] {
            XCTAssertEqual(BlindHomeSOSMode.resolve(order: nil, role: role), .localCall)
        }
        XCTAssertEqual(VolunteerOrderSOSMode.resolve(status: nil), .localCall)
    }

    func testUpdateGateCallContextFollowsTheRoleOfTheEntry() {
        XCTAssertFalse(EmergencyCallContext.updateRequired(role: .volunteer).appendsNoContactHint, "陪跑员的拨号单不列联系人")
        XCTAssertTrue(EmergencyCallContext.updateRequired(role: .blind).appendsNoContactHint)
    }
}
