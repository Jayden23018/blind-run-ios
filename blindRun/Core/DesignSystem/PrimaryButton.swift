import SwiftUI

// MARK: - Primary Button

/// 全宽大按钮，盲人端主操作按钮最小高度 64pt。
/// 支持普通和危险操作两种样式。
struct PrimaryButton: View {
    let title: String
    let isDestructive: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        isDestructive: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(AppFonts.primaryButton())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .background(isDestructive ? AppColors.destructive : AppColors.primary)
            .cornerRadius(12)
        }
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityHint(isDestructive ? "危险操作，需要二次确认" : "点击执行操作")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton("提交预约") {}
        PrimaryButton("取消订单", isDestructive: true) {}
        PrimaryButton("加载中", isLoading: true) {}
    }
    .padding()
}
