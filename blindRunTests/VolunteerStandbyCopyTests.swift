import XCTest
@testable import blindRun

/// 待命接单的文案要如实说「保持 App 开着才收得到新邀请」（#654，审计 V-1、F-13）。
///
/// 机制：待命时只在 App 开着时上报位置，后台定位只在出发到跑步结束这段打开；后端位置 30 秒过期就出候选池，
/// 邀请的推送只发给池里的人。负责人 2026-11-04 定上线前不改机制，界面、同意页、通知说明如实写。
/// 这组用例钉住「每一处都说了」和「哪一处都不再说反话」。
final class VolunteerStandbyCopyTests: XCTestCase {

    func testVolunteerLocationConsentNoLongerClaimsLockedScreenLocatingWhileStandingBy() {
        let first = PrivacyConsentPurpose.volunteerLocationTrack.disclosures[0]
        XCTAssertFalse(first.contains("锁屏后仍在定位"), "待命时后台定位没开过，同意页不能这么写")
        XCTAssertTrue(first.contains("只在助盲跑开着时"), "要写明派单定位只在 App 开着时进行")
        XCTAssertTrue(first.contains("收不到新邀请"), "要写明锁屏后的后果")
    }

    func testVolunteerPushExplanationDoesNotPromiseInvitesWhileAppIsClosed() {
        let text = PushPermissionCopy.explanation(for: .volunteer)
        let promise = text.split(separator: "。").first { $0.contains("即使没打开") }
        XCTAssertNotNil(promise, "订单变化的提醒仍然没打开也会到，这半句要留着")
        XCTAssertFalse(promise?.contains("邀请") ?? true, "新邀请锁屏后收不到，不能放进「没打开也会提醒」")
        XCTAssertTrue(text.contains("保持助盲跑开着"))
    }

    func testEveryStandbySurfaceSaysKeepTheAppOpen() {
        let note = VolunteerAvailabilityCopy.keepAppOpenNote
        let surfaces: [(String, String)] = [
            ("接单页空态", VolunteerDispatchHubCopy.emptySubtitle),
            ("首页派单卡与滑块读屏", VolunteerDispatchSummaryResponse.onlineWaitingText),
            ("滑块读屏提示", VolunteerAvailabilityCopy.slideHint)
        ]
        for (name, text) in surfaces {
            XCTAssertTrue(text.contains(note), "\(name) 没说要保持 App 开着：\(text)")
        }
        XCTAssertFalse(VolunteerDispatchHubCopy.emptySubtitle.contains("你的空闲时间里有合适的陪跑，会邀请你"))
    }
}
