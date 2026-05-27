import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var nickname = ""
    @Published var pointsBalance = 0
    @Published var rows: [VolunteerAvailableOrderRow] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isUpdatingAvailability = false

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var statusText: String {
        isAvailable ? "可接单" : "已关闭接单"
    }

    var statusColor: Color {
        isAvailable ? AppColors.success : AppColors.textSecondary
    }

    var acceptBlockMessage: String? {
        VolunteerOrderActionGuard.acceptBlockMessage(profile: appState?.volunteerProfile)
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        apply(profile: appState.volunteerProfile)
    }

    func load(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let appState else { return }
        isLoading = rows.isEmpty
        errorMessage = nil

        do {
            let response: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(response)
            apply(profile: response.volunteerProfile)

            let orders: [AvailableOrderDto] = try await appState.apiClient.get("/api/orders/available")
            rows = VolunteerAvailableOrderRow.sortedRows(
                orders: orders,
                from: currentLocation,
                locationAuthorized: locationAuthorized
            )
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "订单加载失败，请重试"
            speechService?.speakError("订单加载失败，请重试")
        }
    }

    func setAvailability(_ value: Bool) {
        guard !isUpdatingAvailability, let appState else { return }

        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil

        do {
            let profile: VolunteerProfileDto = try await appState.apiClient.patch(
                "/api/volunteer/availability",
                body: AvailabilityRequest(isAvailable: value)
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }

    private func apply(profile: VolunteerProfileDto?) {
        guard let profile else { return }
        nickname = profile.nickname
        isAvailable = profile.isAvailable
        pointsBalance = profile.pointsBalance
    }
}

// MARK: - Volunteer Home View

struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerHomeViewModel()
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var recenterToken = 0

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    homeMap

                    VStack(spacing: 0) {
                        homeStatusOverlay
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        Spacer()

                        recenterButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        nearbyDemandPanel(maxHeight: proxy.size.height * 0.45)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                }
                .background(AppColors.background)
            }
            .navigationTitle("志愿者首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        VolunteerSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                    .accessibilityHint("进入设置页面")
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomEntries
            }
            .task {
                viewModel.configure(with: appState, speechService: speechService)
                locationService.requestPermission()
                locationService.startUpdating()
                mapCenter = locationService.effectiveLocation
                await loadHome()
            }
            .onReceive(locationService.$currentLocation) { location in
                guard mapCenter == nil, let location else { return }
                mapCenter = location
            }
        }
    }

    private var homeMap: some View {
        MapViewWrapper(
            centerCoordinate: mapCenter ?? locationService.effectiveLocation,
            showsUserLocation: locationService.isAuthorized,
            annotations: viewModel.rows.map(\.annotation),
            zoomLevel: 13,
            recenterToken: recenterToken
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("地图，显示当前位置和附近可接订单点位")
        .accessibilityHint("地图只用于查看附近需求，不提供路线导航或实时轨迹")
        .accessibilityIdentifier("volunteerHomeMap")
    }

    private var homeStatusOverlay: some View {
        VolunteerHomeStatusOverlay(
            nickname: viewModel.nickname.isEmpty ? "志愿者" : viewModel.nickname,
            pointsBalance: viewModel.pointsBalance,
            orderCount: viewModel.rows.count,
            statusText: viewModel.statusText,
            statusColor: viewModel.statusColor,
            isUpdatingAvailability: viewModel.isUpdatingAvailability,
            isApproved: appState.isVolunteerProfileApproved,
            isAvailable: Binding(
                get: { viewModel.isAvailable },
                set: { viewModel.setAvailability($0) }
            ),
            locationText: locationSummaryText,
            acceptBlockMessage: viewModel.acceptBlockMessage
        )
    }

    private var recenterButton: some View {
        Button {
            locationService.requestOneTimeLocation()
            mapCenter = locationService.effectiveLocation
            recenterToken += 1
        } label: {
            Label("回到当前位置", systemImage: "location.fill")
                .font(AppFonts.body().weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(AppColors.background)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 4)
        }
        .accessibilityLabel("回到当前位置")
        .accessibilityHint("将地图中心移动到当前定位，不提供路线导航")
    }

    private func nearbyDemandPanel(maxHeight: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                nearbyOrdersHeader

                if viewModel.isLoading {
                    ProgressView("正在加载订单...")
                        .accessibilityLabel("正在加载订单")
                } else if viewModel.rows.isEmpty {
                    EmptyStateView(
                        title: "暂无可用订单",
                        message: locationService.isAuthorized ? "请稍后刷新。" : "开启定位后可查看距离并接单。"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.rows.prefix(3))) { row in
                            NavigationLink {
                                VolunteerOrderDetailView(orderId: row.order.id, initialOrder: row.order)
                            } label: {
                                VolunteerAvailableOrderCard(row: row, locationAuthorized: locationService.isAuthorized)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(row.accessibilityLabel(locationAuthorized: locationService.isAuthorized))
                            .accessibilityHint("点击查看订单详情")
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }

                #if DEBUG
                DebugTestingPanel()
                    .environmentObject(appState)
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: -8)
    }

    private var nearbyOrdersHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("附近需求 (\(viewModel.rows.count))")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink {
                    VolunteerOrderListView()
                } label: {
                    Text("查看全部")
                        .font(AppFonts.body().weight(.semibold))
                }
                .accessibilityLabel("查看全部订单")
                .accessibilityHint("查看所有可接订单")

                Button {
                    Task { await loadHome() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("刷新附近订单")
                .accessibilityHint("重新加载附近可接订单")
            }

            Text(locationService.isAuthorized ? "地图标点代表附近真实可接机会。" : "定位未开启，订单仍可浏览，但距离隐藏且接单会被禁用。")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return viewModel.rows.isEmpty ? "当前位置已同步" : "附近有 \(viewModel.rows.count) 个可接订单"
        }
        return "需要开启定位权限才能查看距离和接单"
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.effectiveLocation,
            locationAuthorized: locationService.isAuthorized
        )
        if mapCenter == nil {
            mapCenter = locationService.effectiveLocation
        }
    }

    private var bottomEntries: some View {
        HStack(spacing: 10) {
            NavigationLink {
                VolunteerOrderListView()
            } label: {
                VolunteerEntryItem(icon: "list.bullet.rectangle", title: "订单")
            }
            .accessibilityLabel("附近可接订单")
            .accessibilityHint("查看所有可接订单")

            NavigationLink {
                VolunteerServiceRecordsView()
            } label: {
                VolunteerEntryItem(icon: "clock.arrow.circlepath", title: "记录")
            }
            .accessibilityLabel("我的服务记录")

            NavigationLink {
                VolunteerPointsPlaceholderView()
            } label: {
                VolunteerEntryItem(icon: "gift", title: "积分")
            }
            .accessibilityLabel("积分商城")
            .accessibilityHint("查看积分和商城占位页")

            NavigationLink {
                VolunteerSettingsView()
            } label: {
                VolunteerEntryItem(icon: "gearshape", title: "设置")
            }
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct VolunteerHomeStatusOverlay: View {
    let nickname: String
    let pointsBalance: Int
    let orderCount: Int
    let statusText: String
    let statusColor: Color
    let isUpdatingAvailability: Bool
    let isApproved: Bool
    @Binding var isAvailable: Bool
    let locationText: String
    let acceptBlockMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nickname)
                        .font(.title3.bold())
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)

                    Text("当前积分：\(pointsBalance)分")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel("当前积分：\(pointsBalance)分")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Toggle(
                        isOn: $isAvailable
                    ) {
                        Text("可服务开关")
                    }
                    .labelsHidden()
                    .disabled(!isApproved || isUpdatingAvailability)
                    .accessibilityLabel("可服务开关，\(statusText)")
                    .accessibilityHint("关闭后其他用户看不到你的接单状态，但不影响当前订单")

                    if isUpdatingAvailability {
                        ProgressView()
                            .accessibilityLabel("正在更新可服务状态")
                    }
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(statusColor)
                Text("·")
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
                Text("附近 \(orderCount) 个需求")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前状态：\(statusText)，附近有 \(orderCount) 个需求")

            Text(locationText)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(locationText)

            if let acceptBlockMessage {
                Text(acceptBlockMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(acceptBlockMessage)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 6)
    }
}

private struct VolunteerEntryItem: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundColor(AppColors.primary)
    }
}

#if DEBUG
#Preview {
    VolunteerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
