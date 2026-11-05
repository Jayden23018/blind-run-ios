import Combine
import SwiftUI

// MARK: - Blind Runner Profile ViewModel

@MainActor
final class BlindRunnerProfileViewModel: ObservableObject {
    @Published var name = "" { didSet { savedNotice = nil } }
    @Published var defaultPace: PacePreference = .noPreference { didSet { savedNotice = nil } }
    @Published var specialNeeds = "" { didSet { savedNotice = nil } }
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: 陪跑偏好
    //
    // 这三个字段 2026-09-10 之前**在 iOS 上根本没有采集入口** —— `saveProfile` 里写死传 nil，
    // 值一律来自后端选角色时自动建档的默认值（`visionLevel = TOTAL_BLIND`、`hasGuideDog = false`）。
    // 后果不是「资料不全」而是**低视力用户被记成全盲**，而志愿者接单前看到的正是这一行，
    // 据它决定该不该挥手、该不该递绳。
    //
    // 🔴 **同意边界画在 `tetherPreference` 与另外两个之间，不要合并：**
    // 引导方式是偏好不是身份信息，不敏感，任何时候都能填；视力状况与导盲犬是敏感个人信息
    // （PIPL 第二十八条「特定身份」），要走 `PrivacyConsentPurpose.blindVisionProfile` 单独同意。
    // 拒绝了敏感那一半的人**仍然填得了引导方式**，志愿者仍知道该怎么带他 —— 这是「可拒绝」
    // 在产品上真正成立的支点。依据见 `docs/research/vision-level-collection-ui-20260910.md` §4.2。

    /// 引导方式。**不需要同意**，`nil` = 用户还没选。
    @Published var tetherPreference: TetherPreference? { didSet { savedNotice = nil } }
    /// 视力状况。`nil` = 没选或没同意。
    @Published var visionLevel: VisionLevel? { didSet { savedNotice = nil } }
    /// 是否常带导盲犬，三选一（#472）。默认「不说」—— 与后端新建档默认值相同。
    @Published var guideDog: GuideDogStatus = .notSpecified { didSet { savedNotice = nil } }
    /// 写给陪跑员的引导偏好。自由文本 ⇒ 陪跑员**接单后**才看得到（`AGENTS.md` §8），页面上要写明。
    @Published var guidePreferenceText = "" { didSet { savedNotice = nil } }

    /// 是否已就「视力状况 + 导盲犬」取得单独同意。
    ///
    /// 做成 `@Published` 而不是每次现算：现算的计算属性变了 SwiftUI 收不到通知，
    /// 用户在同意页按下「同意并填写」之后界面不会展开，表现就是「点了没反应」。
    @Published private(set) var hasVisionConsent = false

    /// 用户**本次**在同意页明确点了拒绝。只有它为真才会显式传 `NOT_SPECIFIED`：
    /// 「从没被问过」（新设备 / 重装后同意记录不在）不是拒绝，那时不带键让后端保留原值，
    /// 否则会把已存的 `LOW_VISION` 悄悄覆盖成「未提供」。
    @Published private(set) var hasDeclinedVisionConsent = false

    /// 撤回同意已按下、还没保存成功（#352，安卓 #91 同步）。
    ///
    /// 为真时界面已把两项收起（`hasVisionConsent` 置 false），请求体显式传 `NOT_SPECIFIED` + `false`；
    /// **本机同意记录要等保存成功才删** —— 保存失败时删了，下次进来既没有同意也没清掉服务端的值，
    /// 两边说的是两件事。待保存期间重新同意 ⇒ 这次撤回作废（`acceptVisionConsent`）。
    @Published private(set) var isVisionConsentWithdrawalPending = false

    /// 撤回成功后那一句（同时上屏和朗读）。
    @Published private(set) var visionConsentWithdrawnNotice: String?

    /// 普通保存成功后那一句（同时上屏和朗读）。原来成功分支一声不响，
    /// 读屏用户分不清「存上了」和「没按到」，只能反复按（#657 B-6）。
    /// 任何一项再被改动就撤掉（各字段的 `didSet`），免得屏幕说「已保存」而眼前的内容其实没存。
    @Published private(set) var savedNotice: String?
    static let savedNoticeText = "资料已保存。"
    /// 撤回没存上时，失败文案里让用户「再点一次」的那个按钮名。nil = 本页的「保存」/「完成」；
    /// 「隐私与授权」页没有保存按钮，设成它自己的撤回按钮名（#393）。
    var withdrawalRetryButtonTitle: String?

