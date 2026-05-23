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

enum PacePreferenceOption: String, CaseIterable, Identifiable {
    case none
    case slow = "慢跑"
    case medium = "中速"
    case fast = "较快"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "不填写"
        case .slow, .medium, .fast: return rawValue
        }
    }

    var requestValue: String? {
        self == .none ? nil : rawValue
    }
}

// MARK: - Blind Booking ViewModel

@MainActor
final class BlindBookingViewModel: ObservableObject {
    @Published var placeSearchKeyword = ""
    @Published var placeSearchResults: [ResolvedPlace] = []
    @Published var selectedStartPlace: ResolvedPlace?
    @Published var currentResolvedPlace: ResolvedPlace?
    @Published var startLocationDescription = ""
    @Published var appointmentTime = Date()
    @Published var destinationText = ""
    @Published var duration: BookingDurationOption = .none
    @Published var estimatedDistanceText = ""
    @Published var pacePreference: PacePreferenceOption = .none
    @Published var preferSameGender = false
    @Published var remark = ""
    @Published var isSubmitting = false
    @Published var isResolvingStartLocation = false
    @Published var isSearchingPlaces = false
    @Published var errorMessage: String?
    @Published var placeMessage: String?

    private weak var appState: AppState?
    private weak var locationService: LocationService?
    private weak var amapGeocodingService: AMapGeocodingService?
    private var speechService: SpeechService?

