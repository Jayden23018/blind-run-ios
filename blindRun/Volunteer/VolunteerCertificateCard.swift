import SwiftUI

// 资质证书页顶部的证书卡与卡下那句标题（定稿 2026-11-04，#700，照钱包里的证件）。
//
// 状态同时写在卡上（胶囊里的字 + 图标）和卡下标题里，颜色只是冗余线索（WCAG 1.4.1）。
// 卡上不放证书照片：隐私，也省得弱网下载图。

// MARK: - 文案与颜色

extension VolunteerCertificateDisplayState {
    /// 卡的画法。未提交和状态未知画虚线空卡，其余三态画实心卡。
    enum CardStyle {
        case placeholder
        /// 卡底色。两档外观同值（卡上压白字，暗色模式也不能变浅），所以只存一个值。
        case filled(UInt32)

        var isPlaceholder: Bool {
            if case .placeholder = self { return true }
            return false
        }
    }

    /// 实心卡的底色。三种都是**现有**取值、两档外观同值（卡上压白字，暗色模式也不能变浅）：
    /// - 审核中：`Flow.statePaused`（跑步页暂停的灰）
    /// - 已通过：`Flow.stateDeparted`（出发蓝）
    /// - 未通过：`Flow.helpText` 的亮色档（求助红）—— 它的暗色档 `#FF453A` 压白字不到 4.5:1，所以两档都取亮色档。
    /// 白字对比度由 `VolunteerAccountPagesTests.testCertificateCardColoursKeepWhiteTextReadable` 逐色算。
    var cardStyle: CardStyle {
        switch self {
        case .pending: return .filled(AppColors.Flow.statePausedTone.light)
        case .approved: return .filled(AppColors.Flow.stateDepartedTone.light)
        case .rejected: return .filled(AppColors.Flow.helpTextTone.light)
        case .notSubmitted, .statusUnavailable: return .placeholder
        }
    }

    /// 胶囊里的图标。和状态文字一起出现，不单独表达状态。
    var badgeSymbol: String {
        switch self {
        case .pending: return "clock"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle.fill"
        case .notSubmitted: return "person.text.rectangle"
        case .statusUnavailable: return "exclamationmark.circle"
        }
    }

    /// 卡下那句大字。
    func headline(isAlternativeIdentityPath: Bool) -> String {
        switch self {
        case .notSubmitted:
            return isAlternativeIdentityPath
                ? "上传能证明本人身份的材料"
                : "上传\(VolunteerCertificateCopy.issuerName)颁发的证书"
        case .pending:
            return isAlternativeIdentityPath ? "管理员正在人工审核" : "团队正在审核"
        case .approved: return "审核已通过"
        case .rejected: return "审核未通过"
        case .statusUnavailable: return "暂时查不到审核状态"
        }
    }

    /// 虚线空卡里那句话。
    func placeholderText(isAlternativeIdentityPath: Bool) -> String {
        guard self == .notSubmitted else { return displayName }
        return isAlternativeIdentityPath ? "还没有上传身份材料" : "还没有上传证书"
    }
}

enum VolunteerCertificateCardCopy {
    static let certificateTitle = "陪跑员资质证书"
    static let alternativeTitle = "身份材料"
    static let alternativeIssuer = "人工审核"
    static let fileRule = "图片或 PDF，不超过 5 MB。"
    static let spokenFileRule = "图片或 PDF，单个文件不超过 5 兆。"
    /// 替代路径的审核时长只许这样说（与用户协议逐字一致，见 `VolunteerCertificateDisplayState.guidance`）。
    static let alternativeReviewNote = "提交后由管理员人工审核。该方式审核时间较长，但结果等效。"

    /// 未提交时卡下的说明。其余状态用 `VolunteerCertificateUploadViewModel.currentGuidance`。
    static func notSubmittedDetail(isAlternativeIdentityPath: Bool) -> String {
        fileRule + (isAlternativeIdentityPath ? alternativeReviewNote : VolunteerCertificateCopy.reviewerNote)
    }
}

// MARK: - 卡

/// 证书卡。实心卡左上发证方、右上状态胶囊、左下证书名与持证人。
struct VolunteerCertificateCard: View {
    let state: VolunteerCertificateDisplayState
    let isAlternativeIdentityPath: Bool
    /// 持证人姓名，来自 `AppState.volunteerProfile`；没有就不画。
    let holderName: String?

    private static let minHeight: CGFloat = 180

