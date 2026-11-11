import Foundation

/// 约跑页点「开始找陪跑员」那一刻，出发点能不能用「当前位置」（#813）。
///
/// 精确位置关着时，系统给的是几公里外的区域代表点，不能当出发点（`LocationService.isPreciseLocationOff`）。
/// 以前这里什么都不说，只在提交时念「请选择出发地点」。现在：
/// - 精确位置关闭 → 点提交就请求一次临时精确位置（系统框，读屏原生支持）。被拒才给应用自己的短提示。
/// - 定位权限被拒 → 系统不会再弹，直接给短提示，出路是「去设置」。
/// - 出发点是常用地点 → 不管定位怎样都放行（搜索与常用地点照常可用，预约照常提交）。
///
/// 纯函数 + 文案，单测在 `BookingStartGateTests`。规格 `blind-precise-location-gate`。
enum BookingStartGate: Equatable {
    /// 直接提交。
    case proceed
    /// 先请求临时精确位置，再看结果。
    case askPreciseLocation
    /// 定位权限被拒，不能用当前位置。
    case blockedByDeniedLocation

    static func evaluate(usesCurrentLocation: Bool, isDenied: Bool, isPreciseLocationOff: Bool) -> BookingStartGate {
        guard usesCurrentLocation else { return .proceed }
        if isDenied { return .blockedByDeniedLocation }
        return isPreciseLocationOff ? .askPreciseLocation : .proceed
    }
}

/// 应用自己弹的短提示（被拒后）。样式照系统 alert，两个出路：选常用地点 / 去设置。
struct BookingStartGateAlert: Equatable {
    let title: String
    let message: String

    static func make(isDenied: Bool) -> BookingStartGateAlert {
        isDenied
            ? BookingStartGateAlert(title: BookingStartGateCopy.deniedTitle, message: BookingStartGateCopy.deniedMessage)
            : BookingStartGateAlert(title: BookingStartGateCopy.preciseOffTitle, message: BookingStartGateCopy.preciseOffMessage)
    }
}

enum BookingStartGateCopy {
    static let preciseOffTitle = "没有精确位置"
    static let preciseOffMessage = "不能从当前位置出发，陪跑时紧急求助也发不出位置。请选常用地点，或去设置打开精确位置。"
    static let deniedTitle = "没有定位权限"
    static let deniedMessage = "不能从当前位置出发，陪跑时紧急求助也发不出位置。请选常用地点，或去设置打开定位。"
    static let pickFavorite = "选常用地点"
    static let openSettings = "去设置"

    /// 卡底那行小字。出发点是当前位置、且定位用不了时才有；其余 `nil`。
    static func detail(isDenied: Bool, isPreciseLocationOff: Bool) -> String? {
        if isDenied { return "定位权限没开，不能用当前位置" }
        return isPreciseLocationOff ? "精确位置已关闭，开始时请你允许一次" : nil
    }

    /// 进页开场播报里替代「从当前位置出发」的那句。`nil` = 不替代。
    static func entrySpoken(isDenied: Bool, isPreciseLocationOff: Bool) -> String? {
        if isDenied { return "定位权限没开，不能用当前位置出发。请选常用地点，或到设置里打开定位。" }
        return isPreciseLocationOff
            ? "精确位置已关闭，不能用当前位置出发。点开始时请允许精确位置一次，或选常用地点。"
            : nil
    }
}
