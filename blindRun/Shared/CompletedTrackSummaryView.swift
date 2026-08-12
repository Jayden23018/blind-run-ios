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
            let response: OrderTrackResponse = try await appState.apiClient.get("/api/orders/\(orderID)/track")
            track = response
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

struct CompletedTrackSummaryView: View {
    let track: OrderTrackResponse
    let repeatSummary: () -> Void

    private var routeOverlay: [MapPolylineItem] {
        guard track.primaryRouteCoordinates.count >= 2 else { return [] }
        return [MapPolylineItem(id: "blind-primary-route", coordinates: track.primaryRouteCoordinates, isPrimary: true)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本次路线")
                .font(AppFonts.title())
                .accessibilityAddTraits(.isHeader)

            if let emptyText = track.emptyStateText {
                Text(emptyText).font(AppFonts.body())
            } else {
                if let first = track.primaryRouteCoordinates.first {
                    MapViewWrapper(
                        centerCoordinate: first,
                        showsUserLocation: false,
                        polylines: routeOverlay,
                        tracksUserLocation: false,
                        animatesCenterChanges: false
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilitySortPriority(-1)
                    .accessibilityIdentifier("completedTrackAuxiliaryMap")
                }
                summaryRows
            }

            Button("重复当前状态", action: repeatSummary)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 64)
                .accessibilityHint("朗读本次路线的里程、时长和平均配速")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completedTrackSummary")
    }

    @ViewBuilder
    private var summaryRows: some View {
        if let value = track.blindStats.distanceText { summaryRow("里程", value) }
        if let value = track.blindStats.durationText { summaryRow("时长", value) }
        if let value = track.blindStats.averagePaceText { summaryRow("平均配速", value) }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(AppFonts.body())
        .accessibilityElement(children: .combine)
    }
}
