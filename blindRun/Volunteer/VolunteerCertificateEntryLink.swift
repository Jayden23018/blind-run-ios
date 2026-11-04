import SwiftUI
import UIKit

// 从 `VolunteerCertificateUploadView.swift` 原样挪出（#700 改版后那个文件超出 SwiftLint 棘轮）。

// MARK: - Certificate Entry Link

/// 复用的入口行：设置页与首页「尚未通过资质认证」提示共用同一个跳转。
///
/// 标题**默认按认证路径推**，不由调用方硬传 —— 三个调用点里漏改一个，
/// 拒绝了人脸的志愿者就会看到「上传资质证书」，而他手上没有资质证书，
/// 点进去的页面又写着「身份材料」，两处对不上。想覆盖仍可显式传 `title`。
struct VolunteerCertificateUploadEntryLink: View {
    @EnvironmentObject private var appState: AppState

    var title: String?
    var subtitle: String?

    private var isAlternativeIdentityPath: Bool {
        appState.volunteerRegistrationStatus?.hasDeclinedFaceVerification == true
    }

    private var resolvedTitle: String {
        title ?? (isAlternativeIdentityPath ? "上传身份材料" : "上传资质证书")
    }

    private var resolvedSubtitle: String {
        subtitle ?? (isAlternativeIdentityPath
            ? "人工审核通过后才能接单，审核时间较长但结果等效"
            : "\(VolunteerCertificateCopy.issuerName)颁发的证书，审核通过后才能接单")
    }

    var body: some View {
        NavigationLink {
            VolunteerCertificateUploadView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.arrow.up")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedTitle)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(resolvedSubtitle)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(minHeight: 64)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(resolvedTitle)
        .accessibilityHint(resolvedSubtitle)
        .accessibilityIdentifier("volunteerCertificateUploadEntry")
    }
}

// MARK: - Camera Picker

/// 相机拍照。使用系统原生 `UIImagePickerController`，不引入新依赖。
struct VolunteerCertificateCameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
