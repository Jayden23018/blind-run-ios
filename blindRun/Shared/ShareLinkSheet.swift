import SwiftUI
import UIKit

/// `UIActivityViewController` 的 SwiftUI 包装，与 `MessageComposeSheet` 同一套做法
/// （系统界面归系统，我们只负责呈现前后的播报）。
///
/// **为什么不用 `ShareLink`**：`ShareLink` 是一个「用户点它才弹面板」的按钮，要求分享内容
/// 在渲染时就已经存在。这里的链接要先 `POST /api/orders/{id}/share` 才拿得到，
/// 用 `ShareLink` 就得让用户在拿到链接后**再点一次**。对读屏用户，多一次「找到并点中新出现的
/// 按钮」是实打实的成本，而这一步没有任何决策价值 —— 他刚刚才在告知页上按过同意。
///
/// **不做无障碍加工，也做不了**：分享面板是系统托管的，App 注入不了 label 或 traits。
struct ShareLinkSheet: UIViewControllerRepresentable {
    let text: String
    /// 面板关闭时回调。**参数刻意不带「有没有分享成功」** ——
    /// `completionWithItemsHandler` 的 `completed` 只说明用户选没选目标应用，
    /// 不代表对方收到，据它写「已发给家人」就是 `RunPlanLiveShareCopy` 顶部禁的那种话。
    /// 而链接在服务端已经生效，用户选不选目标都一样在分享中，所以这里两种情况文案相同。
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
    }
}

/// `.sheet(item:)` 需要的 `Identifiable` 包装。
///
/// 用 `item:` 而不是 `isPresented:` + 另存一个 `@State`：链接是异步拿到的，
/// 两个状态分开就有「已置 true 但链接还是 nil」的空窗，那一帧会呈现一个空分享面板。
struct ShareLinkPayload: Identifiable, Equatable {
    let id = UUID()
    let text: String
}
