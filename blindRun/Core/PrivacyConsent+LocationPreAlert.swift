import Foundation

/// 位置轨迹说明页（`LocationTrackPreAlertView`）上的一条用途：图标 + 一句话。
struct LocationPreAlertUse: Hashable {
    /// SF Symbol 名。只是装饰，读屏不念。
    let symbol: String
    let text: String
}

/// 位置轨迹的同意排在系统定位授权框之前，所以按苹果 HIG「Pre-alert screens」做成说明页（#776，负责人 2026-11-05 定）：
/// 标题 + 三条用途 + 保存期限与关闭方式 +「查看详细说明」+ 唯一按钮「继续」。
///
/// 这里只能**点名** `disclosures` 里已有的处理行为，不能引入新内容 —— 完整告知仍是 `disclosures`，
/// 收在说明页的「查看详细说明」里。所以改这里不需要 +1 `disclosureVersion`；改 `disclosures` 才要判。
extension PrivacyConsentPurpose {
    /// HIG 原文：用「Continue / Next」这类词说清它会打开系统弹窗，不用「Allow」——
    /// 说明页上的按钮和系统框的「允许」长得像、意思也像，人会顺手点下系统框的允许。
    static let preAlertContinueTitle = "继续"
    /// 只在系统定位已决定、不会再弹系统框时出现（HIG 允许的「法律同意」例外）。
    static let preAlertDeclineTitle = "不同意"

    var preAlertTitle: String {
        switch self {
        case .volunteerLocationTrack: return "接单和陪跑时，你的位置会用来："
        default: return "陪跑时，你的位置会用来："
        }
    }

    /// 三条用途，各自对应 `disclosures` 里的一句。
    var preAlertUses: [LocationPreAlertUse] {
        switch self {
        case .blindLocationTrack:
            return [
                LocationPreAlertUse(symbol: "person.2.fill", text: "让此订单的陪跑员看到你的实时位置，找到你、在跑步中照看你。"),
                LocationPreAlertUse(
                    symbol: "exclamationmark.triangle.fill",
                    text: "用于走散提醒；你发起紧急求助时，当时的位置会用短信发给你的紧急联系人。"
                ),
                LocationPreAlertUse(symbol: "map.fill", text: "跑完后生成这次的路线记录，你和此订单的陪跑员都能查看。")
            ]
        case .volunteerLocationTrack:
            return [
                LocationPreAlertUse(symbol: "bell.fill", text: "接单时给你派附近的陪跑邀请，估算你什么时候该出发。"),
                LocationPreAlertUse(symbol: "person.2.fill", text: "接单后，从你出发到跑完，此订单的视障跑者能看到你的实时位置。"),
                LocationPreAlertUse(
                    symbol: "exclamationmark.triangle.fill",
                    text: "你在陪跑中替跑者发起紧急求助时，当时的位置会用短信发给跑者的紧急联系人。"
                )
            ]
        default:
            return []
        }
    }

    /// 用途下面那段：什么时候在定位、保存多久、怎么关。
    var preAlertFootnote: String {
        switch self {
        case .volunteerLocationTrack:
            return "只在助盲跑开着时为派单获取位置。陪跑中的轨迹保存 90 天，到期自动删除。你可以随时在系统设置里关闭定位。"
        default:
            return "从陪跑员出发到跑步结束持续定位，锁屏后仍在定位。轨迹保存 90 天，到期自动删除。你可以随时在系统设置里关闭定位。"
        }
    }

    /// 说明页的自动播报：标题、三条用途和那段说明。详细说明不念，展开后每条可单独听。
    var preAlertSpokenScript: String {
        ([preAlertTitle] + preAlertUses.map(\.text) + [preAlertFootnote]).joined(separator: " ")
    }
}
