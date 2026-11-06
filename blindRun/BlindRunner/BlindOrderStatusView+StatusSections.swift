import SwiftUI

extension BlindOrderStatusView {
    /// 一句话 + 一个数字，合成**一个** VoiceOver 焦点。
    ///
    /// 距离此前埋在下面的「志愿者信息」卡片里当正文读，而它恰恰是这一页唯一会变的数字 ——
    /// 对标 GoodMaps 的 `Start Walking … 96 ft`、WeWALK 的 `116 meters`：状态旁边就该是那个数
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 4）。
    func statusHeader(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.system(size: 56))
                .foregroundColor(order.status.statusColor)
                .accessibilityHidden(true)

            Text(order.status.displayName)
                .font(.largeTitle.bold())
                .foregroundColor(AppColors.textPrimary)

            Text(order.status.blindRunnerDescription)
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            // 还在等人时，这一格是「已等待 12 分钟」；有志愿者了换成距离；跑起来了换成
            // 约定结束时间。三者状态集互不相交（`offersWaitedDuration` 的注释里有理由），
            // 所以卡上任何时刻只有一个数字。
            if let waitedText = order.blindRunnerWaitedText() {
                Text(waitedText)
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            if let distanceText = viewModel.volunteerDistanceToStartText {
                Text("陪跑员\(distanceText)")
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // 服务进行中，把约定的结束时间摆在首屏。低视力用户靠这行字看到，
            // 读屏用户靠 `statusHeaderAnnouncement` 听到 —— 两条通道都要有。
            if let plannedEndText = plannedEndHeaderText(order) {
                Text(plannedEndText)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusHeaderAnnouncement(order))
    }

    /// 结束时间只在服务进行中出现在首屏。派单期、汇合期摆它没有用（还没开始跑），
    /// 终态更不该摆（已经结束了，一个「预计」是噪音）。
    ///
    /// 拼接抽成独立函数而不是塞进 `Text(...)`：带可选拆包的字符串插值放在 view builder 里
    /// 会把类型检查器拖到超时（`unable to type-check this expression in reasonable time`）。
    private func plannedEndHeaderText(_ order: OrderDetailResponse) -> String? {
        guard order.status == .inProgress, let end = order.plannedEndForAnnouncement else { return nil }
        return "预计 \(end) 结束"
    }

    /// 合并后的朗读文本写死，不交给 `.combine` 自己拼 —— 自动拼接会把状态名、说明和距离
    /// 糊成一长串没有停顿的音。
    private func statusHeaderAnnouncement(_ order: OrderDetailResponse) -> String {
        var parts = [order.status.displayName, order.status.blindRunnerDescription]
        if let waitedText = order.blindRunnerWaitedText() {
            parts.append(waitedText)
        }
        if let distanceText = viewModel.volunteerDistanceToStartText {
            parts.append("陪跑员\(distanceText)")
        }
        if let plannedEndText = plannedEndHeaderText(order) {
            parts.append(plannedEndText)
        }
        return parts.joined(separator: "。")
    }

    @ViewBuilder
    func lifecycleSection(_ order: OrderDetailResponse) -> some View {
        switch order.status.blindRunnerRoute {
        case .tracking, .inService, .terminal:
            // 这三条分支此前各渲染一张「标题 + 正文」卡片，正文都与 `statusHeader` 重复：
            //   · `DRIVER_ARRIVED` 当时的 `arrivedWaitingCopy`（2026-10-06 已删）**就是**它的 `blindRunnerDescription`
            //     （`OrderDisplayHelpers.swift:77` 直接 return 了它）—— 逐字重复
            //   · `IN_PROGRESS` 那句「请与志愿者保持沟通，注意安全。系统会持续同步订单状态，
            //     服务完成后进入评价页面。」33 个字里没有一个能让盲人做出动作：
            //     「持续同步订单状态」是实现细节，「完成后进入评价页面」是还没发生的事
            //   · `.terminal` 的 `terminalSection`（2026-08-19 并进来）整张卡就是
            //     `Text(status.displayName)` + `Text(status.blindRunnerDescription)`，
            //     与 `statusHeader` **逐字**是同两句 —— 已取消 / 暂无志愿者的人把
            //     「本次预约已取消」听两遍，中间还隔着一次滑动
            // 读屏用户为此要多滑一次、把同一件事听两遍。状态语义由 `statusHeader` 一处承担。
            EmptyView()
        case .completion:
            completionRatingSection(order)
        }
    }

    private func completionRatingSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务已完成")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let track = trackViewModel.track {
                // 🚩 这枚「重复当前状态」与导航栏那枚走**同一个函数**（`repeatStatus`）——
                // 同一页上两个入口念出不同的话，对看不见屏幕的人是两个矛盾的事实。
                // 原先它念 `track.spokenSummary`（只有三个数字，没有状态），
                // 而 `repeatStatus` 念的是「状态 + 三个数字 + 求助状态」，是它的严格超集。
                CompletedTrackSummaryView(track: track, recordOrderId: order.orderId, role: .runner) {
                    viewModel.repeatStatus()
                }
            } else if trackViewModel.isLoading {
                ProgressView("正在加载本次路线")
            } else if let error = trackViewModel.errorMessage {
                Text(error).foregroundColor(AppColors.textSecondary).announcesFailure(error, using: speechService)
            }

