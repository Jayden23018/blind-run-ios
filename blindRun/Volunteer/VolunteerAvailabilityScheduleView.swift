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
}

// MARK: - 编辑中的一段

/// 界面上的一段。`id` 只用于 `ForEach`，不上传。
struct VolunteerAvailabilityDraftSlot: Identifiable, Equatable {
    let id = UUID()
    var weekday: String
    var startMinutes: Int
    var endMinutes: Int

    var isValid: Bool {
        VolunteerAvailabilityScheduleEditing.isValid(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    var payload: VolunteerAvailableTimeSlot {
        VolunteerAvailableTimeSlot(
            dayOfWeek: weekday,
            startTime: VolunteerAvailabilityScheduleEditing.raw(fromMinutes: startMinutes),
            endTime: VolunteerAvailabilityScheduleEditing.raw(fromMinutes: endMinutes)
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
    }

    init(weekday: String, startMinutes: Int, endMinutes: Int) {
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    /// 新增时编辑页**预选**的值：周六 07:00–09:00。取周末早晨是因为它是助盲跑最常见的时段
    /// （设计交付文档 v3 的草图与国内跑团调研都是这个时间）。
    /// 只是预选，点「完成」之前不落库 —— 原先一点「添加」就直接存成这一段，
    /// 真机反馈「只能添加一个固定的周六七点到九点」。
    static func makeDefault() -> Self {
        Self(weekday: "SATURDAY", startMinutes: 7 * 60, endMinutes: 9 * 60)
    }
}

// MARK: - View Model

@MainActor
final class VolunteerAvailabilityScheduleViewModel: ObservableObject {
    @Published private(set) var slots: [VolunteerAvailabilityDraftSlot] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private weak var appState: AppState?

    func configure(with appState: AppState) {
        guard self.appState !== appState else { return }
        self.appState = appState
        slots = (appState.volunteerProfile?.availableTimeSlots ?? []).compactMap(VolunteerAvailabilityDraftSlot.init)
    }

    func add(_ slot: VolunteerAvailabilityDraftSlot) {
        slots.append(slot)
        Task { await save() }
    }

    func remove(at offsets: IndexSet) {
        slots.remove(atOffsets: offsets)
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
        let request = VolunteerProfileUpdateRequest(
            name: existing?.name,
            availableTimeSlots: slots.map(\.payload),
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

    var body: some View {
        List {
            Section {
                ForEach(viewModel.slots) { slot in
                    Button {
                        editingSlot = slot
                    } label: {
                        HStack {
                            Text(VolunteerAvailabilitySlotSummary.weekdayName(slot.weekday) ?? slot.weekday)
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text(rangeText(slot))
                                .font(AppFonts.body().monospacedDigit())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(minHeight: 64) // guard:allow small-touch-target
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(announcement(slot))
                    .accessibilityHint("双击修改这一段")
                }
                .onDelete(perform: viewModel.remove)

                Button {
                    newSlot = .makeDefault()
                } label: {
                    Label("添加空闲时间", systemImage: "plus")
                        .frame(minHeight: 64) // guard:allow small-touch-target
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityHint("选择星期几和开始、结束时间，新增一段每周重复的空闲时间")
                .accessibilityIdentifier("volunteerScheduleAddButton")
            } header: {
                Text("这些时间里有合适的陪跑，会邀请你")
            } footer: {
                // 「空闲时间以外不发邀请」是后端的匹配规则，写出来是因为它解释了
                // 「我为什么收不到单」——这一屏最可能被打开的原因。
                Text("空闲时间以外不会给你发邀请。改完自动保存，没有保存按钮。")
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityIdentifier("volunteerScheduleErrorMessage")
                }
            }
        }
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
                VolunteerAvailabilitySlotEditor(slot: slot, onCancel: { editingSlot = nil }) { updated in
                    viewModel.update(updated)
                    editingSlot = nil
                }
            }
        }
        .sheet(item: $newSlot) { slot in
            NavigationStack {
                VolunteerAvailabilitySlotEditor(slot: slot, title: "添加空闲时段", onCancel: { newSlot = nil }) { added in
                    viewModel.add(added)
                    newSlot = nil
                }
            }
        }
    }

    private func rangeText(_ slot: VolunteerAvailabilityDraftSlot) -> String {
        let start = VolunteerAvailabilityScheduleEditing.raw(fromMinutes: slot.startMinutes)
        let end = VolunteerAvailabilityScheduleEditing.raw(fromMinutes: slot.endMinutes)
        return "\(VolunteerAvailabilitySlotSummary.clock(start) ?? "") – \(VolunteerAvailabilitySlotSummary.clock(end) ?? "")"
    }

    private func announcement(_ slot: VolunteerAvailabilityDraftSlot) -> String {
        let day = VolunteerAvailabilitySlotSummary.weekdayName(slot.weekday) ?? slot.weekday
        return "\(day)，\(rangeText(slot))"
    }
}

// MARK: - 单段编辑

private struct VolunteerAvailabilitySlotEditor: View {
    @State private var draft: VolunteerAvailabilityDraftSlot
    private let title: String
    private let onCancel: () -> Void
    private let onDone: (VolunteerAvailabilityDraftSlot) -> Void

    init(
        slot: VolunteerAvailabilityDraftSlot,
        title: String = "空闲时段",
        onCancel: @escaping () -> Void,
        onDone: @escaping (VolunteerAvailabilityDraftSlot) -> Void
    ) {
        _draft = State(initialValue: slot)
        self.title = title
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Picker("星期", selection: $draft.weekday) {
                ForEach(VolunteerAvailabilityScheduleEditing.weekdays, id: \.self) { day in
                    Text(VolunteerAvailabilitySlotSummary.weekdayName(day) ?? day).tag(day)
                }
            }
            minutePicker("开始", minutes: $draft.startMinutes)
            minutePicker("结束", minutes: $draft.endMinutes)

            if !draft.isValid {
                Text(VolunteerAvailabilityScheduleEditing.invalidRangeMessage)
                    .foregroundColor(AppColors.destructive)
                    .accessibilityIdentifier("volunteerScheduleEditorRangeError")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 显式的取消：下滑关 sheet 对读屏用户不可发现。
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onCancel)
                    .accessibilityIdentifier("volunteerScheduleEditorCancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { onDone(draft) }
                    // 非法区间不许保存：`isValid` 为假时后端会收到一个永不命中的窗口，
                    // 而它返回 200，用户不会知道。
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("volunteerScheduleEditorDone")
            }
        }
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
