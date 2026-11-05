import CoreLocation
import SwiftUI
import UIKit

extension BlindBookingView {
    var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("出发地点")

            // 定位被拒时只少掉「当前位置」这一个来源，**其余整条手动路径照常渲染** ——
            // 搜索、常用地点、语音输入都不依赖定位权限（`searchPlaces` 只用 `placeSearchProvider`）。
            // 2026-08-18 之前这里是 `if/else`，被拒时整段被权限提示顶掉，等于关掉定位就没法下单，
            // 违反 Apple 5.1.1(iv)。理由全文见 `BlindBookingGate`。
            if let notice = BlindBookingViewModel.locationDegradationNotice(
                isDenied: locationService.isDenied,
                isPreciseLocationOff: locationService.isPreciseLocationOff
            ) {
                // 被拒时没有临时授权可申请（那要先有定位权限），只给「去设置」。
                locationDegradationView(notice: notice, offersTemporaryPreciseLocation: !locationService.isDenied)
            } else {
                currentLocationCard
            }

            saveFavoriteButton
            // 排在搜索之前：常用地点是**跳过**「地名 → 坐标」那一段，
            // 而搜索是走进那一段。能不走就不该先摆搜索框。
            favoritePlacesSection

            VoiceTextField(
                title: "搜索出发地点",
                placeholder: "例如：科技园地铁站 A 口",
                text: $viewModel.placeSearchKeyword,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .startPlaceSearch,
                accessibilityLabel: "搜索出发地点",
                accessibilityHint: "可以使用语音或键盘搜索高德地点",
                onRecognitionCompleted: { completion in
                    Task {
                        await viewModel.handlePlaceSearchSpeechCompletion(completion)
                    }
                },
                onSubmit: { if !viewModel.isSearchingPlaces { Task { await viewModel.searchPlaces() } } }
            )

            Button {
                Task { await viewModel.searchPlaces() }
            } label: {
                HStack {
                    if viewModel.isSearchingPlaces {
                        ProgressView()
                    }
                    Text(searchButtonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isSearchingPlaces))
            .disabled(isRecognizingStartPlace || viewModel.isSearchingPlaces || viewModel.placeSearchKeyword.trimmed.isEmpty)
            .accessibilityLabel(searchButtonTitle)
            .accessibilityHint(isRecognizingStartPlace ? "请说出地点名称，识别结束后会自动搜索" : "搜索高德地点并显示可选择的出发地点列表")

            placeSearchResultsView

            VoiceTextField(
                title: "出发地点补充描述",
                placeholder: "例如：我在 A 口外侧等候",
                text: $viewModel.startLocationDescription,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .startLocationDescription,
                accessibilityLabel: "出发地点补充描述",
                accessibilityHint: "可以使用语音或键盘补充出发地点说明，不能替代坐标"
            )

            if let placeMessage = viewModel.placeMessage {
                Text(placeMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(placeMessage)
            }

            auxiliaryStartMap
        }
    }

    /// 「收藏这个出发地点」。
    ///
    /// 只在 `selectedStartPlace` 非空时出现，这一条同时挡掉两种不该收藏的东西：
    /// 「当前位置」与演示坐标 —— 它们只会出现在 `resolvedStartPlace` 的兜底分支里，
    /// 从来不会写进 `selectedStartPlace`（见那两处的实现）。所以这里不必再嗅探 `source`。
    @ViewBuilder
    private var saveFavoriteButton: some View {
        if let place = viewModel.selectedStartPlace, !favorites.contains(place) {
            Button {
                if favorites.add(place) {
                    speechService.speak("已收藏出发地点，\(place.title)。下次可以直接选。")
                }
            } label: {
                Label("收藏这个出发地点", systemImage: "star")
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .buttonStyle(OutlineSecondaryButtonStyle())
            .accessibilityLabel("收藏这个出发地点，\(place.title)")
            .accessibilityHint("收藏后可以直接选择，不用再搜一次地名")
            .accessibilityIdentifier("bookingSaveFavoritePlaceButton")
        }
    }

    /// 常用地点列表。
    ///
    /// 每行**两个**独立按钮（选择 / 删除）而不是侧滑删除：侧滑对 VoiceOver 用户是
    /// 「自定义操作」转子里的一项，得先知道它存在才找得到；而误删一条收藏之后，
    /// 用户下一次下单会退回那条最容易出错的搜索路径。
    @ViewBuilder
    private var favoritePlacesSection: some View {
        if !favorites.places.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("常用地点")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(favorites.places) { place in
                    HStack(spacing: 12) {
                        Button {
                            viewModel.selectPlace(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.title)
                                    .font(AppFonts.body().weight(.semibold))
                                    .foregroundColor(AppColors.textPrimary)
                                if !place.addressText.trimmed.isEmpty, place.addressText.trimmed != place.title.trimmed {
                                    Text(place.addressText)
                                        .font(AppFonts.caption())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 64)
                        }
                        .accessibilityLabel(place.bookingSearchAccessibilityLabel)
                        .accessibilityHint("直接使用这个已保存的地点，不再重新搜索")

                        Button {
                            favorites.remove(id: place.id)
                            speechService.speak("已删除常用地点，\(place.title)。")
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.destructive)
                                .frame(width: AppTouchTarget.blindPrimary, height: AppTouchTarget.blindPrimary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除常用地点，\(place.title)")
                    }
                    .padding(.horizontal, 12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                }
            }
            .accessibilityIdentifier("bookingFavoritePlacesSection")
        }
    }

    private var currentLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.selectedStartPlace == nil ? "默认出发点" : "已选择出发点")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Text(viewModel.startPointDisplayText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("出发地点，\(viewModel.startPointDisplayText)")
                    .accessibilityHint("提交预约时会使用这个地点")
                    .accessibilityFocused($focusedStartPlaceCard)

                if viewModel.isResolvingStartLocation {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在使用高德解析当前位置")
                    }
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("正在使用高德解析当前位置")
                } else {
                    Text(locationService.isUsingDemoFallback ? "使用演示坐标，适合模拟器测试。" : "已使用设备当前位置和高德地址作为出发点。")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(locationService.isUsingDemoFallback ? "使用演示坐标，适合模拟器测试" : "已使用设备当前位置和高德地址作为出发点")
                }