    var body: some View {
        switch state.cardStyle {
        case .placeholder:
            placeholder
        case .filled(let rgb):
            filled(rgb)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: state.badgeSymbol)
                .font(.title)
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
            Text(state.placeholderText(isAlternativeIdentityPath: isAlternativeIdentityPath))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
        .background(
            RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous)
                .strokeBorder(AppColors.Flow.ghostStroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private func filled(_ rgb: UInt32) -> some View {
        let background = Color(uiColor: UIColor(rgb: rgb))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(isAlternativeIdentityPath ? VolunteerCertificateCardCopy.alternativeIssuer : VolunteerCertificateCopy.issuerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.Flow.onHeroEyebrow)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                badge(ink: background)
            }
            Spacer(minLength: 36)
            Text(isAlternativeIdentityPath ? VolunteerCertificateCardCopy.alternativeTitle : VolunteerCertificateCardCopy.certificateTitle)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.Flow.onHeroStrong)
                .fixedSize(horizontal: false, vertical: true)
            if let holderName = holderName?.nilIfBlank {
                Text(holderName)
                    .font(.subheadline)
                    .foregroundColor(AppColors.Flow.onHeroBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
    }

    /// 白底胶囊，字用卡的底色：三种卡底压白都过 4.5:1，反过来白底压它们也一样。
    private func badge(ink: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state.badgeSymbol)
                .accessibilityHidden(true)
            Text(state.displayName)
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white))
    }
}

// MARK: - 证书卡 + 卡下标题

/// 证书卡 + 卡下标题与说明。
///
/// 标题与说明按认证路径分。走替代路径的人手上**没有**资质证书 ——
/// 照着「上传资质证书」找，他会以为自己走错了页面。
/// 读屏合成一个焦点，念状态和完整的指引（`guidance`），与「重复当前状态」同一句。
struct VolunteerCertificateStatusSection: View {
    let state: VolunteerCertificateDisplayState
    let isAlternativeIdentityPath: Bool
    /// `VolunteerCertificateUploadViewModel.currentGuidance`。
    let guidance: String
    let holderName: String?

    var body: some View {
        let detail = state == .notSubmitted
            ? VolunteerCertificateCardCopy.notSubmittedDetail(isAlternativeIdentityPath: isAlternativeIdentityPath)
            : guidance
        VStack(alignment: .leading, spacing: 12) {
            VolunteerCertificateCard(
                state: state,
                isAlternativeIdentityPath: isAlternativeIdentityPath,
                holderName: holderName
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(state.headline(isAlternativeIdentityPath: isAlternativeIdentityPath))
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("当前审核状态，\(state.displayName)")
        // 能上传时把文件规则也念出来：屏幕上那句「5 MB」在 `.ignore` 里，读屏听不到（「MB」会念成「M B」，这里写「兆」）。
        .accessibilityValue(state.allowsUpload ? "\(guidance) \(VolunteerCertificateCardCopy.spokenFileRule)" : guidance)
        .accessibilityIdentifier("volunteerCertificateStatusCard")
    }
}

// MARK: - 状态操作行

/// 「重新获取状态」与「重复当前状态」（定稿：从底部大按钮降为一组行，功能保留）。
///
/// 「重复当前状态」任何状态都在：读屏用户错过进页播报就靠它拿回来（skill `aidrun-a11y-voice`）。
/// 「重新获取状态」审核中也给 —— 等审核的人最常做的事就是看结果出来没有。
struct VolunteerCertificateStatusActions: View {
    @ObservedObject var viewModel: VolunteerCertificateUploadViewModel

    var body: some View {
        let state = viewModel.displayState
        let showsRefresh = state == .pending || state == .statusUnavailable
        GroupedCard {
            if showsRefresh {
                Button {
                    Task { await viewModel.refreshStatus(announce: true) }
                } label: {
                    VolunteerAccountActionRowLabel(
                        title: viewModel.isLoadingStatus ? "正在获取状态…" : "重新获取状态",
                        systemImage: "arrow.clockwise",
                        tint: AppColors.primary,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingStatus)
                .accessibilityLabel("重新获取状态")
                .accessibilityHint("重新读取审核状态")
                .accessibilityIdentifier("volunteerCertificateRefreshButton")
                GroupedCardDivider(leadingInset: VolunteerAccountActionRowLabel.dividerInset)
            }

            Button {
                viewModel.announceCurrentStatus()
            } label: {
                VolunteerAccountActionRowLabel(
                    title: "重复当前状态",
                    systemImage: "speaker.wave.2.fill",
                    tint: AppColors.primary,
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前审核状态")
            .accessibilityIdentifier("volunteerCertificateRepeatStatusButton")
        }
    }
}
