import CoreLocation
import SwiftUI

// MARK: - 订单页 v7：出发起地图常驻（#918）

// 定稿见 `docs/ui/mockups/blind-order-tracking-20261109/DECISION.md` 第 4、5、6、10 条。
// 这个文件只放纯逻辑（哪几态走地图、抽屉写什么、地图画什么），视图在
// `BlindOrderTrackingView.swift` / `BlindOrderTrackingDrawer.swift`，单测在
// `BlindOrderTrackingLayoutTests`。

extension RunOrderStatus {
    /// 这一态走「上半屏地图 + 下半屏抽屉」（稿 ⑤–⑧）。其余态仍走 `BlindOrderFlowView`。
    ///
    /// 穷举 switch，理由同 `blindOrderFlowStep`：后端加状态时编译器逼一次决策。
    /// 四态必须走**同一个**视图分支 —— 地图实例在四态间不重建，状态切换只换抽屉
    /// （负责人原话：「它只是换半个屏，所以就感觉是很 continuous 的」）。
    var usesBlindTrackingMap: Bool {
        switch self {
        case .driverEnRoute, .driverArrived, .inProgress, .completed:
            return true
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .cancelled, .rematching, .noVolunteer, .unknown:
            return false
        }
    }
}

// MARK: - 抽屉文案

/// 抽屉标题与副标题。**只用于屏幕与读屏标签**，状态播报（TTS）仍走原来那套，不改。
enum BlindTrackingDrawerCopy {
    /// 拿不到「具体见面位置」时的说法。
    static let meetPointFallback = "集合点"
    static func waitInPlace(place: String?) -> String { "请在\(place?.nilIfBlank ?? meetPointFallback)原地等" }
    static let shareRowTitle = "行程分享给家人"
    static let shareOn = "已开"
    static let shareOff = "未开"
    static let leaveMessage = "留一句话"
    static let call = "打电话"
    static let handleLabel = "进度详情"
    static let handleExpanded = "已展开"
    static let handleCollapsed = "已收起"
    static let expandAction = "展开"
    static let collapseAction = "收起"
    static let handleHint = "双击切换展开和收起，展开后能看到每一步的进度"

    /// 稿 ⑤–⑧ 的标题。`name` 是朗读版姓氏（`volunteerNameForSpeech`）。
    static func title(status: RunOrderStatus, name: String, meetSpot: String?) -> String? {
        switch status {
        case .driverEnRoute:
            return "\(name)正在来找你"
        case .driverArrived:
            return "\(name)到了，在\(meetSpot?.nilIfBlank ?? meetPointFallback)等你"
        case .inProgress:
            return "和\(name)一起跑步中"
        case .completed:
            return "跑完了，和\(name)一起"
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .cancelled, .rematching, .noVolunteer, .unknown:
            return nil
        }
    }

