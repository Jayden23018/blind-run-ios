import CoreLocation
import SwiftUI
import UIKit

// MARK: - V2 填写见面安排（#433）
//
// 视觉稿 v2「② 陪跑员端」V2：整页可滚动，从上到下 开跑时间 → 集合地点 → 具体见面位置 → 本人上衣 → 跑者上衣 → 固定提醒，
// 底部一枚主按钮。陪跑员是明眼人、单手操作：主路径做到「一个字不改，点一下就能提交」。
// 判定都在 `VolunteerMeetupPlanDraft`，这里只负责画与收集输入。

/// 提交的结果。表单据此决定关不关自己。
enum VolunteerMeetupPlanSubmitOutcome: Equatable {
    case submitted
    /// 后端拒绝：表单留着、已填内容保留，错误显示在对应那一块下面。
    case failed(VolunteerMeetupPlanSubmitError)
    /// 这一轮已经结束（或登录失效）：没有可改的了，关掉表单，通话页自己会切到结局。
    case roundEnded
}

struct VolunteerMeetupPlanFormView: View {
    let windowEndsAt: Date?
    let onSubmit: (IntroCallPlanRequest, Double?) async -> VolunteerMeetupPlanSubmitOutcome

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VolunteerMeetupPlanDraft
    @State private var isEditingTime = false
    @State private var showsPlaceSearch = false
    @State private var submitError: VolunteerMeetupPlanSubmitError?
    @State private var isSubmitting = false

    init(
        original: IntroCallOriginalArrangement,
        editing plan: IntroCallMeetupPlan?,
        windowEndsAt: Date?,
        onSubmit: @escaping (IntroCallPlanRequest, Double?) async -> VolunteerMeetupPlanSubmitOutcome
    ) {
        self.windowEndsAt = windowEndsAt
        self.onSubmit = onSubmit
        _draft = State(initialValue: VolunteerMeetupPlanDraft(original: original, editing: plan))
    }

    private var timeError: String? {
        draft.timeError(now: Date(), windowEndsAt: windowEndsAt) ?? (submitError?.slot == .time ? submitError?.message : nil)
    }

    private var placeError: String? {
        draft.placeError ?? (submitError?.slot == .place ? submitError?.message : nil)
    }

