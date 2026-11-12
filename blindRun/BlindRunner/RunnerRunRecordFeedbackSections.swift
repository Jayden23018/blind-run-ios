import SwiftUI

// 跑者跑步详情最后两节：「陪跑员」与「这次陪跑怎么样」（#831，定稿 `docs/ui/mockups/order-done-review-20261107/` v3）。
// 举报与「不再匹配此人」不露在这一页，收进这个人的页面（现有 `BlindPartnerDetailView`）。
// 按钮照 #749：胶囊；这一页唯一的实心按钮是「提交评价」。

// MARK: - 陪跑员

struct RunnerRunRecordVolunteerSection: View {
    @ObservedObject var feedback: RunnerRunFeedbackViewModel
    let orderId: Int64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 头像底色：绿（定稿）。从这里进搭档详情页也用同一个，两处一致。
    private static let tintIndex = 2

    private var displayName: String { feedback.volunteerName ?? PartnerStreakCopy.unknownVolunteerName }
    private var spokenName: String {
        feedback.volunteerName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
    }

    /// 拉黑之后不再给「设为固定搭档」。
    private var showsAddButton: Bool {
        feedback.partnerStatus == .notPartner && !feedback.didBlockVolunteer
    }

    var body: some View {
        // 查不到是不是搭档时也能点进去举报（`personRow` 退回只有 id 和名字的一行）。
        if let row = feedback.personRow {
            VStack(alignment: .leading, spacing: 8) {
                RunRecordSectionTitle(text: "陪跑员").padding(.top, 8)
                RunRecordCard {
                    VStack(alignment: .leading, spacing: 12) {
                        personLink(row)
                        if showsAddButton {
                            addButton
                        }
                        outcomeLines
                    }
                }
                if showsAddButton {
                    GroupedCardFootnote(text: PartnerStreakCopy.blindAddFootnote)
                        .padding(.horizontal, 4)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("runnerRunRecordVolunteer")
        }
    }

    private func personLink(_ row: PartnerRow) -> some View {
        NavigationLink {
            BlindPartnerDetailView(
                row: row,
                index: Self.tintIndex,
                setFavorite: { isFavorite in await feedback.setFavorite(isFavorite) },
                onBlocked: { await feedback.volunteerBlocked() },
                reportOrderId: orderId,
                showsFavoriteActions: feedback.partnerStatus != .unknown
            )
        } label: {
            HStack(spacing: 12) {
                // 辅助功能字号档不画头像，理由同固定搭档列表那一行（`BlindPartnerRowLabel`）。
                if !dynamicTypeSize.isAccessibilitySize {
                    BlindPartnerAvatar(name: displayName, tint: BlindPartnerAvatar.tint(for: row, index: Self.tintIndex))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let status = feedback.partnerStatus.text {
                        Text(status)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                SettingsChevron()
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([spokenName, feedback.partnerStatus.text].compactMap { $0 }.joined(separator: "，"))
        .accessibilityHint("点击查看这位陪跑员，可以举报或不再匹配")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("runnerRunRecordVolunteerRow")
    }

    /// 浅蓝描边胶囊（定稿）。实心留给「提交评价」。
    private var addButton: some View {
        Button(feedback.isUpdatingFavorite ? "正在设为固定搭档…" : PartnerStreakCopy.blindAddTitle) {
            Task { await feedback.addVolunteerToFavorites() }
        }
        .buttonStyle(OutlineSecondaryButtonStyle())
        .disabled(feedback.isUpdatingFavorite)
        .accessibilityLabel(PartnerStreakCopy.addFavoriteTitle(spokenName))
        // 🔴 承诺只能说到「更可能」：收藏只是派单加分。
        .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
        .accessibilityIdentifier("runnerRunRecordAddFavoriteButton")
    }

    /// 成功与失败都在卡里多一行字（播报在 view model 里）：低视力用户走的是视觉那条通道。
    @ViewBuilder
    private var outcomeLines: some View {
        if let notice = feedback.favoriteNotice {
            Text(notice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.success)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("runnerRunRecordFavoriteNotice")
        }
        if let failure = feedback.favoriteErrorMessage {
            Text(failure)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("runnerRunRecordFavoriteError")
        }
    }
}

// MARK: - 这次陪跑怎么样

/// 默认一项都不选；选了才展开评语框（右边同一行是语音输入）和「提交评价」。没有「跳过评价」。
/// 评过的只显示只读卡，不能改。「有没有评过」查完之前整节不出现。
struct RunnerRunRecordReviewSection: View {
    @ObservedObject var feedback: RunnerRunFeedbackViewModel
    @EnvironmentObject private var speechInputService: SpeechInputService
    @EnvironmentObject private var speechService: SpeechService

    /// 订单页已完成那一屏（#968）把标题放进卡片里，小一号；跑步详情仍是卡片外的节标题。
    var titleInsideCard = false

    static let onceOnly = "只能评一次，提交后不能改。"
    static let commentPlaceholder = "想说的话（选填）"

    var body: some View {
        if feedback.hasLoadedReview {
            VStack(alignment: .leading, spacing: 8) {
                if !titleInsideCard {
                    RunRecordSectionTitle(text: RunExperienceRating.sectionTitle).padding(.top, 8)
                }
                RunRecordCard {
                    if titleInsideCard {
                        Text(RunExperienceRating.sectionTitle)
                            .flowFont((16, .semibold, .callout))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .padding(.bottom, 10)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if feedback.didSubmitReview {
                        submittedCard
                    } else {
                        form
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("runnerRunRecordReview")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            RunExperienceRatingPicker(rating: $feedback.reviewRating, showsTitle: false)
                .onChange(of: feedback.reviewRating) { _ in feedback.clearReviewError() }

            if feedback.reviewRating != nil {
                VoiceDictationButton(
                    fieldTitle: "评价内容",
                    text: $feedback.reviewComment,
                    speechInputService: speechInputService,
                    speechService: speechService,
                    speechField: .ratingFeedback,
                    besideField: AnyView(commentEditor)
                )
                .disabled(feedback.isSubmittingReview)

                PrimaryButton("提交评价", isLoading: feedback.isSubmittingReview) {
                    VoiceDictationButton.stopRecording(.ratingFeedback, on: speechInputService)
                    Task { await feedback.submitReview() }
                }
                .accessibilityHint("提交这次陪跑的评价。" + Self.onceOnly)
                .accessibilityIdentifier("runnerRunRecordSubmitReview")
            }

            if let error = feedback.reviewErrorMessage {
                Text(error)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("runnerRunRecordReviewError")
            }

            Text(feedback.reviewRating == nil ? "选一项就能提交。" + Self.onceOnly : Self.onceOnly)
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// iOS 16 的 `TextEditor` 没有占位字：空的时候叠一行灰字，不进读屏（读屏念标签「评价内容，选填」）。
    private var commentEditor: some View {
        TextEditor(text: $feedback.reviewComment)
            .font(AppFonts.body())
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, minHeight: VoiceDictationButton.compactSide + 32)
            .padding(4)
            .overlay(alignment: .topLeading) {
                if feedback.reviewComment.isEmpty {
                    Text(Self.commentPlaceholder)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(AppColors.Flow.page)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: feedback.reviewComment) { _ in feedback.clearReviewError() }
            .disabled(feedback.isSubmittingReview)
            .accessibilityLabel("评价内容，选填")
            .accessibilityIdentifier("runnerRunRecordReviewComment")
    }

    // MARK: 评过了

    /// 档名、评语、评价时间。整张卡一个焦点，一次念完（定稿）；读屏念档名不念分数。
    private var submittedCard: some View {
        let review = feedback.existingReview
        let level = review?.rating.flatMap(RunExperienceRating.init(rawValue:))?.title
            ?? review?.summaryLine ?? "你已评价过这次陪跑"
        let comment = review?.comment?.nilIfBlank
        let time = review?.createdAt?.nilIfBlank?.displayDateTime
        let footer = (time.map { "\($0) 评价 · " } ?? "") + "评价后不能修改"
        let spoken = "你的评价：\(level)。"
            + (comment.map { "评语：\($0)。" } ?? "")
            + (time.map { "\($0)评价，" } ?? "") + "评价后不能修改。"
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppColors.Flow.bluePressed)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppColors.Flow.blueTint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(level)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                if let comment {
                    Text("「\(comment)」")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("runnerRunRecordSubmittedReview")
    }
}
