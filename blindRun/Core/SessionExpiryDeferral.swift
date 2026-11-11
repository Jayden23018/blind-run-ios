import Combine
import Foundation
import SwiftUI

/// 跑步中登录过期、暂缓退出（#376）。
struct SessionExpiryDeferral: Equatable {
    /// 进入暂缓时的角色。横幅文案按它分：跑者「跑完后需要重新登录」，陪跑员「结束陪跑要先重新登录」。
    let role: UserRole?
    /// 需要（再）播报一次就 +1。`ContentView` 按它的变化念，不按整个值 —— 值里还有时间戳。
    var announcementSerial: Int
    var lastAnnouncedAt: Date

    /// 横幅与第一次播报。三件事都要说：发生了什么、为什么没退出、求助怎么办。
    /// 最后一句是 `AGENTS.md` §6 的红线：凭证过期时云端求助发不出去，必须说清「App 不会代你发送求助」。
    var bannerMessage: String {
        switch role {
        case .volunteer:
            return "登录已过期，陪跑可以继续；结束陪跑前要先点「现在重新登录」。"
                + "云端求助发不出去，紧急情况请直接拨打120或110，App 不会代你发送求助。"
        default:
            return "登录已过期，跑完后需要重新登录；"
                + "云端求助发不出去，紧急情况请直接拨打120或110，App 不会代你发送求助。"
        }
    }

    /// 暂缓期间又收到 401（多半是用户自己按了某个按钮）时补念的那一句。比横幅短：横幅一直在屏幕上。
    var reminderMessage: String {
        switch role {
        case .volunteer:
            return "登录已过期，这个操作需要先重新登录，请点屏幕底部的「现在重新登录」。紧急情况请直接拨打120或110。"
        default:
            return "登录已过期，这个操作现在做不了，跑完后需要重新登录。紧急情况请直接拨打120或110。"
        }
    }

    var spokenMessage: String {
        announcementSerial <= 1 ? bannerMessage : reminderMessage
    }
}
