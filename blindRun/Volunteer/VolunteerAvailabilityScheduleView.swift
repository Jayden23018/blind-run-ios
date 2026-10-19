import Combine
import SwiftUI

// MARK: - 时间段的编辑口径（纯函数）

/// 按周重复的空闲时间段，在「后端字符串」与「界面上的分钟数」之间来回。
///
/// 抽成纯类型的理由与 `VolunteerAvailabilitySlide` 一样：格式写错了界面照常能用
/// （Picker 转得动、行也画得出来），只是保存上去的是后端读不懂的串，而 `PUT` 成功返回 200。
/// 没有任何运行时信号。
enum VolunteerAvailabilityScheduleEditing {
    /// 后端 `VolunteerAvailableTimeSlot.dayOfWeek` 的取值，顺序即界面顺序。
    static let weekdays = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]

    /// `"19:30:00"` → `1170`（当天第几分钟）。认不出的取值返回 `nil`，**不回退到 0** ——
    /// 回退的后果是把一个解析失败的时段静默改成「00:00」，用户下次打开才发现。
    static func minutes(from raw: String?) -> Int? {
        let parts = (raw ?? "").split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]), (0..<24).contains(hour),
              let minute = Int(parts[1]), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// `1170` → `"19:30:00"`。契约的 example 就是 `14:30:00`，秒位必须带。
    static func raw(fromMinutes minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return String(format: "%02d:%02d:00", clamped / 60, clamped % 60)
    }

    /// 一个时段成不成立。
    ///
    /// 🔴 **结束必须晚于开始，不接受相等，也不接受跨午夜。**
    /// 跨午夜（22:00–02:00）在契约里无法表达——那是两天的两段，而后端只有 `dayOfWeek` 一个字段。
    /// 允许用户存一个 `22:00–02:00`，后端会把它当成一个长度为负的窗口，结果是这一段**永不命中**，
    /// 而志愿者看到的界面完全正常。
    static func isValid(startMinutes: Int, endMinutes: Int) -> Bool {
        startMinutes >= 0 && endMinutes <= 24 * 60 && endMinutes > startMinutes
    }

    static let invalidRangeMessage = "结束时间要晚于开始时间。跨午夜的时段请拆成两段。"

    /// 上屏用的日期串：以全角「）」结尾时补一个窄空格（U+202F）。
    ///
    /// 「仅 10月19日（周一）」这种以全角右括号收尾的字，真机整页审计（#466）在亮 / 暗、默认 / 最大字号下
    /// 全部报「放大字号可能被裁」，元素截图里「）」顶着框的右边；同屏不带括号的字（含折行的页脚）都过。
    /// 只改上屏的字，读屏标签与发给后端的值都不经过这里。
    static func displayText(_ text: String) -> String {
        text.hasSuffix("）") ? text + "\u{202F}" : text
    }

    /// 页脚那句匹配规则。后端（#410）：**一条每周时段都没有 = 随时可接**，一次性时段只放宽、
    /// 不算「填过」。所以只有存在每周时段时才能说「空闲时间以外不发邀请」；只填了按日期的、
    /// 或一段都没填时那句话是错的 —— 照它理解，他会以为别的日子收不到邀请（#455）。
    static func footerText(for slots: [VolunteerAvailabilityDraftSlot]) -> String {
        let rule = slots.contains { !$0.isOneOff }
            ? "空闲时间以外不会给你发邀请。"
            : "还没有每周重复的时段，任何时间都可能收到邀请；按日期添加的只是多加那一天。"
        return rule + "改完自动保存，没有保存按钮。"
    }

    // MARK: 一次性时段的日期（#455）

    /// 「按日期添加」能选几天：今天起 30 天（含今天）。
    ///
    /// ponytail: 契约与后端都没给上限（后端只校验星期对不对得上），这是 iOS 自己定的。
    /// 不取下单上限 7 天：更远那天的时段，等那天的订单进来时照样有用；
    /// 30 个选项读屏还划得完，再远的空闲用每周时段更合适。要改只改这一处。
    static let oneOffDateWindowDays = 30

    /// 日期加减与星期查表只用 UTC 公历：每天都是 24 小时，没有夏令时那一跳。
    /// 「今天」本身按本机时区取公历日（`VolunteerAvailableTimeSlot.todayString()`，与过期过滤同源），
    /// 一个日历日是星期几与时区无关。
    private static let dayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// `"2026-10-03"` → `"SATURDAY"`。认不出的日期（含 `2026-02-30`）返回 `nil`。
    static func weekday(forDate raw: String) -> String? {
        guard let date = dayDate(raw) else { return nil }
        // Calendar 的 weekday：1 = 周日 … 7 = 周六；`weekdays` 从周一开始。
        let index = dayCalendar.component(.weekday, from: date)
        return weekdays[(index + 5) % 7]
    }

    /// 从 `today` 起连续 `count` 天，第一个就是今天 —— **不含任何过去的日期**。
    static func selectableOneOffDates(today: String, count: Int = oneOffDateWindowDays) -> [String] {
        guard let start = dayDate(today) else { return [] }
        return (0..<max(count, 0)).compactMap { offset in
            dayCalendar.date(byAdding: .day, value: offset, to: start).map { dayString($0) }
        }
    }

    private static func dayDate(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: dayCalendar) else { return nil }
        return dayCalendar.date(from: components)
    }

    private static func dayString(_ date: Date) -> String {
        let parts = dayCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - 编辑中的一段

/// 界面上的一段。`id` 只用于 `ForEach`，不上传。
struct VolunteerAvailabilityDraftSlot: Identifiable, Equatable {
    let id = UUID()
    var weekday: String
    var startMinutes: Int
    var endMinutes: Int
    /// 一次性时段的日期（`yyyy-MM-dd`），`nil` = 每周重复。**必须原样带回去**（#353）：
    /// 丢了它，这一段保存后就变成每周重复。有日期时星期不许改 —— 两者对不上后端回 400。
    var date: String?

    var isOneOff: Bool { date != nil }

    var isValid: Bool {
        VolunteerAvailabilityScheduleEditing.isValid(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    /// 一次性时段的 `dayOfWeek` **在这里再由 `date` 推一次**，不只信 `weekday`：
    /// 两者对不上后端回 400（#455）。日期认不出时退回 `weekday`，让后端的 400 把错报出来。
    var payload: VolunteerAvailableTimeSlot {
        VolunteerAvailableTimeSlot(
            dayOfWeek: date.flatMap { VolunteerAvailabilityScheduleEditing.weekday(forDate: $0) } ?? weekday,
            startTime: VolunteerAvailabilityScheduleEditing.raw(fromMinutes: startMinutes),
            endTime: VolunteerAvailabilityScheduleEditing.raw(fromMinutes: endMinutes),
            date: date
        )
    }

    /// 后端那段读不出开始或结束时间时整段丢掉：显示一个「00:00 – 00:00」会让用户
    /// 以为自己设过这么一段，而**保存时它会被原样写回去**。
    init?(_ slot: VolunteerAvailableTimeSlot) {
        guard let weekday = slot.dayOfWeek?.uppercased(),
              VolunteerAvailabilityScheduleEditing.weekdays.contains(weekday),
              let start = VolunteerAvailabilityScheduleEditing.minutes(from: slot.startTime),
              let end = VolunteerAvailabilityScheduleEditing.minutes(from: slot.endTime)
        else { return nil }
        self.weekday = weekday
        self.startMinutes = start
        self.endMinutes = end
        self.date = slot.date?.nilIfBlank
    }

    init(weekday: String, startMinutes: Int, endMinutes: Int, date: String? = nil) {
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.date = date
    }

    /// 列表与编辑页上的「哪一天」：每周的说「周六」，一次性的说「仅 10月3日（周六）」。
    var dayText: String {
        let weekdayName = VolunteerAvailabilitySlotSummary.weekdayName(weekday) ?? weekday
        guard let date, let dateName = Self.dateLabel(date, weekday: weekday) else { return weekdayName }
        return "仅 \(dateName)"
    }

    /// 「10月3日（周六）」—— 列表行与编辑页的日期选项共用这一种说法。
    static func dateLabel(_ date: String, weekday: String?) -> String? {
        guard let dateName = VolunteerAvailabilitySlotSummary.dateName(date) else { return nil }
        guard let weekdayName = VolunteerAvailabilitySlotSummary.weekdayName(weekday) else { return dateName }
        return "\(dateName)（\(weekdayName)）"
    }

    /// 新增时编辑页**预选**的值：周六 07:00–09:00。取周末早晨是因为它是助盲跑最常见的时段
    /// （设计交付文档 v3 的草图与国内跑团调研都是这个时间）。
    /// 只是预选，点「完成」之前不落库 —— 原先一点「添加」就直接存成这一段，
    /// 真机反馈「只能添加一个固定的周六七点到九点」。
    static func makeDefault() -> Self {
        Self(weekday: "SATURDAY", startMinutes: 7 * 60, endMinutes: 9 * 60)
    }

    /// 「按日期添加」的预选值：今天 07:00–09:00，时间与每周那一档相同。
    static func makeOneOffDefault(today: String) -> Self {
        var slot = makeDefault()
        slot.setDate(today)
        return slot
    }

    /// 换日期时星期跟着换 —— 一次性时段的星期只从日期来，界面上没有别的入口改它。
    mutating func setDate(_ newDate: String) {
        date = newDate
        if let derived = VolunteerAvailabilityScheduleEditing.weekday(forDate: newDate) {
            weekday = derived
        }
    }
}

// MARK: - View Model

@MainActor
final class VolunteerAvailabilityScheduleViewModel: ObservableObject {
    @Published private(set) var slots: [VolunteerAvailabilityDraftSlot] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private weak var appState: AppState?

    private let today: () -> String

    init(today: @escaping () -> String = { VolunteerAvailableTimeSlot.todayString() }) {
        self.today = today
    }

    /// 过期的一次性时段不进列表（契约：后端不清理，客户端自己过滤），也就不会被下一次保存带回去。
    func configure(with appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState
        let today = self.today()
        slots = (appState.volunteerProfile?.availableTimeSlots ?? [])
            .filter { !$0.isExpired(today: today) }
            .compactMap(VolunteerAvailabilityDraftSlot.init)
    }

    /// 「按日期添加」的预选值与可选日期。「今天」与过期过滤同一来源，
    /// 所以可选的第一天永远不会被保存时那道过期过滤滤掉。
    func makeOneOffDraft() -> VolunteerAvailabilityDraftSlot {
        .makeOneOffDefault(today: today())
    }

    func selectableOneOffDates() -> [String] {
        VolunteerAvailabilityScheduleEditing.selectableOneOffDates(today: today())
    }

    func add(_ slot: VolunteerAvailabilityDraftSlot) {
        slots.append(slot)
        Task { await save() }
    }

    /// 编辑页「删除这一段」确认之后（#466 起取代左滑删除）。按 `id` 删，删完整体保存。
    func remove(id: VolunteerAvailabilityDraftSlot.ID) {
        slots.removeAll { $0.id == id }
        Task { await save() }
    }

    func update(_ slot: VolunteerAvailabilityDraftSlot) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[index] = slot
        Task { await save() }
    }

    /// 全量保存。**没有保存按钮**（设计交付文档 v3 §4.3：改完自动保存）。
    ///
    /// 🔴 **请求带上当前 profile 的全部字段，不是只带 `availableTimeSlots`。**
    /// 契约里 `PUT /api/volunteer/profile` **没有写**它是 PATCH 语义还是整体替换
    /// （同一份契约的 `EmergencyContactRequest` 是显式写了 PATCH 的，这条没写）⇒
    /// 只带一个字段在「整体替换」那种语义下会把昵称、导盲犬意愿、配速偏好一起清空，
    /// 而返回照样是 200。带全量在两种语义下都正确。已投 handoff 问清楚。
    func save() async {
        guard let appState else { return }
        let invalid = slots.first { !$0.isValid }
        guard invalid == nil else {
            errorMessage = VolunteerAvailabilityScheduleEditing.invalidRangeMessage
            return
        }

        isSaving = true
        errorMessage = nil
        let existing = appState.volunteerProfile
        // 页面开着跨过零点时，打开时还有效的一次性时段可能刚过期 —— 保存时再滤一次。
        let today = self.today()
        let request = VolunteerProfileUpdateRequest(
            name: existing?.name,
            availableTimeSlots: slots.map(\.payload).filter { !$0.isExpired(today: today) },
            acceptsGuideDog: existing?.acceptsGuideDog,
            paceRange: existing?.paceRange
        )
        do {
            let profile = try await appState.profile.updateVolunteerProfile(request)
            appState.updateVolunteerProfile(profile)
            isSaving = false
        } catch let error as APIError {
            isSaving = false
            if appState.handleAuthenticatedAPIError(error) { return }
            errorMessage = error.localizedMessage
        } catch {
            isSaving = false
            errorMessage = "保存失败，请检查网络后再试一次。"
        }
    }
}

// MARK: - 页面

/// 「我的 › 空闲时间」。设计交付文档 v3 的 S7，**只做时间段那一半**。
///
/// 🚩 **出发地 / 常用交通 / 愿意去多远不做，也不放占位。** 契约里这三个字段 0 命中，
/// 接单半径 `coverageRadiusKm` 是只读的平台固定值（`api_spec.yaml:7397`）。
/// 摆一个点不动的占位行，等于告诉志愿者「这里可以设，只是你还没设」——
/// 而他设不了。要不要加已投 handoff。
struct VolunteerAvailabilityScheduleView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerAvailabilityScheduleViewModel()
    @State private var editingSlot: VolunteerAvailabilityDraftSlot?
    /// 新增走同一个编辑页，点「完成」才加进列表；关掉就是没加。
    @State private var newSlot: VolunteerAvailabilityDraftSlot?

    /// 🔴 **常驻 `ScrollView` + 普通 `VStack`，不是 `List`**（#466，负责人 2026-10-19 拍板）。
    /// `List` 下半屏的元素（页脚、最后一枚添加行）在真机整页审计里被判「改不了字号」，
    /// 而最大字号截图里它们明明放大了 —— `List` 的已知误报（记忆 `list-rows-false-dynamic-type-audit`），
    /// 换成全部常驻的容器才转绿。代价是没有左滑删除：删除挪进编辑页的「删除这一段」。
    /// 别换回 `List` / `LazyVStack`。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // 系统组标题与页脚色是 `secondaryLabel`，压在分组底色上亮色只有 3.29:1，
                // 真机审计报「字再大一点才够」（#466）。`textSecondary` 亮 5.96:1 / 暗 9.5:1。
                Text("这些时间里有合适的陪跑，会邀请你")
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.slots) { slot in
                        slotRow(slot)
                        rowDivider
                    }

                    Button {
                        newSlot = .makeDefault()
                    } label: {
                        addRowLabel("添加空闲时间", systemImage: "plus")
                    }
                    .accessibilityHint("选择星期几和开始、结束时间，新增一段每周重复的空闲时间")
                    .accessibilityIdentifier("volunteerScheduleAddButton")
                    rowDivider

                    // 只放宽、不收紧（后端 #410）：加一段某天的时段不会让别的日子变成「不接」，
                    // 所以这里没有、也不做「这一天不空」。
                    Button {
                        newSlot = viewModel.makeOneOffDraft()
                    } label: {
                        addRowLabel("按日期添加", systemImage: "calendar")
                    }
                    .accessibilityHint("选一个具体日期和开始、结束时间，只在那一天有效")
                    .accessibilityIdentifier("volunteerScheduleAddOneOffButton")
                }
                .padding(.horizontal, 16)
                .background(AppColors.Flow.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // 「空闲时间以外不发邀请」是后端的匹配规则，写出来是因为它解释了
                // 「我为什么收不到单」——这一屏最可能被打开的原因。
                Text(VolunteerAvailabilityScheduleEditing.footerText(for: viewModel.slots))
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(AppColors.Flow.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 16)
                        .accessibilityIdentifier("volunteerScheduleErrorMessage")
                }
            }
            .padding(16)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle("空闲时间")
        .navigationBarTitleDisplayMode(.inline)
        // 设计交付 v3 §4.2 总表：S7「空闲时间与出发地」的底部是空的，只有 S1–S4 那几屏
        // 根页面带标签栏。二级页不带栏还顺带避开一类真实缺陷 —— 见
        // `VolunteerServiceRecognitionView` 上那段（那一页的末行曾被标签栏盖掉半行）。
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isSaving {
                    ProgressView()
                        .accessibilityLabel("正在保存")
                }
            }
        }
        .onAppear { viewModel.configure(with: appState) }
        .sheet(item: $editingSlot) { slot in
            NavigationStack {
                VolunteerAvailabilitySlotEditor(
                    slot: slot,
                    onCancel: { editingSlot = nil },
                    deletion: .init(summary: announcement(slot)) {
                        viewModel.remove(id: slot.id)
                        editingSlot = nil
                    }
                ) { updated in
                    viewModel.update(updated)
                    editingSlot = nil
                }
            }
        }
        .sheet(item: $newSlot) { slot in
            NavigationStack {
                // 新增的一次性时段给日期选择；编辑已有的那一段仍是只读日期行（#357），
                // 要换日期就删掉重加。
                VolunteerAvailabilitySlotEditor(
                    slot: slot,
                    title: slot.isOneOff ? "按日期添加" : "添加空闲时段",
                    dateOptions: slot.isOneOff ? viewModel.selectableOneOffDates() : nil,
                    onCancel: { newSlot = nil }
                ) { added in
                    viewModel.add(added)
                    newSlot = nil
                }
            }
        }
    }

    private func slotRow(_ slot: VolunteerAvailabilityDraftSlot) -> some View {
        Button {
            editingSlot = slot
        } label: {
            HStack {
                Text(VolunteerAvailabilityScheduleEditing.displayText(slot.dayText))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(rangeText(slot))
                    .font(AppFonts.body().monospacedDigit())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 64) // guard:allow small-touch-target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(announcement(slot))
        .accessibilityHint("双击修改或删除这一段")
        .accessibilityIdentifier("volunteerScheduleSlotRow")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(AppColors.Flow.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// 两枚「添加」行的内容。不用 `Label`：`List` 里的 `Label` 被真机审计判
    /// 「放大字号可能被裁」（两枚都报），换成普通 `HStack` + 可折行的 `Text`（#466）。
    private func addRowLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFonts.body())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading) // guard:allow small-touch-target
        .contentShape(Rectangle())
    }

    private func rangeText(_ slot: VolunteerAvailabilityDraftSlot) -> String {
        let start = VolunteerAvailabilityScheduleEditing.raw(fromMinutes: slot.startMinutes)
        let end = VolunteerAvailabilityScheduleEditing.raw(fromMinutes: slot.endMinutes)
        return "\(VolunteerAvailabilitySlotSummary.clock(start) ?? "") – \(VolunteerAvailabilitySlotSummary.clock(end) ?? "")"
    }

    private func announcement(_ slot: VolunteerAvailabilityDraftSlot) -> String {
        "\(slot.dayText)，\(rangeText(slot))"
    }
}

