import Combine
import SwiftUI

@MainActor
final class CompletedTrackSummaryViewModel: ObservableObject {
    @Published private(set) var track: OrderTrackResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(orderID: Int64, appState: AppState) async {
        isLoading = true
        errorMessage = nil
        do {
            track = try await appState.safety.orderTrack(orderId: orderID)
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) {
                errorMessage = "本次路线暂时无法加载。"
            }
        } catch {
            errorMessage = "本次路线暂时无法加载。"
        }
        isLoading = false
    }
}

/// 订单详情里内嵌的轨迹摘要 —— 对标 Strava 列表页那个压缩版式（窄地图 + 一行统计），
/// 大屏在下面那条链接后面：两个角色各进自己的跑后详情（D13；`OrderRouteReplayView` 阶段 5 已删）。
struct CompletedTrackSummaryView: View {
    let track: OrderTrackResponse
    let recordOrderId: Int64
    let role: RunRecordHistoryRole
    let repeatSummary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本次路线")
                .font(AppFonts.title())
                .accessibilityAddTraits(.isHeader)

            if let emptyText = track.emptyStateText {
                Text(emptyText).font(AppFonts.body())
            } else {
                TrackRouteMap(track: track)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilitySortPriority(-1)
                    .accessibilityIdentifier("completedTrackAuxiliaryMap")

                TrackStatsRow(stats: track.blindStats)

                // 独立成行而不是把地图本身做成链接：`MAMapView` 自己吃掉平移手势，
                // 包在 NavigationLink 里点不动。这一行同时也是读屏用户唯一能对上的入口。
                NavigationLink {
                    switch role {
                    case .runner: RunnerRunRecordView(orderId: recordOrderId)
                    case .volunteer: VolunteerRunRecordView(orderId: recordOrderId)
                    }
                } label: {
                    Label("查看跑后详情", systemImage: "map")
                        .font(AppFonts.body())
                }
                .frame(minHeight: 64)
                .accessibilityHint(role == .runner ? "听这次跑步的讲述和声音路线，查看每一公里" : "查看路线、配速、分段和途中记录")
                .accessibilityIdentifier("completedTrackFullScreenLink")
            }

            Button("重复当前状态", action: repeatSummary)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 64)
                .accessibilityHint("朗读本次路线的里程、时长和平均配速")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completedTrackSummary")
    }
}

// MARK: - Route Map

/// 已完成订单的轨迹地图（订单详情内嵌的那一张）。原先订单详情内嵌、全屏回放、盲人跑步记录三个入口共用一份，
/// 起终点标记和视口对齐只写在这里 —— 此前「志愿者服务记录有轨迹、近期服务没有」
/// 正是因为两个详情页各写各的（见 `docs/research/run-track-replay-ui-20260812.md` §3）。
///
/// 地图中心取的是轨迹外接矩形的中心而非起点，理由见
/// `OrderTrackResponse.primaryRouteBoundingCenter` 的注释 —— 传起点会让路线跑出屏幕。
struct TrackRouteMap: View {
    let track: OrderTrackResponse

    var body: some View {
        let coordinates = track.primaryRouteCoordinates
        if coordinates.count >= 2,
           let center = track.primaryRouteBoundingCenter,
           let start = coordinates.first,
           let end = coordinates.last {
            MapViewWrapper(
                centerCoordinate: center,
                showsUserLocation: false,
                annotations: [
                    MapAnnotationItem(id: "route-start", coordinate: start, title: "起点", subtitle: nil, kind: .routeStart),
                    MapAnnotationItem(id: "route-end", coordinate: end, title: "终点", subtitle: nil, kind: .routeEnd)
                ],
                polylines: [MapPolylineItem(id: "blind-primary-route", coordinates: coordinates, isPrimary: true)],
                tracksUserLocation: false,
                animatesCenterChanges: false
            )
            .accessibilityIdentifier("trackRouteMap")
        }
    }
}

// MARK: - Stats

/// 里程 / 时长 / 平均配速三列并排，数字大、标签小在下 —— 对标悦跑圈与 Strava 的活动详情页
/// （`docs/research/run-track-replay-ui-20260812.md` §2）。
///
/// 两点没有跟着对标产品照抄：
/// - **无障碍标签按「标签 值」的语序**。视觉是「值在上、标签在下」，
///   `children: .combine` 会照着视觉顺序读成「10.44 公里 里程」，语序是反的。
/// - **辅助功能字号下换成竖排**，不靠 `minimumScaleFactor` 压字。
///   缩字正是低视力用户最不需要的处理（见记忆 `low-vision-visual-channel-unaudited`）。
struct TrackStatsRow: View {
    let stats: TrackStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var items: [(label: String, value: String)] {
        var result: [(label: String, value: String)] = []
        if let value = stats.distanceText { result.append(("里程", value)) }
        if let value = stats.durationText { result.append(("时长", value)) }
        if let value = stats.averagePaceText { result.append(("平均配速", value)) }
        return result
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        layout {
            ForEach(items, id: \.label) { item in
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center, spacing: 4) {
                    Text(item.value)
                        .font(.title3.weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(item.label)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label) \(item.value)")
            }
        }
    }
}
