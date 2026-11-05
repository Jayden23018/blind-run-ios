import Combine
import CoreLocation
import Foundation

// MARK: - Blind Booking ViewModel

@MainActor
final class BlindBookingViewModel: ObservableObject {
    @Published var currentStep: BlindBookingGuidedStep = .startPoint
    /// 用户设的默认出发地点。语音重说时用它恢复起点。
    var defaultStartPlace: ResolvedPlace?
    @Published var placeSearchKeyword = ""
    @Published var placeSearchResults: [ResolvedPlace] = []
    @Published var selectedStartPlace: ResolvedPlace?
    @Published var currentResolvedPlace: ResolvedPlace?
    /// `currentResolvedPlace` 那次解析所用定位样本的精度，只在差于 50 米时有值（#373）。
    @Published var currentLocationAccuracyMeters: Double?
    var hasAnnouncedWeakStartPointAccuracy = false
    var hasSpokenStartPointPrivacyNotice = false // 见 `BlindBookingViewModel+StartPointPrivacy.swift`
    /// 本次预约的终点。**只有语音会写它** —— 表单向导没有终点输入，产品上终点是纯可选槽位，
    /// 而在表单里再加一段 POI 搜索 + 候选列表，对看不见屏幕的人是又一段同样长的交互。
    ///
    /// `nil` = 用户未指定，任何读回与展示都**一个字不提终点**（不是「原路返回起点」）。
    @Published var endPlace: BookingEndPlace?
    /// 起点的**朗读**形态（后端 `addressShort`，只有 POI 名）。`nil` = 念完整地址。
    ///
    /// **只喂读回。** 下单请求（`startAddress`）、屏幕上的出发地点行、志愿者看到的地址，
    /// 一律仍是 `resolvedStartLocationDescription` 那份完整地址 —— 契约里两者分工明确：
    /// 念的是名字（听得出对不对），下单带的是门牌号（走得到）。
    ///
    /// 生命周期与 `selectedStartPlace` 绑死：`selectPlace` 一律先清空它，
    /// 只有 `applyVoiceResolvedStartPlace` 会在之后写回。所以「屏幕上是 A、耳朵里是 B」构造不出来。
    @Published var voiceStartAddressShort: String?
    @Published var startLocationDescription = ""
    @Published var appointmentTime = Date()
    @Published var routeNotes = ""
    /// 表单那个选择器的绑定。**它只是 UI**，真正下单用的分钟数看 `resolvedDurationMinutes`。
    @Published var duration: BookingDurationOption = .none {
        didSet {
            // 手动改了选择器就以选择器为准 —— 用户刚在屏幕上做的动作，优先级高于上一轮语音。
            guard duration != oldValue else { return }
            exactDurationMinutes = duration.minutes
        }
    }
    /// 语音说出来的**精确**分钟数。
    ///
    /// 枚举只有 6 个档位、最大 120 分钟，而契约允许 10–300（`api_spec.yaml:2549`）。
    /// 枚举存在的理由是「选择器需要有限选项」，而**说话的人不需要选择器** ——
    /// 让语音迁就一个为触屏设计的控件，等于把用户说的「三个小时」改成两小时。
    /// 2026-08-06 用户报的「时间上只有两个小时这样的限制」就是这条。
    @Published var exactDurationMinutes: Int?
    @Published var pacePreference: PacePreference = .noPreference
    @Published var routePreference: RoutePreference = .noPreference
    /// 本次是否携带导盲犬。**三态，不是布尔** —— `nil` 与 `false` 在下单时的含义完全不同：
    ///
    /// - `nil` —— 没提。请求里不传该字段，后端回落 `BlindProfile.hasGuideDog` 档案默认值。
    /// - `false` —— 本次明确不带（语音说「今天不带导盲犬」）。原样传。
    ///
    /// 这个字段进派单的**硬过滤**（不接受导盲犬的志愿者被直接踢出候选池）。
    /// 把 `false` 塌缩成 `nil`，档案里登记了导盲犬的用户说了「今天不带」也会按"带"派单，
    /// 候选池被无声缩小 —— 而盲人全程听不出来。表单那个开关只能表达 `nil`/`true`
    /// （关掉 = 没提），语音是唯一能说出 `false` 的入口。
    @Published var hasGuideDogThisRun: Bool?
    @Published var specialNotes = ""
    @Published var isSubmitting = false
    @Published var isResolvingStartLocation = false
    @Published var isSearchingPlaces = false
    @Published var errorMessage: String?
    @Published var placeMessage: String?
    @Published var searchResultFocusID: String?
    @Published var auxiliaryMapCenter: CLLocationCoordinate2D?
    @Published var auxiliaryMapPlace: ResolvedPlace?