    /// 档案里认得出的引导方式。用户改选「还没决定」时据它判断要不要发 `NOT_SPECIFIED`（#472）：
    /// 原来有值 ⇒ 发，才撤得回；原来就没有或认不出 ⇒ 不带键，免得覆盖一个这个版本不认识的值。
    private var tetherPreferenceBaseline: TetherPreference?
    /// 档案里的导盲犬取值这个版本认不出。为真且用户没改（仍是「不说」）⇒ 保存时不带 `guideDog`。
    private var isGuideDogBaselineUnreadable = false
    /// 档案里的配速这个版本认不出（解码成 `.unknown`，界面显示「无偏好」）。为真且用户没改 ⇒ 保存时不带 `defaultPace`。
    private var isPaceBaselineUnreadable = false
    /// 旧字段 `runningPace`，界面不展示也不改，但契约规定「不带这个键 = 清空」（backend#926 起写明），
    /// 所以每次保存把读到的值原样带回，否则逐行保存会一次次把它清掉。
    private var preservedRunningPace: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var isEditing: Bool {
        appState?.blindProfile != nil
    }

    var canSubmit: Bool {
        !isLoading
    }

    /// 昵称长度，按 UTF-16 数，与后端 `@Size(min = 2, max = 50)` 同口径（契约 `BlindProfileUpdateRequest.name`）。
    static let nicknameLengthRange = 2...50

    /// 昵称不合格时的提示；`nil` = 没问题。
    /// `allowBlank`：整份保存别的行时，没填昵称也照样保存（请求体不带 `name`，后端保留原值，backend#926）；
    /// 昵称编辑页自己保存时不许空着。
    static func nicknameError(_ name: String, allowBlank: Bool) -> String? {
        let length = name.trimmed.utf16.count
        if length == 0 {
            return allowBlank ? nil : "请填写昵称，\(nicknameLengthRange.lowerBound) 到 \(nicknameLengthRange.upperBound) 个字。"
        }
        if length < nicknameLengthRange.lowerBound {
            return "昵称至少 \(nicknameLengthRange.lowerBound) 个字。"
        }
        if length > nicknameLengthRange.upperBound {
            return "昵称最多 \(nicknameLengthRange.upperBound) 个字，现在是 \(length) 个字。"
        }
        return nil
    }

    /// 整份保存前的校验：昵称（可空）+ 引导偏好长度。`nil` = 可以发请求。
    var profileValidationError: String? {
        Self.nicknameError(name, allowBlank: true) ?? guidePreferenceLengthError
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        if let profile = appState.blindProfile {
            name = profile.name ?? ""
            defaultPace = profile.defaultPace?.selectable ?? .noPreference
            isPaceBaselineUnreadable = profile.defaultPace == .unknown
            preservedRunningPace = profile.runningPace
            specialNeeds = profile.specialNeeds ?? ""
            tetherPreference = profile.tetherPreference.flatMap(TetherPreference.init(rawValue:))
            tetherPreferenceBaseline = tetherPreference
            // `NOT_SPECIFIED` 回读成 nil（= Picker 的「不填」）：Picker 没有它的 tag，
            // 直接放进去选中值无效。此时保存不带键，后端保留原值。
            visionLevel = profile.visionLevel.flatMap(VisionLevel.init(rawValue:))
                .flatMap { $0 == .notSpecified ? nil : $0 }
            // 读 `guideDog` 不读旧的 `hasGuideDog`：后者「不说」也给 false，照它回读会让
            // 下一次保存把「不说」改写成「没有」（#472）。
            guideDog = profile.guideDogStatus ?? .notSpecified
            isGuideDogBaselineUnreadable = profile.guideDogStatus == nil
            guidePreferenceText = profile.guidePreferenceText ?? ""
        }

        hasVisionConsent = consentStore?.hasConsented(to: .blindVisionProfile, scope: consentScope) == true
    }

    // MARK: - 敏感项的单独同意

