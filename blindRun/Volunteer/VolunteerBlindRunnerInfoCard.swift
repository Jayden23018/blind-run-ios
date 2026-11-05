import SwiftUI

struct VolunteerBlindRunnerInfoCard: View {
    @Environment(\.openURL) private var openURL
    let order: OrderDetailResponse
    let showPhone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("盲人跑者")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(order.blindName ?? "盲人跑者")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                // 上屏那份留掩码星号，念出来这份去掉。
                .accessibilityLabel("盲人：\(order.blindName?.unmaskedForSpeech ?? "")")

            if showPhone, let phone = order.blindPhone {
                Button {
                    if let url = EmergencyDialer.telURL(for: phone) {
                        EmergencyDialer.dial(url, open: { openURL($0) })
                    }
                } label: {
                    Label(
                        EmergencyContactResponse.maskPhone(phone) ?? phone,
                        systemImage: "phone.fill"
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("拨打盲人电话")
            } else {
                Text("联系方式将在接单后显示")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("联系方式将在接单后显示")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }
}
