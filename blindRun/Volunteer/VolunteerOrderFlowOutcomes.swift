import Foundation

// MARK: - 汇合 / 已完成 / 跑者已取消

/// 设计交付文档 v3 §5 的后三屏。与前三态**同一个** `VolunteerOrderFlowPresentation`
/// 和同一个页面（`VolunteerOrderFlowPage`），只是内容不同 —— 分文件是因为
/// `VolunteerOrderFlowStep.swift` 已经放不下了，不是因为它们是另一种东西。
///
/// 三屏的共同点是**这一页开始变少**：汇合只剩两行（打电话、找不到对方），
/// 已完成与跑者取消连进度条都没有。设计上是刻意的 —— 这几屏的读者要么正在找人、
/// 要么已经跑完，屏幕上每多一行都是干扰。
extension VolunteerOrderFlowPresentation {
    // MARK: 汇合（`DRIVER_ARRIVED`）

    /// - Parameter peerDistanceText: 本机到**跑者**的距离，由视图从最近一条
    ///   `BLIND_LOCATION_UPDATE` 算好传进来；`nil` = 没有新鲜位置（没授权 / 没收到 / 已过期）。
    ///
    /// 🔴 **设计稿这一屏要的是「李明在你右前方」——方位本轮不做。**
    /// 后端确实在 `DRIVER_ARRIVED` 下发跑者坐标（`websocket-protocol.md` 的
    /// `BLIND_LOCATION_UPDATE`，三态都推），所以**距离是真的**；而「右前方」还要一路
    /// 罗盘朝向，`LocationService` 现在没有 heading，那是给全 App 的共享单例加能力。
    /// 项目负责人 2026-09-17 拍板：先只给距离，方位另立项。
    /// 同一屏上「穿深蓝上衣，戴白色帽子」整句不做 —— 那个字段后端 0 命中，
    /// 而且要跑者端先做填写入口。
    static func metUp(order: OrderDetailResponse, peerDistanceText: String?, now: Date = Date()) -> Self {
        let name = order.blindNameForSpeech
        var rows: [Row] = []
        // 设计稿这一屏第一行就是打电话：到了集合点还没看见人的时候，这是唯一有用的动作。
        if let phoneRow = VolunteerOrderFlowPresentation.phoneRow(order: order, asAction: true) {
            rows.append(phoneRow)
        }
        rows.append(
            Row(
                id: "cannotFind",
                label: nil,
                value: VolunteerOrderFlowCopy.cannotFindRunner,
                detail: nil,
                action: .cannotFindRunner,
                accessibilityLabel: VolunteerOrderFlowCopy.cannotFindRunner,
                accessibilityHint: "打开找人的几条建议，可以从那里直接拨号"
            )
        )

        let title = peerDistanceText.map {
            VolunteerOrderFlowCopy.metUpTitle(name: name, distance: $0)
        } ?? VolunteerOrderFlowCopy.metUpStaleTitle(name: name)

        return Self(
            step: .metUp,
            visual: .avatar,
            title: title,
            // 标题里有姓名 ⇒ 屏幕上是掩码、读屏要去星。这里两处都已经走 `blindNameForSpeech`，
            // 所以两个字符串相同；留 `nil` 而不是重复一份，免得日后只改一处。
            titleSpoken: nil,
            subtitle: peerDistanceText == nil
                ? VolunteerOrderFlowCopy.metUpStaleSubtitle
                : (order.startAddress?.nilIfBlank ?? VolunteerOrderFlowCopy.meetingPointUnknown),
            replyNotice: nil,
            isReplyUrgent: false,
            rows: rows,
            // 等满时限后「开始跑步」原地换成「结束等待」（后端 #362）。
            // 判据只有后端给的 `earliestEndWaitAt`，**不自己拿到达时间加 15**。
            primaryAction: VolunteerOrderPhase.resolve(order: order, now: now) == .arrived(canEndWait: true)
                ? .endWaiting : .startRun,
            // 汇合态不是 `IN_PROGRESS` ⇒ 本地拨号（云端 SOS 关着，`AGENTS.md` §6）。
            helpMode: VolunteerOrderSOSMode.resolve(status: order.status)
        )
    }

