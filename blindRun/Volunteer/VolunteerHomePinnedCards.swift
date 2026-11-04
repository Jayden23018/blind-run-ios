import Combine
import SwiftUI

// 陪跑员首页「置顶 · 编辑」（负责人 2026-11-04 看真机截图后要求，选了「选卡片 + 拖动排序」；#694）。
//
// 只存在本机（`AppConstants.UserDefaultsKeys.volunteerHomePinnedCards`），不上后端。
// 首页怎么按它渲染在 `VolunteerProfileFirstScreenView+Pinned.swift`。

// MARK: - 卡片种类

/// 首页能置顶的五张卡。**声明顺序就是默认顺序**（= 设计稿 v3 的顺序）。
enum VolunteerHomeCardKind: String, CaseIterable, Identifiable {
    case duration
    case streak
    case rating
    case recentRun
    case badges

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duration: return VolunteerProfileCopy.durationCardTitle
        case .streak: return VolunteerProfileCopy.streakCardTitle
        case .rating: return VolunteerProfileCopy.ratingCaption
        case .recentRun: return VolunteerProfileCopy.recentSectionTitle
        case .badges: return VolunteerProfileCopy.badgesSectionTitle
        }
    }

    var symbol: String {
        switch self {
        case .duration: return "clock"
        case .streak: return "flame.fill"
        case .rating: return "star.fill"
        case .recentRun: return "figure.run"
        case .badges: return "rosette"
        }
    }

    /// 要等成就接口（`GET /api/volunteer/achievements`）才画得出来的卡。最近陪跑走跑后记录接口，不算。
    var needsAchievements: Bool { self != .recentRun }
}

// MARK: - 编码、分段、排序（纯函数）

/// 置顶设置怎么存、怎么读、首页怎么分段。抽成纯函数：这几处出错时首页仍是一页排版正常的卡片，
/// 只是少了一张或多了一张 —— 没有运行时信号，只能靠单测钉住。
enum VolunteerHomePinnedLayout {
    static let defaultOrder = VolunteerHomeCardKind.allCases

    /// 首页上的一段：单张卡，或连续陪跑与评分并排的一对半宽卡。
    enum Segment: Equatable, Identifiable {
        case single(VolunteerHomeCardKind)
        case pair(VolunteerHomeCardKind, VolunteerHomeCardKind)

        var id: String {
            switch self {
            case .single(let kind): return kind.rawValue
            case .pair(let first, let second): return "\(first.rawValue)+\(second.rawValue)"
            }
        }

        var kinds: [VolunteerHomeCardKind] {
            switch self {
            case .single(let kind): return [kind]
            case .pair(let first, let second): return [first, second]
            }
        }
    }

    /// - `nil`（从没编辑过）⇒ 默认五张全部置顶。
    /// - 空串 ⇒ 一张都不置顶（这是志愿者自己选的，不能当成「没存过」又全放回来）。
    /// - 认不出的卡名丢掉、重复的只留第一个：版本降级或手改过的值不让整块消失。
    static func decode(_ raw: String?) -> [VolunteerHomeCardKind] {
        guard let raw else { return defaultOrder }
        var seen = Set<VolunteerHomeCardKind>()
        return raw.split(separator: ",").compactMap { part in
            guard let kind = VolunteerHomeCardKind(rawValue: part.trimmingCharacters(in: .whitespaces)),
                  seen.insert(kind).inserted else { return nil }
            return kind
        }
    }

    static func encode(_ kinds: [VolunteerHomeCardKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }

    /// 连续陪跑与评分**相邻**时并排成一对半宽卡（谁在前谁在左），否则各占一行。
    static func segments(_ kinds: [VolunteerHomeCardKind]) -> [Segment] {
        var result: [Segment] = []
        var index = 0
        while index < kinds.count {
            let kind = kinds[index]
            let next = index + 1 < kinds.count ? kinds[index + 1] : nil
            if let next, Set([kind, next]) == Set([.streak, .rating]) {
                result.append(.pair(kind, next))
                index += 2
            } else {
                result.append(.single(kind))
                index += 1
            }
        }
        return result
    }

    /// 读屏的「上移 / 下移」。到头了原样返回。
    static func move(_ kind: VolunteerHomeCardKind, by offset: Int, in kinds: [VolunteerHomeCardKind]) -> [VolunteerHomeCardKind] {
        guard let from = kinds.firstIndex(of: kind) else { return kinds }
        let to = from + offset
        guard kinds.indices.contains(to) else { return kinds }
        var moved = kinds
        moved.swapAt(from, to)
        return moved
    }
}

// MARK: - 存储

/// 首页与编辑页共用的一份置顶设置。
///
/// 🚩 **存在 `appState.persistence`，不用 `@AppStorage`。** UI 测试跑在独立的存储域里、
/// 每次启动整域清空（`AppStatePersistenceFactory`）；`@AppStorage` 写的是标准域，
/// 一条用例改过的置顶会漏到下一条用例里。
@MainActor
final class VolunteerHomePinnedStore: ObservableObject {
    @Published private(set) var pinned: [VolunteerHomeCardKind] = VolunteerHomePinnedLayout.defaultOrder
    private var persistence: AppStatePersistence?

