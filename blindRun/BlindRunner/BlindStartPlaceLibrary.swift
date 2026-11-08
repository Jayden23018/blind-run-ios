import CoreLocation
import SwiftUI
import UIKit

// 「默认出发地点」页照苹果地图「资料库」的零件（#817）。
// 定稿 `docs/ui/mockups/start-place-library-20261106/`，尺寸取自稿子 CSS（`.circ` `.it` `.nm` `.sb`）。

// MARK: - 图标

/// 地点前面那个彩色圆里的图标。只做装饰，读屏不念。
///
/// 白图标压在圆上，颜色都是本 App 已有的深色调或定稿原值，白图标对比度 5.18–6.98:1（定稿说明）。
/// 亮暗模式同色：和改版前的方块图标一样，深色圆在黑底上照样看得清。
struct BlindStartPlaceIcon {
    /// 收藏地点按地名自动配的几类。顺序就是判定顺序，先命中先用。
    enum Kind: CaseIterable, Equatable {
        case park, metro, track, school, other
    }

    let symbol: String
    let fill: Color
    var glyph: Color = .white
    /// 只有浅色圆要：圆贴白卡片看不出边界时，描一圈 1pt（`nil` = 不描）。
    var stroke: Color?

    /// 定稿规则：公园 / 绿道 → 树，地铁 / 站 → 列车，操场 / 体育 → 跑道，学校 / 书院 → 学士帽，其余 → 红色图钉。
    static func kind(forTitle title: String) -> Kind {
        let rules: [(Kind, [String])] = [
            (.park, ["公园", "绿道"]),
            (.metro, ["地铁", "站"]),
            (.track, ["操场", "体育"]),
            (.school, ["学校", "书院"])
        ]
        return rules.first { _, words in words.contains { title.contains($0) } }?.0 ?? .other
    }

    static func favorite(title: String) -> BlindStartPlaceIcon {
        switch kind(forTitle: title) {
        case .park: return BlindStartPlaceIcon(symbol: treeSymbol, fill: rgb(0x1F7A3A))
        case .metro: return BlindStartPlaceIcon(symbol: "tram.fill", fill: rgb(AppColors.VolunteerHome.distanceIndigoTone.light))
        case .track: return BlindStartPlaceIcon(symbol: "oval.inset.filled", fill: rgb(AppColors.VolunteerHome.streakOrangeTone.light))
        case .school: return BlindStartPlaceIcon(symbol: "graduationcap.fill", fill: rgb(0x7E3FB8))
        case .other: return BlindStartPlaceIcon(symbol: "mappin", fill: rgb(0xC4281C))
        }
    }

    static let currentLocation = BlindStartPlaceIcon(symbol: "location.fill", fill: rgb(AppColors.voiceStageSurfaceTone.light))
    /// 「添加常用地点」页的搜索结果：沿用改版前的蓝底图钉。
    static let searchResult = BlindStartPlaceIcon(symbol: "mappin", fill: rgb(AppColors.voiceStageSurfaceTone.light))
    static let recent = BlindStartPlaceIcon(symbol: "clock.fill", fill: rgb(AppColors.VolunteerHome.durationTealTone.light))
    /// 卡片底色圆 + 灰描边 + 主色加号：与约跑页未选中的胶囊同一种样子（负责人 11-08 定，#906）。
    /// 稿子原是浅灰底 `#EAEAEA`：贴白卡片只有约 1.2:1，审计按占面积最大的两种颜色判，加了描边仍报对比度不足。
    static let add = BlindStartPlaceIcon(
        symbol: "plus",
        fill: AppColors.Flow.surface,
        glyph: AppColors.primary,
        stroke: AppColors.ButtonPalette.neutralStroke
    )

    /// `tree.fill` 要 iOS 16.1（SF Symbols `name_availability.plist`），部署目标是 16.0：取不到时退回叶子。
    private static let treeSymbol = UIImage(systemName: "tree.fill") == nil ? "leaf.fill" : "tree.fill"

