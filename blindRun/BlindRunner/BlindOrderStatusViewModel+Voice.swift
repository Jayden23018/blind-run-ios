import SwiftUI

extension BlindOrderStatusViewModel {
    /// 按下「问一句」。判定与答句在 `VoiceStatusQuery`，录音与拨号在 `VoiceStatusQuerySession`。
    func askVoiceQuestion() {
        voiceQuerySession.ask()
    }

    /// 陪跑中那屏的「定位正常 / 定位信号弱」。
    ///
    /// 判**本机定位新不新鲜**，复用既有的新鲜度闸（`LocationService.latestBackendSample`），
    /// 不自己再写一套时限。
    ///
    /// 🚩 不绑后端的 `ESCORT_SIGNAL_LOST`：那是一次性告警事件
    /// （`AppRealtimeCoordinator.routeNotification` 把它路由成瞬时提示），没有可持续读的状态；
    /// 而用户看到这一行能做的事只跟本机定位有关。
    ///
    /// 演示坐标一律判成「信号弱」：这一行是安全信息，把 mock 坐标报成「定位正常」，
    /// 用户就会据此认为「播报我的位置」给出的地名是真的。
    /// 🚩 新鲜度取 `escortSampleMaxAge`（60 秒）**而不是** `latestBackendSample` 默认的 15 秒。
    /// 15 秒是求助路径那道闸的值 —— 那一刻宁可说「拿不到位置」也不能用旧坐标。
    /// 这一行是个**常驻指示灯**：等红灯站 20 秒就翻成「信号弱」，它就成了噪音，
    /// 而噪音化的安全指示灯在真的失效时不会有人注意。60 秒的取法与理由见该常量自己的注释。
    var isDeviceLocationFresh: Bool {
        guard let locationService, !locationService.isUsingDemoFallback else { return false }
        return locationService.latestBackendSample(freshness: LocationService.escortSampleMaxAge) != nil
    }

    /// 求助中心里的「播报我的位置」。电话那头的人问「你在哪」时，这是盲人唯一能自己回答的通道。
    ///
    /// 🔴 **拿不到就说拿不到，不编。** 这一句会被用户逐字转述给 110 / 120 ——
    /// 一个猜出来的地名比没有地名危险得多。演示坐标同样一个字都不播（`isUsingDemoFallback`）。
    ///
    /// 两条来源，本机优先：本机定位是此刻的，服务端那份最旧 30 秒，而且只在出发 / 汇合 /
    /// 陪跑中三态才有（匹配中、约好时求助中心同样开着）。本机拿不到或逆地理失败时才问
    /// `GET /api/orders/{id}/location/address`（后端 #387 ①），并照它的 `ageSeconds` 说清新鲜度。
    ///
    /// 🔴 「精确位置」关着时两条来源都不用（#406）：本机是区域代表点，服务端那份来自同一台手机的上报，
    /// 一样是模糊点。也不申请临时精确位置 —— 系统框会在这一刻抢走读屏焦点。
    func announceCurrentLocation() async {
        // 没注入定位服务就判不出精确位置开没开：按拿不到处理，不退到服务端那份（它可能就是模糊点）。
        guard let locationService else {
            speechService?.speak(EmergencySafetyCopy.locationAnnouncement(nil), priority: .onDemand)
            return
        }
        // 答句不走网络、立刻出声，所以不先说「正在获取」—— 说了只会被马上打断。
        if locationService.isPreciseLocationOff {
            speechService?.speak(EmergencySafetyCopy.locationAnnouncementPreciseLocationOff, priority: .onDemand)
            return
        }
        // 逆地理要走一趟网络。先说一句进行时，否则按下去到出结果之间是一段静默 ——
        // 对看不见屏幕的人，静默就是「点了没反应」。答句回来时会盖掉它，那正是想要的
        // （`.onDemand` 同档相互打断，见 `AnnouncementPriority`）。
        speechService?.speak(EmergencySafetyCopy.locating, priority: .onDemand)
        if !locationService.isUsingDemoFallback,
           let coordinate = locationService.currentLocation {
            let place = await placeSearchProvider?.reverseGeocode(coordinate: coordinate)
            // `title` 是 POI 名（「人民公园」），`addressText` 是街道级描述。优先念前者：
            // 电话里说得清的是地标，不是一串门牌号。
            if let description = place.flatMap({ $0.title.nilIfBlank ?? $0.addressText.nilIfBlank }) {
                speechService?.speak(EmergencySafetyCopy.locationAnnouncement(description), priority: .onDemand)
                return
            }
        }
        guard let orderId = currentOrderId,
              let response = try? await appState?.safety.orderLocationAddress(orderId: orderId) else {
            speechService?.speak(EmergencySafetyCopy.locationAnnouncement(nil), priority: .onDemand)
            return
        }
        speechService?.speak(EmergencySafetyCopy.locationAnnouncement(server: response), priority: .onDemand)
    }

    func repeatStatus() {
        if let order {
            var announcement = order.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
            // 「继续等待」只有在这里被念到才会被发现：它是等待期唯一的主动作，
            // 而看不见屏幕的人不会知道页面上多了一个按钮。
            if canShowKeepWaiting {
                announcement += " " + KeepWaitingCopy.repeatStatusSuffix
            }
            // 陪跑中与已完成屏幕上那三个数字**只有这一条通道能听全**：它们是 `Text`，
            // 读屏要逐个滑过去才念，而「重复当前状态」/「播报当前数据」是盲人按一下就听全的入口。
            // 用播报口径（`distanceText` 等）而不是屏幕口径 —— `9'06"` 会被念成「九撇零六引号」。
            if let stats = trackStats,
               let clause = Self.spokenStatsClause(stats, isFinished: order.status == .completed) {
                announcement += " " + clause
            }
            // Canonical order status first, emergency state appended after it — never instead of it.
            if let sos = appState?.emergencyCoordinator.repeatStatusSuffix {
                announcement += " " + sos
            }
            // 按需档：用户刚按了「重复当前状态」/「播报当前数据」。它低于「对方操作」——
            // 状态刚推进时那一句比复述更要紧，复述会排在它后面而不是把它切断。
            // 前置音（单声 0.3 秒）由 `AnnouncementCue.leadIn(for:)` 按档自动加。
            speechService?.speak(announcement, priority: .onDemand)
        } else {
            speechService?.speak("正在获取订单状态。", priority: .onDemand)
        }
    }
}
