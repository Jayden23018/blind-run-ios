import Foundation

/// 出发地点会发给候选陪跑员的提醒（#660 F-14）。
///
/// 起点默认是当前位置，而盲人多半在家里下单。派单邀请把精确地址发给附近每一位候选人，接单前就看得到，
/// 拒单的人也拿到了。地址怎么收窄要等后端（接单前只给街道级），这里先做下单时能做的：说一句。
extension BlindBookingViewModel {
    static let startPointPrivacyNotice = "出发地点会发给附近的候选陪跑员，建议约在公共地点，不要约在家门口。"

    /// 表单上那一行。只在出发点来自设备当前位置时有值；搜索或常用地点是用户自己挑的，不再提醒。
    var startPointPrivacyNotice: String? {
        guard selectedStartPlace == nil, resolvedStartPlace?.source == .deviceLocation else { return nil }
        return Self.startPointPrivacyNotice
    }

    /// 语音读回里接在出发地点后面的那一句。**一次预约只念一次**：读回每改一项就重念一遍整单，
    /// 每遍都带这句会把真正要核对的内容淹掉。没有要念的就返回空串。
    func consumeStartPointPrivacySpeech() -> String {
        guard !hasSpokenStartPointPrivacyNotice, let notice = startPointPrivacyNotice else { return "" }
        hasSpokenStartPointPrivacyNotice = true
        return notice
    }
}