    var minimumAppointmentTime: Date {
        Date().addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60))
    }

    var isAppointmentTimeValid: Bool {
        appointmentTime >= minimumAppointmentTime
    }

    var estimatedDistanceKm: Double? {
        let normalized = estimatedDistanceText.replacingOccurrences(of: "，", with: ".")
        return Double(normalized)
    }

    var canSubmit: Bool {
        !isSubmitting &&
        isAppointmentTimeValid &&
        locationService?.isDenied != true &&
        resolvedStartPlace != nil &&
        (estimatedDistanceText.trimmed.isEmpty || estimatedDistanceKm != nil)
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

    var coordinateSummary: String {
        guard let place = resolvedStartPlace else { return "未获取坐标" }
        return String(format: "纬度 %.6f，经度 %.6f", place.latitude, place.longitude)
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
        self.amapGeocodingService = amapGeocodingService

        if appointmentTime < minimumAppointmentTime {
            appointmentTime = minimumAppointmentTime.addingTimeInterval(60)
        }
    }

    func refreshCurrentLocation() async {
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

        guard let amapGeocodingService, !locationService.isUsingDemoFallback else {
            currentResolvedPlace = fallbackPlace
            placeMessage = locationService.isUsingDemoFallback ? "定位暂不可用，正在使用演示坐标。" : nil
            return
        }

        isResolvingStartLocation = true
        let resolvedPlace = await amapGeocodingService.reverseGeocode(coordinate: coordinate)
        currentResolvedPlace = resolvedPlace ?? fallbackPlace
        isResolvingStartLocation = false
        placeMessage = resolvedPlace == nil ? amapGeocodingService.lastErrorMessage : nil
    }

    func searchPlaces() async {
        guard let amapGeocodingService else { return }
        let keyword = placeSearchKeyword.trimmed
        guard !keyword.isEmpty else {
            placeSearchResults = []
            placeMessage = "请输入要搜索的地点。"
            return
        }

        isSearchingPlaces = true
        placeMessage = nil
        let results = await amapGeocodingService.searchPlaces(
            keyword: keyword,
            near: resolvedStartPlace?.coordinate
        )
        placeSearchResults = results
        isSearchingPlaces = false
        if results.isEmpty {
            placeMessage = amapGeocodingService.lastErrorMessage ?? "未搜索到相关地点。"
        }
    }

    func selectPlace(_ place: ResolvedPlace) {
        selectedStartPlace = place
        placeSearchKeyword = place.title
        placeSearchResults = []
        placeMessage = "已选择出发地点：\(place.title)。"
        speechService?.speak("已选择出发地点，\(place.title)。")
    }

    func sanitizeDistanceInput(_ value: String) {
        let allowed = value.filter { $0.isNumber || $0 == "." || $0 == "，" }
        let normalized = allowed.replacingOccurrences(of: "，", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count <= 2 {
            estimatedDistanceText = normalized
        } else {
            estimatedDistanceText = String(parts[0]) + "." + parts.dropFirst().joined()
        }
    }

    func submit() async -> RunOrderDto? {
        guard let appState, let locationService else { return nil }
        guard appState.isBlindRunnerProfileComplete else {
            return fail("请先完善个人资料。")
        }
        guard locationService.isDenied == false else {
            return fail("定位权限未开启。请前往系统设置开启定位，以便创建跑步预约。")
        }
        guard isAppointmentTimeValid else {
            return fail("预约时间需至少在 30 分钟后。")
        }
        guard estimatedDistanceText.trimmed.isEmpty || estimatedDistanceKm != nil else {
            return fail("预计距离请输入数字。")
        }

        isSubmitting = true
        errorMessage = nil

        guard let startPlace = resolvedStartPlace else {
            return fail("请选择出发地点。")
        }
        let request = CreateOrderRequest(
            startLocation: LocationPoint(
                latitude: startPlace.latitude,
                longitude: startPlace.longitude,
                addressText: resolvedStartLocationDescription,
                source: startPlace.source
            ),
            destinationText: destinationText.nilIfBlank,
            appointmentTime: ISO8601DateFormatter.aidRunFormatter.string(from: appointmentTime),
            estimatedDurationMinutes: duration.minutes,
            estimatedDistanceKm: estimatedDistanceKm,
            pacePreference: pacePreference.requestValue,
            preferSameGender: preferSameGender ? true : nil,
            remark: remark.nilIfBlank
        )

        do {
            let order: RunOrderDto = try await appState.apiClient.post("/api/orders", body: request)
            isSubmitting = false
            speechService?.resetLastStatus()
            speechService?.speak("订单提交成功，等待志愿者接单。")
            return order
        } catch let error as APIError {
            isSubmitting = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return nil
        } catch {
            isSubmitting = false
            return fail("提交失败，请重试。")
        }
    }

    private func fail(_ message: String) -> RunOrderDto? {
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
    let onOrderCreated: (RunOrderDto) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    locationSection
                    appointmentSection
                    optionalSection

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
            Task { await viewModel.refreshCurrentLocation() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("创建预约", style: .title)
                .accessibilityAddTraits(.isHeader)
            Text("默认使用当前位置作为出发点，预约时间必须至少在 30 分钟后。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("默认使用当前位置作为出发点，预约时间必须至少在三十分钟后")
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
                    fieldId: "startPlaceSearch",
                    accessibilityLabel: "搜索出发地点",
                    accessibilityHint: "可以使用语音或键盘搜索高德地点"
                )

                Button {
                    Task { await viewModel.searchPlaces() }
                } label: {
                    HStack {
                        if viewModel.isSearchingPlaces {
                            ProgressView()
                        }
                        Text(viewModel.isSearchingPlaces ? "正在搜索" : "搜索地点")
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSearchingPlaces || viewModel.placeSearchKeyword.trimmed.isEmpty)
                .accessibilityLabel("搜索地点")
                .accessibilityHint("搜索高德地点并显示可选择的出发地点列表")

                placeSearchResultsView

                VoiceTextField(
                    title: "出发地点补充描述",
                    placeholder: "例如：我在 A 口外侧等候",
                    text: $viewModel.startLocationDescription,
                    speechInputService: speechInputService,
                    fieldId: "startLocation",
                    accessibilityLabel: "出发地点补充描述",
                    accessibilityHint: "可以使用语音或键盘补充出发地点说明，不能替代坐标"
                )

                if let placeMessage = viewModel.placeMessage {
                    Text(placeMessage)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(placeMessage)
                }
            }
        }
    }

    private var currentLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MapViewWrapper(
                centerCoordinate: viewModel.resolvedStartPlace?.coordinate ?? locationService.effectiveLocation,
                showsUserLocation: true,
                annotations: viewModel.resolvedStartPlace.map {
                    [
                        MapAnnotationItem(
                            id: "start-location",
                            coordinate: $0.coordinate,
                            title: $0.title,
                            subtitle: $0.addressText
                        )
                    ]
                } ?? [],
                zoomLevel: 16
            )
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("高德地图，显示当前出发地点")
            .accessibilityHint("地图用于确认位置，下面会显示可读地址和坐标")

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.selectedStartPlace == nil ? "默认出发点" : "已选择出发点")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(viewModel.resolvedStartLocationDescription.isEmpty ? "正在获取当前位置" : viewModel.resolvedStartLocationDescription)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("出发地点，\(viewModel.resolvedStartLocationDescription)")
                    .accessibilityHint("提交预约时会把这个地点的经纬度传给服务器")

                Text(viewModel.coordinateSummary)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("出发地点坐标，\(viewModel.coordinateSummary)")

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
                            Text(String(format: "纬度 %.6f，经度 %.6f", place.latitude, place.longitude))
                                .font(AppFonts.caption())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择出发地点，\(place.title)，\(place.addressText)")
                    .accessibilityHint("点击后使用该地点坐标创建预约")
                }
            }
        }
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
                title: "目的地或路线",
                placeholder: "例如：沿公园慢跑一圈",
                text: $viewModel.destinationText,
                speechInputService: speechInputService,
                fieldId: "destination",
                accessibilityLabel: "目的地或路线，选填",
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
                Text("预计距离（公里）")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                TextField("例如：5", text: $viewModel.estimatedDistanceText)
                    .keyboardType(.decimalPad)
                    .font(AppFonts.body())
                    .padding()
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel("预计距离，选填，单位公里")
                    .accessibilityHint("请输入数字，不支持语音输入")
                    .onChange(of: viewModel.estimatedDistanceText) { newValue in
                        viewModel.sanitizeDistanceInput(newValue)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("配速偏好")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Picker("配速偏好", selection: $viewModel.pacePreference) {
                    ForEach(PacePreferenceOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("配速偏好，选填")
                .accessibilityHint("选择慢跑、中速或较快")
            }

            Toggle("需要同性志愿者", isOn: $viewModel.preferSameGender)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("是否需要同性志愿者，选填")
                .accessibilityHint("开启后记录偏好，MVP 不做复杂匹配")

            VoiceTextField(
                title: "备注",
                placeholder: "例如：我会带导盲杖",
                text: $viewModel.remark,
                isMultiline: true,
                speechInputService: speechInputService,
                fieldId: "remark",
                accessibilityLabel: "备注，选填",
                accessibilityHint: "可以使用语音或键盘输入备注"
            )
        }
    }

    private var submitArea: some View {
        VStack(spacing: 10) {
            PrimaryButton("提交预约", isLoading: viewModel.isSubmitting) {
                Task {
                    if let order = await viewModel.submit() {
                        onOrderCreated(order)
                    }
                }
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.45)
            .accessibilityLabel("提交预约")
            .accessibilityHint(viewModel.canSubmit ? "提交后等待志愿者接单" : "请先完成定位、出发地点和有效预约时间")

            PrimaryButton("重复当前状态") {
                speechService.speak("正在创建预约。出发地点：\(viewModel.resolvedStartLocationDescription)。预约时间：\(viewModel.appointmentTime.formatted(date: .abbreviated, time: .shortened))。")
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前预约表单状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Voice Text Field

struct VoiceTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isMultiline = false
    @ObservedObject var speechInputService: SpeechInputService
    let fieldId: String
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            HStack(alignment: .top, spacing: 8) {
                Group {
                    if isMultiline {
                        TextEditor(text: $text)
                            .frame(minHeight: 96)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(AppFonts.body())
                .padding()
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)

                Button {
                    speechInputService.startRecognition(fieldId: fieldId) { recognizedText in
                        text = recognizedText
                    }
                } label: {
                    Image(systemName: speechInputService.isListening(for: fieldId) ? "mic.fill" : "mic")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(AppColors.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("语音输入\(title)")
                .accessibilityHint("点击后说出内容，语音会转换为文字")
            }

            if let errorMessage = speechInputService.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
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