    /// ⑤ 出发的副标题：「距出发地点约 300 米 · 请在南门原地等」。地点取具体见面位置，没有再取出发地址，
    /// 都没有才说「集合点」—— 这一页不再有地点行，地点只能在这一句里念到。
    /// 拿不到距离时只说后半句 —— 不编数字（「N 分钟后到」等 backend#943）。
    static func enRouteSubtitle(distanceText: String?, place: String?) -> String {
        [distanceText?.nilIfBlank, waitInPlace(place: place)].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 抽屉里的竖线

extension BlindOrderTrackingLayout {
    /// ⑤–⑧ 抽屉里那条竖线的输入。`nil` = 这一态不画竖线。
    ///
    /// 不折叠（`folds: false`）：竖线只在拉到顶时才完整看得见，那时五步平铺（稿 C 帧）。
    /// 「等出发」下写「已出发」：稿上是「陈 0:58 出发」，出发时刻要读状态流水，这一页不拉，按稿的兜底只写「已出发」。
    static func timelineInput(status: RunOrderStatus, place: String?) -> BlindOrderTimelineInput? {
        guard status.usesBlindTrackingMap, let position = status.blindOrderTimelinePosition else { return nil }
        var details: [BlindOrderTimelineStep: String] = [.awaitDeparture: "已出发"]
        if position == .current(.meetUp) {
            details[.meetUp] = BlindTrackingDrawerCopy.waitInPlace(place: place)
        }
        return BlindOrderTimelineInput(position: position, details: details, folds: false)
    }
}

// MARK: - 地图画什么

/// 地图这一刻的全部内容。由 `BlindOrderTrackingLayout.mapContent` 算，视图只消费。
struct BlindTrackingMapContent {
    let center: CLLocationCoordinate2D
    let zoomLevel: CGFloat
    let annotations: [MapAnnotationItem]
    let polylines: [MapPolylineItem]
    /// 高德自带的「我」蓝点。已完成那一幕不画（人已经不在路线上了）。
    let showsUserLocation: Bool
}

enum BlindOrderTrackingLayout {
    /// 点与地图边缘至少留的距离。图钉约 20pt 高，留得比它多。
    static let mapPadding: CGFloat = 40
    /// 只有一个点时的缩放级别（约能看清周围两三个路口）。
    static let singlePointZoom: CGFloat = 17
    /// 上半屏地图占可用高度的比例（稿 ⑤：地图约占上半屏）。
    static let mapHeightFraction: CGFloat = 0.48
    /// 抽屉拉到顶时，地图还露出的那一条（稿 C 帧）。要放得下顶栏（命中区 64pt）。
    static let expandedMapStrip: CGFloat = 76

    static let meetPointID = "tracking-meet-point"
    static let volunteerID = "tracking-volunteer"
    static let routeID = "tracking-route"

    /// 竖线的透明度。稿 B 帧：随拉动距离从 0 渐变到 1。
    ///
    /// 🔴 **读屏打开时恒为 1**：读屏用户拖不动抽屉，竖线直接排在抽屉内容最后（DECISION 第 5 条）。
    static func timelineOpacity(progress: CGFloat, voiceOverRunning: Bool) -> Double {
        if voiceOverRunning { return 1 }
        return Double(min(1, max(0, progress)))
    }

    /// 最大字号（AX 档）或横屏矮屏下不画地图，抽屉占满（DECISION「实现时要注意」第 3 条）。
    static func showsMap(isAccessibilitySize: Bool, isCompactHeight: Bool) -> Bool {
        !isAccessibilitySize && !isCompactHeight
    }

    /// 抽屉从收起（0）到拉到顶（1）的进度。
    static func drawerProgress(top: CGFloat, collapsedTop: CGFloat, expandedTop: CGFloat) -> CGFloat {
        let span = collapsedTop - expandedTop
        guard span > 0 else { return 1 }
        return min(1, max(0, (collapsedTop - top) / span))
    }

    /// 地图内容。`nil` = 这一态不走地图，或者一个点都拿不到（视图画纯色底）。
    ///
    /// - 出发 / 已到达：集合点 + 陪跑员 + 我（蓝点由高德画，坐标只用来取景）。
    /// - 陪跑中：已跑路线 + 陪跑员 + 我。
    /// - 已完成：整条路线 + 起终点，不画我。
    ///
    /// 取景**不靠** `isPrimary` 自动取景（小地图上不生效，记忆
    /// `amap-primary-route-fit-not-applied-on-small-map`），按外框自己算缩放级别。
    static func mapContent(
        status: RunOrderStatus,
        meetPoint: CLLocationCoordinate2D?,
        volunteer: CLLocationCoordinate2D?,
        me: CLLocationCoordinate2D?,
        route: [CLLocationCoordinate2D],
        size: CGSize,
        peerTitle: String = "陪跑员"
    ) -> BlindTrackingMapContent? {
        guard status.usesBlindTrackingMap else { return nil }
        let drawsRoute = (status == .inProgress || status == .completed) && route.count >= 2
        var annotations: [MapAnnotationItem] = []
        var polylines: [MapPolylineItem] = []
        var framed: [CLLocationCoordinate2D] = []

        if drawsRoute {
            polylines.append(MapPolylineItem(id: routeID, coordinates: route))
            framed += route
        }
        if status == .completed {
            if drawsRoute, let start = route.first, let end = route.last {
                annotations.append(MapAnnotationItem(id: "tracking-route-start", coordinate: start, title: "起点", subtitle: nil, kind: .routeStart))
                annotations.append(MapAnnotationItem(id: "tracking-route-end", coordinate: end, title: "终点", subtitle: nil, kind: .routeEnd))
            } else if let meetPoint {
                // 没有轨迹（GPS 全程拿不到）时退回集合点，地图不至于空着。
                annotations.append(MapAnnotationItem(id: meetPointID, coordinate: meetPoint, title: "集合点", subtitle: nil, kind: .orderStart))
                framed.append(meetPoint)
            }
        } else {
            if !drawsRoute, let meetPoint {
                annotations.append(MapAnnotationItem(id: meetPointID, coordinate: meetPoint, title: "集合点", subtitle: nil, kind: .orderStart))
                framed.append(meetPoint)
            }
            if let volunteer {
                annotations.append(MapAnnotationItem(id: volunteerID, coordinate: volunteer, title: peerTitle, subtitle: nil, kind: .peer))
                framed.append(volunteer)
            }
            if let me { framed.append(me) }
        }

        guard !framed.isEmpty else { return nil }
        let zoom = min(
            singlePointZoom,
            VolunteerProfileFirstScreen.fittingZoomLevel(framed, in: size, padding: mapPadding)
        )
        return BlindTrackingMapContent(
            center: VolunteerProfileFirstScreen.center(of: framed),
            zoomLevel: zoom,
            annotations: annotations,
            polylines: polylines,
            showsUserLocation: status != .completed
        )
    }
}

// MARK: - 主按钮的读屏提示

/// 订单页两种外壳（`BlindOrderFlowView` 与 v7 的 `BlindOrderTrackingView`）共用，提示只写一份。
extension BlindOrderFlowPresentation.PrimaryAction {
    /// `nil` = 这一档不加提示。`FlowActionButton` 走 `accessibilityHintIfPresent`，
    /// 传空串会**覆盖**掉自动合成的提示，所以不能拿 `""` 当「没有」。
    var blindAccessibilityHint: String? {
        switch self {
        case .callVolunteer:
            // 刻意**不念号码**：VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，
            // 而视障跑者在户外常常不戴耳机（要听车流）—— 外放等于把陪跑员的号码
            // 广播给周围所有人。号码对「要不要打这通电话」没有任何帮助。
            return "系统会先弹出拨号确认，确认后才会拨出"
        case .openIntroCall:
            return IntroCallCopy.blindEntryAccessibilityHint
        case .keepWaiting:
            return KeepWaitingCopy.accessibilityHint
        case .startRun:
            return BlindRunCopy.startRunHint
        case .startRunLocked(let opensAt):
            return BlindRunCopy.startRunLockedHint(opensAt: opensAt)
        case .preparing:
            // 刻意不给提示。`.disabled()` 已经让读屏念「变暗」，再补一句「马上就可以按了」
            // 是在这三秒里往耳朵里多塞一条没有动作可做的信息。
            return nil
        case .announceStats:
            return BlindRunCopy.announceStatsHint
        case .done:
            // 「完成」两个字不说明按下去会发生什么 —— 而这一刻它是这一屏唯一的出口
            //（返回箭头按稿藏掉了）。
            return BlindRunCopy.finishedButtonHint
        }
    }
}
