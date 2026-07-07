import Combine
import CoreLocation
import SwiftUI
import UIKit

// MARK: - Booking Option Types

enum BookingDurationOption: Int, CaseIterable, Identifiable {
    case none = 0
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "不填写"
        case .fifteen: return "15 分钟"
        case .thirty: return "30 分钟"
        case .fortyFive: return "45 分钟"
        case .sixty: return "1 小时"
        case .ninety: return "1.5 小时"
        case .oneTwenty: return "2 小时"
        }
    }

    var minutes: Int? {
        rawValue == 0 ? nil : rawValue
    }
}

enum BlindBookingGuidedStep: Int, CaseIterable, Identifiable {
    case startPoint
    case appointmentTime
    case runningNeeds
    case review

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .startPoint:
            return "确认出发地点"
        case .appointmentTime:
            return "确认预约时间"
        case .runningNeeds:
            return "跑步需求"
        case .review:
            return "确认并提交"
        }
    }

    var shortName: String {
        switch self {
        case .startPoint:
            return "地点"
        case .appointmentTime:
            return "时间"
        case .runningNeeds:
            return "需求"
        case .review:
            return "确认"
        }
    }

    var nextActionTitle: String {
        switch self {
        case .startPoint:
            return "下一步：预约时间"
        case .appointmentTime:
            return "下一步：跑步需求"
        case .runningNeeds:
            return "下一步：确认预约"
        case .review:
            return "提交预约"
        }
    }

    var nextSpeechAction: String {
        switch self {
        case .startPoint:
            return "确认地点后进入预约时间。"
        case .appointmentTime:
            return "确认时间后进入跑步需求。"
        case .runningNeeds:
            return "可跳过选填需求，进入确认预约。"
        case .review:
            return "确认无误后提交预约。"
        }
    }
}

struct BookingReviewItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

// MARK: - Blind Booking ViewModel

@MainActor
final class BlindBookingViewModel: ObservableObject {
    @Published var currentStep: BlindBookingGuidedStep = .startPoint
    @Published var placeSearchKeyword = ""
    @Published var placeSearchResults: [ResolvedPlace] = []
    @Published var selectedStartPlace: ResolvedPlace?
    @Published var currentResolvedPlace: ResolvedPlace?
    @Published var startLocationDescription = ""
    @Published var appointmentTime = Date()
    @Published var routeNotes = ""
    @Published var duration: BookingDurationOption = .none
    @Published var pacePreference: PacePreference = .noPreference
    @Published var routePreference: RoutePreference = .noPreference
    @Published var hasGuideDogThisRun = false
    @Published var specialNotes = ""
    @Published var isSubmitting = false
    @Published var isResolvingStartLocation = false
    @Published var isSearchingPlaces = false
    @Published var errorMessage: String?
    @Published var placeMessage: String?
    @Published var searchResultFocusID: String?
    @Published private(set) var auxiliaryMapCenter: CLLocationCoordinate2D?
    @Published private(set) var auxiliaryMapPlace: ResolvedPlace?

    private weak var appState: AppState?
    private weak var locationService: LocationService?
    private weak var placeSearchProvider: (any PlaceSearchProviding)?
    private var speechService: SpeechService?
    private static let auxiliaryMapMarkerRefreshDistanceMeters: CLLocationDistance = 30

