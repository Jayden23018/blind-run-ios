import SwiftUI

// MARK: - 出发前给陪跑员留一句话（`PUT /api/orders/{id}/runner-message`）

extension RunOrderStatus {
    /// 陪跑员已确定、还没开跑的四态才能留言（契约 `runner-message` 的前置状态，逐字）。
    var acceptsRunnerMessage: Bool {
        [.scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived].contains(self)
    }
}

/// 留言表单页。保存 / 清空都交给 `onSave`，它返回错误文案（`nil` = 成功，本页自己关掉）。
///
/// 错误显示在**这一页**而不是订单页的 footer：表单页盖着订单页，写在底下等于没写。
struct RunnerMessageSheet: View {
    let initialText: String
    let onSave: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(initialText: String, onSave: @escaping (String) async -> String?) {
        self.initialText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    private var length: Int { text.trimmed.utf16.count }
    private var isTooLong: Bool { length > RunnerMessageRequest.maxLength }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("出发前给陪跑员留一句话，比如你穿什么颜色的衣服、在入口哪一侧等。陪跑员会在订单页看到。")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("例如：我穿红色外套，在东门等你", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .font(AppFonts.body())
                        .padding()
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .accessibilityLabel("给陪跑员的留言")
                        .accessibilityHint("最多 \(RunnerMessageRequest.maxLength) 个字")
                        .accessibilityIdentifier("runnerMessageTextField")

                    Text("\(length)/\(RunnerMessageRequest.maxLength)")
                        .font(AppFonts.caption())
                        .foregroundColor(isTooLong ? AppColors.destructive : AppColors.textSecondary)
                        .accessibilityLabel("已写 \(length) 个字，最多 \(RunnerMessageRequest.maxLength) 个字")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("runnerMessageError")
                    }

                    PrimaryButton("发给陪跑员", isLoading: isSaving) { save(text) }
                        .disabled(isSaving)
                        .accessibilityIdentifier("runnerMessageSaveButton")

                    if !initialText.trimmed.isEmpty {
                        Button { save("") } label: {
                            Text("清空留言")
                                .font(AppFonts.primaryButton())
                                .foregroundColor(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(12)
                        }
                        .disabled(isSaving)
                        .accessibilityHint("陪跑员那边将不再显示这句留言")
                    }
                }
                .readableContentColumn()
                .padding(24)
            }
            .background(AppColors.background)
            .navigationTitle("给陪跑员留言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save(_ value: String) {
        isSaving = true
        errorMessage = nil
        Task {
            let error = await onSave(value)
            isSaving = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}