    private var consentStore: PrivacyConsentStore? {
        appState.map { PrivacyConsentStore(persistence: $0.persistence) }
    }

    /// 按**账号**记：同一台手机换人用不是罕见场景，视障用户的设备常由家人协助设置
    /// （与 `PrivacyConsentScope` 上那段同源）。这一页在登录后才可达，`.device` 分支正常走不到，
    /// 但留着比 `guard` 掉强 —— 拿不到 userId 时宁可多问一次，也不要让界面一声不响。
    private var consentScope: PrivacyConsentScope {
        appState?.currentUser.map { .user(String($0.userId)) } ?? .device
    }

    func acceptVisionConsent() {
        consentStore?.recordConsent(to: .blindVisionProfile, scope: consentScope)
        hasVisionConsent = true
        hasDeclinedVisionConsent = false
        isVisionConsentWithdrawalPending = false
        visionConsentWithdrawnNotice = nil
    }

    func declineVisionConsent() {
        hasDeclinedVisionConsent = true
    }

    /// 撤回「视力状况 + 导盲犬」的同意：界面立刻收起，并**立刻整表单保存**一次。
    /// 保存中不响应（`isLoading`），免得两次请求的先后决定最终结果。
    func withdrawVisionConsent() {
        guard hasVisionConsent, !isLoading else { return }
        // 撤回靠整份保存。资料自己过不了校验（昵称长度不对、引导偏好超长）时一个请求都发不出去：
        // 先收起再被 `submit()` 拦下，界面就在说一件没发生的事，离开再进来两项又回来了。
        // 所以不收起、不记待撤回，只念校验错误；改好后再按一次撤回。
        guard profileValidationError == nil else {
            submit()
            return
        }
        hasVisionConsent = false
        isVisionConsentWithdrawalPending = true
        visionConsentWithdrawnNotice = nil
        visionLevel = nil
        guideDog = .notSpecified
        submit()
    }

    /// 超长时的提示；`nil` = 长度没问题。按 UTF-16 数，与后端 `@Size` 同口径。
    var guidePreferenceLengthError: String? {
        let length = guidePreferenceText.trimmed.utf16.count
        let limit = BlindProfileUpdateRequest.guidePreferenceMaxLength
        guard length > limit else { return nil }
        return "引导偏好最多 \(limit) 个字，现在是 \(length) 个字。"
    }

    func submit() {
        guard canSubmit, let appState else { return }
        // 提交前就拦：等后端 400 回来，用户白写一遍还不知道差多少。
        if let validationError = profileValidationError {
            errorMessage = validationError
            speechService?.speakError(validationError)
            return
        }

        Task {
            await saveProfile(appState: appState)
        }
    }

