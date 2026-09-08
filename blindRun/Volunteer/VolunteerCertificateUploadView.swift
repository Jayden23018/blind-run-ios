import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

//
//  志愿者资质证书上传（POST /api/volunteer/verification）
//
//  契约唯一源是后端仓库源码（api_spec.yaml 与源码冲突时以源码为准）：
//  - 字段名 `file`（`VolunteerController.java:64` `@RequestParam("file")`，multipart/form-data）
//  - Content-Type 必须 `image/*` 或 `application/pdf`（`VolunteerController.java:73`）
//  - 大小上限 5 MB（`VolunteerController.java:77` `file.getSize() > 5 * 1024 * 1024`）
//  - 扩展名白名单 .jpg/.jpeg/.png/.gif/.webp/.bmp/.pdf（`LocalFileStorageService.java:26`）
//  - 存储层还会校验魔数与扩展名是否匹配（`LocalFileStorageService.java:96`），
//    所以客户端一律**按内容嗅探**决定扩展名与 MIME，不信任来源文件名。
//  - 成功响应 `{"success":true,"status":"PENDING"}`；失败是 400 且**没有 errorCode**，
//    只有 `{"success":false,"code":400,"message":"..."}`。
//  - 状态查询 `GET /api/volunteer/verification/status` → `{"status":"NONE|PENDING|APPROVED|REJECTED"}`
//    （`VolunteerController.java:86`）。只有 APPROVED 对应 `verified=true`，其余三态都接不了单。
//
//  隐私：证书文件属于敏感材料。不写日志、不落 UserDefaults/Keychain、不在无障碍文案里
//  出现原始文件名或本地路径；界面只展示「类型 + 大小」。
//

// MARK: - Backend Response

/// `POST /api/volunteer/verification` 与 `GET /api/volunteer/verification/status` 共用。
/// 上传响应含 `success` + `status`，状态查询只含 `status`，都是可选解码。
struct VolunteerVerificationStatusResponse: Codable, Sendable {
    let success: Bool?
    let status: String?

    init(success: Bool? = nil, status: String? = nil) {
        self.success = success
        self.status = status
    }
}

// MARK: - Certificate Status

/// 后端 `VerificationStatus` 的四个取值。未知取值落 `.unknown`，不抛解码错误。
enum VolunteerCertificateStatus: String, Codable, Sendable {
    case none = "NONE"
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case unknown = "UNKNOWN"

    static func parse(_ raw: String?) -> VolunteerCertificateStatus {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return .unknown }
        return VolunteerCertificateStatus(rawValue: raw.uppercased()) ?? .unknown
    }
}

/// 页面实际展示的五态：四个后端状态 + 「状态拉取失败」。
/// 纯数据，无副作用，便于单测。
enum VolunteerCertificateDisplayState: Equatable, Sendable {
    case notSubmitted
    case pending
    case approved
    case rejected
    /// `GET /api/volunteer/verification/status` 失败：不猜测状态，也不允许盲传。
    case statusUnavailable

    static func from(status: VolunteerCertificateStatus, statusLoadFailed: Bool) -> VolunteerCertificateDisplayState {
        if statusLoadFailed { return .statusUnavailable }
        switch status {
        case .none: return .notSubmitted
        case .pending: return .pending
        case .approved: return .approved
        case .rejected: return .rejected
        case .unknown: return .statusUnavailable
        }
    }

    var displayName: String {
        switch self {
        case .notSubmitted: return "未提交"
        case .pending: return "审核中"
        case .approved: return "已通过"
        case .rejected: return "未通过"
        case .statusUnavailable: return "状态未知"
        }
    }

    /// 是否可以接单。只有 APPROVED 为真（后端 `ScoringService` 与接单守卫都只认 `verified=true`）。
    var canAcceptOrders: Bool {
        self == .approved
    }

