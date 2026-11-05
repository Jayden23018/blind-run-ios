import SwiftUI

// MARK: - Reusable Views

struct VolunteerStatusBanner: View {
    let status: RunOrderStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.statusSymbolName)
                .font(.title)
                .foregroundColor(status.statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.displayName)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text(status.volunteerDescription)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.displayName)，\(status.volunteerDescription)")
    }
}