    /// 请求体构造抽成纯函数，理由是**这里有一条测不到就守不住的红线**：
    /// 没取得单独同意时 `visionLevel` / `guideDog` 必须缺席。
    /// 走网络去验它要一个 20 个方法的 `ProfileServing` 替身，而这一层本来就没有副作用。
    /// 形状照抄 `BlindBookingViewModel.makeCreateOrderRequest`。
    func makeProfileUpdateRequest() -> BlindProfileUpdateRequest {
        BlindProfileUpdateRequest(
            // 没填昵称就不带键（后端保留原值，backend#926）：新用户登录后直接进首页（#781），
            // 可能还没填昵称就来改别的行，带空串会被 400「姓名不能为空」。
            name: name.trimmed.nilIfBlank,
            runningPace: preservedRunningPace,
            specialNeeds: specialNeeds.nilIfBlank,
            // 🔴 **没取得单独同意就绝不传「默认值」。**
            // 传 `TOTAL_BLIND` 或 `false` 会把「用户没说」伪造成「用户说了」。
            // 三种情形：同意 → 用户选的值（视力没选 = 不带键；导盲犬「不说」= `NOT_SPECIFIED`）；
            // 本次明确拒绝 / 撤回待保存 → 两项都显式传 `NOT_SPECIFIED`（后端迁移 0056 / backend#326，
            // 导盲犬是后端 #800 / backend#773）；从没被问过 → 两个键都不带，后端保留原值。
            // 用例 `BlindEscortPreferencesTests.testProfileUpdateOmitsVisionFieldsWithoutConsent` /
            // `testDecliningVisionConsentSendsNotSpecified` 钉住。
            // 导盲犬在拒绝 / 撤回时**不许**传 `NO`（#352 时传过 `hasGuideDog: false`）：后端会存成
            // 「明确没有导盲犬」，那正是上面说的把「用户没说」伪造成「用户说了」（#472）。
            visionLevel: hasVisionConsent
                ? visionLevel?.rawValue
                : (isWithholdingVisionFields ? VisionLevel.notSpecified.rawValue : nil),
            guideDog: hasVisionConsent
                ? consentedGuideDogValue
                : (isWithholdingVisionFields ? GuideDogStatus.notSpecified.rawValue : nil),
            // 引导方式不在同意门后面 —— 它不敏感，而且它是拒绝了敏感项的用户
            // 唯一还能给志愿者的准备依据。挪到门后面会让「可拒绝」变成空话。
            // 「还没决定」= nil：原来有值就发 `NOT_SPECIFIED`，否则撤不回（#472，backend#795）。
            tetherPreference: tetherPreference?.rawValue
                ?? (tetherPreferenceBaseline == nil ? nil : TetherPreference.notSpecifiedRawValue),
            chatPreference: nil,
            // 「无偏好」明确发 `NO_PREFERENCE`（契约枚举有这个值）：查看页逐行保存后会念「已保存：无偏好」，
            // 不带键的话服务端保留旧配速，那句话就是假的（#750）。只有档案里的值认不出且用户没改时才不带键。
            defaultPace: isPaceBaselineUnreadable && defaultPace == .noPreference ? nil : defaultPace,
            // 总是带上：空串 = 清空。带 nil 等于「保留原值」，用户删光了却删不掉。
            guidePreferenceText: guidePreferenceText.trimmed
        )
    }

    /// 本次明确拒绝或撤回待保存：两个敏感项要显式发「不提供」。
    private var isWithholdingVisionFields: Bool {
        hasDeclinedVisionConsent || isVisionConsentWithdrawalPending
    }

    /// 同意时导盲犬要发的值。档案里的值认不出且用户没改 ⇒ 不带键（`nil`），保留后端原值。
    private var consentedGuideDogValue: String? {
        isGuideDogBaselineUnreadable && guideDog == .notSpecified ? nil : guideDog.rawValue
    }

    /// 查看页「点哪行改哪行」（#750）：调用方先把新值写进本对象，再调这里整份保存。
    /// 校验没过或没存上 ⇒ 调 `revert` 把值改回去，并上屏、念出原因；返回是否存上。
    ///
    /// `revert` 在主线程上同步调用，不存起来（记忆 `unannotated-async-closure-property-crashes-on-device`）。
    /// `requiresNickname`：昵称编辑页传 true，空昵称不许存；别的行昵称可以空着。
    @discardableResult
    func saveChange(savedLabel: String, requiresNickname: Bool = false, revert: () -> Void) async -> Bool {
        guard let appState, !isLoading else {
            revert()
            return false
        }
        let validationError = (requiresNickname ? Self.nicknameError(name, allowBlank: false) : nil)
            ?? profileValidationError
        if let validationError {
            revert()
            errorMessage = validationError
            speechService?.speakError(validationError)
            return false
        }
        let saved = await saveProfile(appState: appState, savedText: Self.savedChangeText(savedLabel))
        if !saved {
            revert()
        }
        return saved
    }

    static func savedChangeText(_ label: String) -> String {
        "已保存：\(label)"
    }

    /// 进选择页 / 编辑页时清掉上一页留下的提示，免得「已保存：牵引绳」出现在配速页上。
    func clearTransientNotices() {
        savedNotice = nil
        errorMessage = nil
    }

