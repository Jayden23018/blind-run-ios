import CoreLocation
import XCTest
@testable import blindRun

/// #667：受控公开的开放范围（`GET /api/config/rules` 的 `launchScope`）与三个建单拒绝码。
@MainActor
final class LaunchScopeTests: XCTestCase {

    // MARK: - 解码

    func testDecodesLaunchScopeFromTheRulesPayload() throws {
        let json = #"""
        {"lateCancelWindowHours":12,"volunteerOrderAutoOpenLeadMinutes":120,
         "launchScope":{"acceptingOrders":true,"areaRestricted":true,"dutyHoursRestricted":true,
           "areaHint":"目前只开放深圳市、杭州市","dutyHoursHint":"可预约的开跑时间是周一到周五 18:00 到 21:00",
           "openAreas":[{"name":"深圳市","southLat":22.4,"northLat":22.9,"westLng":113.7,"eastLng":114.6}],
           "dutyWindows":[{"days":["MONDAY","FRIDAY","SOMEDAY"],"start":"18:00","end":"21:00"}]}}
        """#
        let decoded = try JSONDecoder().decode(RuleParamsResponse.self, from: Data(json.utf8))
        let scope = try XCTUnwrap(decoded.launchScope)
        XCTAssertTrue(scope.acceptingOrders)
        XCTAssertEqual(scope.areaHint, "目前只开放深圳市、杭州市")
        XCTAssertEqual(scope.openAreas?.first?.name, "深圳市")
        XCTAssertEqual(scope.dutyWindows?.first?.days, ["MONDAY", "FRIDAY", "SOMEDAY"], "不认识的星期名不许让整条失败")
    }

    /// 旧后端没有这个字段；下发了但形状不对也不许把另外两个规则参数一起带崩。
    func testMissingOrMalformedLaunchScopeKeepsTheOtherRuleValues() throws {
        let old = try JSONDecoder().decode(
            RuleParamsResponse.self, from: Data(#"{"lateCancelWindowHours":6}"#.utf8)
        )
        XCTAssertNil(old.launchScope)
        XCTAssertEqual(old.lateCancelWindowHours, 6)

        let broken = try JSONDecoder().decode(
            RuleParamsResponse.self, from: Data(#"{"lateCancelWindowHours":6,"launchScope":"NONE"}"#.utf8)
        )
        XCTAssertNil(broken.launchScope)
        XCTAssertEqual(broken.lateCancelWindowHours, 6)
        XCTAssertEqual(BookingLaunchAvailability(broken.launchScope), .open, "读不出来就放行，后端兜底")
    }

    /// 列表读不出来时布尔和提示句照用，只是不判「在不在范围里」。
    func testUnreadableAreaListStillShowsTheHintWithoutGuessingInsideOrOutside() throws {
        let json = #"{"acceptingOrders":true,"areaRestricted":true,"dutyHoursRestricted":false,"areaHint":"目前只开放深圳市","openAreas":[{"name":"深圳市"}],"dutyWindows":[]}"#
        let scope = try JSONDecoder().decode(LaunchScopeResponse.self, from: Data(json.utf8))
        XCTAssertNil(scope.openAreas)
        XCTAssertNil(scope.containsStart(latitude: 0, longitude: 0))
        XCTAssertEqual(scope.areaNotice(latitude: 0, longitude: 0), "目前只开放深圳市")
    }

    // MARK: - 范围判定

    /// 四条边都算在内；差一点点就在外。
    func testOpenAreaEdgesAreInclusive() {
        let scope = restricted()
        XCTAssertEqual(scope.containsStart(latitude: 22.4, longitude: 113.7), true, "西南角")
        XCTAssertEqual(scope.containsStart(latitude: 22.9, longitude: 114.6), true, "东北角")
        XCTAssertEqual(scope.containsStart(latitude: 22.9001, longitude: 114.0), false)
        XCTAssertEqual(scope.containsStart(latitude: 30.27, longitude: 120.15), true, "第二块矩形（杭州）")
    }

    /// 按北京时间的星期与分钟比，两端都含。2026-11-06 是星期五，11-07 是星期六。
    func testDutyWindowEndsAreInclusiveByMinute() {
        let scope = restricted()
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-06T18:00:00")), true, "起点")
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-06T21:00:00")), true, "终点")
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-06T21:00:59")), true, "按分钟比，21:00 这一分钟都算")
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-06T21:01:00")), false)
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-06T17:59:00")), false)
        XCTAssertEqual(scope.admitsStart(beijing("2026-11-07T19:00:00")), false, "星期六不在时段里")
    }

    /// 跨午夜的时段契约没定义：不判「在不在」，只念后端那句。
    func testOvernightWindowIsNotJudged() {
        let scope = LaunchScopeResponse(
            acceptingOrders: true, areaRestricted: false, dutyHoursRestricted: true, dutyHoursHint: "可预约的开跑时间是每天 20:00 到 01:00",
            dutyWindows: [.init(days: ["FRIDAY"], start: "20:00", end: "01:00")]
        )
        XCTAssertNil(scope.admitsStart(beijing("2026-11-06T23:00:00")))
        XCTAssertEqual(scope.dutyHoursNotice(start: beijing("2026-11-06T23:00:00")), "可预约的开跑时间是每天 20:00 到 01:00")
    }

    func testUnrestrictedScopeSaysNothingEvenWithEmptyLists() {
        let scope = LaunchScopeResponse(acceptingOrders: true, areaRestricted: false, dutyHoursRestricted: false)
        XCTAssertNil(scope.areaNotice(latitude: 1, longitude: 1))
        XCTAssertNil(scope.dutyHoursNotice(start: beijing("2026-11-07T03:00:00")))
        XCTAssertEqual(BookingLaunchAvailability(scope), .open)
    }

    /// 范围内只念后端那句；范围外在前面说一句「不在范围内」。城市名与时段只来自后端。
    func testStepNoticesUseTheServerHintAndOnlyPrefixWhenOutside() {
        let scope = restricted()
        XCTAssertEqual(scope.areaNotice(latitude: 22.5, longitude: 114.0), "目前只开放深圳市、杭州市")
        XCTAssertEqual(scope.areaNotice(latitude: nil, longitude: nil), "目前只开放深圳市、杭州市", "还没选出发点时只念提示")
        XCTAssertEqual(
            scope.areaNotice(latitude: 39.9, longitude: 116.4),
            LaunchScopeCopy.outsideAreaPrefix + "目前只开放深圳市、杭州市"
        )
        XCTAssertEqual(scope.dutyHoursNotice(start: beijing("2026-11-06T19:00:00")), "可预约的开跑时间是周一到周五 18:00 到 21:00")
        XCTAssertEqual(
            scope.dutyHoursNotice(start: beijing("2026-11-07T19:00:00")),
            LaunchScopeCopy.outsideDutyHoursPrefix + "可预约的开跑时间是周一到周五 18:00 到 21:00"
        )
    }

    func testClosedScopeShowsTheServerHintOrAGenericSentence() {
        let closed = LaunchScopeResponse(acceptingOrders: false, areaRestricted: true, dutyHoursRestricted: false, areaHint: "陪跑服务暂未开放")
        XCTAssertEqual(BookingLaunchAvailability(closed), .closed(notice: "陪跑服务暂未开放"))
        let silent = LaunchScopeResponse(acceptingOrders: false, areaRestricted: true, dutyHoursRestricted: false)
        XCTAssertEqual(BookingLaunchAvailability(silent), .closed(notice: LaunchScopeCopy.closedFallback))
    }

    // MARK: - 按账号读

    func testRuleParamsAreClearedWhenTheSessionEnds() async {
        let (appState, auth) = makeAuthAppState()
        auth.ruleParamsResult = .success(rules(restricted()))
        await appState.loadRuleParamsIfNeeded()
        XCTAssertNotNil(appState.ruleParamsResponse?.launchScope)

        appState.clearSession()
        XCTAssertNil(appState.ruleParamsResponse, "上一个账号的开放范围留给了下一个账号")

        appState.accessToken = "token-b"
        await appState.loadRuleParamsIfNeeded()
        XCTAssertEqual(auth.calls.filter { $0.hasPrefix("ruleParams") }.count, 2, "换账号后没有重新读")
    }

    /// 请求在路上时换了账号：回来的那份属于上一个账号，丢弃。
    func testRuleParamsReturningAfterAnAccountSwitchAreDiscarded() async {
        let (appState, auth) = makeAuthAppState()
        auth.ruleParamsResult = .success(rules(restricted()))
        auth.ruleParamsWillReturn = { appState.accessToken = "token-b" }
        await appState.loadRuleParamsIfNeeded()
        XCTAssertNil(appState.ruleParamsResponse)
    }

    /// 同一次登录里续期换 token：结果要留下。比 token 值的话，token 过期那次进入下单页读到的「暂未开放」会被丢掉。
    func testRuleParamsSurviveATokenRenewalInTheSameLogin() async {
        let (appState, auth) = makeAuthAppState()
        auth.ruleParamsResult = .success(rules(restricted()))
        auth.ruleParamsWillReturn = { appState.applyRenewedAccessToken("token-a-renewed") }
        await appState.loadRuleParamsIfNeeded()
        XCTAssertNotNil(appState.ruleParamsResponse?.launchScope)
    }

    func testForcedReloadReadsAgainEvenAfterASuccess() async {
        let (appState, auth) = makeAuthAppState()
        auth.ruleParamsResult = .success(rules(restricted()))
        await appState.loadRuleParamsIfNeeded()
        auth.ruleParamsResult = .success(rules(LaunchScopeResponse(acceptingOrders: false, areaRestricted: true, dutyHoursRestricted: false)))
        await appState.loadRuleParamsIfNeeded(force: true)
        XCTAssertEqual(BookingLaunchAvailability(appState.ruleParamsResponse?.launchScope), .closed(notice: LaunchScopeCopy.closedFallback))
    }

    // MARK: - 三个建单拒绝码

    func testEmptyServerMessageFallsBackToTheBackendDefaultSentence() {
        let error = APIError.serverError(ErrorResponse(code: "APPOINTMENT_OUTSIDE_DUTY_HOURS", message: ""))
        XCTAssertEqual(error.localizedMessage, LaunchScopeCopy.outsideDutyHoursFallback)
    }

    func testOutsideOpenAreaReadsTheServerMessageAndKeepsTheChoices() async {
        let message = "这个出发点不在开放范围内。目前只开放深圳市、杭州市，请换一个开放范围内的出发点"
        let form = makeSubmittingForm(rejectingWith: "ORDER_OUTSIDE_OPEN_AREA", message: message)
        let time = form.viewModel.appointmentTime

        let response = await form.viewModel.submit()

        XCTAssertNil(response)
        XCTAssertEqual(form.viewModel.errorMessage, message, "要原样显示后端 message，不换成通用的「下单失败」")
        XCTAssertTrue(form.speech.spokenHistoryForTesting.contains(message), "要原样念后端 message")
        XCTAssertEqual(form.viewModel.appointmentTime, time, "已选的内容不许丢")
        XCTAssertEqual(form.viewModel.specialNotes, "慢一点")
        XCTAssertNotNil(form.viewModel.selectedStartPlace)
    }

    func testOutsideDutyHoursReadsTheServerMessageAndKeepsTheChoices() async {
        let message = "这个时间没有值守人员，暂不接受预约。可预约的开跑时间是周一到周五 18:00 到 21:00，请换个时间"
        let form = makeSubmittingForm(rejectingWith: "APPOINTMENT_OUTSIDE_DUTY_HOURS", message: message)
        let place = form.viewModel.selectedStartPlace

        _ = await form.viewModel.submit()

        XCTAssertEqual(form.viewModel.errorMessage, message)
        XCTAssertTrue(form.speech.spokenHistoryForTesting.contains(message))
        XCTAssertEqual(form.viewModel.selectedStartPlace, place, "已选的内容不许丢")
        XCTAssertEqual(form.viewModel.specialNotes, "慢一点")
    }

    /// 暂不接受预约：入口闸门换成告知页并念后端这句；不把用户带去改地点或时间。
    func testServiceNotOpenSwitchesTheEntryToTheClosedNoticeWithTheServerMessage() async {
        let message = "陪跑服务暂未开放，现在还不能预约，开放后再来下单"
        let form = makeSubmittingForm(rejectingWith: "ORDER_SERVICE_NOT_OPEN", message: message)

        _ = await form.viewModel.submit()

        XCTAssertEqual(BookingLaunchAvailability(form.appState.ruleParamsResponse?.launchScope), .closed(notice: message))
        XCTAssertFalse(form.speech.spokenHistoryForTesting.contains(message), "告知页出现时会念，这里先念会被它切断")
    }

    // MARK: - 见面安排单

    func testMeetupPlanRejectionsLandOnTheMatchingBlockWithTheServerMessage() {
        let time = VolunteerMeetupPlanSubmitError.make(
            for: APIError.serverError(ErrorResponse(code: "APPOINTMENT_OUTSIDE_DUTY_HOURS", message: "可预约的开跑时间是周一到周五 18:00 到 21:00")),
            distanceFromOriginal: nil
        )
        XCTAssertEqual(time, VolunteerMeetupPlanSubmitError(slot: .time, message: "可预约的开跑时间是周一到周五 18:00 到 21:00"))

        let place = VolunteerMeetupPlanSubmitError.make(
            for: APIError.serverError(ErrorResponse(code: "ORDER_OUTSIDE_OPEN_AREA", message: "新集合点不在开放范围内，目前只开放深圳市")),
            distanceFromOriginal: 500
        )
        XCTAssertEqual(place, VolunteerMeetupPlanSubmitError(slot: .place, message: "新集合点不在开放范围内，目前只开放深圳市"))
    }

    // MARK: - 夹具

    private func restricted() -> LaunchScopeResponse {
        LaunchScopeResponse(
            acceptingOrders: true,
            areaRestricted: true,
            dutyHoursRestricted: true,
            areaHint: "目前只开放深圳市、杭州市",
            dutyHoursHint: "可预约的开跑时间是周一到周五 18:00 到 21:00",
            openAreas: [
                .init(name: "深圳市", southLat: 22.4, northLat: 22.9, westLng: 113.7, eastLng: 114.6),
                .init(name: "杭州市", southLat: 29.9, northLat: 30.6, westLng: 119.8, eastLng: 120.5)
            ],
            dutyWindows: [.init(days: ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY"], start: "18:00", end: "21:00")]
        )
    }

    private func rules(_ scope: LaunchScopeResponse) -> RuleParamsResponse {
        RuleParamsResponse(lateCancelWindowHours: 12, volunteerOrderAutoOpenLeadMinutes: 120, launchScope: scope)
    }

    private func beijing(_ text: String) -> Date {
        DateFormatter.aidRunBackendLocalDateTime.date(from: text)!
    }

    private func makeAuthAppState() -> (AppState, FakeAuthService) {
        let auth = FakeAuthService()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        addTeardownBlock { persistence.reset() }
        let appState = AppState(auth: auth, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token-a"
        return (appState, auth)
    }

    /// 下单 view model 的 `appState` / `locationService` 是 `weak`：整套依赖由用例持有，不能只活在 helper 里。
    private struct SubmittingForm {
        let viewModel: BlindBookingViewModel
        let speech: SpeechService
        let appState: AppState
        let location: LocationService
        let orders: FakeOrderService
    }

    /// 门槛全过、可以提交的下单 view model，后端用 `code` 拒绝这一单。
    private func makeSubmittingForm(rejectingWith code: String, message: String) -> SubmittingForm {
        let orders = FakeOrderService()
        orders.createOrderResult = .failure(APIError.serverError(ErrorResponse(code: code, message: message)))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        addTeardownBlock { persistence.reset() }
        let appState = AppState(orders: orders, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let speech = SpeechService()
        let location = LocationService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: speech, locationService: location, appState: appState)
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1", title: "人民广场", addressText: "上海市黄浦区人民广场",
            latitude: 31.2304, longitude: 121.4737, source: .manual
        )
        viewModel.appointmentTime = BookingTimeFixture.daytime()
        viewModel.specialNotes = "慢一点"
        XCTAssertTrue(viewModel.canSubmit, "前提：门槛全过")
        return SubmittingForm(viewModel: viewModel, speech: speech, appState: appState, location: location, orders: orders)
    }
}
