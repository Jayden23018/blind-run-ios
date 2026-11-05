import SwiftUI

struct VolunteerServiceRecordRow: View {
    let record: VolunteerServiceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.sortKey.displayDateTime)
                    .font(.headline)
                Spacer()
                Text(record.order.status.displayName)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(record.order.status == .completed ? AppColors.success : AppColors.textSecondary)
            }
            Text("盲人：\(record.order.blindName ?? "")")
                .font(AppFonts.body())
            Text(record.order.startAddress ?? "")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            // 这里此前是 `record.pointsText`，恒为「+100 积分」——一个后端不存在的数字。
            // 删掉不补：完成状态已经在上面那行显示了，服务量在「服务成就」页。
        }
        .padding(.vertical, 4)
    }
}