    private(set) weak var appState: AppState?
    private(set) weak var locationService: LocationService?
    weak var placeSearchProvider: (any PlaceSearchProviding)?
    private(set) var speechService: SpeechService?
    static let auxiliaryMapMarkerRefreshDistanceMeters: CLLocationDistance = 30

    func configure(
        appState: AppState,
        locationService: LocationService,
        speechService: SpeechService,
        amapGeocodingService: AMapGeocodingService
    ) {
        self.appState = appState
        self.locationService = locationService
        self.speechService = speechService
        self.placeSearchProvider = amapGeocodingService

        reseedAppointmentTimeIfExpired()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DAYTIME_APPOINTMENT"] == "1" {
            appointmentTime = Self.uiTestDaytimeAppointment(now: Date())
        }
        #endif
    }

    #if DEBUG
    /// UI 测试用的开跑时间：北京时间「明天 10:00」，与运行时刻无关（#418）。
    ///
    /// 默认值「现在 + 31 分钟」在北京时间约 20:30 之后跑，整段行程会撞上夜间窗口，
    /// 下单冒烟因此「白天绿、半夜红」。真机上语音向导会把页面直接切到审阅步，
    /// 绕过时间那一步的逐步检查，于是用例看到的是一枚亮不起来的「提交预约」。
    /// 明天 10:00 距现在落在 (10, 34] 小时，过得了提前量、7 天上限和夜间窗口三道。
    nonisolated static func uiTestDaytimeAppointment(now: Date, calendar: Calendar = .aidRunBackend) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
    #endif

    /// 演示坐标能否当作下单起点。
    ///
    /// 兜底坐标是北京一个固定点。它落到云端就是把一个可能在上海的盲人约到另一个城市；
    /// 更隐蔽的是 `resolvedStartPlace` 因为总有兜底值而**永不为 nil**，
    /// `.startPoint` 这道门槛于是恒真 —— 一道写好的门槛在生产里是死代码。
    ///
    /// 放行的只有两处，它们都不会产生真实订单：不发网络请求的 Mock 通道，
    /// 以及显式打开了演示定位的 UI 测试。正式通道一律走「请选择出发地点」。
    var allowsDemoFallbackAsStartPoint: Bool {
        if appState?.currentEnvironment.isMock == true { return true }
        return locationService?.isDemoLocationForcedForTesting == true
    }

    func bookingCoordinate(from locationService: LocationService) -> CLLocationCoordinate2D {
        guard let currentLocation = locationService.currentLocation else {
            // 调用方已用 `allowsDemoFallbackAsStartPoint` 过滤过，走到这里只可能是 Mock 或 UI 测试。
            return locationService.effectiveLocation
        }
        return BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: currentLocation, system: .wgs84Device, source: .device)
        )?.coordinate ?? currentLocation
    }

    #if DEBUG
    func configureForTesting(
        placeSearchProvider: (any PlaceSearchProviding)? = nil,
        speechService: SpeechService,
        locationService: LocationService? = nil,
        appState: AppState? = nil
    ) {
        self.placeSearchProvider = placeSearchProvider
        self.speechService = speechService
        self.locationService = locationService
        self.appState = appState
    }
    #endif

    func makeCreateOrderRequest() -> CreateOrderRequest? {
        guard let startPlace = resolvedStartPlace else { return nil }
        let plannedStartTime = DateFormatter.aidRunBackendLocalDateTime.string(from: appointmentTime)
        let plannedEndTime = DateFormatter.aidRunBackendLocalDateTime.string(from: plannedEndDate)

        return CreateOrderRequest(
            startLatitude: startPlace.latitude,
            startLongitude: startPlace.longitude,
            startAddress: resolvedStartLocationDescription,
            // 三项一律从 `endPlace` 取。坐标成对由 `BookingEndPlace.init` 保证，
            // 这里不再判一次 —— 判两次就有两份规则，迟早有一份忘了改。
            endAddress: endPlace?.address,
            endLatitude: endPlace?.latitude,
            endLongitude: endPlace?.longitude,
            plannedStartTime: plannedStartTime,
            plannedEndTime: plannedEndTime,
            expectedDurationMinutes: resolvedDurationMinutes,
            pacePreference: pacePreference == .noPreference ? nil : pacePreference,
            routePreference: routePreference == .noPreference ? nil : routePreference,
            routeNotes: routeNotes.nilIfBlank,
            // 三态原样透传。⚠️ 不要写成 `hasGuideDogThisRun ?? false` 或
            // `hasGuideDogThisRun == true ? true : nil` —— 前者把"没提"变成"明确不带"，
            // 后者把"明确不带"变成"没提"，两个方向都会静默改掉派单候选池。
            hasGuideDogThisRun: hasGuideDogThisRun,
            specialNotes: specialNotes.nilIfBlank
        )
    }
    // 提交（`submit()`）在 `BlindBookingViewModel+Submit.swift`。
}
