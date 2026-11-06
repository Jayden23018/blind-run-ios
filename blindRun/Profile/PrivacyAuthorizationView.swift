import SwiftUI

// MARK: - 隐私与授权（#393，#754 拆两层）

/// 盲人端三项单独同意的撤回，放在同一处、同一种交互（PIPL 第十五条：同意要能撤回，撤回要和给出一样便捷）。
///
/// #754 起照设置 App「隐私与安全」拆两层：第一层只看状态，每项点进去一页，在那一页撤回。
/// 第一层没有撤回按钮，误触撤回的机会少了；撤回结果留在撤回行下面并朗读一次。
///
/// 撤回不加二次确认：随时可以重新同意，资料页 #352 那一项也是按下即生效（与安卓 #91 一致）。
enum PrivacyAuthorizationCopy {
    static let title = "隐私与授权"
    /// 陪跑员端整句用（`VolunteerPrivacyAuthorizationView`）。
    static let granted = "当前：已同意。"

    // 第一层
    static let intro = "你同意过的三件事。点进去看用途，也可以撤回。"
    static let listFootnote = "撤回后，下次要用到时会重新问你。"
    static let grantedValue = "已同意"
    static let notGrantedValue = "没有同意"
    /// 第二层「当前」那一行的名称。
    static let currentStatusTitle = "当前"

    static let voiceTitle = "语音下单"
    static let voicePurpose = "用语音下单时，你说的话转成文字后会发给阿里云通义千问（第三方大模型），帮助理解你要去哪里、什么时候出发。"
    static let voiceNotGrantedHint = "下次用语音下单前会先问你，也可以改用手动填写。"
    /// 撤回行的可见标题各不相同：语音控制（「点按……」）按可见标题找按钮。
    static let voiceRevokeButtonTitle = "撤回语音下单的同意"
    static let voiceRevokeLabel = "撤回语音下单的同意。撤回后不再把你说的话发给第三方大模型，下次用语音下单前会重新问你"
    static let voiceRevokeFootnote = "撤回后不再把你说的话发给第三方大模型。下次用语音下单前会重新问你，也可以改用手动填写。"
    static let voiceRevoked = "已撤回。语音下单不会再把你说的话发给第三方大模型；下次用语音下单前会重新问你，也可以改用手动填写。"

    static let visionTitle = "视力状况和导盲犬"
    static let visionPurpose = "这两项属于敏感个人信息，只用来让陪跑员知道该怎么准备。"
    static let visionNotGrantedHint = "想填可以到「个人资料」里点「视力状况与导盲犬」。"
    static let visionProfileNotLoaded = "资料还没加载出来，请先打开一次「个人资料」，再回来撤回。"
    static let visionWithdrawalPendingValue = "撤回还没完成"
    static let visionWithdrawalPendingHint = "资料里的视力状况和导盲犬还在。"
    /// 失败那句「请再点一次『…』」里的按钮名也用它（`withdrawalRetryButtonTitle`）。
    static let visionRevokeButtonTitle = "撤回视力状况和导盲犬的同意"
    /// 以可见标题开头：失败那句让用户「再点一次」这个名字，读屏念到的按钮名要对得上。
    static let visionRevokeLabel = "撤回视力状况和导盲犬的同意。按下后立刻把资料里这两项改成不提供，以后想填可以再同意"
    static let visionRevokeFootnote = "撤回后，资料里的视力状况和导盲犬会立刻改成不提供。以后想填可以再同意。"

    static let locationTitle = "陪跑时的位置共享"
    static let locationPurpose = "从陪跑员出发来找你到跑步结束，持续获取你的位置，显示给此订单的陪跑员；求助时附上当时的位置。"
    static let locationNotGrantedHint = "下次预约陪跑、或已约好的陪跑出发前会先问你。"
    static let locationRevokeButtonTitle = "撤回位置共享的同意"
    static let locationRevokeLabel = "撤回陪跑时位置共享的同意。撤回后不再获取你的位置，求助也不附位置，下次预约陪跑或已约好的陪跑出发前会重新问你"
    static let locationRevokeFootnote = "撤回后不再获取你的位置，求助也不附位置。下次预约陪跑、或已约好的陪跑出发前会重新问你。"
    static let locationRevoked = "已撤回。不再获取你的位置，求助也不会附上位置；下次预约陪跑、或已约好的陪跑出发前会重新问你。"
    static let locationBlockedDuringEscort =
        "正在陪跑，现在撤回会让对方立刻看不到你的位置，所以请在此订单结束后再来撤回。现在就要停，可以在系统设置里关闭助盲跑的定位权限。"
}

/// 视力那一项此刻怎么显示（#393）。抽成纯函数只为可测：撤回保存失败后要能原地重试，而不是按钮消失、状态说错。
enum VisionRevokeRow: Equatable {
    /// 资料没加载：撤回会被表单校验挡下，先去个人资料。
    case profileNotLoaded
    /// 已同意：显示撤回行。
    case granted
    /// 撤回已按下、还没保存成功：说清没完成，撤回行改为重试同一次保存。
    case withdrawalPending
    case notGranted

    static func resolve(hasConsent: Bool, withdrawalPending: Bool, profileLoaded: Bool) -> VisionRevokeRow {
        if withdrawalPending { return profileLoaded ? .withdrawalPending : .profileNotLoaded }
        guard hasConsent else { return .notGranted }
        return profileLoaded ? .granted : .profileNotLoaded
    }

    /// 第一层灰字与第二层「当前」行右侧的短值。资料没加载时同意记录还在，仍说已同意。
    var value: String {
        switch self {
        case .profileNotLoaded, .granted: return PrivacyAuthorizationCopy.grantedValue
        case .withdrawalPending: return PrivacyAuthorizationCopy.visionWithdrawalPendingValue
        case .notGranted: return PrivacyAuthorizationCopy.notGrantedValue
        }
    }