    // MARK: 已完成（`COMPLETED`）

    /// 无进度条：四步讲的是「这一单走到哪了」，而这一屏讲的是「它结束了」。
    static func completed(order: OrderDetailResponse) -> Self {
        let name = order.blindNameForSpeech
        let rows: [Row] = [
            Row(
                id: "runRecord",
                label: nil,
                value: VolunteerOrderFlowCopy.viewRunRecord,
                detail: nil,
                action: .viewRunRecord,
                accessibilityLabel: VolunteerOrderFlowCopy.viewRunRecord,
                accessibilityHint: "查看本次的路线、里程和配速"
            ),
            Row(
                id: "reportIssue",
                label: nil,
                value: VolunteerOrderFlowCopy.reportIssue,
                detail: nil,
                action: .reportIssue,
                accessibilityLabel: VolunteerOrderFlowCopy.reportIssue,
                // 契约在 `POST /api/support/tickets` 的 description 上逐字写着
                // 「这不是紧急求助入口」，所以这里的提示要先把时效说清楚。
                accessibilityHint: "提交一条事后反馈，不会立刻有人联系你"
            )
        ]

        return Self(
            step: nil,
            visual: .successCheck,
            title: VolunteerOrderFlowCopy.completedTitle,
            titleSpoken: nil,
            // 两个数各自可缺 ⇒ 缺的那半句整段不出现，一个占位符都不留。
            subtitle: VolunteerOrderFlowCopy.completedSummary(
                name: name,
                distanceMeters: order.actualDistanceMeters,
                durationSeconds: order.actualDurationSeconds
            ) ?? "",
            replyNotice: nil,
            isReplyUrgent: false,
            rows: rows,
            primaryAction: .doneReviewing,
            helpMode: VolunteerOrderSOSMode.resolve(status: order.status)
        )
    }

    // MARK: 跑者已取消（`CANCELLED`）

    /// 这一屏在此之前**根本不存在**：`VolunteerInServiceViewModel.apply` 收到 `CANCELLED`
    /// 就把 `order` 置 nil，两个渲染分支都取不到订单 ⇒ 屏幕退化成一片空白背景，
    /// 只播一句 TTS。志愿者能看到的只有一个没有内容的页面和一个返回箭头。
    ///
    /// 🚩 只管 `CANCELLED`（盲人取消）。`REMATCHING` 是**志愿者自己**退出后的状态，
    /// 那条路仍然直接关页面回首页 —— 他刚按完「仍然取消」，再给他看一屏说明是多余的。
    static func cancelledByRunner(order: OrderDetailResponse, now: Date = Date()) -> Self {
        let name = order.blindNameForSpeech
        var rows: [Row] = []
        if let time = order.blindRunnerShortStartText(now: now) {
            rows.append(
                Row(
                    id: "plannedTime",
                    label: VolunteerOrderFlowCopy.plannedTimeLabel,
                    value: time,
                    detail: nil,
                    action: nil,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.plannedTimeLabel)，\(time)",
                    accessibilityHint: nil
                )
            )
        }
        if let place = order.startAddress?.nilIfBlank {
            rows.append(
                Row(
                    id: "meetingPoint",
                    label: VolunteerOrderFlowCopy.meetingPointLabel,
                    value: place,
                    detail: nil,
                    // 已经取消了，导航过去没有意义 ⇒ 这一行不可点。
                    action: nil,
                    accessibilityLabel: "\(VolunteerOrderFlowCopy.meetingPointLabel)，\(place)",
                    accessibilityHint: nil
                )
            )
        }

        return Self(
            step: nil,
            visual: .mutedAvatar,
            title: VolunteerOrderFlowCopy.runnerCancelledTitle(name: name),
            titleSpoken: nil,
            subtitle: VolunteerOrderFlowCopy.runnerCancelledSubtitle,
            replyNotice: nil,
            isReplyUrgent: false,
            rows: rows,
            primaryAction: .backToHome,
            // v3 设计稿这一屏的注解是「这时不需要求助入口」；交付包 v2 改为全页都有 ——
            // 跑者取消时陪跑员可能已经在户外（02「跑者取消」）。
            helpMode: VolunteerOrderSOSMode.resolve(status: order.status)
        )
    }
}