    /// 本地校验没过时主按钮置灰（走 `.disabled`，读屏念「变暗」）—— 错误已经写在对应那一块下面了。
    private var canSubmit: Bool {
        !isSubmitting && draft.timeError(now: Date(), windowEndsAt: windowEndsAt) == nil && draft.placeError == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FlowMetrics.v2SectionGap) {
                    Text(VolunteerMeetupPlanCopy.intro)
                        .flowFont(FlowV2Fonts.callout())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if submitError?.slot == .general, let message = submitError?.message {
                        errorText(message)
                            .accessibilityIdentifier("volunteerMeetupPlanGeneralError")
                    }

                    timeCard
                    placeCard
                    meetSpotCard
                    colorCard(
                        title: VolunteerMeetupPlanCopy.volunteerColorLabel,
                        selection: $draft.volunteerTopColor
                    )
                    colorCard(
                        title: VolunteerMeetupPlanCopy.runnerColorLabel,
                        selection: $draft.runnerTopColor
                    )

                    Text(VolunteerMeetupPlanCopy.greetingReminder)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, FlowMetrics.v2ScreenPadding)
                .padding(.vertical, FlowMetrics.v2SectionGap)
                .readableContentColumn()
            }
            .background(AppColors.Flow.page.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { submitBar }
            .navigationTitle(VolunteerMeetupPlanCopy.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VolunteerMeetupPlanCopy.cancel) { dismiss() }
                        .accessibilityIdentifier("volunteerMeetupPlanCancelButton")
                }
            }
            .navigationDestination(isPresented: $showsPlaceSearch) {
                VolunteerMeetupPlaceSearchView(
                    near: draft.original.startLatitude.flatMap { lat in
                        draft.original.startLongitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
                    }
                ) { place in
                    draft.place = place
                    clearSubmitError(.place)
                    showsPlaceSearch = false
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .accessibilityIdentifier("volunteerMeetupPlanForm")
    }

    // MARK: 开跑时间

    private var timeCard: some View {
        sectionCard {
            sectionHeader(VolunteerMeetupPlanCopy.timeLabel, changed: draft.timeChanged)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(timeValue)
                    .flowFont(FlowV2Fonts.headline())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                editButton(accessibilityLabel: "修改开跑时间") {
                    if !isEditingTime, draft.plannedStart == nil {
                        // 第一次展开：从原约（或已过时的原约之后的最早一档）开始，不让选择器停在一个选不了的值上。
                        let earliest = VolunteerMeetupPlanDraft.earliestStart(now: Date(), windowEndsAt: windowEndsAt)
                        let base = draft.original.plannedStartTime.map { VolunteerMeetupPlanDraft.roundedUp($0) } ?? earliest
                        draft.plannedStart = max(base, earliest)
                    }
                    isEditingTime.toggle()
                }
                .accessibilityIdentifier("volunteerMeetupPlanEditTimeButton")
            }
            .accessibilityElement(children: .contain)
            if draft.timeChanged, let line = VolunteerMeetupPlanCopy.originalTimeLine(
                start: draft.original.plannedStartTime, end: draft.original.plannedEndTime
            ) {
                detailText(line)
            }
            if isEditingTime {
                MinuteIntervalDatePicker(
                    date: Binding(
                        get: { draft.plannedStart ?? VolunteerMeetupPlanDraft.earliestStart(now: Date(), windowEndsAt: windowEndsAt) },
                        set: { draft.plannedStart = $0; clearSubmitError(.time) }
                    ),
                    minimumDate: VolunteerMeetupPlanDraft.earliestStart(now: Date(), windowEndsAt: windowEndsAt),
                    maximumDate: VolunteerMeetupPlanDraft.latestStart(now: Date())
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("volunteerMeetupPlanTimePicker")
                if draft.timeChanged {
                    FlowTextButton(title: VolunteerMeetupPlanCopy.restoreTimeButton, tone: .link) {
                        draft.plannedStart = nil
                        isEditingTime = false
                        clearSubmitError(.time)
                    }
                }
            }
            if let timeError {
                errorText(timeError)
                    .accessibilityIdentifier("volunteerMeetupPlanTimeError")
            }
        }
    }

    private var timeValue: String {
        guard let start = draft.effectiveStart else { return "按原约定" }
        return VolunteerMeetupPlanCopy.timeRange(start: start, end: draft.effectiveEnd, now: Date())
    }

    // MARK: 集合地点

    private var placeCard: some View {
        sectionCard {
            sectionHeader(VolunteerMeetupPlanCopy.placeLabel, changed: draft.placeChanged)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(draft.effectiveAddress ?? "按原约定")
                    .flowFont(FlowV2Fonts.headline())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                editButton(accessibilityLabel: "修改集合地点") {
                    showsPlaceSearch = true
                }
                .accessibilityIdentifier("volunteerMeetupPlanEditPlaceButton")
            }
            .accessibilityElement(children: .contain)
            if draft.placeChanged, let line = VolunteerMeetupPlanCopy.originalPlaceLine(
                address: draft.original.startAddress, distance: draft.distanceFromOriginal
            ) {
                detailText(line)
            }
            if draft.placeChanged {
                FlowTextButton(title: VolunteerMeetupPlanCopy.restorePlaceButton, tone: .link) {
                    draft.place = nil
                    clearSubmitError(.place)
                }
            }
            if let placeError {
                errorText(placeError)
                    .accessibilityIdentifier("volunteerMeetupPlanPlaceError")
            }
        }
    }

    // MARK: 具体见面位置

    private var meetSpotCard: some View {
        sectionCard {
            sectionHeader(VolunteerMeetupPlanCopy.meetSpotLabel, changed: false)
            HStack(spacing: 8) {
                TextField(VolunteerMeetupPlanCopy.meetSpotPlaceholder, text: Binding(
                    get: { draft.meetSpotNote },
                    set: { draft.meetSpotNote = VolunteerMeetupPlanDraft.limitedMeetSpotNote($0) }
                ))
                .flowFont(FlowV2Fonts.callout())
                .foregroundColor(AppColors.Flow.primaryText)
                .submitLabel(.done)
                .accessibilityLabel(VolunteerMeetupPlanCopy.meetSpotLabel)
                .accessibilityHint("最多 \(IntroCallMeetupPlan.meetSpotNoteMaxLength) 个字")
                .accessibilityIdentifier("volunteerMeetupPlanMeetSpotField")
                Text("\(draft.meetSpotNote.count) / \(IntroCallMeetupPlan.meetSpotNoteMaxLength)")
                    .flowFont(FlowV2Fonts.subhead(), monospacedDigit: true)
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColors.Flow.separator, lineWidth: 1)
            )
        }
    }

    // MARK: 上衣颜色

    private func colorCard(title: String, selection: Binding<MeetupTopColor?>) -> some View {
        sectionCard {
            sectionHeader(title, changed: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(MeetupTopColor.selectableColors, id: \.self) { color in
                    colorChip(
                        label: VolunteerMeetupPlanCopy.colorShortName(color),
                        spoken: VolunteerMeetupPlanCopy.colorName(color),
                        swatch: Self.swatch(for: color),
                        isSelected: selection.wrappedValue == color
                    ) { selection.wrappedValue = color }
                }
                colorChip(
                    label: VolunteerMeetupPlanCopy.unconfirmedColor,
                    spoken: VolunteerMeetupPlanCopy.unconfirmedColor,
                    swatch: nil,
                    isSelected: selection.wrappedValue == nil
                ) { selection.wrappedValue = nil }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func colorChip(
        label: String,
        spoken: String,
        swatch: Color?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(AppColors.Flow.separator, lineWidth: 1))
                        .frame(width: 18, height: 18)
                }
                Text(label)
                    .flowFont(FlowV2Fonts.callout(bold: isSelected))
                    .foregroundColor(AppColors.Flow.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AppColors.Flow.accent : AppColors.Flow.separator,
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 色块是这一页**唯一**出现「内容颜色」的地方（视觉稿 V2 说明）：它表示衣服的颜色，不是界面配色，
    /// 所以不走 `AppColors`。只给明眼的陪跑员看；盲人端只念颜色名。
    static func swatch(for color: MeetupTopColor) -> Color {
        switch color {
        case .black: return .black
        case .white: return .white
        case .gray: return .gray
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .unknown: return .clear
        }
    }

    // MARK: 主按钮

    private var submitBar: some View {
        VStack(spacing: 6) {
            if let caption = draft.submitButtonCaption {
                // 同一句话进主按钮的 hint；这里对读屏隐藏，免得念两遍（同 `OrderFlowPrimaryAction.caption`）。
                Text(caption)
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            FlowActionButton(
                draft.submitButtonTitle,
                style: .raisedPrimary,
                isLoading: isSubmitting,
                isEnabled: canSubmit,
                accessibilityHint: [draft.submitButtonCaption, "跑者确认后即完成约定"].compactMap { $0 }.joined(separator: "。")
            ) {
                submit()
            }
            .accessibilityIdentifier("volunteerMeetupPlanSubmitButton")
        }
        .padding(.horizontal, FlowMetrics.v2ScreenPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.Flow.page.ignoresSafeArea())
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        submitError = nil
        let request = draft.request()
        let distance = draft.distanceFromOriginal
        Task {
            let outcome = await onSubmit(request, distance)
            isSubmitting = false
            switch outcome {
            case .submitted, .roundEnded:
                dismiss()
            case .failed(let error):
                submitError = error
                if error.slot == .time { isEditingTime = true }
            }
        }
    }

    private func clearSubmitError(_ slot: VolunteerMeetupPlanErrorSlot) {
        if submitError?.slot == slot { submitError = nil }
    }

    // MARK: 小零件

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowCard {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func sectionHeader(_ title: String, changed: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .flowFont(FlowV2Fonts.subhead(bold: true))
                .foregroundColor(AppColors.Flow.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if changed {
                FlowTag(text: VolunteerMeetupPlanCopy.changedTag)
            }
        }
    }

    private func editButton(accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(VolunteerMeetupPlanCopy.editButton)
                .flowFont(FlowV2Fonts.callout(bold: true))
                .foregroundColor(AppColors.Flow.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .flowFont(FlowV2Fonts.subhead())
            .foregroundColor(AppColors.Flow.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorText(_ message: String) -> some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .flowFont(FlowV2Fonts.subhead(bold: true))
        .foregroundColor(AppColors.destructive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}

// MARK: - 地点搜索（高德输入提示）

/// 选新的集合点。搜索走现有的 `AMapGeocodingService.searchPlaces`（POI 关键词，搜不到再走输入提示）。
/// 坐标经 `BackendCoordinateNormalizer.backend` 这一道单点入口：高德结果本来就是 GCJ-02，原样通过；
/// 不合法的坐标在这里被挡掉，不带进请求体。
struct VolunteerMeetupPlaceSearchView: View {
    let near: CLLocationCoordinate2D?
    let onSelect: (VolunteerMeetupPlanDraft.Place) -> Void

    @EnvironmentObject private var geocodingService: AMapGeocodingService
    @State private var keyword = ""
    @State private var results: [ResolvedPlace] = []
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField(VolunteerMeetupPlanCopy.placeSearchPrompt, text: $keyword)
                        .submitLabel(.search)
                        .onSubmit(search)
                        .accessibilityIdentifier("volunteerMeetupPlaceSearchField")
                    Button(VolunteerMeetupPlanCopy.placeSearchButton, action: search)
                        .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        .frame(minHeight: 44)
                }
            }
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let message {
                Text(message)
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
            }
            ForEach(results) { place in
                Button {
                    select(place)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.title)
                            .flowFont(FlowV2Fonts.callout(bold: true))
                            .foregroundColor(AppColors.Flow.primaryText)
                        if !place.addressText.trimmed.isEmpty {
                            Text(place.addressText)
                                .flowFont(FlowV2Fonts.subhead())
                                .foregroundColor(AppColors.Flow.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(VolunteerMeetupPlanCopy.placeSearchTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSearching else { return }
        isSearching = true
        message = nil
        Task {
            let found = await geocodingService.searchPlaces(keyword: text, near: near)
            results = found
            isSearching = false
            if found.isEmpty {
                message = geocodingService.lastErrorMessage ?? VolunteerMeetupPlanCopy.placeSearchFailed
            }
        }
    }

    private func select(_ place: ResolvedPlace) {
        guard place.source != .demoDefault,
              let coordinate = BackendCoordinateNormalizer.backend(latitude: place.latitude, longitude: place.longitude)
        else {
            message = VolunteerMeetupPlanCopy.placeCoordinateInvalid
            return
        }
        onSelect(VolunteerMeetupPlanDraft.Place(
            address: place.title,
            latitude: coordinate.coordinate.latitude,
            longitude: coordinate.coordinate.longitude
        ))
    }
}

// MARK: - 5 分钟一档的时间选择器

/// SwiftUI `DatePicker` 没有 `minuteInterval`，包一层 `UIDatePicker`（iOS 16 部署目标下唯一的办法）。
struct MinuteIntervalDatePicker: UIViewRepresentable {
    @Binding var date: Date
    let minimumDate: Date
    let maximumDate: Date
    var minuteInterval: Int = VolunteerMeetupPlanDraft.minuteInterval

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .wheels
        picker.locale = Locale(identifier: "zh_CN")
        picker.minuteInterval = minuteInterval
        picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.date = $date
        picker.minuteInterval = minuteInterval
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        if picker.date != date {
            picker.setDate(date, animated: false)
        }
    }

    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) {
            self.date = date
        }

        @objc func valueChanged(_ sender: UIDatePicker) {
            date.wrappedValue = sender.date
        }
    }
}
