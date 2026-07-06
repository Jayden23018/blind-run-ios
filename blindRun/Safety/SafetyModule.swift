import SwiftUI

// MARK: - Emergency Safety

enum EmergencySafetyCopy {
    static let title = "一键求助"
    static let confirmButtonTitle = "确认求助"
    static let cancelButtonTitle = "取消"
    static let confirmationMessage = "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
    static let placeholderMessage = "当前版本未开放紧急求助入口，请按既定人工安全预案处理。"
    static let deferredActionMessage = "当前版本未开放紧急求助入口，请按既定人工安全预案处理。"
    static let accessibilityLabel = "一键求助，遇到紧急情况时点击"
    static let accessibilityHint = "需要二次确认，当前版本未开放紧急求助入口"
}

struct EmergencyActionButton: View {
    let isLoading: Bool
    let action: () -> Void

    init(isLoading: Bool = false, action: @escaping () -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        PrimaryButton(EmergencySafetyCopy.title, isDestructive: true, isLoading: isLoading, action: action)
            .accessibilityLabel(EmergencySafetyCopy.accessibilityLabel)
            .accessibilityHint(EmergencySafetyCopy.accessibilityHint)
    }
}

struct EmergencyPlaceholderNotice: View {
    var body: some View {
        Text(EmergencySafetyCopy.placeholderMessage)
            .font(AppFonts.caption())
            .foregroundColor(AppColors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(EmergencySafetyCopy.placeholderMessage)
    }
}

extension View {
    func emergencyConfirmationAlert(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(EmergencySafetyCopy.title, isPresented: isPresented) {
            Button(EmergencySafetyCopy.confirmButtonTitle, role: .destructive, action: onConfirm)
            Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.confirmationMessage)
        }
    }
}