            if viewModel.didSubmitReview {
                if let review = viewModel.existingReview {
                    submittedReviewSummary(review)
                }
                Text("感谢反馈，可以返回首页。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("感谢反馈，可以返回首页")
            } else {
                reviewInputSection
            }

            favoriteVolunteerSection(order)

            if viewModel.didSubmitReview {
                Button("返回首页") { dismiss() }.buttonStyle(OutlineSecondaryButtonStyle()) // 同上：「完成」才是实心主按钮
                .accessibilityLabel("返回首页")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    /// 还没提交评价时的打分、评价内容和两个按钮。从 `completionRatingSection` 拆出来（#795 加语音按钮后超长）。
    @ViewBuilder
    private var reviewInputSection: some View {
        RunExperienceRatingPicker(rating: $viewModel.reviewRating) // 默认不选，见 `RunExperienceRating.swift`

        TextEditor(text: $viewModel.reviewComment)
            .frame(minHeight: 96)
            .padding(8)
            .background(AppColors.background)
            .cornerRadius(8)
            .accessibilityLabel("评价内容，选填")

        VoiceDictationButton(
            fieldTitle: "评价内容",
            text: $viewModel.reviewComment,
            speechInputService: speechInputService,
            speechService: speechService,
            speechField: .ratingFeedback
        )
        .disabled(viewModel.isSubmittingReview)

        // 描边次按钮：底部「完成」是这一屏唯一的实心主按钮（设计稿 ④；2026-10-05 评审第 2 条）。提交中淡下去并换文案。
        Button(viewModel.isSubmittingReview ? "正在提交…" : "提交评价") {
            VoiceDictationButton.stopRecording(.ratingFeedback, on: speechInputService)
            Task { await viewModel.submitReview() }
        }
            .buttonStyle(OutlineSecondaryButtonStyle()).disabled(viewModel.isSubmittingReview)
        .accessibilityLabel(viewModel.isSubmittingReview ? "正在提交评价" : "提交评价")
        .accessibilityHint("提交本次服务评分和评价")

        Button("跳过评价") {
            viewModel.skipReview()
            dismiss()
        }
        .buttonStyle(TextButtonStyle(tint: AppColors.textSecondary, alignment: .center))
        .accessibilityLabel("跳过评价")
    }

    /// 「把这一单的志愿者设为固定搭档」。
    ///
    /// 🚩 **这是全 App 第二个、也是覆盖面最大的收藏入口。** 另一个在设置页的固定搭档列表里，
    /// 但那里只能收藏**已经点亮火花**的一对 —— 而火花开关（`app.incentive.streak.enabled`）
    /// 后端默认关着，所以在它打开之前，那个入口实际上一个人也收藏不了。
    /// 这条路不依赖火花：收藏的门槛是「一起跑完至少一单」，而这一页就站在那一单上。
    ///
    /// 位置在评价之后：评价是这一屏的主动作（有时限压力、后端会催），收藏没有。
    ///
    /// 三个渲染条件缺一不可：
    /// - `COMPLETED` —— 门槛是跑完，跑之前点必然吃 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE`
    /// - `volunteerId != nil` —— 结构判据，不另外判状态（后端接单前本就不下发它）
    /// - `isVolunteerFavorited != nil` —— 查不到收藏状态时整块不出现，理由见那个属性
    @ViewBuilder
    private func favoriteVolunteerSection(_ order: OrderDetailResponse) -> some View {
        if order.status == .completed,
           order.volunteerId != nil,
           let isFavorited = viewModel.isVolunteerFavorited {
            let name = order.volunteerName?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
            VStack(alignment: .leading, spacing: 8) {
                if isFavorited {
                    // 已经是搭档时只陈述事实，不给「取消收藏」——
                    // 取消的是一段跨越很多次跑步的关系，而这一页只有其中一次的上下文。
                    // 取消入口在设置页的固定搭档列表，那里看得到全部搭档。
                    Text("\(name)已经是你的固定搭档")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderAlreadyFavoriteText")
                } else {
                    Button(PartnerStreakCopy.addFavoriteTitle(name)) {
                        Task { await viewModel.addVolunteerToFavorites() }
                    }
                    .buttonStyle(TextButtonStyle(alignment: .center))
                    .disabled(viewModel.isUpdatingFavorite)
                    // 🔴 承诺只能说到「更可能」。收藏加的 15 分在满分 100 的五维加权和之外，
                    // 附近有个不错的陌生人时固定搭档仍然会输 —— 说「优先派给他」是承诺一件系统做不到的事。
                    .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
                    .accessibilityIdentifier("blindOrderAddFavoriteButton")
                }

                // 成功与失败都要**在屏幕上多出一行字**，不能只靠播报：
                // 低视力用户走的是视觉那条通道（AGENTS.md §1.4）。
                if let notice = viewModel.favoriteNotice {
                    Text(notice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderFavoriteNotice")
                }
                if let failure = viewModel.favoriteErrorMessage {
                    Text(failure)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderFavoriteError")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 已提交过的评价读回来。
    ///
    /// 这一块的存在理由是**重进这一单**：`didSubmitReview` 只活在这个进程里，
    /// 重开 App 再进已完成的订单，用户看到的是一张空白评价表 —— 填完提交只会撞上
    /// 409「已评价过此订单」。把真实评价念出来，用户才知道这一单已经评过、评的是什么。
    /// 合成一个焦点：星数和评语分两次读会让读屏用户以为是两条不同的记录。
    private func submittedReviewSummary(_ review: OrderReview) -> some View {
        let comment = review.comment?.nilIfBlank
        let reviewedAt = review.createdAt?.nilIfBlank?.displayDateTime
        // 视觉与读屏两条通道给同一份内容，不给读屏偷偷多塞一句 —— 低视力用户走的是视觉那条
        // （AGENTS.md §1.4）。
        return VStack(alignment: .leading, spacing: 4) {
            Text(review.summaryLine)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            if let comment {
                Text(comment)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            if let reviewedAt {
                Text("评价于\(reviewedAt)")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            review.summaryLine
                + (comment.map { "，评语：\($0)" } ?? "")
                + (reviewedAt.map { "，评价于\($0)" } ?? "")
        )
    }

    /// 「刚才到底发生了什么」。
    ///
    /// 折叠，理由与「预约信息」同一条：这是用户想回溯时才来找的信息，不是主路径上的动作。
    /// 摊开会让读屏用户在到达「重复当前状态」之前多滑十几次。
    var statusLogSection: some View {
        DisclosureGroup("状态变更记录", isExpanded: $showStatusLogs) {
            statusLogContent
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到此订单每一次状态变化和发生时间")
        .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
    }

    @ViewBuilder
    private var statusLogContent: some View {
        if viewModel.isLoadingStatusLogs && viewModel.statusLogs.isEmpty {
            ProgressView("正在获取状态变更记录")
                .tint(AppColors.primary)
                .accessibilityLabel("正在获取状态变更记录")
        } else if let errorMessage = viewModel.statusLogsErrorMessage {
            // 「拿不到」和「没有记录」必须分得开：前者可以重试，后者重试也没用。
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(errorMessage)
        } else if viewModel.statusLogs.isEmpty {
            Text("暂无状态变更记录")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("暂无状态变更记录")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 后端已按时间倒序给，最新的一条在最上面 —— 读屏第一个听到的就是刚发生的事。
                ForEach(viewModel.statusLogs) { log in
                    infoRow(log.changedAt.displayDateTime, log.displayText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
