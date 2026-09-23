import SwiftUI
import UIKit

/// 自定义 overlay 盖住整屏时，把同一个宿主里 UIKit 平台容器（`TabView` → `UITabBarController`、
/// `NavigationStack` → `UINavigationController`）的整棵视图树对读屏藏起来。挂在被盖住那一层的 `.background` 上。
///
/// 🔴 **光用 SwiftUI 的 `.accessibilityHidden` 不够**：它跨不过 UIKit 平台视图边界，
/// 容器里的页面、push 出去的二级页和 UIKit 标签栏照样暴露；对容器根视图设
/// `accessibilityElementsHidden` 也不被采用。唯一真机实测有效的是把容器根视图的
/// `accessibilityElements` 置为 `[]`，恢复时设回 `nil`（记忆 `hide-uikit-hosted-tree-from-accessibility`）。
/// 纯 SwiftUI 的部分仍要调用方自己挂 `.accessibilityHidden` —— 两者管的不是同一段树。
///
/// 做法：从探针往上找到第一个 view controller（托管这一层的 hosting controller），
/// 把它**所有直接子控制器**的根视图子元素列表置空。overlay 本身是纯 SwiftUI、不是子控制器，不受影响。
struct HostedContainersAccessibilityHider: UIViewRepresentable {
    let isHidden: Bool

    final class Coordinator {
        var appliedIsHidden = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 只在翻转时写。挂在根上时宿主任何一次发布都会触发 update，每次都写 `nil`
        // 会把别处（例如邀请卡）对同一个容器置的 `[]` 冲掉。
        // ponytail: 两处同时要藏同一个容器时后收起的一方会把它放出来；目前两层遮罩互斥，真叠加了再做引用计数。
        guard context.coordinator.appliedIsHidden != isHidden else { return }
        context.coordinator.appliedIsHidden = isHidden
        let isHidden = isHidden
        // 推到下一拍：本次 update 里 responder 链与子控制器不一定已经就位。
        DispatchQueue.main.async {
            guard let host = sequence(first: uiView as UIResponder, next: \.next)
                .first(where: { $0 is UIViewController }) as? UIViewController
            else { return }
            for child in host.children {
                child.view.accessibilityElements = isHidden ? [] : nil
            }
        }
    }
}
