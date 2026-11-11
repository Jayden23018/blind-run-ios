import SwiftUI

extension BlindOrderStatusView {
    @ViewBuilder
    var content: some View {
        if let order = viewModel.order, BlindOrderStage.resolve(order.status) != nil {
            // 订单页 v7 ①–④（#917）：匹配中、商量见面安排、已约好。出发起仍走下面的骨架（#918 另做）。
            stageContent(order)
        } else if let presentation = flowPresentation, let order = viewModel.order {
            // 设计稿的骨架。**六幕共用同一套布局**，只换内容 —— 改版前每态一个
            // 独立页面，而 iOS 切页时 VoiceOver 会把焦点移回第一个元素，读屏用户每次
            // 都要从头找。单页原地更新让焦点保持不动，只播报变化。
            //
            // 🔴 `IN_PROGRESS` 2026-09-16 起也走这里（原先是一整屏独立的深底执行屏）。
            // 那一屏被移出的东西**一件都没删**，只是换了落点：三个数字进
            // `BlindActiveRunView`（现在是这张卡的内容区）、定位新鲜度进顶行、
            // 求助失败与撤销进 `flowFooter`、「重复当前状态」由主按钮「播报当前数据」承担。
            // 🔴 **`debugMockControls` 必须在骨架的 ScrollView 里面（走 footer），
            // 不能当 `BlindOrderFlowView` 的兄弟节点。**
            //
            // 它原先挂在外层 `VStack` 上，于是在**横屏**（可用高度约 390pt）里：
            // 那三个 mock 按钮按自然高度占掉一大片、底部两个版位再占一片，
            // 留给状态卡与信息列表的空间被压到几乎为零 —— 真机横屏截图上状态标题、
            // 副标题、四行信息**一个字都看不到**，而「求助与安全」被拉成一个巨块。
            // 这是 2026-09-16 第一次真机跑 `testBlindOrderStatusInLandscapePassesAccessibilityAudit`
            // 时暴露的：那两条 `Contrast failed` 的元素是**没有任何文字的近白色区域**，
            // 也就是被压扁的卡片本身，不是配色问题。
            //
            // 改版前它就在 `trackingContent` 的 ScrollView 里（跟着内容滚），
            // 阶段 3a 把它提到外面是无意的 —— 放回去即恢复。
            // `#if DEBUG` + `currentEnvironment == .mock` 两道闸没动，Release 里仍是 `EmptyView`。
            BlindOrderFlowView(
                presentation: presentation,
                order: order,
                stats: viewModel.trackStats,
                isLocationFresh: viewModel.isDeviceLocationFresh,
                onOpenStartPlace: nil,
                onLastRowTapped: { handleFlowLastRow(order) },
                onPrimaryAction: { handleFlowPrimaryAction(presentation, order: order) },
                onOpenSafetyHub: { showSafetyHub = true },
                onCallVolunteer: { dialVolunteer(order) },
                onEditRunnerMessage: order.status.acceptsRunnerMessage ? { showRunnerMessage = true } : nil,
                onArrivalCancel: { showCancelConfirmation = true },
                footer: {
                    VStack(spacing: 16) {
                        flowFooter(order)
                        // 🔴 已完成那一幕只留绿色卡（负责人 2026-11-07 定，#831）。2026-09-17 「把改版前那一页
                        // 原样接回来」的决定作废：评价与「设为固定搭档」挪进跑者跑步详情（`RunnerRunRecordFeedbackSections.swift`），
                        // 举报与不再匹配收进这个人的页面（`BlindPartnerDetailView`）；本单信息与状态流水不再显示。
                        // 跑完当场停在这一页时不另加去跑步详情的入口，要评价从首页 → 记录进去。
                        if order.status != .completed { OrderCounterpartSafetySection(order: order) }
                        debugMockControls(order)
                    }
                }
            )
        } else if let order = viewModel.order, order.status.usesBlindTerminalPage {
            // 已取消 / 暂无志愿者（#818）：与骨架同一套版式，见 `BlindOrderStatusView+Terminal.swift`。
            terminalContent(order)
        } else {
            // 只读退路：`.unknown` 与还没拿到订单的加载态。
            // 这一条**不许删** —— 后端加状态时它是未知态唯一的落点。
            trackingContent
        }
    }

