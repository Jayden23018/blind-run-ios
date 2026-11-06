import SwiftUI

// MARK: - 约跑「先匹配后商量」（#806）
//
// 视觉照模拟图 v4（`docs/ui/mockups/blind-match-first-20261106/`，负责人 2026-11-06「同意 v4」），
// 版式取自负责人给的参考图逐像素实测。两处负责人批准的有意偏离：
// - 未选中的选项描边用灰按钮描边色（`ButtonPalette.neutralStroke`，过 3:1），不用参考图的极浅灰；
// - 每个选项的可点区撑到 ≥64pt 高（看得见的胶囊仍是 48 / 45 / 44），盲人端可点下限。
// 行为见 OpenSpec `booking-match-first`：只选日期 + 时段，具体几点可不选；下单发时段单。

struct BlindMatchFirstBookingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService

    /// 首页设的默认出发地点（常用地点）。没有就点「常用地点」时只告知。
    let favoritePlace: ResolvedPlace?
    let onOrderCreated: (OrderResponse) -> Void

    @StateObject private var viewModel = BlindBookingViewModel()
    @State private var now = Date()
    @State private var selectedDay: Date?
    @State private var selectedSlot: BookingDaySlot?
    @State private var preferredStart: Date?
    @State private var usesFavorite = false
    @State private var hasAppeared = false

    private static let horizontalPadding: CGFloat = 18.5
    private static let minimumHitHeight: CGFloat = 64
    /// 日期圆的直径（参考图实测 48）。只是看得见的圆，可点区是整列 60 宽、≥64 高。
    private static let dayCircleDiameter: CGFloat = 48

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                startPointSection
                dateBand
                    .padding(.top, 24)
                slotSection
                    .padding(.top, 28)
                Rectangle()
                    .fill(AppColors.Flow.separator)
                    .frame(height: 1)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                startTimeSection
                    .padding(.top, 12)
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(AppFonts.body().bold())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.top, 16)
                        .accessibilityIdentifier("matchFirstBookingError")
                }
            }
            .padding(.bottom, 24)
            .readableContentColumn()
        }
        .background(AppColors.Flow.surface.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { submitBar }
        .navigationTitle("预约陪跑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: handleAppear)
        .requestsLocationUpdates(.blindBooking)
        .onChange(of: locationService.currentLocation) { _ in
            Task { await viewModel.refreshCurrentLocationIfNeeded() }
        }
        .onChange(of: locationService.accuracyAuthorization) { _ in
            Task { await viewModel.refreshCurrentLocationIfNeeded() }
        }
        .accessibilityIdentifier("matchFirstBookingPage")
    }

    // MARK: 从哪出发

    private var startPointSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("从哪出发？")
                .padding(.top, 20)
            HStack(spacing: 19) {
                pill("当前位置", isSelected: !usesFavorite, height: 48) { useCurrentLocation() }
                    .accessibilityIdentifier("matchFirstStartCurrent")
                pill("常用地点", isSelected: usesFavorite, height: 48) { useFavorite() }
                    .accessibilityIdentifier("matchFirstStartFavorite")
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, 8)
            Text(startPointDetail)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Self.horizontalPadding)
                .accessibilityIdentifier("matchFirstStartDetail")
        }
    }

    private var startPointDetail: String {
        let place = viewModel.resolvedStartPlace?.title.nilIfBlank
        if usesFavorite { return "\(place ?? "常用地点") · 见面点电话里再定" }
        if let place { return "\(place)附近 · 见面点电话里再定" }
        return viewModel.isResolvingStartLocation ? "正在获取当前位置…" : "还没拿到当前位置"
    }

    // MARK: 哪天跑

    private var dateBand: some View {
        let days = BookingSlotPlanner.days(now: now)
        return VStack(alignment: .leading, spacing: 14) {
            monthRow(days: days)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        dayButton(day, index: index, total: days.count)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.page)
    }

    /// 参考图的月份带：当前月加粗，前后渐淡。只是装饰，日期本身会念出几月几日，所以不进读屏。
    private func monthRow(days: [Date]) -> some View {
        let month = Calendar.aidRunBackend.component(.month, from: selectedDay ?? days.first ?? now)
        return HStack(spacing: 18) {
            ForEach([-2, -1, 0, 1, 2], id: \.self) { offset in
                monthLabel(month: month, offset: offset)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .accessibilityHidden(true)
    }

    private func monthLabel(month: Int, offset: Int) -> some View {
        let value: Int = ((month - 1 + offset) % 12 + 12) % 12 + 1
        let isCurrent = offset == 0
        let fade: Double = abs(offset) == 1 ? 0.8 : 0.55
        let color: Color = isCurrent ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText.opacity(fade)
        return Text("\(value)月")
            .font(.footnote.weight(isCurrent ? .semibold : .regular))
            .foregroundColor(color)
    }

    private func dayButton(_ day: Date, index: Int, total: Int) -> some View {
        let isAvailable = BookingSlotPlanner.isDayAvailable(day, now: now)
        let isSelected = selectedDay == day
        let number = Calendar.aidRunBackend.component(.day, from: day)
        return Button {
            selectDay(day)
        } label: {
            VStack(spacing: 8) {
                Text("\(number)")
                    .font(.title3.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(dayNumberColor(isAvailable: isAvailable, isSelected: isSelected))
                    .frame(width: Self.dayCircleDiameter, height: Self.dayCircleDiameter) // guard:allow small-touch-target 只是圆，可点区见下方整列 60×64
                    .background(Circle().fill(dayFill(isAvailable: isAvailable, isSelected: isSelected)))
                    .overlay(dayBorder(isAvailable: isAvailable, isSelected: isSelected))
                Text(BookingSlotText.weekdayName(day))
                    .font(AppFonts.caption())
                    .foregroundColor(isSelected ? AppColors.Flow.navy : AppColors.Flow.secondaryText)
            }
            .frame(width: 60)
            .frame(minHeight: Self.minimumHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookingSlotText.spokenDay(day, now: now) + (isAvailable ? "" : "，今天的时段都已过"))
        .accessibilityValue("第 \(index + 1) 项，共 \(total) 项")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayNumberColor(isAvailable: Bool, isSelected: Bool) -> Color {
        guard isAvailable else { return AppColors.Flow.secondaryText }
        return isSelected ? AppColors.Flow.navy : AppColors.Flow.primaryText
    }

    private func dayFill(isAvailable: Bool, isSelected: Bool) -> Color {
        if isSelected { return AppColors.Flow.surface }
        return isAvailable ? AppColors.Flow.blueTint : AppColors.Flow.page
    }

    @ViewBuilder
    private func dayBorder(isAvailable: Bool, isSelected: Bool) -> some View {
        if isSelected {
            Circle().strokeBorder(AppColors.ButtonPalette.primaryFill, lineWidth: 1.5)
        } else if !isAvailable {
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, style: StrokeStyle(lineWidth: 1, dash: [3]))
        }
    }

    // MARK: 大概什么时候

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("大概什么时候？")
            HStack(spacing: 19) {
                ForEach(BookingDaySlot.allCases) { slot in
                    let range = selectedDay.flatMap { BookingSlotPlanner.window(day: $0, slot: slot, now: now) }
                    pill(slot.title, isSelected: selectedSlot == slot, height: 45, isEnabled: range != nil) {
                        selectSlot(slot)
                    }
                    .accessibilityLabel(
                        range.map { "\(slot.title)，\(BookingSlotText.clock($0.start))到\(BookingSlotText.clock($0.end))之间" } ?? "\(slot.title)，已过"
                    )
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, 6)
        }
    }

    // MARK: 想几点开始（可不选）

    private var startTimeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(startTimeHint)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Self.horizontalPadding)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(startTimes, id: \.self) { time in
                    pill(BookingSlotText.clock(time), isSelected: preferredStart == time, height: 44, fillsWidth: true) {
                        togglePreferredStart(time)
                    }
                    .accessibilityHint("可以不选，电话里再定")
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
        }
    }

    private var startTimes: [Date] {
        guard let selectedDay, let selectedSlot else { return [] }
        return BookingSlotPlanner.startTimes(day: selectedDay, slot: selectedSlot, now: now)
    }

    private var startTimeHint: String {
        guard let selectedDay, let selectedSlot,
              let range = BookingSlotPlanner.window(day: selectedDay, slot: selectedSlot, now: now) else {
            return "先选一个时段"
        }
        return "\(selectedSlot.title) \(BookingSlotText.clock(range.start))–\(BookingSlotText.clock(range.end)) 之间 · 具体几点可以不选，电话里再定"
    }

    // MARK: 主按钮

    private var submitBar: some View {
        PrimaryButton("开始找陪跑员", isLoading: viewModel.isSubmitting) {
            Task { await submit() }
        }
        .disabled(currentSlot == nil)
        .accessibilityLabel(submitSpokenLabel)
        .accessibilityIdentifier("matchFirstSubmitButton")
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 8)
        .background(AppColors.Flow.surface.ignoresSafeArea())
    }

    private var submitSpokenLabel: String {
        guard let slot = currentSlot else { return "开始找陪跑员，还没选时段" }
        var text = "开始找陪跑员，\(BookingSlotText.spokenDay(slot.day, now: now))\(slot.slot.title)"
        if let preferred = slot.preferredStart { text += "，想 \(BookingSlotText.clock(preferred)) 左右开始" }
        return text
    }

    // MARK: 小部件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(AppColors.Flow.navy)
            .padding(.horizontal, Self.horizontalPadding)
            .accessibilityAddTraits(.isHeader)
    }

    /// 参考图的胶囊：白底、选中只换 1.5pt 蓝描边（不加粗、不填色）。可点区撑到 64pt 高。
    private func pill(
        _ title: String,
        isSelected: Bool,
        height: CGFloat,
        isEnabled: Bool = true,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(pillTextColor(isEnabled: isEnabled, isSelected: isSelected))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, fillsWidth ? 4 : 15)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
                .background(Capsule().fill(isEnabled ? AppColors.Flow.surface : AppColors.Flow.page))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? AppColors.ButtonPalette.primaryFill : AppColors.ButtonPalette.neutralStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
                .frame(minHeight: Self.minimumHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pillTextColor(isEnabled: Bool, isSelected: Bool) -> Color {
        guard isEnabled else { return AppColors.Flow.secondaryText }
        return isSelected ? AppColors.Flow.navy : AppColors.Flow.primaryText
    }

    // MARK: 选择

    private var currentSlot: BookingFlexibleSlot? {
        guard let selectedDay, let selectedSlot else { return nil }
        return BookingSlotPlanner.makeSlot(day: selectedDay, slot: selectedSlot, preferredStart: preferredStart, now: now)
    }

    private func selectDay(_ day: Date) {
        selectedDay = day
        if let slot = selectedSlot, BookingSlotPlanner.window(day: day, slot: slot, now: now) != nil { return }
        selectedSlot = BookingDaySlot.allCases.first { BookingSlotPlanner.window(day: day, slot: $0, now: now) != nil }
        preferredStart = nil
    }

    private func selectSlot(_ slot: BookingDaySlot) {
        guard selectedSlot != slot else { return }
        selectedSlot = slot
        preferredStart = nil
    }

    private func togglePreferredStart(_ time: Date) {
        preferredStart = preferredStart == time ? nil : time
    }

    private func useCurrentLocation() {
        usesFavorite = false
        viewModel.selectedStartPlace = nil
        Task { await viewModel.refreshCurrentLocation() }
    }

    private func useFavorite() {
        guard let favoritePlace else {
            speechService.speak("还没有设默认的常用地点，可以在首页设置。这次先用当前位置。")
            return
        }
        usesFavorite = true
        viewModel.selectPlace(favoritePlace, announce: false)
    }

    private func handleAppear() {
        now = Date()
        if locationService.isNotDetermined {
            locationService.requestPermission()
        }
        viewModel.configure(
            appState: appState,
            locationService: locationService,
            speechService: speechService,
            amapGeocodingService: amapGeocodingService
        )
        Task { await viewModel.refreshCurrentLocation() }
        guard !hasAppeared else { return }
        hasAppeared = true
        if let initial = BookingSlotPlanner.defaultSelection(now: now) {
            selectedDay = initial.day
            selectedSlot = initial.slot
        }
        speechService.speak(entryAnnouncement)
    }

    private var entryAnnouncement: String {
        guard let slot = currentSlot else { return "预约陪跑。现在没有可以约的时段。" }
        return "预约陪跑。从当前位置出发。已选\(BookingSlotText.spokenDay(slot.day, now: now))\(slot.slot.title)，"
            + "\(BookingSlotText.clock(slot.start))到\(BookingSlotText.clock(slot.end))之间。具体几点可以不选。点「开始找陪跑员」就开始匹配。"
    }

    private func submit() async {
        now = Date()
        guard let slot = currentSlot else {
            viewModel.errorMessage = "这个时段已经过了，请换一个时段。"
            speechService.speakError("这个时段已经过了，请换一个时段。")
            return
        }
        viewModel.flexibleSlot = slot
        if let response = await viewModel.submit() {
            onOrderCreated(response)
        }
    }
}