// MARK: - 单段编辑

private struct VolunteerAvailabilitySlotEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: VolunteerAvailabilityDraftSlot
    private let title: String
    /// 非 nil = 新增一次性时段，日期可选；nil 时一次性时段的日期只读。
    private let dateOptions: [String]?
    private let onCancel: () -> Void
    /// 非 nil = 编辑已有的一段，底部出「删除这一段」；新增时为 nil，不出删除。
    private let deletion: Deletion?
    private let onDone: (VolunteerAvailabilityDraftSlot) -> Void
    @State private var confirmsDeletion = false
    @State private var showsDateList = false

    /// 「删除这一段」（#466 起取代左滑删除）。标签取**打开编辑页时**那一段 ——
    /// 删的是保存过的那段，不是编辑中的草稿。
    struct Deletion {
        /// 「周六，07:00 – 09:00」—— 与列表那一行的读屏标签同一说法。
        let summary: String
        let perform: () -> Void
    }

    init(
        slot: VolunteerAvailabilityDraftSlot,
        title: String = "空闲时段",
        dateOptions: [String]? = nil,
        onCancel: @escaping () -> Void,
        deletion: Deletion? = nil,
        onDone: @escaping (VolunteerAvailabilityDraftSlot) -> Void
    ) {
        // 预选日期与可选列表是两次取的「今天」，跨零点时预选那天可能已不在列表里 ——
        // 不对齐的话选择器显示空白，而点「完成」存下的那天会被保存时的过期过滤静默丢掉。
        var initial = slot
        if let first = dateOptions?.first, let date = slot.date, dateOptions?.contains(date) == false {
            initial.setDate(first)
        }
        _draft = State(initialValue: initial)
        self.title = title
        self.dateOptions = dateOptions
        self.onCancel = onCancel
        self.deletion = deletion
        self.onDone = onDone
    }

    var body: some View {
        Form {
            if draft.isOneOff, let dateOptions, !dateOptions.isEmpty {
                datePicker(dateOptions)
            } else if draft.isOneOff {
                // 一次性时段的星期由日期决定，改了就和日期对不上（后端 400）。只读一行。
                // 不用 `LabeledContent`：它的值是系统 `secondaryLabel`，与上面日期一行是同一个对比度问题（#466）。
                dateRowContent(draft.dayText)
                    .accessibilityElement(children: .combine)
            } else {
                Picker("星期", selection: $draft.weekday) {
                    ForEach(VolunteerAvailabilityScheduleEditing.weekdays, id: \.self) { day in
                        Text(VolunteerAvailabilitySlotSummary.weekdayName(day) ?? day).tag(day)
                    }
                }
            }
            minutePicker("开始", minutes: $draft.startMinutes)
            minutePicker("结束", minutes: $draft.endMinutes)

            if !draft.isValid {
                Text(VolunteerAvailabilityScheduleEditing.invalidRangeMessage)
                    .foregroundColor(AppColors.destructive)
                    .accessibilityIdentifier("volunteerScheduleEditorRangeError")
            }

            if let deletion {
                Section {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Text("删除这一段")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 64) // guard:allow small-touch-target
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("删除 \(deletion.summary)")
                    .accessibilityHint("删除前会再确认一次")
                    .accessibilityIdentifier("volunteerScheduleEditorDelete")
                }
            }
        }
        // 与删除紧急联系人同一种确认（`EmergencyContactsView`）：标题、「确认删除」、「取消」、一句说明。
        .alert("确认删除这一段", isPresented: $confirmsDeletion) {
            Button("确认删除", role: .destructive) { deletion?.perform() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(deletion?.summary ?? "")」这一段空闲时间，并立即保存。需要时可以重新添加。")
        }
        // 挂在 `Form` 上而不是那一行上：`navigationDestination` 放进懒加载容器的行里不可靠。
        .navigationDestination(isPresented: $showsDateList) {
            if let dateOptions, let first = dateOptions.first {
                VolunteerAvailabilityDateList(options: dateOptions, selected: draft.date ?? first) { draft.setDate($0) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 显式的取消：下滑关 sheet 对读屏用户不可发现。
            // 叉 / 勾图标而不是文字（#466）：导航栏里的文字按钮不随 Dynamic Type 放大，
            // 真机审计两枚都判「改不了字号」+ 对比度不过。图标是 iOS 26 起表单页的系统写法，
            // 读屏照念「取消」「完成」，长按出系统的大字预览。
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark")
                }
                .accessibilityIdentifier("volunteerScheduleEditorCancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { onDone(draft) } label: {
                    Label("完成", systemImage: "checkmark")
                }
                // 非法区间不许保存：`isValid` 为假时后端会收到一个永不命中的窗口，
                // 而它返回 200，用户不会知道。
                .disabled(!draft.isValid)
                .accessibilityIdentifier("volunteerScheduleEditorDone")
            }
        }
    }

    /// 一次性时段的日期选择：今天起固定天数，**没有过去的日期**；星期随日期一起换。
    ///
    /// ponytail: 列日期串而不是 `DatePicker`，理由同下面的时间选择 ——
    /// 不在 `Date` 与「哪一天」之间换算；读屏下是一行按钮，双击推出一页日期列表逐行可念可选。
    /// 紧凑 `DatePicker` 在 `Form` 里是一枚远小于 64pt 的胶囊。
    ///
    /// 不用 `Picker(.navigationLink)`（#466）：它把选中值画成系统 `secondaryLabel`，压白底约 3.4:1，
    /// 真机审计报「日期」一行对比度不够，而 `Picker` 改不了值的颜色。自己写这一行，值用 `textSecondary`。
    /// 菜单样式（`Form` 默认）也不行：真机量过可点的那颗按钮只有 34pt。
    ///
    /// 也不用 `NavigationLink`：`Form` 里它的标签文字被真机审计判「放大字号可能被裁」，换成竖排照样报；
    /// 普通按钮 + `navigationDestination` 推同一页就过了。箭头自己画。
    private func datePicker(_ options: [String]) -> some View {
        let selected = draft.date ?? options[0]
        return Button {
            showsDateList = true
        } label: {
            HStack(spacing: 8) {
                dateRowContent(Self.dateOptionText(selected))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("双击换一天")
        .accessibilityIdentifier("volunteerScheduleEditorDatePicker")
    }

    /// 「日期」+ 值的一行。最大字号下左右放不下，改成上下两行；两段字都能折行（真机审计报过「可能被裁」）。
    private func dateRowContent(_ value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        return layout {
            Text("日期")
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(VolunteerAvailabilityScheduleEditing.displayText(value))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 64) // guard:allow small-touch-target
    }

    /// `"2026-10-03"` →「10月3日（周六）」，与列表的「仅 10月3日（周六）」同一口径。
    static func dateOptionText(_ day: String) -> String {
        VolunteerAvailabilityDraftSlot.dateLabel(day, weekday: VolunteerAvailabilityScheduleEditing.weekday(forDate: day)) ?? day
    }

    /// 15 分钟一档的时间选择。
    ///
    /// ponytail: 用 `Picker` 而不是 `DatePicker(displayedComponents: .hourAndMinute)` ——
    /// 后者要在 `Date` 与「当天第几分钟」之间来回换算，而这一屏根本没有日期这个概念，
    /// 换算处正是跨时区、跨夏令时会出事的地方。96 个选项对 VoiceOver 也比转轮好走。
    private func minutePicker(_ title: String, minutes: Binding<Int>) -> some View {
        Picker(title, selection: minutes) {
            ForEach(Array(stride(from: 0, to: 24 * 60, by: 15)), id: \.self) { value in
                Text(VolunteerAvailabilitySlotSummary.clock(
                    VolunteerAvailabilityScheduleEditing.raw(fromMinutes: value)
                ) ?? "")
                .tag(value)
            }
        }
    }
}

// MARK: - 一次性时段的日期列表

/// 「日期」一行推出来的那一页：逐行一个日期，选中的那行带勾，点一下就回编辑页。
/// 与原先 `Picker(.navigationLink)` 推出来的页面同一种行为（#466 换掉的只是编辑页那一行的颜色）。
private struct VolunteerAvailabilityDateList: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(options, id: \.self) { day in
            Button {
                onSelect(day)
                dismiss()
            } label: {
                HStack {
                    Text(VolunteerAvailabilitySlotEditor.dateOptionText(day))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 8)
                    if day == selected {
                        Image(systemName: "checkmark")
                            .foregroundColor(AppColors.primary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 64) // guard:allow small-touch-target
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(day == selected ? .isSelected : [])
        }
        .navigationTitle("日期")
        .navigationBarTitleDisplayMode(.inline)
    }
}