    /// 是否允许发起上传。审核中不重复上传；已通过后端会直接拒绝；状态未知时先取回状态再说。
    var allowsUpload: Bool {
        self == .notSubmitted || self == .rejected
    }

    /// 明确告诉志愿者「现在能不能接单、下一步做什么」。走人脸活体那条路的文案。
    var guidanceMessage: String {
        switch self {
        case .notSubmitted:
            return "尚未提交资质证书，当前无法接单。请上传资质证书图片或 PDF，提交后由管理员审核。"
        case .pending:
            return "资质证书已提交，正在等待管理员审核。审核中暂时无法接单，也不需要重复上传，请耐心等待。"
        case .approved:
            return "资质证书已通过审核，你现在可以接单了。请回到首页开启接单开关。"
        case .rejected:
            return "资质证书未通过审核，当前无法接单。请重新上传清晰完整的证书图片或 PDF。"
        case .statusUnavailable:
            return "暂时无法获取资质审核状态，因此无法确认能否接单。请检查网络后重新获取状态。"
        }
    }

    /// 按认证路径选文案。
    ///
    /// 两条路径走的是**同一个端点、同一个存储槽位**（`POST /api/volunteer/verification`），
    /// 后端不区分也无法区分上传的是什么 —— 差别只在客户端怎么称呼它：
    /// 走活体的人传「资质证书」，拒绝人脸的人传「能证明本人身份的材料」。
    /// 所以这里只分文案，**不分端点、不加参数**。
    ///
    /// 🚨 替代路径那套里**不得出现「资质证书」**（他要传的不是这个，照着找会找不到东西），
    /// 也**不得编审核时长**：只说「审核时间较长，但结果等效」，与用户协议 `:194` 逐字一致。
    func guidance(isAlternativeIdentityPath: Bool) -> String {
        guard isAlternativeIdentityPath else { return guidanceMessage }
        switch self {
        case .notSubmitted:
            return "尚未提交身份材料，当前无法接单。请上传能证明本人身份的材料，图片或 PDF 均可，提交后由管理员人工审核。该方式审核时间较长，但结果等效。"
        case .pending:
            return "身份材料已提交，正在等待管理员人工审核。该方式审核时间较长，但结果等效。审核期间暂时无法接单，也不需要重复上传。"
        case .approved:
            return "身份材料已通过人工审核，你现在可以接单了。请回到首页开启接单开关。"
        case .rejected:
            return "身份材料未通过人工审核，当前无法接单。请重新上传能清晰证明本人身份的材料。"
        case .statusUnavailable:
            return "暂时无法获取审核状态，因此无法确认能否接单。请检查网络后重新获取状态。"
        }
    }
}

// MARK: - Local File Rules

/// 客户端本地校验规则，逐条对齐后端实现（见文件头注释）。
/// 超限或类型不对时**不发请求**，直接给可听的错误。
enum VolunteerCertificateFileRules {
    /// `VolunteerController.java:77`：`file.getSize() > 5 * 1024 * 1024` 即 400。
    static let maxByteCount = 5 * 1024 * 1024