    @discardableResult
    private func saveProfile(appState: AppState, savedText: String = savedNoticeText) async -> Bool {
        isLoading = true
        errorMessage = nil
        savedNotice = nil
        // 请求发出那一刻是不是在撤回 —— 结果回来时据它决定删不删同意记录。
        let withdrawing = isVisionConsentWithdrawalPending

        do {
            let profile = try await appState.profile.updateBlindProfile(makeProfileUpdateRequest())
            appState.updateBlindProfile(profile)
            // 基线跟着服务器走：不更新的话，「先选牵引绳保存、再改回还没决定保存」第二次会不带键。
            tetherPreferenceBaseline = profile.tetherPreference.flatMap(TetherPreference.init(rawValue:))
            isGuideDogBaselineUnreadable = profile.guideDogStatus == nil
            isPaceBaselineUnreadable = profile.defaultPace == .unknown
            preservedRunningPace = profile.runningPace
            isLoading = false
            if withdrawing, isVisionConsentWithdrawalPending {
                consentStore?.revokeConsent(to: .blindVisionProfile, scope: consentScope)
                isVisionConsentWithdrawalPending = false
                visionConsentWithdrawnNotice = VisionConsentWithdrawalCopy.succeeded
                speechService?.speak(VisionConsentWithdrawalCopy.succeeded)
            } else {
                // 撤回那次已经有自己的成功句，再说一句会把它从半句切断（后到的 speak 打断先到的）。
                savedNotice = savedText
                speechService?.speak(savedText)
            }
            return true
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return false
            }
            reportSaveFailure(error.localizedMessage, withdrawing: withdrawing)
            return false
        } catch {
            isLoading = false
            reportSaveFailure("保存失败，请重试", withdrawing: withdrawing)
            return false
        }
    }

    /// 撤回那一次没存上：同意记录不删，说清要再按一次保存（按钮名在首次引导态是「完成」）。
    private func reportSaveFailure(_ message: String, withdrawing: Bool) {
        let text = withdrawing
            ? VisionConsentWithdrawalCopy.failed(saveButtonTitle: withdrawalRetryButtonTitle ?? (isEditing ? "保存" : "完成"))
            : message
        errorMessage = text
        speechService?.speakError(text)
    }
}

// MARK: - Blind Runner Profile View

