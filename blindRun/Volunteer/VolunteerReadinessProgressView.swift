// `import Combine` 只为 `@Published` / `ObservableObject` 的合成。本文件的数据流全走 async/await。
import Combine
import SwiftUI

// MARK: - ViewModel

/// 读三路状态拼成总进度。判定全在 `VolunteerReadinessProgress.resolve`，这里只负责取数。
@MainActor
final class VolunteerReadinessProgressViewModel: ObservableObject {
    @Published private(set) var progress = VolunteerReadinessProgress.resolve(
        registration: nil,
        certificate: .statusUnavailable,
        certificateRejectionReason: nil,
        dispatchReasons: nil
    )
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isAlternativeIdentityPath = false

    private weak var appState: AppState?
    private var speechService: SpeechService?
    /// 注册流程里 AppState 还是旧快照（完成态要等用户离开才发布），这时用流程自己手上的状态。
    private var registrationOverride: VolunteerRegistrationStatus?

    func configureAndLoad(
        appState: AppState,
        speechService: SpeechService,
        registration: VolunteerRegistrationStatus? = nil,
        announces: Bool
    ) async {
        self.appState = appState
        self.speechService = speechService
        registrationOverride = registration
        // 从证书页返回时 `.task` 会重跑，整段进度不再念第二遍。
        await reload(announces: announces && !hasLoaded)
    }

    /// 从证书页、培训页返回时刷新。还没配置过时什么都不做。
    func reloadIfConfigured() {
        guard appState != nil else { return }
        Task { await reload(announces: false) }
    }

    func reload(announces: Bool) async {
        guard let appState, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let loadedRegistration = loadRegistration(appState)
        async let loadedCertificate = loadCertificate(appState)
        async let loadedReasons = loadDispatchReasons(appState)
        let (registration, certificate, dispatchReasons) =
            await (loadedRegistration, loadedCertificate, loadedReasons)
        guard appState.accessToken != nil else { return }

        isAlternativeIdentityPath = registration?.hasDeclinedFaceVerification == true
        progress = .resolve(
            registration: registration,
            certificate: certificate.state,
            certificateRejectionReason: certificate.rejectionReason,
            dispatchReasons: dispatchReasons
        )
        hasLoaded = true
        if announces { speechService?.speak(progress.spoken) }
    }

    private func loadRegistration(_ appState: AppState) async -> VolunteerRegistrationStatus? {
        if let registrationOverride { return registrationOverride }
        do {
            return try await appState.profile.volunteerRegistrationStatus()
        } catch {
            // 能进首页说明实名与人脸已经过了，缓存在这两步上不会说错话，
            // 还能保住替代路径的称呼（他没有证书）。
            return appState.volunteerRegistrationStatus
        }
    }

    private func loadCertificate(
        _ appState: AppState
    ) async -> (state: VolunteerCertificateDisplayState, rejectionReason: String?) {
        do {
            let response = try await appState.profile.volunteerVerificationStatus()
            let status = VolunteerCertificateStatus.parse(response.status)
            if status != .unknown { appState.updateVolunteerVerificationStatus(status.rawValue) }
            return (.from(status: status, statusLoadFailed: false), response.rejectionReason)
        } catch {
            return (.statusUnavailable, nil)
        }
    }

    private func loadDispatchReasons(
        _ appState: AppState
    ) async -> [VolunteerDispatchNotAvailableReason]? {
        do {
            return try await appState.orders.dispatchSummary().notAvailableReasons
        } catch {
            return nil
        }
    }
}

// MARK: - Page

/// 首页点滑块进来的那一页。注册结束页用同一份内容，只是外面没有这层滚动。
struct VolunteerReadinessProgressView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerReadinessProgressViewModel()

    var body: some View {
        ScrollView {
            VolunteerReadinessProgressContent(viewModel: viewModel)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
        .background(AppColors.background)
        .navigationTitle(VolunteerReadinessCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.configureAndLoad(
                appState: appState,
                speechService: speechService,
                announces: true
            )
        }
    }
}

// MARK: - Content

struct VolunteerReadinessProgressContent: View {
    @ObservedObject var viewModel: VolunteerReadinessProgressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.hasLoaded {
                Text(viewModel.progress.title)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("volunteerReadinessTitle")

                if let subtitle = viewModel.progress.subtitle {
                    Text(subtitle)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VolunteerReadinessStepList(
                    steps: viewModel.progress.steps,
                    isAlternativeIdentityPath: viewModel.isAlternativeIdentityPath
                )

                if viewModel.progress.steps.contains(where: { $0.state == .unknown }) {
                    Button(VolunteerReadinessCopy.reloadTitle) {
                        Task { await viewModel.reload(announces: true) }
                    }
                    .buttonStyle(OutlineSecondaryButtonStyle())
                    .disabled(viewModel.isLoading)
                    .accessibilityHint("重新读取接单前进度")
                    .accessibilityIdentifier("volunteerReadinessReloadButton")
                }
            } else {
                ProgressView("正在读取接单前进度...")
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("正在读取接单前进度")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { viewModel.reloadIfConfigured() }
    }
}

/// 五步列表。遍历顺序就是实名 → 培训的声明顺序。
struct VolunteerReadinessStepList: View {
    let steps: [VolunteerReadinessProgress.Step]
    var showsDestinations = true
    var isAlternativeIdentityPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in
                if showsDestinations, let destination = step.destination {
                    NavigationLink {
                        destinationView(destination)
                    } label: {
                        row(step, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    // 与首屏培训卡同一个写法：不在 `NavigationLink` 上做 combine，免得丢 link 特性。
                    .accessibilityLabel(step.spoken)
                    .accessibilityHint(hint(for: destination))
                    .accessibilityIdentifier("volunteerReadinessStep.\(step.kind.rawValue)")
                } else {
                    row(step, showsChevron: false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(step.spoken)
                        .accessibilityIdentifier("volunteerReadinessStep.\(step.kind.rawValue)")
                }
            }
        }
    }

    private func row(_ step: VolunteerReadinessProgress.Step, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 图标只是冗余线索，状态全在文字里（WCAG 1.4.1）。
            Image(systemName: icon(for: step.state))
                .font(.title3)
                .foregroundColor(tint(for: step.state))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                Text(step.statusText)
                    .font(AppFonts.body())
                    .foregroundColor(tint(for: step.state))
                if let detail = step.detail {
                    Text(detail)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
    }

    @ViewBuilder
    private func destinationView(_ destination: VolunteerReadinessProgress.Destination) -> some View {
        switch destination {
        case .certificateUpload:
            // 显式传路径：注册结束页的 AppState 还是旧快照（见上传页 ViewModel 的注释）。
            VolunteerCertificateUploadView(forcesAlternativeIdentityPath: isAlternativeIdentityPath)
        case .training:
            VolunteerTrainingView()
        }
    }

    private func hint(for destination: VolunteerReadinessProgress.Destination) -> String {
        switch destination {
        case .certificateUpload: return "打开上传页"
        case .training: return "打开陪跑培训"
        }
    }

    private func icon(for state: VolunteerReadinessProgress.StepState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .actionNeeded: return "exclamationmark.circle.fill"
        case .inReview, .waiting: return "clock"
        case .rejected: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func tint(for state: VolunteerReadinessProgress.StepState) -> Color {
        switch state {
        case .done: return AppColors.success
        case .actionNeeded: return AppColors.warning
        case .rejected: return AppColors.destructive
        case .inReview, .waiting, .unknown: return AppColors.textSecondary
        }
    }
}
