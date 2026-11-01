import Combine
import SwiftUI

// 盲人首页没有订单时的内容：深蓝预约卡占满剩余高度，下方按用户状态放真实内容。
// OpenSpec `redesign-blind-home-idle-state`。

extension FlowMetrics {
    /// 预约卡的白圆。对照 Aira 呼叫卡：圆的直径约占卡宽 40%。
    static let bookingProminentIconDiameter: CGFloat = 148
    /// 预约卡长满一屏时的白圆。
    static let bookingLargestIconDiameter: CGFloat = 188
    /// 矮窗口（iPhone 横屏）的白圆。竖排的圆加文字会超过可用高度，文字压到标签栏后面。
    static let bookingCompactIconDiameter: CGFloat = 96
    /// 预约卡下方的锻炼块和入口行。比深蓝卡小一档，层级差看得出来。
    static let homeRowRadius: CGFloat = 16
}

extension FlowFonts {
    static func bookingProminentTitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (32, .semibold, .title) }
    static func bookingLargestTitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (36, .semibold, .largeTitle) }
    static func bookingProminentSubtitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (17, .regular, .body) }
}

// MARK: - 数据

/// 本月锻炼块的文字。次数为 0 时没有这一块：页面上写「还没有记录」只是泼冷水。
struct BlindHomeRunSummary: Equatable, Codable {
    let period: String
    let headline: String
    let spokenText: String

    init?(monthTitle: String, runs: Int, distanceM: Int?, spokenText: String) {
        guard runs > 0 else { return nil }
        period = "\(monthTitle)已跑"
        headline = distanceM.map { "\(runs) 次 · \(RunRecordHistoryViewModel.kilometres($0)) 公里" } ?? "\(runs) 次"
        self.spokenText = spokenText
    }
}

/// 预约卡下方放什么。
///
/// 没实名时预约必定失败，下方只放实名入口。跑过的人一定已实名，所以实名行和锻炼块不会同时出现。
/// 其余情况有什么真实内容就放什么，一项都没有时卡片长满。
///
/// 出发地点行给跑过的人或有常用地点的人：新用户没有可换的地点，预约时本来就默认用当前定位。
struct BlindHomeBelowCard: Equatable {
    var showsIdentityRow = false
    var runSummary: BlindHomeRunSummary?
    var startRowTitle: String?

    var isEmpty: Bool { !showsIdentityRow && runSummary == nil && startRowTitle == nil }

    static func resolve(
        isIdentityVerified: Bool,
        runSummary: BlindHomeRunSummary?,
        hasRunBefore: Bool,
        favoriteCount: Int,
        defaultPlaceTitle: String?,
        isCurrentLocationUnavailable: Bool
    ) -> BlindHomeBelowCard {
        guard isIdentityVerified else { return BlindHomeBelowCard(showsIdentityRow: true) }
        guard hasRunBefore || favoriteCount > 0 else { return BlindHomeBelowCard(runSummary: runSummary) }
        let title: String
        if let defaultPlaceTitle {
            title = "从\(defaultPlaceTitle)出发"
        } else {
            title = isCurrentLocationUnavailable ? "选择出发地点" : "用当前定位出发"
        }
        return BlindHomeBelowCard(runSummary: runSummary, startRowTitle: title)
    }
}

/// 上次看到的锻炼数据。冷启动时先用它排版，数据回来时卡片才不会缩一下。
struct BlindHomeRunSnapshot: Equatable, Codable {
    var summary: BlindHomeRunSummary?
    var hasRunBefore: Bool
}

@MainActor
final class BlindHomeIdleModel: ObservableObject {
    @Published private(set) var snapshot: BlindHomeRunSnapshot

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: AppConstants.UserDefaultsKeys.blindHomeRunSnapshot)
        snapshot = saved.flatMap { try? JSONDecoder().decode(BlindHomeRunSnapshot.self, from: $0) }
            ?? BlindHomeRunSnapshot(summary: nil, hasRunBefore: false)
    }

    /// 取最近一个有记录的月份：本月没跑过而以前跑过时退到上月，否则每月 1 号这一块都会消失。
    /// 加载失败时保留上次的内容，不把老用户当成新用户。
    func refresh(appState: AppState) async {
        let history = RunRecordHistoryViewModel(role: .runner)
        // 不传 `speechService`：首页不自动念这一句。
        history.configure(with: appState, speechService: nil)
        await history.load()
        if history.history?.monthSummary.runs == 0, history.hasAnyCompletedOrder == true {
            await history.showPreviousMonth()
        }
        guard let month = history.history?.monthSummary, let hasCompletedOrder = history.hasAnyCompletedOrder else { return }
        // 订单列表只取最近一页，全是取消单时看不到已完成的，所以月度次数也算数。
        let hasRunBefore = hasCompletedOrder || month.runs > 0
        let summary = history.summaryText(spoken: true).flatMap {
            BlindHomeRunSummary(monthTitle: history.monthTitle, runs: month.runs, distanceM: month.distanceM, spokenText: $0)
        }
        apply(BlindHomeRunSnapshot(summary: summary, hasRunBefore: hasRunBefore))
    }

    func apply(_ newValue: BlindHomeRunSnapshot) {
        snapshot = newValue
        defaults.set(try? JSONEncoder().encode(newValue), forKey: AppConstants.UserDefaultsKeys.blindHomeRunSnapshot)
    }

    func content(
        isIdentityVerified: Bool,
        favorites: FavoritePlaceStore,
        isCurrentLocationUnavailable: Bool
    ) -> BlindHomeBelowCard {
        BlindHomeBelowCard.resolve(
            isIdentityVerified: isIdentityVerified,
            runSummary: snapshot.summary,
            hasRunBefore: snapshot.hasRunBefore,
            favoriteCount: favorites.places.count,
            defaultPlaceTitle: favorites.defaultPlace?.title,
            isCurrentLocationUnavailable: isCurrentLocationUnavailable
        )
    }
}

