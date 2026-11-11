import SwiftUI

// MARK: - 约跑「先匹配后商量」（#806，v5 #821）
//
// v4（负责人 2026-11-06「同意 v4」）照参考图 2 逐像素画。v5（负责人 2026-11-07 批）改三处：
// - 「从哪出发？」换成「默认出发地点」页同一套彩色圆排（`BookingStartPlacePicker`），全部常用地点都能选；
// - 日期改成真实日历（`BookingDateStrip`）：可约天数读后端 `maxLeadDays`（backend#935，放宽到 30 天），
//   能翻周、月份可点；
// - 时段与后端值守时段取交集，不在值守里的段灰掉并写原因，后端那句提示原样显示。
// 三个问题标题加大，各自一张白卡，页面灰底（与资料库页、「我的」同一套分组卡）。
// 行为见 OpenSpec `blind-booking-match-first`：只选日期 + 时段，具体几点可不选；下单发时段单。

struct BlindMatchFirstBookingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService

    /// 首页那份常用地点。进页默认选其中的默认出发地点；从添加页回来能看到新收藏。
    @ObservedObject var favoritePlaces: FavoritePlaceStore
    let onAddFavorite: () -> Void
    let onOrderCreated: (OrderResponse) -> Void

    @StateObject private var viewModel = BlindBookingViewModel()
    @State private var now = Date()
    @State private var selectedDay: Date?
    @State private var selectedSlot: BookingDaySlot?
    @State private var preferredStart: Date?
    /// 这一单从哪个常用地点出发。`nil` = 当前定位。只管这一单，不改默认出发地点。
    @State private var selectedFavoriteID: String?
    @State private var hasAppeared = false
    /// 被拒后的短提示（#813）。`nil` = 不显示。
    @State private var gateAlert: BookingStartGateAlert?
    /// 点提交后等系统框回答的这段时间，按钮不可重复点。
    @State private var isCheckingStartPoint = false

    private static let horizontalPadding: CGFloat = 16

    private var rules: BookingRules { BookingRules(appState: appState) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("从哪出发？")
                if let notice = launchAreaNotice { areaNoticeRow(notice) }
                BookingStartPlacePicker(
                    places: favoritePlaces.places,
                    selectedPlaceID: selectedFavoriteID,
                    deviceLocation: isLocationUnavailable ? nil : locationService.currentLocation,
                    detail: startPointDetail,
                    onSelectCurrent: useCurrentLocation,
                    onSelect: useFavorite,
                    onAdd: onAddFavorite
                )
                sectionTitle("哪天跑？")
                GroupedCard {
                    BookingDateStrip(now: now, rules: rules, selectedDay: selectedDay) { day in selectDay(day) }
                }
                sectionTitle("大概什么时候？")
                GroupedCard {
                    BookingSlotSection(
                        now: now, rules: rules, selectedDay: selectedDay, selectedSlot: selectedSlot,
                        preferredStart: preferredStart, dutyHoursHint: dutyHoursHint,
                        onSelectSlot: selectSlot, onTogglePreferredStart: togglePreferredStart
                    )
                }
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(AppFonts.body().bold())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .accessibilityIdentifier("matchFirstBookingError")
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.bottom, 24)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
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
        // 规则晚到（或值守时段变了）时，已选的日子 / 时段可能不再合法：换到最近能约的。
        .onChange(of: rules) { _ in revalidateSelection() }
        // 从添加页回来：添加页会把选中的地点（新收藏、已收藏过的、或「使用当前定位」）设成默认出发地点并朗读，
        // 这一单就跟着从那里出发。看默认 id 不看收藏条数：选已收藏过的地点时条数不变。
        .onChange(of: favoritePlaces.defaultPlaceID) { _ in
            if let place = favoritePlaces.defaultPlace {
                useFavorite(place)
            } else {
                useCurrentLocation()
            }
        }
        // 先 contain 再挂 id：否则这个 id 盖掉页里所有子元素的 id（#814），审计也认不出底栏。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("matchFirstBookingPage")
        .alert(gateAlert?.title ?? "", isPresented: gateAlertIsPresented, presenting: gateAlert) { _ in
            Button(BookingStartGateCopy.pickFavorite, role: .cancel) {}
            Button(BookingStartGateCopy.openSettings) { SystemSettingsLink.open() }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var gateAlertIsPresented: Binding<Bool> {
        Binding(get: { gateAlert != nil }, set: { if !$0 { gateAlert = nil } })
    }

    // MARK: 从哪出发

    private var isLocationUnavailable: Bool { locationService.isDenied || locationService.isPreciseLocationOff }

    private var selectedFavorite: ResolvedPlace? {
        favoritePlaces.places.first { $0.id == selectedFavoriteID }
    }

    /// 出发点是当前位置、而定位用不了时才有（选了常用地点就不说）。
    private var locationGateNote: String? {
        guard selectedFavoriteID == nil else { return nil }
        return BookingStartGateCopy.detail(isDenied: locationService.isDenied, isPreciseLocationOff: locationService.isPreciseLocationOff)
    }

    /// 后端下发的开放范围那句（`launchScope.areaHint`），城市不写死；没有限制时 `nil`。
    /// 已选的出发点不在范围里时，`areaNotice` 会在前面加一句。直接读 `appState`：视图首帧早于 `onAppear` 里的 `configure`。
    private var launchAreaNotice: String? {
        let place = selectedFavorite ?? viewModel.resolvedStartPlace
        return appState.ruleParamsResponse?.launchScope?.areaNotice(latitude: place?.latitude, longitude: place?.longitude)
    }

    private func areaNoticeRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(AppColors.Flow.secondaryText)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("matchFirstLaunchAreaNotice")
    }

    private var startPointDetail: String {
        if let locationGateNote { return locationGateNote }
        if let selectedFavorite { return "\(selectedFavorite.title) · 见面点电话里再定" }
        if let place = viewModel.resolvedStartPlace?.title.nilIfBlank { return "\(place)附近 · 见面点电话里再定" }
        return viewModel.isResolvingStartLocation ? "正在获取当前位置…" : "还没拿到当前位置"
    }

    /// 值守时段那句由后端拼好，原样显示（`LaunchScopeResponse.dutyHoursHint`）。没有限制时不显示。
    private var dutyHoursHint: String? {
        guard let scope = appState.ruleParamsResponse?.launchScope, scope.dutyHoursRestricted else { return nil }
        return scope.dutyHoursHint
    }

    // MARK: 主按钮

    private var submitBar: some View {
        PrimaryButton("开始找陪跑员", isLoading: viewModel.isSubmitting || isCheckingStartPoint) {
            Task { await submit() }
        }
        .disabled(currentSlot == nil || isCheckingStartPoint)
        .accessibilityLabel(submitSpokenLabel)
        .accessibilityIdentifier("matchFirstSubmitButton")
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 8)
        .background(AppColors.Flow.page.ignoresSafeArea())
        // 不透明底栏：无障碍审计据此认出滚到它后面的胶囊（看不见，不算对比度失败）。先 contain，免得盖掉按钮自己的 id。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindBookingSubmitBar")
    }

    private var submitSpokenLabel: String {
        guard let slot = currentSlot else { return "开始找陪跑员，还没选时段" }
        var text = "开始找陪跑员，\(BookingSlotText.spokenDay(slot.day, now: now))\(slot.slot.title)"
        if let preferred = slot.preferredStart { text += "，想 \(BookingSlotText.clock(preferred)) 左右开始" }
        return text
    }

    // MARK: 小部件

    /// 三个问题的标题：比 v4 的 `.headline` 大一档（负责人 11-07：「从哪出发」太小、和下面分不开）。
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundColor(AppColors.Flow.navy)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 22)
            .padding(.bottom, 9)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: 选择

    private var currentSlot: BookingFlexibleSlot? {
        guard let selectedDay, let selectedSlot else { return nil }
        return BookingSlotPlanner.makeSlot(
            day: selectedDay, slot: selectedSlot, preferredStart: preferredStart, now: now, rules: rules
        )
    }

    private func selectDay(_ day: Date) {
        selectedDay = day
        if let slot = selectedSlot, BookingSlotPlanner.window(day: day, slot: slot, now: now, rules: rules) != nil { return }
        selectedSlot = BookingSlotPlanner.firstAvailableSlot(day: day, now: now, rules: rules)
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

    /// 已选的日子不能约了就换到最早能约的；日子还行但时段不行就换到这天第一个能约的时段。
    private func revalidateSelection() {
        guard let day = selectedDay, BookingSlotPlanner.isDayAvailable(day, now: now, rules: rules) else {
            let initial = BookingSlotPlanner.defaultSelection(now: now, rules: rules)
            selectedDay = initial?.day
            selectedSlot = initial?.slot
            preferredStart = nil
            return
        }
        selectDay(day)
    }

    private func useCurrentLocation() {
        selectedFavoriteID = nil
        viewModel.selectedStartPlace = nil
        Task { await viewModel.refreshCurrentLocation() }
    }

    private func useFavorite(_ place: ResolvedPlace) {
        selectedFavoriteID = place.id
        viewModel.selectPlace(place, announce: false)
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
        guard !hasAppeared else {
            revalidateSelection()
            return
        }
        hasAppeared = true
        // 首页设了默认常用地点就从那里出发（v4 总是选当前位置，首页的默认设了也不起作用）。
        if let place = favoritePlaces.defaultPlace { useFavorite(place) }
        if let initial = BookingSlotPlanner.defaultSelection(now: now, rules: rules) {
            selectedDay = initial.day
            selectedSlot = initial.slot
        }
        speechService.speak(entryAnnouncement)
    }

    /// 开场只念一次（后到的 `speak` 会切断先到的）：定位用不了时换掉「从当前位置出发」，有开放范围就附一句。
    private var entryAnnouncement: String {
        let origin = selectedFavorite?.title ?? BlindStartPlaceCopy.currentLocation
        let gateNote = selectedFavoriteID == nil
            ? BookingStartGateCopy.entrySpoken(isDenied: locationService.isDenied, isPreciseLocationOff: locationService.isPreciseLocationOff)
            : nil
        let departure = gateNote ?? "从\(origin)出发。"
        let scope = launchAreaNotice.map { "\($0)。" } ?? ""
        guard let slot = currentSlot else { return "预约陪跑。\(departure)\(scope)现在没有可以约的时段。" }
        return "预约陪跑。\(departure)\(scope)已选\(BookingSlotText.spokenDay(slot.day, now: now))\(slot.slot.title)，"
            + "\(BookingSlotText.clock(slot.start))到\(BookingSlotText.clock(slot.end))之间。具体几点可以不选。点「开始找陪跑员」就开始匹配。"
    }

    /// 出发点是当前位置、而定位用不了时：精确位置关闭 → 请求一次临时精确位置，允许后取新位置再放行；
    /// 被拒（或权限被拒）→ 弹短提示并朗读，不提交。出发点是常用地点时直接放行。
    private func passesStartGate() async -> Bool {
        let gate = BookingStartGate.evaluate(
            usesCurrentLocation: selectedFavoriteID == nil,
            isDenied: locationService.isDenied,
            isPreciseLocationOff: locationService.isPreciseLocationOff
        )
        switch gate {
        case .proceed:
            return true
        case .blockedByDeniedLocation:
            showGateAlert(isDenied: true)
            return false
        case .askPreciseLocation:
            isCheckingStartPoint = true
            defer { isCheckingStartPoint = false }
            let stillOff = await locationService.requestTemporaryPreciseLocationAndWaitForAnswer(for: .bookingStartPoint)
            if stillOff {
                showGateAlert(isDenied: false)
                return false
            }
            await viewModel.refreshCurrentLocation()
            return true
        }
    }

    private func showGateAlert(isDenied: Bool) {
        let alert = BookingStartGateAlert.make(isDenied: isDenied)
        gateAlert = alert
        speechService.speakError(alert.message)
    }

    private func submit() async {
        now = Date()
        guard let slot = currentSlot else {
            viewModel.errorMessage = "这个时段已经过了，请换一个时段。"
            speechService.speakError("这个时段已经过了，请换一个时段。")
            return
        }
        guard await passesStartGate() else { return }
        viewModel.flexibleSlot = slot
        if let response = await viewModel.submit() {
            onOrderCreated(response)
        }
    }
}