    var minimumAppointmentTime: Date {
        Date().addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60))
    }

    var isAppointmentTimeValid: Bool {
        appointmentTime >= minimumAppointmentTime
    }

    var canSubmit: Bool {
        !isSubmitting &&
        isAppointmentTimeValid &&
        locationService?.isDenied != true &&
        resolvedStartPlace != nil
    }

    var isFirstStep: Bool {
        currentStep == BlindBookingGuidedStep.allCases.first
    }

    var isReviewStep: Bool {
        currentStep == .review
    }

    var canAdvanceFromCurrentStep: Bool {
        blockingReasonForCurrentStep == nil
    }

    var blockingReasonForCurrentStep: String? {
        switch currentStep {
        case .startPoint:
            if locationService?.isDenied == true {
                return "定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。"
            }
            if resolvedStartPlace == nil {
                return "请选择出发地点。"
            }
            return nil
        case .appointmentTime:
            return isAppointmentTimeValid ? nil : "预约时间需至少在 30 分钟后。"
        case .runningNeeds:
            return nil
        case .review:
            if locationService?.isDenied == true {
                return "定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。"
            }
            if resolvedStartPlace == nil {
                return "请选择出发地点。"
            }
            if !isAppointmentTimeValid {
                return "预约时间需至少在 30 分钟后。"
            }
            return nil
        }
    }

    var stepProgressText: String {
        let total = BlindBookingGuidedStep.allCases.count
        return "第 \(currentStep.rawValue + 1) 步，共 \(total) 步"
    }

    var appointmentSummary: String {
        let timeText = DateFormatter.aidRunDisplayDateTime.string(from: appointmentTime)
        if isAppointmentTimeValid {
            return "预约时间：\(timeText)。"
        }
        return "预约时间：\(timeText)。预约时间需至少在 30 分钟后。"
    }

    var startPointSourceText: String {
        guard let place = resolvedStartPlace else {
            return "出发地点尚未解析。"
        }
        switch place.source {
        case .deviceLocation:
            return selectedStartPlace == nil ? "使用设备当前位置。" : "已选择高德地点。"
        case .manual:
            return "已选择高德地点。"
        case .demoDefault:
            return "正在使用演示坐标，不代表真实会合点。"
        }
    }

    var startPointSummary: String {
        let placeText = resolvedStartLocationDescription.nilIfBlank ?? "正在获取当前位置"
        return "\(startPointSourceText)出发地点：\(placeText)。"
    }

    var optionalReviewItems: [BookingReviewItem] {
        var items: [BookingReviewItem] = []
        if let routeNotes = routeNotes.nilIfBlank {
            items.append(BookingReviewItem(id: "routeNotes", title: "路线备注", value: routeNotes))
        }
        if duration != .none {
            items.append(BookingReviewItem(id: "duration", title: "预计时长", value: duration.displayName))
        }
        if pacePreference != .noPreference {
            items.append(BookingReviewItem(id: "pace", title: "配速偏好", value: pacePreference.displayName))
        }
        if routePreference != .noPreference {
            items.append(BookingReviewItem(id: "route", title: "路线偏好", value: routePreference.displayName))
        }
        if hasGuideDogThisRun {
            items.append(BookingReviewItem(id: "guideDog", title: "导盲犬", value: "本次携带"))
        }
        if let specialNotes = specialNotes.nilIfBlank {
            items.append(BookingReviewItem(id: "specialNotes", title: "特殊说明", value: specialNotes))
        }
        return items
    }

    var optionalNeedsSpeechSummary: String {
        let items = optionalReviewItems
        guard !items.isEmpty else {
            return "没有填写选填跑步需求。"
        }
        return items.map { "\($0.title)：\($0.value)" }.joined(separator: "。") + "。"
    }

    var reviewSummarySpeech: String {
        let blockingText = blockingReasonForCurrentStep.map { "当前还不能提交，\($0)" } ?? ""
        return "请确认预约。\(startPointSummary)\(appointmentSummary)\(optionalNeedsSpeechSummary)\(blockingText)"
    }

    var currentStepSpeechSummary: String {
        let blockingText = blockingReasonForCurrentStep.map { "当前阻塞：\($0)" } ?? ""
        switch currentStep {
        case .startPoint:
            return "当前步骤：确认出发地点。\(startPointSummary)\(currentStep.nextSpeechAction)\(blockingText)"
        case .appointmentTime:
            return "当前步骤：确认预约时间。\(appointmentSummary)\(currentStep.nextSpeechAction)\(blockingText)"
        case .runningNeeds:
            return "当前步骤：跑步需求，全部选填。\(optionalNeedsSpeechSummary)\(currentStep.nextSpeechAction)"
        case .review:
            return reviewSummarySpeech
        }
    }

    var auxiliaryMapAccessibilityLabel: String {
        let placeText = resolvedStartLocationDescription.nilIfBlank ?? "出发地点待确认"
        return "辅助地图，\(startPointSourceText)当前出发地点：\(placeText)"
    }

    var resolvedStartLocationDescription: String {
        guard let place = resolvedStartPlace else { return "" }
        let baseAddress = place.addressText.trimmed.isEmpty ? place.title : place.addressText.trimmed
        let supplement = startLocationDescription.trimmed
        if supplement.isEmpty {
            return baseAddress
        }
        if baseAddress.contains(supplement) {
            return baseAddress
        }
        return "\(baseAddress)；补充：\(supplement)"
    }

    var resolvedStartPlace: ResolvedPlace? {
        if let selectedStartPlace {
            return selectedStartPlace
        }
        if let currentResolvedPlace {
            return currentResolvedPlace
        }
        guard let locationService else { return nil }
        let coordinate = locationService.effectiveLocation
        return ResolvedPlace(
            id: locationService.isUsingDemoFallback ? "demo-current" : "device-current",
            title: locationService.isUsingDemoFallback ? "当前位置（演示坐标）" : "当前位置",
            addressText: locationService.isUsingDemoFallback ? "北京市（演示位置）" : "当前位置",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: locationService.isUsingDemoFallback ? .demoDefault : .deviceLocation
        )
    }

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

        if appointmentTime < minimumAppointmentTime {
            appointmentTime = minimumAppointmentTime.addingTimeInterval(60)
        }
    }

    #if DEBUG
    func configureForTesting(
        placeSearchProvider: any PlaceSearchProviding,
        speechService: SpeechService,
        locationService: LocationService? = nil
    ) {
        self.placeSearchProvider = placeSearchProvider
        self.speechService = speechService
        self.locationService = locationService
    }
    #endif

    func refreshCurrentLocation(lockMapCenterIfNeeded: Bool = true) async {
        guard let locationService else { return }
        guard !locationService.isDenied else {
            placeMessage = "需要开启定位权限才能创建预约。"
            return
        }

        let coordinate = locationService.effectiveLocation
        let fallbackPlace = ResolvedPlace(
            id: locationService.isUsingDemoFallback ? "demo-current" : "device-current",
            title: locationService.isUsingDemoFallback ? "当前位置（演示坐标）" : "当前位置",
            addressText: locationService.isUsingDemoFallback ? "北京市（演示位置）" : "当前位置",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: locationService.isUsingDemoFallback ? .demoDefault : .deviceLocation
        )

        guard let placeSearchProvider, !locationService.isUsingDemoFallback else {
            currentResolvedPlace = fallbackPlace
            updateAuxiliaryMapPlaceIfNeeded(to: fallbackPlace, lockMapCenterIfNeeded: lockMapCenterIfNeeded)
            if lockMapCenterIfNeeded {
                lockInitialAuxiliaryMapCenter(to: fallbackPlace.coordinate)
            }
            placeMessage = locationService.isUsingDemoFallback ? "定位暂不可用，正在使用演示坐标。" : nil
            return
        }

        isResolvingStartLocation = true
        let resolvedPlace = await placeSearchProvider.reverseGeocode(coordinate: coordinate)
        let finalPlace = resolvedPlace ?? fallbackPlace
        currentResolvedPlace = finalPlace
        updateAuxiliaryMapPlaceIfNeeded(to: finalPlace, lockMapCenterIfNeeded: lockMapCenterIfNeeded)
        if lockMapCenterIfNeeded {
            lockInitialAuxiliaryMapCenter(to: finalPlace.coordinate)
        }
        isResolvingStartLocation = false
        placeMessage = resolvedPlace == nil ? placeSearchProvider.lastErrorMessage : nil
    }

    func refreshCurrentLocationIfNeeded() async {
        guard selectedStartPlace == nil,
              !isResolvingStartLocation else { return }
        await refreshCurrentLocation(lockMapCenterIfNeeded: false)
    }

    func searchPlaces(triggeredBySpeech: Bool = false) async {
        guard let placeSearchProvider else { return }
        let keyword = placeSearchKeyword.trimmed
        guard !keyword.isEmpty else {
            placeSearchResults = []
            placeMessage = "请输入要搜索的地点。"
            speechService?.announce(placeMessage ?? "")
            return
        }

        isSearchingPlaces = true
        placeMessage = nil
        let results = await placeSearchProvider.searchPlaces(
            keyword: keyword,
            near: resolvedStartPlace?.coordinate
        )
        placeSearchResults = results
        isSearchingPlaces = false
        if results.isEmpty {
            placeMessage = placeSearchProvider.lastErrorMessage ?? "未搜索到相关地点。"
            searchResultFocusID = nil
            speechService?.announce(placeMessage ?? "")
        } else {
            let firstPlace = results[0]
            searchResultFocusID = firstPlace.id
            speechService?.announce("已找到 \(results.count) 个地点，第一个是 \(firstPlace.title)。")
        }
    }

    func handlePlaceSearchSpeechCompletion(_ completion: SpeechInputCompletion) async {
        guard completion.field == .startPlaceSearch,
              completion.reason.shouldTriggerSearchWithRecognizedText else { return }
        let recognizedText = completion.recognizedText.trimmed
        guard !recognizedText.isEmpty else { return }
        placeSearchKeyword = recognizedText
        await searchPlaces(triggeredBySpeech: true)
    }

    func selectPlace(_ place: ResolvedPlace) {
        selectedStartPlace = place
        auxiliaryMapPlace = place
        auxiliaryMapCenter = place.coordinate
        placeSearchKeyword = place.title
        placeSearchResults = []
        searchResultFocusID = nil
        placeMessage = "已选择出发地点：\(place.title)。"
        speechService?.speak("已选择出发地点，\(place.title)。")
    }

    private func updateAuxiliaryMapPlaceIfNeeded(
        to place: ResolvedPlace,
        lockMapCenterIfNeeded: Bool
    ) {
        guard selectedStartPlace == nil else { return }
        guard let currentMapPlace = auxiliaryMapPlace else {
            auxiliaryMapPlace = place
            if lockMapCenterIfNeeded {
                lockInitialAuxiliaryMapCenter(to: place.coordinate)
            }
            return
        }

        if currentMapPlace.source == .demoDefault && place.source != .demoDefault {
            auxiliaryMapPlace = place
            auxiliaryMapCenter = place.coordinate
            return
        }

        let distance = CLLocation(latitude: currentMapPlace.latitude, longitude: currentMapPlace.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        if distance >= Self.auxiliaryMapMarkerRefreshDistanceMeters {
            auxiliaryMapPlace = place
        }
    }

    private func lockInitialAuxiliaryMapCenter(to coordinate: CLLocationCoordinate2D) {
        guard auxiliaryMapCenter == nil else { return }
        auxiliaryMapCenter = coordinate
    }

    func moveToNextStep() {
        guard canAdvanceFromCurrentStep else {
            let message = blockingReasonForCurrentStep ?? "请先完成当前步骤。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        guard let currentIndex = BlindBookingGuidedStep.allCases.firstIndex(of: currentStep),
              currentIndex < BlindBookingGuidedStep.allCases.count - 1 else {
            return
        }
        errorMessage = nil
        currentStep = BlindBookingGuidedStep.allCases[currentIndex + 1]
        speechService?.speak(currentStepSpeechSummary)
    }

    func moveToPreviousStep() {
        guard let currentIndex = BlindBookingGuidedStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0 else {
            return
        }
        errorMessage = nil
        currentStep = BlindBookingGuidedStep.allCases[currentIndex - 1]
        speechService?.speak(currentStepSpeechSummary)
    }

    func repeatCurrentStepStatus() {
        speechService?.speak(currentStepSpeechSummary)
    }

    func makeCreateOrderRequest() -> CreateOrderRequest? {
        guard let startPlace = resolvedStartPlace else { return nil }
        let plannedStartTime = DateFormatter.aidRunBackendLocalDateTime.string(from: appointmentTime)
        let plannedEndTime: String
        if let minutes = duration.minutes {
            let endDate = appointmentTime.addingTimeInterval(TimeInterval(minutes * 60))
            plannedEndTime = DateFormatter.aidRunBackendLocalDateTime.string(from: endDate)
        } else {
            let endDate = appointmentTime.addingTimeInterval(3600)
            plannedEndTime = DateFormatter.aidRunBackendLocalDateTime.string(from: endDate)
        }

        return CreateOrderRequest(
            startLatitude: startPlace.latitude,
            startLongitude: startPlace.longitude,
            startAddress: resolvedStartLocationDescription,
            plannedStartTime: plannedStartTime,
            plannedEndTime: plannedEndTime,
            expectedDurationMinutes: duration.minutes,
            pacePreference: pacePreference == .noPreference ? nil : pacePreference,
            routePreference: routePreference == .noPreference ? nil : routePreference,
            routeNotes: routeNotes.nilIfBlank,
            hasGuideDogThisRun: hasGuideDogThisRun ? true : nil,
            specialNotes: specialNotes.nilIfBlank
        )
    }

    func submit() async -> OrderResponse? {
        guard let appState, let locationService else { return nil }
        guard appState.isBlindProfileComplete else {
            return fail("请先完善个人资料。")
        }
        guard locationService.isDenied == false else {
            return fail("定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。")
        }
        guard isAppointmentTimeValid else {
            return fail("预约时间需至少在 30 分钟后。")
        }

        isSubmitting = true
        errorMessage = nil

        guard let request = makeCreateOrderRequest() else {
            isSubmitting = false
            return fail("请选择出发地点。")
        }

        do {
            let response: OrderResponse = try await appState.apiClient.post("/api/orders", body: request)
            isSubmitting = false
            speechService?.resetLastStatus()
            speechService?.speak("订单提交成功，系统正在为你派单。")
            return response
        } catch let error as APIError {
            isSubmitting = false
            if appState.handleAuthenticatedAPIError(error) {
                return nil
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return nil
        } catch {
            isSubmitting = false
            return fail("提交失败，请重试。")
        }
    }

    private func fail(_ message: String) -> OrderResponse? {
        errorMessage = message
        speechService?.speakError(message)
        return nil
    }
}

// MARK: - Blind Booking View

struct BlindBookingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BlindBookingViewModel()
    @AccessibilityFocusState private var focusedSearchResultID: String?
    let onOrderCreated: (OrderResponse) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    guidedStepHeader
                    currentStepContent

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                            .accessibilityHint("错误提示")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            submitArea
        }
        .navigationTitle("创建预约")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if locationService.isNotDetermined {
                locationService.requestPermission()
            }
            locationService.startUpdating()
            viewModel.configure(
                appState: appState,
                locationService: locationService,
                speechService: speechService,
                amapGeocodingService: amapGeocodingService
            )
            Task { await viewModel.refreshCurrentLocation() }
        }
        .onChange(of: locationService.currentLocation) { _ in
            Task { await viewModel.refreshCurrentLocationIfNeeded() }
        }
        .onChange(of: viewModel.searchResultFocusID) { focusID in
            focusedSearchResultID = focusID
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("创建预约", style: .title)
                .accessibilityAddTraits(.isHeader)
            Text("按步骤确认出发地点、预约时间和选填需求，最后再提交。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("按步骤确认出发地点、预约时间和选填需求，最后再提交")
        }
    }

    private var guidedStepHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.stepProgressText)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel(viewModel.stepProgressText)

            HStack(spacing: 8) {
                ForEach(BlindBookingGuidedStep.allCases) { step in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(step.rawValue <= viewModel.currentStep.rawValue ? AppColors.primary : AppColors.textSecondary.opacity(0.25))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(step.shortName)
                            .font(AppFonts.caption())
                            .foregroundColor(step == viewModel.currentStep ? AppColors.textPrimary : AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(viewModel.stepProgressText)，当前步骤：\(viewModel.currentStep.displayName)")

            Text(viewModel.currentStep.displayName)
                .font(.title2.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.currentStepSpeechSummary)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(viewModel.currentStepSpeechSummary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch viewModel.currentStep {
        case .startPoint:
            locationSection
        case .appointmentTime:
            appointmentSection
        case .runningNeeds:
            optionalSection
        case .review:
            reviewSection
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("出发地点")

            if locationService.isDenied {
                permissionDeniedView
            } else {
                currentLocationCard

                VoiceTextField(
                    title: "搜索出发地点",
                    placeholder: "例如：科技园地铁站 A 口",
                    text: $viewModel.placeSearchKeyword,
                    speechInputService: speechInputService,
                    speechService: speechService,
                    speechField: .startPlaceSearch,
                    accessibilityLabel: "搜索出发地点",
                    accessibilityHint: "可以使用语音或键盘搜索高德地点",
                    onRecognitionCompleted: { completion in
                        Task {
                            await viewModel.handlePlaceSearchSpeechCompletion(completion)
                        }
                    }
                )

                Button {
                    Task { await viewModel.searchPlaces() }
                } label: {
                    HStack {
                        if viewModel.isSearchingPlaces {
                            ProgressView()
                        }
                        Text(searchButtonTitle)
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecognizingStartPlace || viewModel.isSearchingPlaces || viewModel.placeSearchKeyword.trimmed.isEmpty)
                .accessibilityLabel(searchButtonTitle)
                .accessibilityHint(isRecognizingStartPlace ? "请说出地点名称，识别结束后会自动搜索" : "搜索高德地点并显示可选择的出发地点列表")

                placeSearchResultsView

                VoiceTextField(
                    title: "出发地点补充描述",
                    placeholder: "例如：我在 A 口外侧等候",
                    text: $viewModel.startLocationDescription,
                    speechInputService: speechInputService,
                    speechService: speechService,
                    speechField: .startLocationDescription,
                    accessibilityLabel: "出发地点补充描述",
                    accessibilityHint: "可以使用语音或键盘补充出发地点说明，不能替代坐标"
                )

                if let placeMessage = viewModel.placeMessage {
                    Text(placeMessage)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(placeMessage)
                }

                auxiliaryStartMap
            }
        }
    }

    private var currentLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.selectedStartPlace == nil ? "默认出发点" : "已选择出发点")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(viewModel.resolvedStartLocationDescription.isEmpty ? "正在获取当前位置" : viewModel.resolvedStartLocationDescription)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("出发地点，\(viewModel.resolvedStartLocationDescription)")
                    .accessibilityHint("提交预约时会使用这个地点")

                if viewModel.isResolvingStartLocation {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在使用高德解析当前位置")
                    }
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("正在使用高德解析当前位置")
                } else {
                    Text(locationService.isUsingDemoFallback ? "使用演示坐标，适合模拟器测试。" : "已使用设备当前位置和高德地址作为出发点。")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(locationService.isUsingDemoFallback ? "使用演示坐标，适合模拟器测试" : "已使用设备当前位置和高德地址作为出发点")
                }
            }
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private var auxiliaryStartMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("辅助地图")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            MapViewWrapper(
                centerCoordinate: viewModel.auxiliaryMapCenter ?? viewModel.auxiliaryMapPlace?.coordinate ?? viewModel.resolvedStartPlace?.coordinate ?? locationService.effectiveLocation,
                showsUserLocation: true,
                annotations: (viewModel.auxiliaryMapPlace ?? viewModel.resolvedStartPlace).map {
                    [
                        MapAnnotationItem(
                            id: "start-location",
                            coordinate: $0.coordinate,
                            title: $0.title,
                            subtitle: $0.addressText
                        )
                    ]
                } ?? [],
                zoomLevel: 16,
                tracksUserLocation: false,
                animatesCenterChanges: false
            )
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.auxiliaryMapAccessibilityLabel)
            .accessibilityHint("地图仅用于视觉确认，出发地点文字和语音摘要在上方")
            .accessibilityIdentifier("blindBookingAuxiliaryMap")
        }
    }

    @ViewBuilder
    private var placeSearchResultsView: some View {
        if !viewModel.placeSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索结果")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(viewModel.placeSearchResults) { place in
                    Button {
                        viewModel.selectPlace(place)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.title)
                                .font(AppFonts.body().weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(place.addressText)
                                .font(AppFonts.caption())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityFocused($focusedSearchResultID, equals: place.id)
                    .accessibilityLabel(place.bookingSearchAccessibilityLabel)
                    .accessibilityHint("点击后使用该地点坐标创建预约")
                }
            }
        }
    }

    private var isRecognizingStartPlace: Bool {
        speechInputService.isListening(for: .startPlaceSearch)
    }

    private var searchButtonTitle: String {
        if isRecognizingStartPlace {
            return "语音识别中"
        }
        if viewModel.isSearchingPlaces {
            return "正在搜索"
        }
        return "搜索地点"
    }

    private var permissionDeniedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要开启定位权限才能创建预约。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.warning)
                .accessibilityLabel("需要开启定位权限才能创建预约")

            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("去设置")
            .accessibilityHint("打开系统设置以开启定位权限")
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .onAppear {
            speechService.speakError("定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。")
        }
    }

    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("预约时间")
            DatePicker(
                "预约时间",
                selection: $viewModel.appointmentTime,
                in: viewModel.minimumAppointmentTime...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityLabel("预约时间，\(viewModel.appointmentTime.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint("请选择至少三十分钟后的时间")

            Text("预约时间需至少在 30 分钟后。")
                .font(AppFonts.caption())
                .foregroundColor(viewModel.isAppointmentTimeValid ? AppColors.textSecondary : AppColors.destructive)
                .accessibilityLabel("预约时间需至少在三十分钟后")
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("更多选项（选填）")

            VoiceTextField(
                title: "路线备注",
                placeholder: "例如：沿公园慢跑一圈",
                text: $viewModel.routeNotes,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .destinationRoute,
                accessibilityLabel: "路线备注，选填",
                accessibilityHint: "可以使用语音或键盘输入路线说明"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("预计时长")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Picker("预计时长", selection: $viewModel.duration) {
                    ForEach(BookingDurationOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("预计时长，选填")
                .accessibilityHint("点击选择预计跑步时长")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("配速偏好")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Picker("配速偏好", selection: $viewModel.pacePreference) {
                    ForEach(PacePreference.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("配速偏好，选填")
                .accessibilityHint("选择走跑结合、轻松、中等或快速")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("路线偏好")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Picker("路线偏好", selection: $viewModel.routePreference) {
                    ForEach(RoutePreference.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("路线偏好，选填")
                .accessibilityHint("选择公园步道、街道或跑道")
            }

            Toggle("本次携带导盲犬", isOn: $viewModel.hasGuideDogThisRun)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("是否本次携带导盲犬，选填")
                .accessibilityHint("开启后记录本次跑步携带导盲犬")

            VoiceTextField(
                title: "特殊说明",
                placeholder: "例如：我会带导盲杖",
                text: $viewModel.specialNotes,
                isMultiline: true,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .remark,
                accessibilityLabel: "特殊说明，选填",
                accessibilityHint: "可以使用语音或键盘输入特殊说明"
            )
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("确认预约")

            reviewRow(title: "出发地点", value: viewModel.resolvedStartLocationDescription.nilIfBlank ?? "出发地点待确认")
            reviewRow(title: "预约时间", value: DateFormatter.aidRunDisplayDateTime.string(from: viewModel.appointmentTime))

            if viewModel.optionalReviewItems.isEmpty {
                Text("未填写选填跑步需求。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("未填写选填跑步需求")
            } else {
                ForEach(viewModel.optionalReviewItems) { item in
                    reviewRow(title: item.title, value: item.value)
                }
            }

            if let blockingReason = viewModel.blockingReasonForCurrentStep {
                Text(blockingReason)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(blockingReason)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func reviewRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }

    private var submitArea: some View {
        VStack(spacing: 10) {
            if let blockingReason = viewModel.blockingReasonForCurrentStep {
                Text(blockingReason)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(blockingReason)
            }

            HStack(spacing: 12) {
                if !viewModel.isFirstStep {
                    Button("上一步") {
                        viewModel.moveToPreviousStep()
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(minWidth: 96)
                    .frame(minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(12)
                    .accessibilityLabel("上一步")
                    .accessibilityHint("返回上一个预约步骤")
                }

                PrimaryButton(viewModel.currentStep.nextActionTitle, isLoading: viewModel.isSubmitting) {
                    if viewModel.isReviewStep {
                        Task {
                            if let response = await viewModel.submit() {
                                onOrderCreated(response)
                            }
                        }
                    } else {
                        viewModel.moveToNextStep()
                    }
                }
                .disabled(primaryActionDisabled)
                .opacity(primaryActionDisabled ? 0.45 : 1)
                .accessibilityLabel(viewModel.currentStep.nextActionTitle)
                .accessibilityHint(primaryActionHint)
            }

            PrimaryButton("重复当前状态") {
                viewModel.repeatCurrentStepStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前预约步骤状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var primaryActionDisabled: Bool {
        viewModel.isReviewStep ? !viewModel.canSubmit : !viewModel.canAdvanceFromCurrentStep
    }

    private var primaryActionHint: String {
        if let blockingReason = viewModel.blockingReasonForCurrentStep {
            return blockingReason
        }
        return viewModel.isReviewStep ? "提交后系统将为你派单" : "进入下一步"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindBookingView { _ in }
            .environmentObject(AppState())
            .environmentObject(LocationService())
            .environmentObject(SpeechService())
            .environmentObject(SpeechInputService())
            .environmentObject(AMapGeocodingService())
    }
}
#endif
