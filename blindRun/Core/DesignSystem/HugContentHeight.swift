import SwiftUI

// 邀请卡（`VolunteerInviteSheet.card`，#181）与星火页浮层（`XinghuoMapView.overlay`）共用的一份。
// 两处原先各有一份逐字相同的私有副本。

/// 高度 = min(子视图的理想高度, 父视图给的高度)。用来让常驻的 `ScrollView` 按内容定高：
/// 纵向 `ScrollView` 在不限高的提议下报的是内容高度，限高时照常滚。
struct HugContentHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? ideal.width,
            height: min(ideal.height, proposal.height ?? .infinity)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