    /// 第二层「当前」那组下面的补充说明。资料没加载那句不在这里：它占撤回行的位置（详情页的结果行）。
    var hint: String? {
        switch self {
        case .profileNotLoaded, .granted: return nil
        case .withdrawalPending: return PrivacyAuthorizationCopy.visionWithdrawalPendingHint
        case .notGranted: return PrivacyAuthorizationCopy.visionNotGrantedHint
        }
    }

    var offersRevoke: Bool { self == .granted || self == .withdrawalPending }
}

/// 三项的图标与底色（定稿 `docs/ui/mockups/blind-privacy-20261105/`）。图标只是装饰，读屏不念。
/// 底色只取 `AppColors` 已有的色值（设计方向：不新增强调色），亮暗同值、压白字，同「我的」方块。
/// 定稿里视力那项是紫色，仓库没有紫色，用最接近的靛蓝。
enum PrivacyConsentIcon {
    static let shieldRGB = AppColors.voiceStageSurfaceTone.light
    static let voice = (systemImage: "mic.fill", rgb: AppColors.VolunteerHome.durationTealTone.light)
    static let vision = (systemImage: "eye.fill", rgb: AppColors.VolunteerHome.distanceIndigoTone.light)
    static let location = (systemImage: "location.fill", rgb: AppColors.voiceStageSurfaceTone.light)
}

/// 第一层：说明卡 + 三行（名称、灰字状态、箭头）。撤回在每项的详情页（`PrivacyConsentDetailView.swift`）。
struct PrivacyAuthorizationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    /// 视力那项复用资料页的撤回（整表单保存，两项发 `NOT_SPECIFIED`，保存成功才删同意记录）。
    /// 放在第一层持有、传给详情页：返回列表再进去，撤回待保存与失败那句都还在。
    @StateObject private var profileViewModel = BlindRunnerProfileViewModel()
    /// `hasVoiceOrderConsent` / `hasLocationTrackConsent` 是现读的计算属性，SwiftUI 收不到通知。
    /// 从详情页返回时自增一次让列表重读 —— 只读它、不拿它当 `.id`：换 id 会重建整页，读屏焦点跳回页首。
    @State private var refreshTick = 0
    /// `configure` 只做一次：再调会用资料覆盖表单，撤回待保存时重试就会把旧的视力取值发回去。
    @State private var didConfigureProfile = false

    var body: some View {
        let _ = refreshTick
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PrivacyAuthorizationIntroCard()
                VStack(alignment: .leading, spacing: 8) {
                    GroupedCard {
                        voiceRow
                        GroupedCardDivider(leadingInset: PrivacyConsentListRowLabel.dividerInset)
                        visionRow
                        GroupedCardDivider(leadingInset: PrivacyConsentListRowLabel.dividerInset)
                        locationRow
                    }
                    GroupedCardFootnote(text: PrivacyAuthorizationCopy.listFootnote)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(PrivacyAuthorizationCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮胶囊会切掉页面最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            refreshTick += 1
            guard !didConfigureProfile else { return }
            didConfigureProfile = true
            profileViewModel.configure(with: appState, speechService: speechService)
            profileViewModel.withdrawalRetryButtonTitle = PrivacyAuthorizationCopy.visionRevokeButtonTitle
        }
    }

    // MARK: 三行

    private var voiceRow: some View {
        listRow(
            title: PrivacyAuthorizationCopy.voiceTitle,
            status: appState.hasVoiceOrderConsent ? PrivacyAuthorizationCopy.grantedValue : PrivacyAuthorizationCopy.notGrantedValue,
            icon: PrivacyConsentIcon.voice,
            identifier: "privacyVoiceOrderConsentEntry"
        ) {
            PrivacyVoiceConsentDetailView()
        }
    }

    private var visionRow: some View {
        let row = VisionRevokeRow.resolve(
            hasConsent: profileViewModel.hasVisionConsent,
            withdrawalPending: profileViewModel.isVisionConsentWithdrawalPending,
            profileLoaded: appState.blindProfile != nil
        )
        return listRow(
            title: PrivacyAuthorizationCopy.visionTitle,
            status: row.value,
            icon: PrivacyConsentIcon.vision,
            identifier: "privacyVisionConsentEntry"
        ) {
            PrivacyVisionConsentDetailView(profileViewModel: profileViewModel)
        }
    }

    private var locationRow: some View {
        let granted = appState.hasLocationTrackConsent(.blindLocationTrack)
        return listRow(
            title: PrivacyAuthorizationCopy.locationTitle,
            status: granted ? PrivacyAuthorizationCopy.grantedValue : PrivacyAuthorizationCopy.notGrantedValue,
            icon: PrivacyConsentIcon.location,
            identifier: "privacyLocationTrackConsentEntry"
        ) {
            PrivacyLocationConsentDetailView()
        }
    }

    private func listRow<Destination: View>(
        title: String,
        status: String,
        icon: (systemImage: String, rgb: UInt32),
        identifier: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            PrivacyConsentListRowLabel(title: title, status: status, systemImage: icon.systemImage, rgb: icon.rgb)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(status)")
        .accessibilityHint("查看这项同意的用途，也可以在里面撤回")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// 第一层顶部说明卡：盾牌图标、标题、一句话（照设置 App「隐私与安全」）。
struct PrivacyAuthorizationIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: UIColor(rgb: PrivacyConsentIcon.shieldRGB)))
                )
                .accessibilityHidden(true)
            Text(PrivacyAuthorizationCopy.title)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(PrivacyAuthorizationCopy.intro)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrivacyAuthorizationView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
