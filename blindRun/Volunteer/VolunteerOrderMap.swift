import SwiftUI

struct VolunteerOrderMap: View {
    @EnvironmentObject private var locationService: LocationService
    let order: OrderDetailResponse

    var body: some View {
        if let coordinate = orderCoordinate(order) {
            MapViewWrapper(
                centerCoordinate: coordinate,
                showsUserLocation: locationService.isAuthorized,
                annotations: [
                    MapAnnotationItem(
                        id: String(order.orderId),
                        coordinate: coordinate,
                        title: order.startAddress ?? "",
                        subtitle: order.blindName
                    )
                ],
                zoomLevel: 15
            )
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("地图，出发地点：\(order.startAddress ?? "地址待同步")")
            .accessibilityHint("地图用于视觉确认出发点；订单信息区域会读出地址和距离")
        }
    }
}