    /// 骨架信息列表之后那块「刚才那一下的结果」。**三态正常时整块为空。**
    ///
    /// 这不是补充装饰，是把改版前那条滚动列表末尾的**可见失败面**接回来：骨架换掉
    /// `trackingContent` 的同时也换掉了 `viewModel.errorMessage` 与实时分享结果提示
    /// 唯一的渲染点。少了它，失败只剩一句 TTS，而不开读屏的低视力用户屏幕上零变化。
    ///
    /// 短信降级按钮同样在这里：`showSMSFallback` 只在实时分享失败后为真，
    /// 而那一刻「把行程告诉家人」这件事仍然做得到 —— 收走入口等于把人支上死路。
    @ViewBuilder
    func flowFooter(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 10) {
            // 跑步中不再有节奏按钮（2026-10-07 方向 A，负责人：「跑者和陪跑员会直接沟通」）。
            // 跑步中这一屏只剩「听当前状态」与底部求助，跑者基本不需要碰手机。
            // 求助的结果面。**不额外判相位** —— 云端求助只在 `IN_PROGRESS` 可发
            // （`canBlindRunnerTriggerEmergency`），所以这三块在别的幕里本来就恒为空；
            // 多一道相位闸只会多一个能判错的地方，而判错的方向是「求助失败了却没有兜底按钮」。
            BlindRunSafetyResultSection(
                coordinator: appState.emergencyCoordinator,
                onLocalCall: { showEmergencyCallOptions = true },
                onCancelOwnEmergency: { showEmergencyCancelConfirmation = true }
            )

            if let notice = shareViewModel.notice {
                Text(notice.text)
                    .font(AppFonts.body())
                    .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(notice.text)
                    .accessibilityIdentifier("blindOrderStatusShareRunPlanNotice")
            }

            // 只在实时分享走不通时露出来。`canSendText` 一并判掉：这台设备本来就发不了
            // 短信时摆出降级入口，等于把用户支上一条同样走不通的路。
            if shareViewModel.showSMSFallback, MessageComposeSheet.canSendText {
                runPlanShareButton(
                    title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                    hint: RunPlanLiveShareCopy.smsFallbackHint,
                    identifier: "blindOrderStatusShareRunPlanButton",
                    tint: AppColors.primary,
                    action: { shareRunPlanBySMS(order) }
                )
            }

            // 字号用 `AppFonts.body()`，**不用骨架的 13pt `rowDetail`** ——
            // 这是这一页唯一的可见失败面，而它替代的那处（`trackingContent` 末尾）
            // 就是 body。为了跟骨架的视觉调性一致而把它调小一档，等于专门在
            // 「不开读屏的低视力用户唯一能读到失败原因的地方」减字号。
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(errorMessage)
                    .accessibilityIdentifier("blindOrderFlowErrorMessage")
            }
        }
    }

    /// 信息列表最后一行。能取消的态弹取消确认，不能取消的态开求助中心。
    ///
    /// 「遇到问题」落到求助中心而不是新开一页：联系陪跑员 / 播报位置 / 问一句 /
    /// 拨紧急联系人与 120、110 全都已经在那一层里，是这一刻用户可能要做的事的完整集合。
    private func handleFlowLastRow(_ order: OrderDetailResponse) {
        if order.status.canBlindRunnerCancel {
            showCancelConfirmation = true
        } else {
            showSafetyHub = true
        }
    }

    /// 本地拨号弹窗的第一句该说哪一种。判据与 `BlindRunnerTabView.callContext` 逐字相同：
    /// 云端那条路此刻通不通，就决定了「刚才那一下到底发生了什么」是哪个答案。
    var emergencyCallContext: EmergencyCallContext {
        EmergencyCallContext.runner(for: sosMode)
    }

    /// 求助中心底部那条走云端还是本地拨号。跑步中登录已过期（#376）落本地拨号那一档。
    var sosMode: BlindHomeSOSMode {
        BlindHomeSOSMode.resolve(
            order: viewModel.order,
            role: appState.activeRole,
            isSessionExpired: appState.isSessionExpiryDeferred
        )
    }

    /// 求助中心那一格按下去：起分享还是停分享。
    ///
    /// **分流放在这里而不是弹层里**：起分享要先过明示同意那道门
    /// （`RunPlanShareConsentStep.next`，判定见 `requestLiveShare`），
    /// 而「同意过没有」是按用户存的本地状态，弹层拿不到也不该拿到。
    func toggleLiveShare() {
        if shareViewModel.isLiveSharing {
            Task { await shareViewModel.stopLiveShare() }
        } else {
            requestLiveShare()
        }
    }

    /// 约好态的主按钮与汇合页的「打电话给<陪跑员>」共用。
    ///
    /// 拨号一律经 `EmergencyDialer`：它拦掩码串、并只取数字位；掩码串若不拦会拼成 `tel://1381234`，
    /// 而空号在界面上看不出任何异常（守卫 `raw-open-url` 拦绕开它的写法）。
    /// 拿不到号码时**出声**：按钮只在拼得出 URL 时才渲染，走到这里说明轮询间号码被收回了 ——
    /// 静默 return 在盲人端就是「点了没反应」。
    func dialVolunteer(_ order: OrderDetailResponse) {
        guard let url = EmergencyDialer.telURL(for: order.volunteerPhone?.nilIfBlank) else {
            speechService.speakError("暂时无法获取陪跑员电话，请稍后重试。")
            return
        }
        EmergencyDialer.dial(url)
    }

    private func handleFlowPrimaryAction(
        _ presentation: BlindOrderFlowPresentation,
        order: OrderDetailResponse
    ) {
        switch presentation.primaryAction {
        case .callVolunteer:
            dialVolunteer(order)
        case .openIntroCall:
            // 通话态 2026-11-11 起走 v7 同页（`stageContent`），骨架不再渲染这一态，走不到这里。
            break
        case .keepWaiting:
            Task { await viewModel.keepWaiting() }
        case .startRun:
            Task { await viewModel.startRun() }
        case .startRunLocked:
            // 不可按（`.disabled()`），走不到这里。显式分支理由同 `.preparing`。
            break
        case .announceStats:
            // 与导航栏那枚「重复当前状态」是**同一个函数**：`repeatStatus` 播的就是
            // 状态 + 里程 / 时长 / 配速（用播报口径，不是屏幕上那个 `9'06"`）。
            // 两处各写一份的下场是跑步中那屏播的和别处不一样，而没有人会发现。
            viewModel.repeatStatus()
        case .done:
            // 「完成」只是离开这一页（订单早已是 `COMPLETED`，结束权在陪跑员手上）。
            dismiss()
        case .preparing:
            // 倒计时那三秒按钮是 `.disabled()` 的，走不到这里。留一个显式分支而不是
            // 并进 `nil`：`PrimaryAction` 加档时编译器会逼一次决策。
            break
        case nil:
            break
        }
    }

    private var trackingContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在获取订单状态...")
                        .tint(AppColors.primary)
                        .accessibilityLabel("正在获取订单状态")
                }

                if let order = viewModel.order {
                    // 顺序即优先级：状态（一句话 + 一个数字）→ 这一态唯一的主动作 →
                    // 同一态的次级动作 → 附属动作 → 其余全部下沉。此前主动作排在第 4 位，
                    // 读屏要滑过状态卡、地图、生命周期卡才够得着。
                    //
                    // `actionSection` 2026-08-19 从第 8 位提到这里：它装的是**这一态的
                    // 状态机动作**（等待中取消、终态返回首页），与上面的主动作同族；
                    // 而「把行程告诉家人」是附属动作 —— 跑不跑得成与它无关。
                    // 排在附属动作后面的直接后果：延长次数用完的 `REMATCHING`
                    // 主动作版位是空的，于是首屏第一个能按的东西是分享，
                    // 而此刻用户唯一还能做的决定是「要不要取消」。
                    statusHeader(order)
                        .accessibilityFocused($statusHeaderFocused)
                    volunteerCallSection(order)
                    keepWaitingSection(order)
                    actionSection(order)
                    runPlanShareSection(order)
                    dispatchAlgorithmNoticeSection(order)
                    peerMapSection(order)
                    OrderCounterpartSafetySection(order: order)
                    orderInfoSection(order)
                    statusLogSection
                    debugMockControls(order)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            // 这一页在 iPad 上最吃亏：状态卡、生命周期、订单信息全是长文本行，
            // 不限宽时一行横跨 1024pt。见 `BlindLayout.readableContentWidth`。
            .readableContentColumn()
        }
    }
}