    /// `LocalFileStorageService.java:26` 的扩展名白名单。
    static let allowedExtensions: [String] = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "pdf"]

    static func mimeType(forExtension fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        default: return nil
        }
    }

    /// 按内容魔数判定真实类型，签名与 `LocalFileStorageService.validateMagicBytes` 一一对应。
    /// 返回 nil 表示后端一定会拒（HEIC 等），调用方需要先转码。
    static func detectExtension(from data: Data) -> String? {
        func matches(_ offset: Int, _ expected: [UInt8]) -> Bool {
            guard data.count >= offset + expected.count else { return false }
            let start = data.index(data.startIndex, offsetBy: offset)
            for (index, byte) in expected.enumerated() where data[data.index(start, offsetBy: index)] != byte {
                return false
            }
            return true
        }

        if matches(0, [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if matches(0, [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if matches(0, [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if matches(0, [0x52, 0x49, 0x46, 0x46]) && matches(8, [0x57, 0x45, 0x42, 0x50]) { return "webp" }
        if matches(0, [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if matches(0, [0x42, 0x4D]) { return "bmp" }
        return nil
    }

    static func validate(fileExtension: String, byteCount: Int) -> VolunteerCertificateFileError? {
        if byteCount <= 0 { return .emptyFile }
        guard allowedExtensions.contains(fileExtension.lowercased()) else { return .unsupportedType }
        if byteCount > maxByteCount { return .tooLarge(byteCount: byteCount) }
        return nil
    }

    static func sizeText(_ byteCount: Int) -> String {
        let megabytes = Double(byteCount) / 1_048_576
        if megabytes >= 0.1 {
            return String(format: "%.1f MB", megabytes)
        }
        return "\(max(1, byteCount / 1024)) KB"
    }
}

enum VolunteerCertificateFileError: Error, Equatable, Sendable {
    case emptyFile
    case unsupportedType
    case tooLarge(byteCount: Int)

    var message: String {
        switch self {
        case .emptyFile:
            return "所选文件内容为空，请重新选择文件。"
        case .unsupportedType:
            return "文件格式不支持。请上传 JPG、PNG、GIF、WEBP、BMP 图片或 PDF 文件。"
        case .tooLarge(let byteCount):
            return "文件大小超过 5 MB 上限，当前约 \(VolunteerCertificateFileRules.sizeText(byteCount))。请压缩后重试。"
        }
    }
}

/// 待上传的证书。刻意不保存来源文件名和本地路径：文件名统一生成为 `certificate.<ext>`。
struct VolunteerCertificateFile: Equatable, Sendable {
    let fileExtension: String
    let mimeType: String
    let data: Data

    var fileName: String { "certificate.\(fileExtension)" }
    var byteCount: Int { data.count }

    /// 展示与播报只说类型和大小，不出现原始文件名。
    var summaryText: String {
        "\(fileExtension.uppercased()) 文件，约 \(VolunteerCertificateFileRules.sizeText(byteCount))"
    }

    /// 从任意来源的原始数据构造。类型由内容嗅探决定；HEIC 等无法识别的图片会转成 JPEG。
    static func make(from data: Data) -> Result<VolunteerCertificateFile, VolunteerCertificateFileError> {
        guard !data.isEmpty else { return .failure(.emptyFile) }

        var payload = data
        var detected = VolunteerCertificateFileRules.detectExtension(from: payload)

        if detected == nil, let image = UIImage(data: payload), let jpeg = jpegData(from: image) {
            payload = jpeg
            detected = "jpg"
        }

        guard let fileExtension = detected,
              let mimeType = VolunteerCertificateFileRules.mimeType(forExtension: fileExtension) else {
            return .failure(.unsupportedType)
        }

        if let error = VolunteerCertificateFileRules.validate(
            fileExtension: fileExtension,
            byteCount: payload.count
        ) {
            // 图片超限时先尝试压缩再判定，避免用户拍一张就被卡死。
            if case .tooLarge = error,
               fileExtension != "pdf",
               let image = UIImage(data: payload),
               let compressed = jpegData(from: image),
               compressed.count <= VolunteerCertificateFileRules.maxByteCount {
                return .success(VolunteerCertificateFile(
                    fileExtension: "jpg",
                    mimeType: "image/jpeg",
                    data: compressed
                ))
            }
            return .failure(error)
        }

        return .success(VolunteerCertificateFile(
            fileExtension: fileExtension,
            mimeType: mimeType,
            data: payload
        ))
    }

    /// 逐级降质直到不超过上限；仍超限则返回 nil 交由调用方报错。
    static func jpegData(from image: UIImage) -> Data? {
        for quality in [CGFloat(0.9), 0.7, 0.5, 0.3] {
            guard let data = image.jpegData(compressionQuality: quality) else { continue }
            if data.count <= VolunteerCertificateFileRules.maxByteCount {
                return data
            }
        }
        return image.jpegData(compressionQuality: 0.3)
    }
}

// MARK: - ViewModel

@MainActor
final class VolunteerCertificateUploadViewModel: ObservableObject {
    @Published private(set) var status: VolunteerCertificateStatus = .unknown
    @Published private(set) var statusLoadFailed = false
    @Published private(set) var isLoadingStatus = false
    @Published private(set) var isUploading = false
    @Published private(set) var selectedFile: VolunteerCertificateFile?
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var displayState: VolunteerCertificateDisplayState {
        VolunteerCertificateDisplayState.from(status: status, statusLoadFailed: statusLoadFailed)
    }

    /// 这个人走的是不是「二要素 + 人工审核」替代路径。
    ///
    /// 判据取自注册状态里的 `faceVerifyStatus`，**不是**由调用方传参数进来的 ——
    /// 上传页有三个入口（首页两处、订单流一处），传参数就意味着漏改一处就会给
    /// 拒绝了人脸的人显示「上传资质证书」，而他手上根本没有资质证书。
    /// `AppState.volunteerRegistrationStatus` 是 `@Published`，状态一变这页会跟着重绘。
    var isAlternativeIdentityPath: Bool {
        appState?.volunteerRegistrationStatus?.hasDeclinedFaceVerification == true
    }

    var canUpload: Bool {
        displayState.allowsUpload && selectedFile != nil && !isUploading && !isLoadingStatus
    }

    var materialNoun: String {
        isAlternativeIdentityPath ? "身份材料" : "资质证书"
    }

    var uploadButtonTitle: String {
        displayState == .rejected ? "重新提交\(materialNoun)" : "提交\(materialNoun)"
    }

    var currentGuidance: String {
        displayState.guidance(isAlternativeIdentityPath: isAlternativeIdentityPath)
    }

    /// 进入页面、状态变化、「重复当前状态」共用同一句播报。
    var statusAnnouncement: String {
        var parts = ["当前审核状态，\(displayState.displayName)。", currentGuidance]
        if let selectedFile {
            parts.append("已选择\(selectedFile.summaryText)。")
        }
        if let successMessage { parts.append(successMessage) }
        if let errorMessage { parts.append(errorMessage) }
        return parts.joined(separator: " ")
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        if status == .unknown, !statusLoadFailed {
            status = VolunteerCertificateStatus.parse(appState.volunteerProfile?.verificationStatus)
        }
    }

    func announceCurrentStatus() {
        speechService?.speak(statusAnnouncement)
    }

    // MARK: - Status

    /// 权威状态只能来自 `GET /api/volunteer/verification/status`，失败时不臆测。
    func refreshStatus(announce: Bool = false) async {
        guard let appState else { return }
        isLoadingStatus = true
        do {
            let response = try await appState.profile.volunteerVerificationStatus()
            let parsed = VolunteerCertificateStatus.parse(response.status)
            isLoadingStatus = false
            if parsed == .unknown {
                statusLoadFailed = true
            } else {
                status = parsed
                statusLoadFailed = false
                appState.updateVolunteerVerificationStatus(parsed.rawValue)
            }
        } catch let error as APIError {
            isLoadingStatus = false
            if appState.handleAuthenticatedAPIError(error) { return }
            statusLoadFailed = true
        } catch {
            isLoadingStatus = false
            statusLoadFailed = true
        }
        if announce {
            announceCurrentStatus()
        }
    }

    // MARK: - File Selection

    func selectFile(data: Data) {
        successMessage = nil
        switch VolunteerCertificateFile.make(from: data) {
        case .success(let file):
            selectedFile = file
            errorMessage = nil
            speechService?.speak("已选择\(file.summaryText)。点击提交\(materialNoun)上传。")
        case .failure(let failure):
            selectedFile = nil
            errorMessage = failure.message
            speechService?.speakError(failure.message)
        }
    }

    func selectionFailed(message: String) {
        selectedFile = nil
        successMessage = nil
        errorMessage = message
        speechService?.speakError(message)
    }

    func clearSelection() {
        selectedFile = nil
    }

    // MARK: - Upload

    func upload() {
        guard !isUploading else { return }
        guard let file = selectedFile else {
            let message = "请先选择要上传的\(materialNoun)。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard displayState.allowsUpload else {
            errorMessage = currentGuidance
            speechService?.speakError(currentGuidance)
            return
        }
        Task { await performUpload(file: file) }
    }

    private func performUpload(file: VolunteerCertificateFile) async {
        guard let appState else { return }
        isUploading = true
        errorMessage = nil
        successMessage = nil
        speechService?.speak("正在上传\(materialNoun)，请稍候。")

        do {
            _ = try await appState.profile.uploadVolunteerCertificate(
                MultipartFile(
                    fieldName: "file",
                    fileName: file.fileName,
                    mimeType: file.mimeType,
                    data: file.data
                )
            )
            isUploading = false
            selectedFile = nil
            // 状态一律回读，不用上传响应里的值臆测。
            await refreshStatus()
            successMessage = statusLoadFailed
                ? "\(materialNoun)已提交，但暂时没能读回审核状态，请稍后重新获取。"
                : "\(materialNoun)已提交，等待管理员审核。"
        } catch let error as APIError {
            isUploading = false
            if appState.handleAuthenticatedAPIError(error) { return }
            // 保留已选文件，用户可直接重试。
            errorMessage = "\(error.localizedMessage) 可点击提交\(materialNoun)重试。"
        } catch {
            isUploading = false
            errorMessage = "\(materialNoun)上传失败，请重试。"
        }

        announceCurrentStatus()
    }
}

// MARK: - View

/// 可独立 push 的资质证书上传页。入口：志愿者设置页 + 首页「尚未通过资质认证」提示。
struct VolunteerCertificateUploadView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerCertificateUploadViewModel()

    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var showsCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusCard
                if viewModel.displayState.allowsUpload {
                    pickerSection
                    selectedFileSection
                }
                messageSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(AppColors.background)
        .navigationTitle(viewModel.materialNoun)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.refreshStatus(announce: true)
        }
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showsCamera) {
            VolunteerCertificateCameraPicker { image in
                if let data = VolunteerCertificateFile.jpegData(from: image) {
                    viewModel.selectFile(data: data)
                } else {
                    viewModel.selectionFailed(message: "照片处理失败，请重新拍摄。")
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Sections

    /// 标题与说明按认证路径分。走替代路径的人手上**没有**资质证书 ——
    /// 照着「上传资质证书」找，他会以为自己走错了页面。
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText(viewModel.isAlternativeIdentityPath ? "身份材料" : "资质证书", style: .title)
                .accessibilityAddTraits(.isHeader)

            let intro = viewModel.isAlternativeIdentityPath
                ? "你选择了不做人脸认证。请上传能证明本人身份的材料，管理员人工审核通过后才能接单。支持图片或 PDF，单个文件不超过 5 MB。"
                : "上传助盲陪跑相关资质或培训证书，管理员审核通过后才能接单。支持图片或 PDF，单个文件不超过 5 MB。"
            Text(intro)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                // 「5 MB」读屏会念成「5 M B」，标签里写「5 兆」。
                .accessibilityLabel(intro.replacingOccurrences(of: "5 MB", with: "5 兆"))
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText(viewModel.displayState.displayName, style: .status)
            Text(viewModel.currentGuidance)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前审核状态，\(viewModel.displayState.displayName)")
        .accessibilityValue(viewModel.currentGuidance)
        .accessibilityIdentifier("volunteerCertificateStatusCard")
    }

    private var pickerSection: some View {
        // 读屏用户听到的每一处都要指同一样东西，否则「拍照上传」到底拍什么是靠猜的。
        let noun = viewModel.materialNoun
        return VStack(alignment: .leading, spacing: 12) {
            Text("选择\(noun)文件")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if VolunteerCertificateCameraPicker.isAvailable {
                pickerButton(
                    title: "拍照上传",
                    systemImage: "camera",
                    accessibilityHint: "打开相机拍摄\(noun)照片"
                ) {
                    showsCamera = true
                }
            }

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                pickerButtonLabel(title: "从相册选择", systemImage: "photo.on.rectangle")
            }
            .accessibilityLabel("从相册选择")
            .accessibilityHint("从相册中选择一张\(noun)照片")

            pickerButton(
                title: "选择文件",
                systemImage: "doc",
                accessibilityHint: "从文件中选择\(noun)图片或 PDF"
            ) {
                showsFileImporter = true
            }
        }
    }

    @ViewBuilder
    private var selectedFileSection: some View {
        if let file = viewModel.selectedFile {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title3)
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("待上传文件")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                    Text(file.summaryText)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer(minLength: 0)

                Button("移除") {
                    viewModel.clearSelection()
                }
                .font(AppFonts.body())
                .frame(minHeight: 44)
                .accessibilityLabel("移除已选文件")
                .accessibilityHint("移除后可以重新选择\(viewModel.materialNoun)")
            }
            .padding()
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
            .accessibilityIdentifier("volunteerCertificateSelectedFile")
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if viewModel.isUploading {
            HStack(spacing: 8) {
                ProgressView()
                Text("正在上传\(viewModel.materialNoun)...")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在上传\(viewModel.materialNoun)")
        }
        if let successMessage = viewModel.successMessage {
            Text(successMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel(successMessage)
        }
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .accessibilityLabel(errorMessage)
                .accessibilityIdentifier("volunteerCertificateErrorMessage")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if viewModel.displayState.allowsUpload {
                PrimaryButton(viewModel.uploadButtonTitle, isLoading: viewModel.isUploading) {
                    viewModel.upload()
                }
                .disabled(!viewModel.canUpload)
                .opacity(viewModel.canUpload ? 1 : 0.45)
                .accessibilityLabel(viewModel.uploadButtonTitle)
                .accessibilityHint(viewModel.canUpload ? "点击后上传所选\(viewModel.materialNoun)" : "请先选择\(viewModel.materialNoun)文件")
                .accessibilityIdentifier("volunteerCertificateUploadButton")
            }

            if viewModel.displayState == .statusUnavailable {
                PrimaryButton("重新获取状态", isLoading: viewModel.isLoadingStatus) {
                    Task { await viewModel.refreshStatus(announce: true) }
                }
                .accessibilityLabel("重新获取状态")
                .accessibilityHint("重新读取审核状态")
            }

            PrimaryButton("重复当前状态") {
                viewModel.announceCurrentStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前审核状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Picker Helpers

    private func pickerButton(
        title: String,
        systemImage: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            pickerButtonLabel(title: title, systemImage: systemImage)
        }
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private func pickerButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .font(AppFonts.primaryButton())
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(AppColors.secondaryBackground)
        .foregroundColor(AppColors.textPrimary)
        .cornerRadius(8)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.selectionFailed(message: "读取相册照片失败，请重新选择。")
                return
            }
            viewModel.selectFile(data: data)
        } catch {
            viewModel.selectionFailed(message: "读取相册照片失败，请重新选择。")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                viewModel.selectionFailed(message: "读取所选文件失败，请重新选择。")
                return
            }
            viewModel.selectFile(data: data)
        case .failure:
            viewModel.selectionFailed(message: "读取所选文件失败，请重新选择。")
        }
    }
}

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
            : "资质审核通过后才能接单")
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

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerCertificateUploadView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
