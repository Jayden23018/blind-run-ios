import MessageUI
import SwiftUI

/// 系统短信 composer 的结果。**只有这三种，且都不代表送达。**
///
/// `.sent` 的含义是「用户在系统界面里点了发送」，不是「收件人收到了」——
/// Apple 文档对 `didFinishWith result:` 的说明就是这个口径。任何据此写出的
/// 「已通知家人」都是假的，文案约束见 `RunPlanShareCopy`。
enum MessageComposeOutcome {
    case sent
    case cancelled
    case failed
}

/// `MFMessageComposeViewController` 的 SwiftUI 包装。
///
/// **不做无障碍加工，也做不了**：系统 composer 跑在独立进程，App 无法往里注入
/// `accessibilityLabel`、traits 或自定义转子 —— 那棵无障碍树归 Apple。我们能做的全部
/// 在自己这一侧：呈现前的按钮 label / hint，以及**关闭后主动播报结果**。
/// 后者不是锦上添花：盲人看不到 sheet 收起，不播就等于按下去之后什么都没发生。
struct MessageComposeSheet: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (MessageComposeOutcome) -> Void

    /// 呈现前必须先问这一句。`false` 时**不要**呈现：系统 composer 没有存草稿这一步，
    /// 呈现出来只会是个什么都做不了的空壳。
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients
        // 预填只是建议：用户可以在系统界面里改掉收件人和正文，改完之后内容不再由 App 掌控。
        // 这是「不许宣称已送达」的第二个理由（第一个是 `.sent` 本身不保证送达）。
        controller.body = body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeOutcome) -> Void

        init(onFinish: @escaping (MessageComposeOutcome) -> Void) {
            self.onFinish = onFinish
        }

        /// 这里**不自己 dismiss**。Apple 的文档写的是「delegate 负责 dismiss」，那是 UIKit 的
        /// 呈现方式；在 SwiftUI 的 `.sheet` 里关闭权归 `isPresented`，两边都关会打架
        /// （sheet 已经收起，controller 再 dismiss 一次会把它上面那一层也带走）。
        /// 调用方在 `onFinish` 里把 `isPresented` 置 false，状态保持单一真相。
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            switch result {
            case .sent:
                onFinish(.sent)
            case .cancelled:
                onFinish(.cancelled)
            case .failed:
                onFinish(.failed)
            // 未来新增的结果一律按「没成功」处理：宁可让用户去短信里确认一次，
            // 也不要把一个不认识的结果说成已发送。
            default:
                onFinish(.failed)
            }
        }
    }
}