                // 精确授权下精度差于 50 米（#373）。出现时念一次（本页只一次，去重在 view model）。
                if let accuracyNotice = viewModel.startPointAccuracyNotice {
                    Text(accuracyNotice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(accuracyNotice)
                        .accessibilityIdentifier("bookingStartPointAccuracyNotice")
                        .onAppear { viewModel.announceWeakStartPointAccuracyIfNeeded() }
                }
            }
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private var auxiliaryStartMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("辅助地图")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            MapViewWrapper(
                centerCoordinate: viewModel.auxiliaryMapCenter ?? viewModel.auxiliaryMapPlace?.coordinate ?? viewModel.resolvedStartPlace?.coordinate ?? locationService.effectiveBackendLocation,
                showsUserLocation: true,
                annotations: (viewModel.auxiliaryMapPlace ?? viewModel.resolvedStartPlace).map {
                    [
                        MapAnnotationItem(
                            id: "start-location",
                            coordinate: $0.coordinate,
                            title: $0.title,
                            subtitle: $0.addressText
                        )
                    ]
                } ?? [],
                zoomLevel: 16,
                tracksUserLocation: false,
                animatesCenterChanges: false
            )
            .decorativeMapHeight(160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.auxiliaryMapAccessibilityLabel)
            .accessibilityHint("地图仅用于视觉确认，出发地点文字和语音摘要在上方")
            .accessibilityIdentifier("blindBookingAuxiliaryMap")
        }
    }

    @ViewBuilder
    private var placeSearchResultsView: some View {
        if !viewModel.placeSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("搜索结果")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(viewModel.placeSearchResults) { place in
                    Button {
                        viewModel.selectPlace(place)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.title)
                                .font(AppFonts.body().weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                            Text(place.addressText)
                                .font(AppFonts.caption())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityFocused($focusedSearchResultID, equals: place.id)
                    .accessibilityLabel(place.bookingSearchAccessibilityLabel)
                    .accessibilityHint("选为出发地点，还不会提交预约")
                }
            }
        }
    }

    private var isRecognizingStartPlace: Bool {
        speechInputService.isListening(for: .startPlaceSearch)
    }

    private var searchButtonTitle: String {
        if isRecognizingStartPlace {
            return "语音识别中"
        }
        if viewModel.isSearchingPlaces {
            return "正在搜索"
        }
        return "搜索地点"
    }

    /// 定位被拒时的降级告知。**这不是错误态** —— 预约在这个状态下照常能提交，
    /// 所以用 `speak` 而不是 `speakError`（后者带错误震动与错误音，对一个还能继续走的流程
    /// 是在制造「我是不是做错了」的错觉）。
    ///
    /// 文案从 `BlindBookingViewModel.locationDegradationNotice(isDenied:)` 传进来，
    /// 屏幕、`accessibilityLabel`、`speak` 三处读的是同一个入参 —— 三处各自去取一次常量的话，
    /// 「屏幕与耳朵读同一份文案」就只是巧合，没有任何东西拦得住其中一处改掉。
    ///
    /// `offersTemporaryPreciseLocation`：「精确位置」关闭那一档（#373）多一个按钮，申请临时精确位置。
    /// 两个按钮竖直堆叠、整行铺满（盲人端次级操作不并排）。
    private func locationDegradationView(notice: String, offersTemporaryPreciseLocation: Bool = false) -> some View {
        let settingsTitle = offersTemporaryPreciseLocation ? "去设置打开精确位置" : "去设置开启定位"
        return VStack(alignment: .leading, spacing: 12) {
            Text(notice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(notice)

            // 🔴 64pt 由 `PrimaryButtonStyle` 挂在 label 上：frame 挂在 Button 外面只撑大布局、不撑大可点区域 ——
            // 真机量到的是 34.7pt（2026-10-09，#373 的 UI 用例），低于盲人端 64pt 下限。
            if offersTemporaryPreciseLocation {
                Button {
                    viewModel.requestTemporaryPreciseLocation()
                } label: {
                    Text("临时开启精确位置")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("临时开启精确位置")
                .accessibilityHint("如果弹出系统提示，选允许后就能用当前位置作为出发地点；不开启也可以继续手动搜索")
                .accessibilityIdentifier("bookingRequestTemporaryPreciseLocationButton")
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url) // guard:allow raw-open-url 系统设置，不是拨号
                }
            } label: {
                Text(settingsTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel(settingsTitle)
            .accessibilityHint(
                offersTemporaryPreciseLocation
                    ? "打开系统设置，在定位里为助盲跑打开精确位置；不开启也可以继续手动搜索出发地点"
                    : "打开系统设置以开启定位权限；不开启也可以继续手动搜索出发地点"
            )
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        // `.contain`：不配它，容器的 identifier 会盖掉两枚按钮各自的 identifier（真机层级里三个元素同名）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookingLocationDegradationNotice")
        .onAppear {
            speechService.speak(notice)
        }
        // 被拒 ⇄ 精确位置关闭之间切换时视图身份不变、`onAppear` 不再触发；换了文案要重念。
        .onChange(of: notice) { newNotice in
            speechService.speak(newNotice)
        }
    }
}
