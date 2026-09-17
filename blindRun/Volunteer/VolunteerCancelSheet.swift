import SwiftUI

// MARK: - 「取消这次陪跑？」底部弹层

/// 设计交付文档 v3 §5 的取消确认层（草图 `png/04-取消迟到爽约.png` 左一）。
///
/// 从 `confirmationDialog` 换成弹层的理由是**版位**：系统对话框把两个选项排成等宽两枚按钮，
/// 而这一屏的默认动作明确是「不取消」——黄色主按钮给「保留这次陪跑」，
/// 「仍然取消」是底下一行灰字。**不用红色**：实心红在本 App 里只给紧急求助（§1.2）。
///
/// 文案全部来自 `VolunteerOrderFlowCopy.cancelSheet(for:plannedStart:)`，这里一个中文字面量都没有
/// —— 那一段里写着为什么 12 小时那句话只说「会马上重新找人」、不提任何取消记录。
struct VolunteerCancelSheet: View {
    let copy: VolunteerOrderFlowCopy.CancelSheetCopy
    let isSubmitting: Bool
    let onKeep: () -> Void
    let onCancelOrder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.title)
                .font(AppFonts.title())
                .accessibilityAddTraits(.isHeader)

            if let lateNotice = copy.lateNotice {
                Text(lateNotice)
                    .font(AppFonts.body())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("volunteerCancelSheetLateNotice")
            }

            Text(copy.message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowActionButton(
                copy.keep,
                style: .primary,
                accessibilityHint: "关掉这一层，这一单仍然是你的"
            ) {
                onKeep()
            }
            .accessibilityIdentifier("volunteerCancelSheetKeep")

            Button(action: onCancelOrder) {
                Group {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text(copy.cancel)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                // 灰字按钮也要够得着：64pt 是本仓库盲人端的最小触达（低视力志愿者同样受益）。
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
            }
            .disabled(isSubmitting)
            .accessibilityLabel(copy.cancel)
            .accessibilityHint("这一单会转给其他志愿者")
            .accessibilityIdentifier("volunteerCancelSheetConfirm")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableContentColumn()
    }
}

#if DEBUG
#Preview("取消弹层 · 12 小时内") {
    VolunteerCancelSheet(
        copy: VolunteerOrderFlowCopy.cancelSheet(
            for: .pendingAccept,
            plannedStart: Date().addingTimeInterval(3 * 3600)
        ),
        isSubmitting: false,
        onKeep: {},
        onCancelOrder: {}
    )
}

#Preview("取消弹层 · 还早") {
    VolunteerCancelSheet(
        copy: VolunteerOrderFlowCopy.cancelSheet(
            for: .scheduledConfirmed,
            plannedStart: Date().addingTimeInterval(72 * 3600)
        ),
        isSubmitting: false,
        onKeep: {},
        onCancelOrder: {}
    )
}
#endif
