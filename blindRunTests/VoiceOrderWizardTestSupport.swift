import CoreLocation
import XCTest
@testable import blindRun

/// 语音下单向导的状态机。录音那一段由 `SpeechInputService` 自己的用例覆盖，这里锁的是向导独有的三条
/// 规则：`needReask` 不推进、连续听不清要降级回表单、解析结果落到正确的表单字段。
@MainActor
protocol VoiceOrderWizardTestSupport: XCTestCase {}

extension VoiceOrderWizardTestSupport {
    // MARK: - Helpers

    /// 构造一条 `/voice/parse` 响应。默认值 = 「什么都没抽到、不用重问、没有表态」，
    /// 每个用例只写它真正关心的那几项，读起来才看得出这条用例在测什么。
    static func parseResponse(
        plannedStartTime: String? = nil,
        durationMinutes: Int? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        missing: [VoiceOrderMissingSlot] = [],
        needReask: Bool = false,
        ttsText: String = "好的，我记下了",
        endAddress: String? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        hasGuideDog: Bool? = nil,
        userIntent: VoiceUserIntent? = nil,
        correctionTarget: VoiceCorrectionTarget? = nil,
        correctionUnclear: Bool = false,
        candidates: [AddressCandidate] = [],
        addressUnresolved: Bool = false,
        partialStartTime: VoicePartialStartTime? = nil
    ) -> ParseVoiceOrderResponse {
        ParseVoiceOrderResponse(
            plannedStartTime: plannedStartTime,
            durationMinutes: durationMinutes,
            address: address,
            latitude: latitude,
            longitude: longitude,
            missing: missing,
            needReask: needReask,
            ttsText: ttsText,
            endAddress: endAddress,
            endLatitude: endLatitude,
            endLongitude: endLongitude,
            endAddressUnresolved: endAddress == nil ? nil : (endLatitude == nil),
            hasGuideDog: hasGuideDog,
            userIntent: userIntent,
            correctionTarget: correctionTarget,
            correctionUnclear: correctionUnclear,
            candidates: candidates,
            addressUnresolved: addressUnresolved,
            partialStartTime: partialStartTime
        )
    }

    /// 一条候选。默认坐标落在深圳南山区 —— 就是用户报这个 bug 的那片地方。
    static func candidate(
        _ name: String,
        address: String? = nil,
        latitude: Double = 22.5333,
        longitude: Double = 113.9300
    ) -> AddressCandidate {
        AddressCandidate(
            name: name, address: address, adname: "南山区", business: nil,
            distanceMeters: 400, latitude: latitude, longitude: longitude
        )
    }

    static func date(hoursFromNow hours: Double) -> Date {
        Date().addingTimeInterval(3600 * hours)
    }

    static func backendTime(hoursFromNow hours: Double) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: date(hoursFromNow: hours))
    }

    func makeWizard(
        stub: VoiceOrderAPIClientStub,
        bookingViewModel: BlindBookingViewModel? = nil,
        speechService: SpeechService = SpeechService(),
        startingAt step: VoiceOrderWizard.Step = .freeform,
        didCaptureStartTime: Bool = false,
        currentCoordinate: (() -> LocatedCoordinate?)? = nil
    ) -> VoiceOrderWizard {
        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()
        addTeardownBlock { _ = bookingViewModel } // wizard 对它是 weak：不攥到用例结束就等于传 nil（#601）
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel, speechService: speechService,
            // 这批用例全走 `startForTesting(at:)`，不开麦，不需要活着的语音服务（等于传 nil）。
            speechInputService: SpeechInputService(), // guard:allow weak-temporary
            voiceOrderService: VoiceOrderService(transport: stub),
            currentCoordinate: currentCoordinate
        )
        wizard.startForTesting(at: step, didCaptureStartTime: didCaptureStartTime)
        return wizard
    }

    func makeUnstartedWizard(
        bookingViewModel: BlindBookingViewModel,
        speechInputService: SpeechInputService? = nil
    ) -> VoiceOrderWizard {
        let wizard = VoiceOrderWizard()
        wizard.configure(
            bookingViewModel: bookingViewModel,
            speechService: SpeechService(),
            // 参数是非可选的，但 wizard 那侧是 `weak var`：不传时这个临时对象出了本行就释放，
            // wizard 拿到的实际是 nil。走门槛分支的用例本来就不碰语音服务，故此保持现状；
            // 需要真的语音服务的用例（见 testStartFallsBackImmediately...）必须自己 `let` 住再传进来。
            speechInputService: speechInputService ?? SpeechInputService(), // guard:allow weak-temporary
            voiceOrderService: VoiceOrderService(transport: VoiceOrderAPIClientStub())
        )
        return wizard
    }
}
