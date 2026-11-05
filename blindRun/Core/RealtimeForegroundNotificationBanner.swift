import Combine
import Foundation
import SwiftUI

struct RealtimeForegroundNotificationBanner: View {
    let notification: RealtimeForegroundNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.priority == .high ? "exclamationmark.triangle.fill" : "bell.fill")
                .foregroundColor(notification.priority == .high ? AppColors.destructive : AppColors.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title = notification.title?.nilIfBlank {
                    Text(title).font(AppFonts.body().weight(.bold))
                }
                Text(notification.displayText).font(AppFonts.body())
            }
            Spacer(minLength: 8)
            // `TextButtonStyle` 自带 `maxWidth: .infinity`：不收住宽度会和上面的 Spacer 对半分这一行，把通知文字挤窄。
            Button(action: onDismiss) {
                Text("关闭").frame(minWidth: AppTouchTarget.blindPrimary)
            }
            .buttonStyle(TextButtonStyle(alignment: .center))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHint("关闭当前通知并显示下一条通知")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(notification.priority == .high ? AppColors.destructive : AppColors.primary, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notification.speechText)
        .accessibilityAddTraits(notification.priority == .high ? .isHeader : [])
        .accessibilityIdentifier("realtimeForegroundNotification")
    }
}
