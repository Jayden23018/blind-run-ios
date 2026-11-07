import MAMapKit
import UIKit

// 跑后详情地图（OpenSpec `add-volunteer-run-record-detail`）的线和标注。
// API 依据 `docs/research/amap-gradient-polyline-and-outline-20260924.md`（本机 SDK 11.1.200 头文件）。
// 标注图片亮暗同值（白底近黑字），所以不进 `AMapContainer.applyColorScheme` 的重画列表。

extension RouteLineStyle {
    var isPace: Bool {
        if case .pace = self { return true }
        return false
    }
}

enum RunRouteGlyph {
    /// 描边色 `#1C1C1E`（负责人 2026-09-24：描边改近黑，D8 不动）。
    static let outlineRGB: UInt32 = 0x1C1C1E
    static let outlineWidth: CGFloat = 11
    static let paceWidth: CGFloat = 6.5
    static let highlightWidth: CGFloat = 18

    static func renderer(for polyline: MAPolyline, style: RouteLineStyle, contrast: RunPaceContrast) -> MAOverlayRenderer? {
        switch style {
        case .outline:
            let renderer = MAPolylineRenderer(polyline: polyline)
            renderer?.lineWidth = contrast.routeOutlineWidth // 增强对比度时加宽（#579）
            renderer?.strokeColor = UIColor(rgb: outlineRGB)
            renderer?.lineJoinType = kMALineJoinRound
            renderer?.lineCapType = kMALineCapRound
            return renderer
        case .highlight:
            let renderer = MAPolylineRenderer(polyline: polyline)
            renderer?.lineWidth = highlightWidth
            renderer?.strokeColor = UIColor(rgb: AppColors.tactileYellowTone.light)
            renderer?.lineJoinType = kMALineJoinRound
            renderer?.lineCapType = kMALineCapRound
            return renderer
        case .pace(_, let fractions):
            guard let multi = polyline as? MAMultiPolyline,
                  let renderer = MAMultiColoredPolylineRenderer(multiPolyline: multi) else { return nil }
            renderer.lineWidth = paceWidth
            renderer.strokeColors = fractions.map { RunPacePalette.color(fraction: $0, isDark: contrast.isDark) }
            renderer.isGradient = true
            return renderer
        }
    }

    static func image(for kind: MapAnnotationKind) -> (image: UIImage, zIndex: Int)? {
        switch kind {
        case .runKilometre(let km):
            return (circle(text: "\(km)"), 1)
        case .runRest(let text):
            return (capsule(text: text, symbol: "pause.fill"), 2)
        case .runBubble(let text):
            return (capsule(text: text, symbol: nil, fontSize: 15), 3)
        case .runEndpoint(let isStart, let compact):
            // 终点压在起点上面：起终点重合时两个都看得见一半，红点在上。
            return (endpoint(isStart: isStart, compact: compact), isStart ? 2 : 3)
        default:
            return nil
        }
    }

    // MARK: 画图（白底近黑字，压任何底图都清楚）

    private static var ink: UIColor { UIColor(rgb: outlineRGB) }

    private static func circle(text: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let side = max(20, label.size().width + 8)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let rect = CGRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.white.setFill()
            path.fill()
            ink.setStroke()
            path.lineWidth = 1
            path.stroke()
            let size = label.size()
            label.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
    }

    /// 白圈彩芯圆点（照健身）。绿 / 红取 `AppColors.success` / `destructive` 的亮色档，亮暗同值：白圈让它压任何底图都清楚。
    private static func endpoint(isStart: Bool, compact: Bool) -> UIImage {
        let side: CGFloat = compact ? 10 : 18
        let ring: CGFloat = compact ? 2 : 3
        let fill = UIColor(rgb: isStart ? 0x1B7F3B : 0xC81E14)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            fill.setFill()
            UIBezierPath(ovalIn: CGRect(x: ring, y: ring, width: side - ring * 2, height: side - ring * 2)).fill()
        }
    }

    private static func capsule(text: String, symbol: String?, fontSize: CGFloat = 12) -> UIImage {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let label = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let icon = symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: fontSize - 2, weight: .bold))?
                .withTintColor(ink, renderingMode: .alwaysOriginal)
        }
        let textSize = label.size()
        let iconWidth = icon.map { $0.size.width + 4 } ?? 0
        let size = CGSize(width: ceil(textSize.width + iconWidth + 16), height: ceil(textSize.height + 8))
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: size.height / 2)
            UIColor.white.setFill()
            path.fill()
            ink.setStroke()
            path.lineWidth = 1
            path.stroke()
            var x: CGFloat = 8
            if let icon {
                icon.draw(at: CGPoint(x: x, y: (size.height - icon.size.height) / 2))
                x += iconWidth
            }
            label.draw(at: CGPoint(x: x, y: (size.height - textSize.height) / 2))
        }
    }
}
