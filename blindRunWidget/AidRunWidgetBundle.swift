import SwiftUI
import WidgetKit

/// 本扩展目前**只装锁屏实时活动**，没有主屏小组件。
/// 加小组件的话在这里再挂一个 `Widget`，不要另起 extension target。
@main
struct AidRunWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            RunLiveActivityWidget()
            GuideRunActivityWidget()
        }
    }
}
