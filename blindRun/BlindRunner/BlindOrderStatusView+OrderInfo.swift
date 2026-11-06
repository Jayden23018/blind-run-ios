import SwiftUI

extension BlindOrderStatusView {
    /// 「匹配规则说明」——《互联网信息服务算法推荐管理规定》第十六条的「显著方式告知」。
    ///
    /// **版位**：附属动作（分享）之后、地图之前。本文件开头写死的顺序原则是
    /// 「状态 → 主动作 → 同态次级动作 → 附属动作 → 其余下沉」，而这一条是**信息性**的：
    /// 它不该抢在「取消订单」前面（那是此刻唯一真正的决定），也不能沉到订单信息下面 ——
    /// 看不见屏幕的人靠遍历顺序发现功能存在，沉下去等于没做，而「显著」正是这条法规要的东西。
    ///
    /// 🚩 **刻意不进 `repeatStatus` 播报。** 「继续等待」进播报是因为它有时限、不按订单会被自动取消；
    /// 算法告知没有时限，为它把最高频的那条路径（每次复述状态）加长不划算。它的发现路径是遍历顺序。
    ///
    /// `buttonShapeOutlineIfNeeded` 不能省：纯文字行，开启「按钮形状」的低视力用户
    /// 否则看不出它可点（与 `keepWaitingSection` / `actionSection` 同一条理由）。
    @ViewBuilder
    func dispatchAlgorithmNoticeSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersDispatchAlgorithmNotice {
            NavigationLink {
                DispatchAlgorithmNoticeView()
            } label: {
                Text(DispatchAlgorithmNoticeCopy.entryTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .buttonShapeOutlineIfNeeded(color: AppColors.primary)
            .accessibilityLabel(DispatchAlgorithmNoticeCopy.entryTitle)
            .accessibilityHint(DispatchAlgorithmNoticeCopy.entryAccessibilityHint)
            .accessibilityIdentifier("blindOrderStatusDispatchAlgorithmNoticeLink")
        }
    }

    /// 折叠。这 8 行在下单时已经被逐条读回确认过一遍，服务进行中它们既不可改也无需再听 ——
    /// 摊开就是读屏用户在主路径上多滑 8 次。`DisclosureGroup` 保留了「想听时能听」，
    /// 而不是把信息删掉。
    func orderInfoSection(_ order: OrderDetailResponse) -> some View {
        DisclosureGroup("预约信息") {
            orderInfoRows(order)
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到预约时间、出发地点等已确认的信息")
    }

    func orderInfoRows(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            // 约定的结束时间。取 `plannedEnd`，**不是** `预约时间 + 预计时长` 推的 ——
            // 理由见 `plannedEndForAnnouncement`。下面那行「预计时长」是用户下单时选的档位，
            // 两者放在一起时更要分清：时长是意愿，结束时间是后端算出来的约定。
            if let plannedEnd = order.plannedEndForAnnouncement {
                infoRow("预计结束时间", plannedEnd)
            }
            if let address = order.startAddress, !address.trimmed.isEmpty {
                infoRow("出发地点", address)
            }
            if let endAddress = order.endAddressForDisplay {
                infoRow("结束地点", endAddress)
            }
            if let routeNotes = order.routeNotes, !routeNotes.trimmed.isEmpty {
                infoRow("路线备注", routeNotes)
            }
            if let duration = order.expectedDurationMinutes {
                infoRow("预计时长", "\(duration) 分钟")
            }
            if let pace = order.pacePreference {
                infoRow("配速偏好", pace.displayName)
            }
            if let route = order.routePreference {
                infoRow("路线偏好", route.displayName)
            }
            if order.hasGuideDogThisRun == true {
                infoRow("导盲犬", "本次携带")
            }
            if let notes = order.specialNotes, !notes.trimmed.isEmpty {
                infoRow("特殊说明", notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}