    private static func rgb(_ value: UInt32) -> Color { Color(uiColor: UIColor(rgb: value)) }
}

/// 彩色实心圆 + 图标。`diameter` 60（资料库圆排）、30（列表行）、52（最大字号列表）。
struct BlindStartPlaceIconCircle: View {
    let icon: BlindStartPlaceIcon
    let diameter: CGFloat

    var body: some View {
        Image(systemName: icon.symbol)
            // 图标约占直径一半（稿子 60 圆里 29、30 圆里 17）。装饰图形，不跟字号走。
            .font(.system(size: diameter * 0.44, weight: .semibold))
            .foregroundColor(icon.glyph)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(icon.fill))
            .overlay {
                if let stroke = icon.stroke {
                    Circle().strokeBorder(stroke, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 距离

/// 收藏地点的副标题「X 公里」。拿不到定位时不写（定稿：「拿不到定位不写距离」）。
enum BlindStartPlaceDistance {
    /// 设备坐标是 WGS84，收藏是高德 GCJ-02：先换算再量，直接量在国内会偏几百米。
    static func meters(from device: CLLocationCoordinate2D?, to place: ResolvedPlace) -> CLLocationDistance? {
        guard let device else { return nil }
        return DistanceCalculator.distanceFromDeviceToBackend(
            deviceCoordinate: device,
            backendCoordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        )
    }

    /// 10 公里以内保留一位小数（稿子「3.1 公里」「0.6 公里」），再远取整。最少写 0.1，不写「0.0 公里」。
    static func text(meters: CLLocationDistance) -> String {
        let kilometers = max(meters, 100) / 1000
        if kilometers < 10 { return String(format: "%.1f 公里", kilometers) }
        return "\(Int(kilometers.rounded())) 公里"
    }

    /// 读屏念的那句（稿子读屏第 6 条「离你 3.1 公里」）。
    static func spoken(meters: CLLocationDistance) -> String { "离你 \(text(meters: meters))" }
}

// MARK: - 资料库圆

/// 圆 + 下面两行字，整格一个按钮（稿子 `.it`，约 85 × 104pt）。
struct BlindStartPlaceCircleButton: View {
    static let circleDiameter: CGFloat = 60
    /// 稿子 `.it{min-height:104px}`：圆 60 + 13 + 两行名称 + 副标题。
    static let minimumHeight: CGFloat = 104

    let title: String
    let subtitle: String?
    let icon: BlindStartPlaceIcon
    let isSelected: Bool
    let accessibilityLabel: String
    var accessibilityHint: String?
    let identifier: String
    /// 选中时圆下那行主色小字。默认出发地点页写「默认」，约跑页写「这次从这里」（#821）。
    var selectedTag: String = BlindStartPlaceCopy.defaultTag
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                BlindStartPlaceIconCircle(icon: icon, diameter: Self.circleDiameter)
                    // 稿子 `box-shadow: 0 0 0 3px #fff, 0 0 0 6px blue`：圆外留 3pt 白缝再画 3pt 蓝环，不占版面。
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(AppColors.primary, lineWidth: 3)
                                .frame(width: Self.circleDiameter + 12, height: Self.circleDiameter + 12)
                        }
                    }
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)
                    .padding(.top, 13)
                if isSelected {
                    Text(selectedTag)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .padding(.top, 1)
                } else if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 行

// #817 从 `BlindFavoritePlaceAddPage.swift` 挪来（那个文件超了 SwiftLint 的 400 行上限）。

/// 彩色圆形图标 + 名称 + 灰字副标题（#817 起照苹果地图「最近」列表：30pt 圆，原来是 32pt 圆角方块）。
/// 图标只是装饰，读屏不念。可点区由 `contentShape` 撑满整行，高度不低于 64pt。
///
/// 「添加常用地点」页用默认参数，版式与改版前一样；「默认出发地点」页与「常用地点」列表页
/// 传 `prominent`（粗标题、行高 72，稿子 `.rw`）、最大字号时传 `iconDiameter: 52`。
struct BlindFavoritePlaceRowLabel: View {
    /// 分隔线照苹果从图标左缘画起（稿子 `.rw+.rw{border-top}`，`margin-left:16px`）。
    static let dividerInset: CGFloat = GroupedCardMetrics.rowHorizontalPadding
    /// 稿子 `.rw{min-height:72px}`。
    static let prominentMinHeight: CGFloat = 72

    let title: String
    let subtitle: String?
    let icon: BlindStartPlaceIcon
    let isSelected: Bool
    var prominent = false
    var iconDiameter: CGFloat = 30
    /// 副标题是「默认」时用主色加粗（最大字号列表里的选中行，稿 ④）。
    var subtitleIsDefaultTag = false
    var showsDefaultBadge = false

    var body: some View {
        // 稿子 `.ri{margin-right:13px}`（最大字号 14）；添加页沿用改版前的 12，版式不动。
        HStack(spacing: iconDiameter > 30 ? 14 : (prominent ? 13 : 12)) {
            BlindStartPlaceIconCircle(icon: icon, diameter: iconDiameter)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(prominent ? .headline : AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleIsDefaultTag ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundColor(subtitleIsDefaultTag ? AppColors.primary : AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if showsDefaultBadge {
                BlindStartPlaceDefaultBadge()
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: prominent ? Self.prominentMinHeight : AppTouchTarget.blindPrimary,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

// MARK: - 「默认」标签

/// 「常用地点」列表里默认那一行右边的小标签（稿子 `.pill`）。浅蓝底深蓝字，亮 #E6EEFA / #0A4FA6。
struct BlindStartPlaceDefaultBadge: View {
    var body: some View {
        Text(BlindStartPlaceCopy.defaultTag)
            .font(.footnote.weight(.semibold))
            .foregroundColor(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x9CC3FF) : UIColor(rgb: 0x0A4FA6) }))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x1C3352) : UIColor(rgb: 0xE6EEFA) }))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - 组标题

/// 卡片上方的灰色组标题（稿子 `.sh`：15pt semibold 灰，左缘与卡片齐）。
struct BlindStartPlaceSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 文案

enum BlindStartPlaceCopy {
    static let title = "默认出发地点"
    static let currentDefaultHeader = "现在默认从这里出发"
    static let libraryHeader = "常用地点"
    static let recentHeader = "最近跑过的地点"
    static let currentLocation = "当前定位"
    static let currentLocationFollows = "跟着你走"
    static let currentLocationEveryTime = "每次从你所在的位置出发"
    static let add = "添加"
    static let addSpoken = "添加常用地点"
    static let defaultTag = "默认"
    static let defaultSpoken = "默认出发地点"
    static let setDefaultHint = "设为默认出发地点"

    static func allFavorites(count: Int) -> String { "全部 \(count) 个常用地点" }

    static func changed(to title: String) -> String { "默认出发地点已改为\(title)。" }
    static let saveFailed = "默认出发地点没有保存成功，请再试一次。"

    // 「常用地点」列表页（屏 ⑤）
    static let listTitle = "常用地点"
    static func listHeader(count: Int) -> String { "\(count) 个，最多 \(FavoritePlaceStore.capacity) 个" }
    static let listFootnote = "点一行设为默认出发地点。向左滑可以删除；读屏用户上下轻扫选「删除」操作。删掉的是默认地点时，自动改回当前定位并朗读。"
    static let listEmpty = "还没有常用地点。"
    static let delete = "删除"
    static func deleted(_ title: String, wasDefault: Bool) -> String {
        wasDefault ? "已删除\(title)，默认出发地点改回当前定位。" : "已删除\(title)。"
    }
}