/// 个人资料（#750，负责人 2026-11-05「按推荐开工」）：先看后改。点哪一行改哪一行，改完当场整份保存
/// （选项类推入 `BlindProfileChoicePage`，文字类推入 `BlindProfileTextEditPage`）。
///
/// 只有这一种排法：#781 起新用户登录后直接进首页，不再有「首次建档一次填完」的表单，
/// 约跑页缺资料时也是推入本页（负责人 2026-11-05 批准）。
struct BlindRunnerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerProfileViewModel()
    @State private var showVisionConsent = false
    @State private var visionConsentDeclineNotice: String?
    @State private var hasConfigured = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sections
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(BlindAccountCopy.profileTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guard !hasConfigured else {
                // 从选择页 / 编辑页退回来：那一页的保存结果已经念过，这里不再说话，
                // 否则后到的播报会把「已保存：xx」切断（记忆 `later-speak-silently-cuts-the-earlier-one`）。
                viewModel.clearTransientNotices()
                return
            }
            hasConfigured = true
            viewModel.configure(with: appState, speechService: speechService)
            // 本页没有「保存」按钮，撤回没存上时让用户再点撤回那一行（同隐私与授权页，#393）。
            viewModel.withdrawalRetryButtonTitle = BlindProfileCopy.withdrawRowTitle
            speechService.speak("个人资料。点哪一项就改哪一项，改完当场保存。")
        }
        // 小弹窗（#769）：fullScreenCover 只是容器，背景透明，卡片居中。
        .fullScreenCover(isPresented: $showVisionConsent) {
            visionConsentScreen
        }
    }

    /// 视力状况的单独同意小弹窗（PIPL 第二十九条）。
    ///
    /// 复用 `ConsentDisclosureView(purpose:)`，文案全部取自 `PrivacyConsentPurpose`——
    /// 那是被单测钉住的合规文本，**不许在 View 里另写一份**。
    private var visionConsentScreen: some View {
        ConsentDisclosureView(
            purpose: .blindVisionProfile,
            onAgree: {
                viewModel.acceptVisionConsent()
                visionConsentDeclineNotice = nil
                showVisionConsent = false
            },
            onDecline: {
                // 不劝返、不重试 —— 拒绝是一个完整的答案
                // （`docs/research/face-verify-decline-alternative-path-ux-20260908.md`）。
                // 反馈同时给屏幕和耳朵：只给一边就有一半用户拿不到。
                viewModel.declineVisionConsent()
                visionConsentDeclineNotice = PrivacyConsentPurpose.blindVisionProfile.declinedFeedback
                showVisionConsent = false
                speechService.speak(PrivacyConsentPurpose.blindVisionProfile.declinedFeedback)
            }
        )
        .task {
            speechService.speak(text: PrivacyConsentPurpose.blindVisionProfile.spokenScript)
        }
    }

    // MARK: - 各组

    @ViewBuilder
    private var sections: some View {
        ProfileAccountHeader(
            name: viewModel.name.nilIfBlank ?? BlindProfileCopy.unfilled,
            roleLine: BlindProfileCopy.roleLine
        )

        BlindProfileGroup {
            row(
                title: BlindProfileCopy.nickname,
                value: viewModel.name.nilIfBlank ?? BlindProfileCopy.unfilled,
                accessibilityLabel: "昵称，必填",
                identifier: "blindProfileNicknameRow"
            ) {
                BlindProfileTextEditPage(viewModel: viewModel, field: .nickname, text: $viewModel.name)
            }
        }

        BlindProfileGroup(title: BlindProfileCopy.dispatchGroupTitle) {
            // 引导方式**排在视力状况前面**、且**不在单独同意门后面**：它是偏好不是身份信息，
            // 拒绝了敏感项的人仍能告诉陪跑员该递绳还是该挽手臂（依据见 `BlindEscortPreferencesTests` 文件头）。
            row(
                title: BlindProfileCopy.tether,
                value: viewModel.tetherPreference?.displayName ?? BlindProfileCopy.tetherUndecided,
                accessibilityLabel: "希望怎么被引导，选填",
                identifier: "blindProfileTetherPreferencePicker"
            ) {
                BlindProfileChoicePage(
                    viewModel: viewModel,
                    title: BlindProfileCopy.tether,
                    choices: BlindProfileChoices.tether,
                    selection: $viewModel.tetherPreference,
                    footnote: BlindProfileCopy.tetherChoiceFootnote
                )
            }
            GroupedCardDivider()
            row(
                title: BlindProfileCopy.pace,
                value: viewModel.defaultPace.displayName,
                accessibilityLabel: "默认配速偏好，选填",
                identifier: "blindProfilePaceRow"
            ) {
                BlindProfileChoicePage(
                    viewModel: viewModel,
                    title: BlindProfileCopy.pace,
                    choices: BlindProfileChoices.pace,
                    selection: $viewModel.defaultPace,
                    footnote: BlindProfileCopy.paceChoiceFootnote
                )
            }
        }

        BlindProfileGroup(title: BlindProfileCopy.acceptedGroupTitle) {
            textRow(.guideNote, text: $viewModel.guidePreferenceText, identifier: "blindProfileGuideNoteRow")
            GroupedCardDivider()
            textRow(.specialNeeds, text: $viewModel.specialNeeds, identifier: "blindProfileSpecialNeedsRow")
        }

        visionGroup

        BlindProfileEmergencyContactsGroup()

        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .accessibilityLabel(errorMessage)
        }
    }

    /// 一行：名称在左、值在右、带箭头，点了推入选择页或编辑页。
    /// 读屏念「名称 + 值」，标签沿用改版前控件的说法，标识沿用改版前控件的 id（UI 用例按它找元素）。
    private func row<Destination: View>(
        title: String,
        value: String,
        accessibilityLabel: String,
        identifier: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            SettingsRowLabel(title: title, value: value)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value)
        .accessibilityHint("点开修改，改完当场保存")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    /// 两段自由文本：有内容时名称下面露原文，没填写时右侧写「未填写」。
    private func textRow(
        _ field: BlindProfileTextField,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        let value = text.wrappedValue.nilIfBlank ?? BlindProfileCopy.unfilled
        return NavigationLink {
            BlindProfileTextEditPage(viewModel: viewModel, field: field, text: text)
        } label: {
            BlindProfileDetailRowLabel(title: field.title, detail: text.wrappedValue)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(field.accessibilityLabel)
        .accessibilityValue(value)
        .accessibilityHint("点开修改，改完按保存")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 视力状况（敏感，走单独同意）

    /// 视力状况与导盲犬。
    ///
    /// 未同意时这一组**只有一行**而不是两个摊开的选项：读屏用户一次划动就跳过
    /// （与 `RoleSelectionView.inviteCodeSection` 折叠成按钮同一条理由），
    /// 而且摊开的选项本身就意味着「已经可以填了」—— 那与「收集前取得单独同意」相反。
    @ViewBuilder
    private var visionGroup: some View {
        if viewModel.hasVisionConsent {
            BlindProfileGroup(title: BlindProfileCopy.visionGroupTitle, footnote: BlindProfileCopy.visionConsentedFootnote) {
                row(
                    title: BlindProfileCopy.vision,
                    value: BlindProfileCopy.visionLevelTitle(viewModel.visionLevel),
                    accessibilityLabel: "视力状况，选填",
                    identifier: "blindProfileVisionLevelPicker"
                ) {
                    BlindProfileChoicePage(
                        viewModel: viewModel,
                        title: BlindProfileCopy.vision,
                        choices: BlindProfileChoices.vision,
                        selection: $viewModel.visionLevel,
                        footnote: BlindProfileCopy.visionChoiceFootnote
                    )
                }
                GroupedCardDivider()
                row(
                    title: BlindProfileCopy.guideDog,
                    value: viewModel.guideDog.profileOptionTitle,
                    accessibilityLabel: "平时使用导盲犬，选填",
                    identifier: "blindProfileGuideDogMenu"
                ) {
                    BlindProfileChoicePage(
                        viewModel: viewModel,
                        title: BlindProfileCopy.guideDog,
                        choices: BlindProfileChoices.guideDog,
                        selection: $viewModel.guideDog,
                        footnote: BlindProfileCopy.guideDogChoiceFootnote
                    )
                }
                GroupedCardDivider()
                // 同意要能撤回（PIPL 第十五条）。按下立刻保存（#352）。
                withdrawRow {
                    visionConsentDeclineNotice = nil
                    viewModel.withdrawVisionConsent()
                }
            }
        } else {
            BlindProfileGroup(title: BlindProfileCopy.visionGroupTitle, footnote: BlindProfileCopy.visionPendingFootnote) {
                if viewModel.isVisionConsentWithdrawalPending {
                    // 撤回已按下、还没存上：两项已经收起，撤回行要留着让用户重试，
                    // 失败文案说的就是「再点一次『撤回这两项的同意』」（同隐私与授权页的 `withdrawalPending`）。
                    withdrawRow {
                        viewModel.submit()
                    }
                    GroupedCardDivider()
                }
                Button {
                    showVisionConsent = true
                } label: {
                    SettingsRowLabel(title: BlindProfileCopy.fillVisionRowTitle, titleColor: AppColors.primary)
                }
                .buttonStyle(.plain)
                // 撤回正在保存时不许重新打开同意页：结果回来前重新同意，最终状态取决于两件事谁先完成。
                .disabled(viewModel.isLoading)
                .accessibilityLabel("填写视力状况")
                .accessibilityHint("视力状况和导盲犬属于敏感个人信息，点开后会先告知再由你决定填不填")
                .accessibilityIdentifier("blindProfileVisionConsentDisclosure")
            }
        }

        if let notice = viewModel.visionConsentWithdrawnNotice {
            // 同拒绝那一句：必须上屏，不能只播报。
            noticeLine(notice, identifier: "blindProfileVisionConsentWithdrawnNotice")
        }

        if let notice = visionConsentDeclineNotice {
            // 🚩 拒绝的反馈必须**上屏**，不能只 `speak`。只播报的话，明眼陪同者与
            // 低视力用户按下「不填这一项」之后屏幕上一个字都不多，看起来就是按钮坏了
            // （记忆 `claimed-fallback-may-not-exist-in-release` 的同一形状）。
            noticeLine(notice, identifier: "blindProfileVisionConsentDeclineNotice")
        }
    }

    private func withdrawRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRowLabel(
                title: BlindProfileCopy.withdrawRowTitle,
                titleColor: AppColors.destructive,
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(VisionConsentWithdrawalCopy.accessibilityLabel)
        .accessibilityIdentifier("blindProfileVisionConsentWithdraw")
    }

    private func noticeLine(_ notice: String, identifier: String) -> some View {
        Text(notice)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .accessibilityLabel(notice)
            .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindRunnerProfileView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