// MARK: - 预约卡

/// 没有订单时的预约卡。按下去的行为、读屏文案和 identifier 都与 `BlindHomeBookingBlock` 相同。
///
/// 构图参照 Aira 首页的呼叫卡：白圆与文字整组居中。卡片变高时圆和字跟着放大，
/// 不用 `Spacer` 把图标和文字分到上下两端，否则中间会空出一块。
struct BlindHomeProminentBookingCard: View {
    let isEnabled: Bool
    let isLargest: Bool
    let action: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Button(action: action) {
            Group {
                if verticalSizeClass == .compact {
                    HStack(spacing: 20) {
                        icon
                        titles(alignment: .leading)
                    }
                } else {
                    VStack(spacing: 20) {
                        icon
                        titles(alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(FlowMetrics.homeCardPadding)
            .background(AppColors.Flow.navy)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeCardRadius, style: .continuous))
            .flowCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isEnabled ? "预约新的陪跑" : "预约新的陪跑，订单状态尚未确认")
        .accessibilityHint(BlindHomeBookingBlock.bookingHint(isEnabled: isEnabled))
        .modifier(BookingBlockIdentifier(isEnabled: isEnabled))
    }

    private func titles(alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: 6) {
            Text("预约新的陪跑")
                .flowFont(isLargest ? FlowFonts.bookingLargestTitle() : FlowFonts.bookingProminentTitle())
                .foregroundColor(.white)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
            Text("选好时间和地点，系统帮你找陪跑员")
                .flowFont(FlowFonts.bookingProminentSubtitle())
                .foregroundColor(AppColors.Flow.onNavySecondary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 两个人形一前一后：这个入口预约的是「有人陪着跑」，只画一个人说不清这件事。
    private var icon: some View {
        ZStack {
            runner(AppColors.Flow.accent)
                .offset(x: -iconDiameter * 0.18)
            runner(AppColors.Flow.navy)
                .offset(x: iconDiameter * 0.15)
        }
        .frame(width: iconDiameter, height: iconDiameter)
        .background(Color.white, in: Circle())
        .accessibilityHidden(true)
    }

    private func runner(_ color: Color) -> some View {
        Image(systemName: "figure.run")
            .font(.system(size: iconDiameter * 0.44, weight: .semibold))
            .foregroundColor(color)
    }

    private var iconDiameter: CGFloat {
        if verticalSizeClass == .compact { return FlowMetrics.bookingCompactIconDiameter }
        return isLargest ? FlowMetrics.bookingLargestIconDiameter : FlowMetrics.bookingProminentIconDiameter
    }
}

// MARK: - 卡片下方

struct BlindHomeBelowCardView: View {
    let content: BlindHomeBelowCard
    let onVerifyIdentity: () -> Void
    let onOpenRecords: () -> Void
    let onChangeStartPlace: () -> Void

    var body: some View {
        if content.showsIdentityRow {
            BlindHomeQuickRow(
                title: "完成实名认证",
                hint: "完成后才能预约陪跑",
                identifier: "blindHomeVerifyIdentityRow",
                action: onVerifyIdentity
            )
        }
        if let summary = content.runSummary {
            BlindHomeRunSummaryBlock(summary: summary, action: onOpenRecords)
        }
        if let title = content.startRowTitle {
            BlindHomeQuickRow(
                title: title,
                actionText: "更改",
                hint: "更改默认出发地点",
                identifier: "blindHomeStartPlaceRow",
                action: onChangeStartPlace
            )
        }
    }
}

/// 本月锻炼块。整块是一个按钮，按下去进「记录」。
struct BlindHomeRunSummaryBlock: View {
    let summary: BlindHomeRunSummary
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.period)
                        .flowFont(FlowFonts.bookingSubtitle())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary.headline)
                        .flowFont(FlowFonts.bookingTitle())
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    homeBlockActionText("查看记录")
                }
                homeBlockChevron
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, FlowMetrics.bookingBlockHorizontalPadding)
            .padding(.vertical, 14)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeRowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(summary.spokenText)
        .accessibilityHint("打开跑步记录")
        .accessibilityIdentifier("blindHomeRunSummary")
    }
}

/// 预约卡下方的一行入口。全宽，竖直堆叠，不并排。
struct BlindHomeQuickRow: View {
    let title: String
    var actionText: String?
    let hint: String
    let identifier: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .flowFont(FlowFonts.homeCardRowTitle())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    // 占满图标左侧的宽度。用 `Spacer` 顶开时，审计会把后面跟图标的字判成「可能被裁」。
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionText, !dynamicTypeSize.isAccessibilitySize {
                    homeBlockActionText(actionText)
                }
                homeBlockChevron
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, FlowMetrics.bookingBlockHorizontalPadding)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeRowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

private func homeBlockActionText(_ text: String) -> some View {
    Text(text)
        .flowFont(FlowFonts.bookingSubtitle())
        .foregroundColor(AppColors.Flow.accent)
        .accessibilityHidden(true)
}

private var homeBlockChevron: some View {
    Image(systemName: "chevron.right")
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(AppColors.Flow.secondaryText)
        .accessibilityHidden(true)
}
