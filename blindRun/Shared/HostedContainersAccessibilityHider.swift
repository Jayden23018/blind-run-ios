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
        /// 藏着期间定时补藏后出现的容器（#414）：冷启动时同行态同意页先盖上来，根路由还在「正在恢复账号资料」，
        /// 志愿者主页的 `TabView` 是之后才挂上的子控制器 —— 只在翻转那一拍藏一次，它就整棵留在读屏树里。
        /// ponytail: 0.3 秒轮询，只在遮罩盖着时跑；要省掉就换成监听宿主 `children` 的变化（UIKit 没有现成通知）。
        var reapplyTimer: Timer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.reapplyTimer?.invalidate()
        coordinator.reapplyTimer = nil
    }

    /// 从探针往上找宿主，把它的直接子控制器的根视图子元素列表置空（藏）或设回 `nil`（放）。
    /// 藏的时候跳过已经是空列表的，免得定时补藏每一拍都改写一次无障碍树。
    private static func apply(isHidden: Bool, from probe: UIView) {
        guard let host = sequence(first: probe as UIResponder, next: \.next)
            .first(where: { $0 is UIViewController }) as? UIViewController
        else { return }
        for child in host.children {
            if isHidden {
                if child.view.accessibilityElements?.isEmpty != true { child.view.accessibilityElements = [] }
            } else {
                child.view.accessibilityElements = nil
            }
        }
    }

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
        let coordinator = context.coordinator
        guard coordinator.appliedIsHidden != isHidden else { return }
        coordinator.appliedIsHidden = isHidden
        coordinator.reapplyTimer?.invalidate()
        coordinator.reapplyTimer = nil
        let isHidden = isHidden
        // 推到下一拍：本次 update 里 responder 链与子控制器不一定已经就位。
        DispatchQueue.main.async { [weak uiView] in
            // 这一拍之前又翻回去了：交给后来那次，别在它之后再藏一遍、再起一个定时器。
            guard let uiView, coordinator.appliedIsHidden == isHidden else { return }
            Self.apply(isHidden: isHidden, from: uiView)
            guard isHidden else { return }
            coordinator.reapplyTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak uiView] _ in
                guard let uiView else { return }
                Self.apply(isHidden: true, from: uiView)
            }
        }
    }
}

/// 系统模态（`fullScreenCover` / `sheet`）弹出时，把**弹出它的那一层**整棵视图树对读屏藏起来。
/// 挂在被弹出内容里（`.background(PresenterAccessibilityHider())`），出现即藏、移除即放。
///
/// 🔴 **系统模态并不会自动做这件事**：2026-10-14 真机（iPhone 16 Pro，iOS 27.0.1）实测，
/// 语音下单同意页（`fullScreenCover`）完全盖住下单页 3 秒后，下单页的导航栏和按钮仍在 XCUITest 树里，
/// 只是 `isHittable == false`（#374 的 `testVoiceOrderConsentIsolatesTheScreenAndDeclineFallsBackToTheForm`）。
/// 上面那个类型从挂载点往上找宿主，从被弹出的内容里找不到被盖住的那一层，所以另起一个，走 `presentingViewController`。
/// 弹出方实测是根部的 `UIHostingController<ContentView>`：对**它的**根视图置空无效（与上面同一个限制），
/// 要置空它的直接子控制器（`TabView` 的 `UITabBarController` 挂在那里）。
struct PresenterAccessibilityHider: UIViewRepresentable {
    final class Coordinator {
        var hiddenViews: [UIView] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        let coordinator = context.coordinator
        // 推到下一拍：makeUIView 时探针还没进窗口，responder 链接不上被弹出的控制器。
        DispatchQueue.main.async {
            guard coordinator.hiddenViews.isEmpty,
                  let presented = sequence(first: view as UIResponder, next: \.next)
                    .first(where: { $0 is UIViewController }) as? UIViewController,
                  let presenter = presented.presentingViewController
            else { return }
            let targets = presenter.children.isEmpty ? [presenter.view!] : presenter.children.map(\.view!)
            for target in targets { target.accessibilityElements = [] }
            coordinator.hiddenViews = targets
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        for view in coordinator.hiddenViews { view.accessibilityElements = nil }
        coordinator.hiddenViews = []
    }
}
