import CoreLocation
import SwiftUI

// MARK: - 汇合页方位（陪跑员订单页 v2）
//
// 交付包 02 ④「汇合」与 03 §三。方位由客户端用自己的朝向算，后端只给距离档位
// （对接说明 §3.3）。本文件的判断全是纯函数，视图只画。

/// 八个方位。相对角度 θ = 跑者方位角 − 手机朝向，取 (−180, 180]，右为正。
enum DirectionSector: Int, CaseIterable, Equatable {
    case front, frontRight, right, backRight, back, backLeft, left, frontLeft

    /// 屏幕与读屏用的描述，接在「在你」后面。
    var text: String {
        switch self {
        case .front: return "前方"
        case .frontRight: return "右前方"
        case .right: return "右边"
        case .backRight: return "右后方"
        case .back: return "身后"
        case .backLeft: return "左后方"
        case .left: return "左边"
        case .frontLeft: return "左前方"
        }
    }

    /// 扇区中心角（度）。
    var center: Double { Double(rawValue) * 45 > 180 ? Double(rawValue) * 45 - 360 : Double(rawValue) * 45 }

    static let halfWidth: Double = 22.5
    /// 两边各留 5° 的滞回，避免描述来回跳（交付包 02）。
    static let hysteresis: Double = 5

    /// 把任意角度归到 (−180, 180]。
    static func normalized(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// 两个角度之间的最短夹角（0…180）。
    static func separation(_ a: Double, _ b: Double) -> Double {
        abs(normalized(a - b))
    }

    /// 不带滞回的原始分区。
    /// 边界按交付包 02 的写法归属：|θ|≤22.5 前方；22.5–67.5 前侧；67.5–112.5 侧边；112.5–157.5 后侧；其余身后。
    static func raw(relativeDegrees: Double) -> DirectionSector {
        let d = normalized(relativeDegrees)
        let isRight = d > 0
        switch abs(d) {
        case ...22.5: return .front
        case ...67.5: return isRight ? .frontRight : .frontLeft
        case ...112.5: return isRight ? .right : .left
        case ...157.5: return isRight ? .backRight : .backLeft
        default: return .back
        }
    }

    /// 带滞回：只要还落在上一个扇区外扩 5° 的范围里，就保持上一个描述。
    static func describe(relativeDegrees: Double, previous: DirectionSector?) -> DirectionSector {
        if let previous, separation(relativeDegrees, previous.center) <= halfWidth + hysteresis {
            return previous
        }
        return raw(relativeDegrees: relativeDegrees)
    }

    /// 从 `from` 指向 `to` 的方位角（度，正北为 0，顺时针）。
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// 朝向低通滤波（交付包 03 §三：α = 0.2，变化小于 3° 不更新）。处理 359° → 1° 的绕圈。
enum HeadingFilter {
    static let alpha: Double = 0.2
    static let minimumChange: Double = 3

    /// 返回新的平滑朝向；变化不足 3° 时返回 `nil`（调用方不必更新视图）。
    static func next(previous: Double?, raw: Double) -> Double? {
        guard let previous else { return wrap360(raw) }
        let delta = DirectionSector.normalized(raw - previous)
        let smoothed = wrap360(previous + alpha * delta)
        return DirectionSector.separation(smoothed, previous) < minimumChange ? nil : smoothed
    }

    private static func wrap360(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}

enum DirectionDialGeometry {
    static let minimumSector: Double = 60
    static let maximumSector: Double = 120

    /// 扇形宽度 `max(60°, 2·atan(精度 / 距离))`，上限 120°（交付包 02）。
    static func sectorWidth(accuracyMeters: Double, distanceMeters: Double) -> Double {
        guard distanceMeters > 0 else { return maximumSector }
        let spread = 2 * atan(accuracyMeters / distanceMeters) * 180 / .pi
        return min(max(minimumSector, spread), maximumSector)
    }
}

// MARK: 方位盘

/// 直径 180 的白色圆盘：顶部刻度 = 你面朝的方向；扇形 = 跑者大致方向；圆心写「你」。
///
/// **整个对读屏隐藏**：方位只由标题和副文朗读（交付包 02）。
struct DirectionDial: View {
    /// 相对角度。`nil` = 不画扇形（`FAR` / `UNKNOWN` / 拿不到朝向），圆盘降到 50% 透明。
    let relativeDegrees: Double?
    var sectorWidth: Double = DirectionDialGeometry.minimumSector

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let diameter: CGFloat = 180

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.Flow.surface)
                .shadow(color: AppColors.Flow.navy.opacity(0.10), radius: 15, x: 0, y: 12)

            Capsule()
                .fill(AppColors.Flow.navy)
                .frame(width: 3, height: 8)
                .offset(y: -Self.diameter / 2 + 10)

            if let relativeDegrees {
                ZStack {
                    SectorShape(width: sectorWidth)
                        .fill(AppColors.Flow.accent.opacity(0.16))
                    Triangle()
                        .fill(AppColors.Flow.accent)
                        .frame(width: 14, height: 12)
                        .offset(y: -Self.diameter / 2 + 20)
                }
                .rotationEffect(.degrees(relativeDegrees))
                // 03 §三：`.interactiveSpring(response: 0.3)`；减弱动态效果下仍跟随（这是信息），但不做 spring。
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3), value: relativeDegrees)
                .transition(.opacity)
            }

            Text("你")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(AppColors.Flow.navy, in: Circle())
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .opacity(relativeDegrees == nil ? 0.5 : 1)
        .accessibilityHidden(true)
    }
}

/// 以正上方为中心、宽 `width` 度的扇形。
private struct SectorShape: Shape {
    var width: Double

    var animatableData: Double {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 - width / 2),
            endAngle: .degrees(-90 + width / 2),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: 等待环（④b）

/// 从到达开始计时，15 分钟填满的金色环；中心是已等的分钟数（交付包 02 ④b）。
/// 每秒推进一次、不做缓动（03 §三）。
struct WaitRing: View {
    let waitedSeconds: Int
    var fullSeconds: Int = 900

    private var fraction: CGFloat { min(1, CGFloat(max(0, waitedSeconds)) / CGFloat(fullSeconds)) }
    private var minutes: Int { max(0, waitedSeconds) / 60 }

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.Flow.surfaceSubtle, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AppColors.Flow.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(minutes)").flowHeroNumber(FlowV2Fonts.heroS)
                Text("分钟").flowFont(FlowV2Fonts.subhead(bold: true))
            }
            .foregroundColor(AppColors.Flow.primaryText)
        }
        .frame(width: DirectionDial.diameter, height: DirectionDial.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已等 \(minutes) 分钟，等满 15 分钟可以结束等待")
    }
}

// MARK: - Previews

#Preview("方位盘 · 各状态") {
    ScrollView {
        VStack(spacing: 24) {
            DirectionDial(relativeDegrees: 30)
            DirectionDial(relativeDegrees: -100, sectorWidth: 110)
            DirectionDial(relativeDegrees: nil)
            WaitRing(waitedSeconds: 11 * 60)
            WaitRing(waitedSeconds: 900)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    .background(AppColors.Flow.page)
}

#Preview("方位盘 · 深色") {
    VStack(spacing: 24) {
        DirectionDial(relativeDegrees: 150)
        WaitRing(waitedSeconds: 5 * 60)
    }
    .padding()
    .background(AppColors.Flow.page)
    .preferredColorScheme(.dark)
}