    var unpinned: [VolunteerHomeCardKind] {
        VolunteerHomeCardKind.allCases.filter { !pinned.contains($0) }
    }

    func configure(persistence: AppStatePersistence) {
        guard self.persistence == nil else { return }
        self.persistence = persistence
        pinned = VolunteerHomePinnedLayout.decode(
            persistence.string(forKey: AppConstants.UserDefaultsKeys.volunteerHomePinnedCards)
        )
    }

    func pin(_ kind: VolunteerHomeCardKind) {
        guard !pinned.contains(kind) else { return }
        save(pinned + [kind])
    }

    func unpin(_ kind: VolunteerHomeCardKind) {
        save(pinned.filter { $0 != kind })
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var moved = pinned
        moved.move(fromOffsets: source, toOffset: destination)
        save(moved)
    }

    func move(_ kind: VolunteerHomeCardKind, by offset: Int) {
        save(VolunteerHomePinnedLayout.move(kind, by: offset, in: pinned))
    }

    private func save(_ kinds: [VolunteerHomeCardKind]) {
        pinned = kinds
        persistence?.set(VolunteerHomePinnedLayout.encode(kinds), forKey: AppConstants.UserDefaultsKeys.volunteerHomePinnedCards)
    }
}

// MARK: - 编辑页

/// 「编辑置顶」：上面一组是置顶的卡（拖动右侧把手排序，左侧红色减号移出），
/// 下面一组是没置顶的卡（左侧绿色加号加入）。照健康 App「编辑置顶」的形状。
///
/// 读屏用户拖不了把手：置顶行带「上移」「下移」两个自定义动作。
/// 加 / 减号用 `.borderless` 按钮：编辑态的 `List` 里，默认样式的按钮会和整行的点按抢事件。
struct VolunteerHomePinnedEditView: View {
    @ObservedObject var store: VolunteerHomePinnedStore

    var body: some View {
        List {
            Section {
                if store.pinned.isEmpty {
                    Text(VolunteerProfileCopy.pinnedEditEmpty)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.pinned) { kind in
                    row(kind, isPinned: true)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                sectionText(VolunteerProfileCopy.pinnedSectionTitle)
            } footer: {
                sectionText(VolunteerProfileCopy.pinnedEditFooter)
            }

            if !store.unpinned.isEmpty {
                Section {
                    ForEach(store.unpinned) { kind in
                        row(kind, isPinned: false)
                    }
                } header: {
                    sectionText(VolunteerProfileCopy.pinnedEditOthersTitle)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(VolunteerProfileCopy.pinnedEditNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("volunteerHomePinnedEditView")
    }

    /// 分区标题与脚注。系统默认的 `secondaryLabel` 灰压在分组底色上不到 4.5:1（真机审计报 Contrast nearly passed），
    /// 改用 `AppColors.textSecondary`。
    private func sectionText(_ text: String) -> some View {
        Text(text)
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ kind: VolunteerHomeCardKind, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                if isPinned { store.unpin(kind) } else { store.pin(kind) }
            } label: {
                Image(systemName: isPinned ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(isPinned ? AppColors.destructive : AppColors.success)
                    // 44pt 是系统触达下限（志愿者端不受盲人端 64pt 线约束）。
                    .frame(minWidth: 44, minHeight: 44)  // guard:allow small-touch-target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPinned
                ? VolunteerProfileCopy.pinnedRemoveLabel(kind.title)
                : VolunteerProfileCopy.pinnedAddLabel(kind.title))
            .accessibilityIdentifier(isPinned ? "volunteerHomePinnedRemove.\(kind.rawValue)" : "volunteerHomePinnedAdd.\(kind.rawValue)")

            // 不用 `Label`：编辑态 `List` 里它给文字的宽度只够两个字，AX5 下「陪伴时长」被折成「陪伴 / 时长」，
            // 审计报「改不了字号」「文字被裁」（2026-11-04 真机）。图标与文字分开排，文字占满余下宽度。
            Image(systemName: kind.symbol)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityHidden(true)
            Text(kind.title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if isPinned {
                Button(VolunteerProfileCopy.pinnedMoveUp) { store.move(kind, by: -1) }
                Button(VolunteerProfileCopy.pinnedMoveDown) { store.move(kind, by: 1) }
            }
        }
    }
}
